#!/usr/bin/env bash
#
# tests for the rust component (Stage 6) — contract behaviour with a
# stubbed package layer, plus fully mocked end-to-end runs of bootstrap.sh
# (fake sudo/package manager on PATH; marker files stand in for installed
# packages, so the real host is never modified).
#
# The e2e tests assume a supported host family (same as test_pkg.sh): the OS
# is detected for real, only package operations are faked.
#
# shellcheck disable=SC2016  # single-quoted snippets expand in the inner shell

set -uo pipefail
export NO_COLOR=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/helpers.sh"

MOCK_ROOT=$(mktemp -d)
trap 'rm -rf "$MOCK_ROOT"' EXIT

MOCK_BIN="$MOCK_ROOT/bin"
MOCK_STATE="$MOCK_ROOT/state"
MOCK_LOG="$MOCK_ROOT/commands.log"

# ---------------------------------------------------------------------------
# Unit harness: run a snippet in a fresh shell with the libraries and the
# rust module loaded (stub pkg_* inside the snippet as needed).
# ---------------------------------------------------------------------------
rs_eval() {
    bash -c '
        set -uo pipefail
        SCRIPT_DIR=$1
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/lib/common.sh"
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/lib/pkg.sh"
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/modules/rust.sh"
        eval "$2"
    ' bash "$ROOT" "$1" 2>&1
}

test_rust_enabled_returns_true() {
    local rc=0
    rs_eval 'rust_enabled' || rc=$?
    assert_eq "$rc" "0"
}

