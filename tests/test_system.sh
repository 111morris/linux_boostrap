#!/usr/bin/env bash
#
# tests for the system component (Stage 2) — contract behaviour with a
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
# system module loaded (stub pkg_* inside the snippet as needed).
# ---------------------------------------------------------------------------
sys_eval() {
    bash -c '
        set -uo pipefail
        SCRIPT_DIR=$1
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/lib/common.sh"
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/lib/pkg.sh"
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/modules/system.sh"
        eval "$2"
    ' bash "$ROOT" "$1" 2>&1
}

test_system_enabled_returns_true() {
    local rc=0
    sys_eval 'system_enabled' || rc=$?
    assert_eq "$rc" "0"
}

test_system_check_installed_when_all_present() {
    local out
    out=$(sys_eval '
        pkg_is_installed() { return 0; }
        BASELINE_PACKAGES="git curl"
        system_check
    ')
    assert_eq "$out" "installed"
}

test_system_check_lists_missing_packages() {
    local out
    out=$(sys_eval '
        pkg_is_installed() { [[ $1 == git ]]; }
        BASELINE_PACKAGES="git curl vim"
        system_check
    ')
    assert_eq "$out" "missing: curl vim"
}

test_system_run_full_flow_when_update_enabled() {
    local out
    out=$(sys_eval '
        pkg_update() { echo "CALL update"; }
        pkg_upgrade() { echo "CALL upgrade"; }
        pkg_install() { echo "CALL install $*"; }
        pkg_is_installed() { return 1; }
        UPDATE_SYSTEM=true
        BASELINE_PACKAGES="git curl"
        system_run
    ')
    assert_eq "$out" $'CALL update\nCALL upgrade\nCALL install git curl'
}

test_system_run_skips_upgrade_when_disabled() {
    local out
    out=$(sys_eval '
        pkg_update() { echo "CALL update"; }
        pkg_upgrade() { echo "CALL upgrade"; }
        pkg_install() { echo "CALL install $*"; }
        pkg_is_installed() { return 1; }
        UPDATE_SYSTEM=false
        BASELINE_PACKAGES="git"
        system_run
    ')
    assert_contains "$out" "[ SKIP ] System upgrade disabled (UPDATE_SYSTEM=false)"
    assert_contains "$out" "CALL install git"
    assert_not_contains "$out" "CALL upgrade"
}

test_system_run_skips_install_when_present() {
    local out
    out=$(sys_eval '
        pkg_update() { echo "CALL update"; }
        pkg_upgrade() { echo "CALL upgrade"; }
        pkg_install() { echo "CALL install"; }
        pkg_is_installed() { return 0; }
        UPDATE_SYSTEM=false
        BASELINE_PACKAGES="git"
        system_run
    ')
    assert_contains "$out" "[ SKIP ] Baseline packages already installed"
    assert_not_contains "$out" "CALL install"
}

test_system_run_stops_at_first_failure() {
    local out
    out=$(sys_eval '
        pkg_update() { return 1; }
        pkg_upgrade() { echo "CALL upgrade"; }
        pkg_install() { echo "CALL install"; }
        pkg_is_installed() { return 1; }
        UPDATE_SYSTEM=true
        BASELINE_PACKAGES="git"
        system_run && echo "REACHED_END" || echo "RC=$?"
    ')
    assert_contains "$out" "RC=1"
    assert_not_contains "$out" "REACHED_END"
    assert_not_contains "$out" "CALL upgrade"
    assert_not_contains "$out" "CALL install"
}

test_system_verify_fails_when_missing() {
    local out
    out=$(sys_eval '
        pkg_is_installed() { return 1; }
        BASELINE_PACKAGES="git vim"
        system_verify || echo "RC=$?"
    ')
    assert_contains "$out" "missing after install: git vim"
    assert_contains "$out" "RC=1"
}

test_system_verify_confirms_when_present() {
    local out rc=0
    out=$(sys_eval '
        pkg_is_installed() { return 0; }
        BASELINE_PACKAGES="git vim"
        system_verify
    ') || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "baseline verified (2 packages present)"
}

test_system_run_dry_run_shows_commands() {
    local out rc=0
    out=$(sys_eval '
        DRY_RUN=true
        UPDATE_SYSTEM=true
        BASELINE_PACKAGES="git curl"
        declare -a SUDO=(sudo)
        PKG_MANAGER=dnf
        PKG_CMD=dnf
        pkg_load_map rhel
        pkg_is_installed() { return 1; }
        system_run
    ') || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "[ DRY  ] sudo dnf -y makecache --refresh"
    assert_contains "$out" "[ DRY  ] sudo dnf -y upgrade"
    assert_contains "$out" "[ DRY  ] sudo dnf -y install git curl"
}

test_baseline_logical_names_resolve_per_family() {
    local out
    out=$(sys_eval '
        for family in debian rhel arch suse alpine; do
            unset PKG_MAP
            pkg_load_map "$family"
            printf "%s: %s\n" "$family" \
                "$(pkg_resolve ssh-client build-essential cc fd)"
        done
    ')
    assert_contains "$out" "debian: openssh-client build-essential gcc fd-find"
    assert_contains "$out" "rhel: openssh-clients gcc gcc-c++ make fd-find"
    assert_contains "$out" "arch: openssh base-devel gcc fd"
    assert_contains "$out" "suse: openssh-clients gcc gcc-c++ make fd"
    assert_contains "$out" "alpine: openssh build-base gcc fd"
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

# require_family — detect the host family or fail this test with a reason.
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
# mock sudo: pretend to be passwordless, execute the command directly
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

test_e2e_fresh_machine_installs_baseline() {
    local family out rc=0
    family=$(require_family)
    make_shims "$family"
    reset_mocks

    out=$(run_mocked --non-interactive) || rc=$?
    assert_eq "$rc" "0" "fresh-machine run exit code"
    assert_contains "$out" "Refreshing"
    assert_contains "$out" "Installing:"
    if [[ $family == arch ]]; then
        assert_contains "$out" "upgrading together (pacman -Syu)"
    else
        assert_contains "$out" "Upgrading system packages"
    fi
    assert_contains "$out" "baseline verified"
    assert_contains "$out" "Bootstrap completed — all selected components verified"
    assert_contains "$out" "[  OK  ] system"
    assert_file_exists "$MOCK_STATE/git"
    assert_file_exists "$MOCK_STATE/jq"
}

test_e2e_second_run_is_idempotent() {
    local family rc=0 second
    family=$(require_family)
    make_shims "$family"
    reset_mocks

    run_mocked --non-interactive >/dev/null || rc=$?
    assert_eq "$rc" "0" "first run exit code"
    rc=0

    second=$(run_mocked --non-interactive) || rc=$?
    assert_eq "$rc" "0" "second run exit code"
    assert_contains "$second" "[ OK  ] system: installed"
    assert_contains "$second" "[ SKIP ] Baseline packages already installed"
    assert_not_contains "$second" "Installing:"
    assert_contains "$second" "baseline verified"
}

test_e2e_skip_update_env_is_honoured() {
    local family out rc=0
    family=$(require_family)
    make_shims "$family"
    reset_mocks

    export UPDATE_SYSTEM=false
    out=$(run_mocked --non-interactive) || rc=$?
    unset UPDATE_SYSTEM
    assert_eq "$rc" "0" "run with UPDATE_SYSTEM=false exit code"
    assert_contains "$out" "[ SKIP ] System upgrade disabled (UPDATE_SYSTEM=false)"
    assert_not_contains "$out" "Upgrading system packages"
    assert_not_contains "$out" "upgrading together"
    assert_contains "$out" "Installing:"
    assert_file_exists "$MOCK_STATE/git"
}

test_e2e_failed_install_fails_the_run() {
    local family out rc=0
    family=$(require_family)
    make_shims "$family"
    reset_mocks

    export MOCK_FAIL_INSTALL=1
    out=$(run_mocked --non-interactive) || rc=$?
    unset MOCK_FAIL_INSTALL

    assert_eq "$rc" "1" "failed install must fail the run"
    assert_contains "$out" "Command failed (exit 1)"
    assert_contains "$out" "[ FAIL ] system"
    assert_contains "$out" "Bootstrap completed with 1 failed component(s)"
    assert_contains "$out" "Results"
    assert_not_contains "$out" "Bootstrap completed — all selected"
}

t_run \
    test_system_enabled_returns_true \
    test_system_check_installed_when_all_present \
    test_system_check_lists_missing_packages \
    test_system_run_full_flow_when_update_enabled \
    test_system_run_skips_upgrade_when_disabled \
    test_system_run_skips_install_when_present \
    test_system_run_stops_at_first_failure \
    test_system_verify_fails_when_missing \
    test_system_verify_confirms_when_present \
    test_system_run_dry_run_shows_commands \
    test_baseline_logical_names_resolve_per_family \
    test_e2e_fresh_machine_installs_baseline \
    test_e2e_second_run_is_idempotent \
    test_e2e_skip_update_env_is_honoured \
    test_e2e_failed_install_fails_the_run

t_summary