test_rust_enabled_false_when_config_disabled() {
    local out rc=0
    out=$(rs_eval '
        INSTALL_RUST=false
        rust_enabled && echo "yes" || echo "no"
    ') || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "no"
}

test_rust_check_installed_when_all_present() {
    local out
    out=$(rs_eval '
        pkg_is_installed() { return 0; }
        rust_check
    ')
    assert_eq "$out" "installed"
}

test_rust_check_missing_rustc() {
    local out
    out=$(rs_eval '
        pkg_is_installed() {
            [[ $1 == "rustc" ]] && return 1
            return 0
        }
        rust_check
    ')
    assert_eq "$out" "missing: rustc"
}

test_rust_check_missing_cargo() {
    local out
    out=$(rs_eval '
        pkg_is_installed() {
            [[ $1 == "cargo" ]] && return 1
            return 0
        }
        rust_check
    ')
    assert_eq "$out" "missing: cargo"
}

test_rust_check_missing_both() {
    local out
    out=$(rs_eval '
        pkg_is_installed() { return 1; }
        rust_check
    ')
    assert_eq "$out" "missing: rustc cargo"
}

test_rust_run_installs_when_missing() {
    local out
    out=$(rs_eval '
        pkg_is_installed() { return 1; }
        pkg_install() { echo "CALL install $*"; }
        rust_run
    ')
    assert_eq "$out" "CALL install rustc cargo"
}

test_rust_run_skips_when_present() {
    local out
    out=$(rs_eval '
        pkg_is_installed() { return 0; }
        pkg_install() { echo "CALL install $*"; }
        rust_run
    ')
    assert_eq "$out" ""
}

test_rust_run_stops_at_first_failure() {
    local out
    out=$(rs_eval '
        pkg_is_installed() { return 1; }
        pkg_install() { return 1; }
        rust_run && echo "REACHED_END" || echo "RC=$?"
    ')
    assert_contains "$out" "RC=1"
    assert_not_contains "$out" "REACHED_END"
}

test_rust_verify_fails_when_missing() {
    local out
    out=$(rs_eval '
        pkg_is_installed() { return 1; }
        rust_verify || echo "RC=$?"
    ')
    assert_contains "$out" "rustc not found"
    assert_contains "$out" "RC=1"
}

test_rust_verify_confirms_when_present() {
    local out rc=0
    out=$(rs_eval '
        pkg_is_installed() { return 0; }
        rustc() {
            if [[ $1 == "--version" ]]; then echo "rustc 1.75.0"; return 0; fi
            return 0
        }
        rust_verify
    ') || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "rust configured (rustc 1.75.0)"
}

test_rust_run_dry_run_shows_commands() {
    local out rc=0
    out=$(rs_eval '
        DRY_RUN=true
        pkg_is_installed() { return 1; }
        declare -a SUDO=(sudo)
        PKG_MANAGER=dnf
        PKG_CMD=dnf
        pkg_load_map rhel
        rust_run
    ') || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "[ DRY  ] sudo dnf -y install rust cargo"
}

# ---------------------------------------------------------------------------
# Mocked end-to-end runs: fake sudo + package manager on PATH. The real host
# is never touched; installed packages are marker files in $MOCK_STATE.
# ---------------------------------------------------------------------------

detect_family() {
    bash -c '
        set -uo pipefail
        # shellcheck source=/dev/null
        source "$1/lib/common.sh"
        # shellcheck source=/dev/null
        source "$1/lib/os.sh"
        detect_os >/dev/null
        printf "%s" "$OS_FAMILY"
    ' bash "$ROOT" 2>/dev/null
}

require_family() {
    local family
    if ! family=$(detect_family); then
        printf 'cannot detect a supported OS family on this host\n' >&2
        return 1
    fi
    printf '%s' "$family"
}

make_shims() {
    local family=$1
    mkdir -p "$MOCK_BIN" "$MOCK_STATE"

    cat >"$MOCK_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
if [[ ${1:-} == -n ]]; then shift; fi
exec "$@"
SHIM

    cat >"$MOCK_BIN/rpm" <<'SHIM'
#!/usr/bin/env bash
printf 'rpm %s\n' "$*" >>"${MOCK_LOG:?}"
if [[ ${1:-} == -q ]]; then
    if [[ -f ${MOCK_STATE:?}/${2:-} ]]; then exit 0; fi
    exit 1
fi
exit 0
SHIM

    case "$family" in
        rhel)
            cat >"$MOCK_BIN/dnf" <<'SHIM'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >>"${MOCK_LOG:?}"
installing=false
for arg in "$@"; do
    if [[ $installing == true ]]; then
        if [[ $arg == -* ]]; then continue; fi
        if [[ ${MOCK_FAIL_INSTALL:-0} == 1 ]]; then exit 1; fi
        : >"${MOCK_STATE:?}/$arg"
    elif [[ $arg == install ]]; then
        installing=true
    fi
done
exit 0
SHIM
            ;;
        debian)
            cat >"$MOCK_BIN/apt-get" <<'SHIM'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"${MOCK_LOG:?}"
installing=false
for arg in "$@"; do
    if [[ $installing == true ]]; then
        if [[ $arg == -* ]]; then continue; fi
        if [[ ${MOCK_FAIL_INSTALL:-0} == 1 ]]; then exit 1; fi
        : >"${MOCK_STATE:?}/$arg"
    elif [[ $arg == install ]]; then
        installing=true
    fi
done
exit 0
SHIM
            cat >"$MOCK_BIN/dpkg-query" <<'SHIM'
#!/usr/bin/env bash
printf 'dpkg-query %s\n' "$*" >>"${MOCK_LOG:?}"
pkg=${@: -1}
if [[ -f ${MOCK_STATE:?}/$pkg ]]; then
    printf 'install ok installed'
    exit 0
fi
exit 1
SHIM
            ;;
        arch)
            cat >"$MOCK_BIN/pacman" <<'SHIM'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >>"${MOCK_LOG:?}"
if [[ ${1:-} == -Q ]]; then
    if [[ -f ${MOCK_STATE:?}/${2:-} ]]; then exit 0; fi
    exit 1
fi
installing=false
for arg in "$@"; do
    if [[ $installing == true ]]; then
        if [[ $arg == -* ]]; then continue; fi
        if [[ ${MOCK_FAIL_INSTALL:-0} == 1 ]]; then exit 1; fi
        : >"${MOCK_STATE:?}/$arg"
    elif [[ $arg == -S ]]; then
        installing=true
    fi
done
exit 0
SHIM
            ;;
        suse)
            cat >"$MOCK_BIN/zypper" <<'SHIM'
#!/usr/bin/env bash
printf 'zypper %s\n' "$*" >>"${MOCK_LOG:?}"
installing=false
for arg in "$@"; do
    if [[ $installing == true ]]; then
        if [[ $arg == -* ]]; then continue; fi
        if [[ ${MOCK_FAIL_INSTALL:-0} == 1 ]]; then exit 1; fi
        : >"${MOCK_STATE:?}/$arg"
    elif [[ $arg == install ]]; then
        installing=true
    fi
done
exit 0
SHIM
            ;;
        alpine)
            cat >"$MOCK_BIN/apk" <<'SHIM'
#!/usr/bin/env bash
printf 'apk %s\n' "$*" >>"${MOCK_LOG:?}"
if [[ ${1:-} == info ]]; then
    if [[ -f ${MOCK_STATE:?}/${3:-} ]]; then exit 0; fi
    exit 1
fi
installing=false
for arg in "$@"; do
    if [[ $installing == true ]]; then
        if [[ $arg == -* ]]; then continue; fi
        if [[ ${MOCK_FAIL_INSTALL:-0} == 1 ]]; then exit 1; fi
        : >"${MOCK_STATE:?}/$arg"
    elif [[ $arg == add ]]; then
        installing=true
    fi
done
exit 0
SHIM
            ;;
        *)
            printf 'unsupported host family for mocks: %s\n' "$family" >&2
            return 1
            ;;
    esac

    chmod +x "$MOCK_BIN"/*
}

reset_mocks() {
    rm -rf "$MOCK_STATE"
    mkdir -p "$MOCK_STATE"
    : >"$MOCK_LOG"
}

run_mocked() {
    PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_STATE="$MOCK_STATE" \
        BOOTSTRAP_STATE_DIR="$MOCK_ROOT/state-dir" \
        bash "$ROOT/bootstrap.sh" "$@" 2>&1
}

test_e2e_fresh_machine_installs_rust() {
    local family out rc=0
    family=$(require_family)
    make_shims "$family"
    reset_mocks

    out=$(run_mocked --non-interactive --modules rust) || rc=$?
    assert_eq "$rc" "0" "fresh-machine run exit code"
    assert_contains "$out" "Installing:"
    assert_contains "$out" "rust configured"
    assert_contains "$out" "Bootstrap completed — all selected components verified"
    assert_contains "$out" "[  OK  ] rust"
}

test_e2e_second_run_rust_idempotent() {
    local family rc=0 second
    family=$(require_family)
    make_shims "$family"
    reset_mocks

    run_mocked --non-interactive --modules rust >/dev/null || rc=$?
    assert_eq "$rc" "0" "first run exit code"
    rc=0

    second=$(run_mocked --non-interactive --modules rust) || rc=$?
    assert_eq "$rc" "0" "second run exit code"
    assert_contains "$second" "[ OK  ] rust: installed"
    assert_not_contains "$second" "Installing:"
    assert_contains "$second" "rust configured"
}

t_run \
    test_rust_enabled_returns_true \
    test_rust_enabled_false_when_config_disabled \
    test_rust_check_installed_when_all_present \
    test_rust_check_missing_rustc \
    test_rust_check_missing_cargo \
    test_rust_check_missing_both \
    test_rust_run_installs_when_missing \
    test_rust_run_skips_when_present \
    test_rust_run_stops_at_first_failure \
    test_rust_verify_fails_when_missing \
    test_rust_verify_confirms_when_present \
    test_rust_run_dry_run_shows_commands \
    test_e2e_fresh_machine_installs_rust \
    test_e2e_second_run_rust_idempotent

t_summary
