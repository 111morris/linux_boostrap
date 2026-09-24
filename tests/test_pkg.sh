#!/usr/bin/env bash
#
# tests for lib/pkg.sh — family→manager mapping, package-name resolution,
# dry-run behaviour of every package-manager backend, installed probes.

set -uo pipefail
export NO_COLOR=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/pkg.sh"

TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT

# dry_probe <family> <manager> <update_system> <cmd...>
# Runs the command with DRY_RUN=true and prints the log output.
dry_probe() {
    local family=$1 manager=$2 update=$3
    shift 3
    (
        set -Eeuo pipefail
        # shellcheck source=../lib/common.sh
        source "$ROOT/lib/common.sh"
        # shellcheck source=../lib/pkg.sh
        source "$ROOT/lib/pkg.sh"
        DRY_RUN=true
        declare -a SUDO=()
        OS_FAMILY=$family
        PKG_MANAGER=$manager
        PKG_CMD=$manager
        if [[ $manager == apt ]]; then
            PKG_CMD=apt-get
        fi
        UPDATE_SYSTEM=$update
        pkg_load_map "$family"
        "$@"
    )
}

test_family_to_manager_mapping() {
    assert_eq "$(pkg_manager_for_family debian)" "apt"
    assert_eq "$(pkg_manager_for_family rhel)" "dnf"
    assert_eq "$(pkg_manager_for_family arch)" "pacman"
    assert_eq "$(pkg_manager_for_family suse)" "zypper"
    assert_eq "$(pkg_manager_for_family alpine)" "apk"
    if pkg_manager_for_family solaris; then
        printf 'solaris should not map to a manager\n' >&2
        return 1
    fi
}

test_rhel_package_map_resolution() {
    pkg_load_map rhel
    assert_eq "$(pkg_resolve fd ripgrep git)" "fd-find ripgrep git"
    assert_eq "$(pkg_resolve build-essential)" "gcc gcc-c++ make"
    assert_eq "$(pkg_resolve ssh-client)" "openssh-clients"
    assert_eq "$(pkg_resolve gpg)" "gnupg2"
}

test_dedupe_after_resolution() {
    pkg_load_map rhel
    assert_eq "$(pkg_resolve python python-venv)" "python3"
}

test_debian_package_map_resolution() {
    pkg_load_map debian
    assert_eq "$(pkg_resolve fd node python-venv xz)" "fd-find nodejs python3-venv xz-utils"
}

test_arch_package_map_resolution() {
    pkg_load_map arch
    assert_eq "$(pkg_resolve build-essential python-venv ssh-client)" "base-devel python openssh"
}

test_unknown_logical_name_passes_through() {
    pkg_load_map rhel
    assert_eq "$(pkg_resolve totally-made-up-pkg)" "totally-made-up-pkg"
}

test_dry_install_apt() {
    local out
    out=$(dry_probe debian apt true pkg_install git fd)
    assert_contains "$out" "[ INFO ] Installing: git fd-find"
    assert_contains "$out" "[ DRY  ] apt-get install -y git fd-find"
}

test_dry_install_dnf() {
    local out
    out=$(dry_probe rhel dnf true pkg_install git fd)
    assert_contains "$out" "[ DRY  ] dnf -y install git fd-find"
}

test_dry_install_pacman() {
    local out
    out=$(dry_probe arch pacman true pkg_install git)
    assert_contains "$out" "[ DRY  ] pacman -S --needed --noconfirm git"
}

test_dry_install_zypper() {
    local out
    out=$(dry_probe suse zypper true pkg_install git)
    assert_contains "$out" "[ DRY  ] zypper --non-interactive install git"
}

test_dry_install_apk() {
    local out
    out=$(dry_probe alpine apk true pkg_install git)
    assert_contains "$out" "[ DRY  ] apk add git"
}

test_dry_update_per_manager() {
    assert_contains "$(dry_probe debian apt true pkg_update)" \
        "[ DRY  ] apt-get update"
    assert_contains "$(dry_probe rhel dnf true pkg_update)" \
        "[ DRY  ] dnf -y makecache --refresh"
    assert_contains "$(dry_probe suse zypper true pkg_update)" \
        "[ DRY  ] zypper --non-interactive refresh"
    assert_contains "$(dry_probe alpine apk true pkg_update)" \
        "[ DRY  ] apk update"
}

test_dry_upgrade_per_manager() {
    assert_contains "$(dry_probe debian apt true pkg_upgrade)" \
        "[ DRY  ] apt-get -y upgrade"
    assert_contains "$(dry_probe rhel dnf true pkg_upgrade)" \
        "[ DRY  ] dnf -y upgrade"
    assert_contains "$(dry_probe suse zypper true pkg_upgrade)" \
        "[ DRY  ] zypper --non-interactive upgrade"
}

test_pacman_refresh_and_upgrade_are_one_operation() {
    local out
    out=$(
        set -Eeuo pipefail
        source "$ROOT/lib/common.sh"
        source "$ROOT/lib/pkg.sh"
        DRY_RUN=true
        declare -a SUDO=()
        OS_FAMILY=arch
        PKG_MANAGER=pacman
        PKG_CMD=pacman
        UPDATE_SYSTEM=true
        pkg_load_map arch
        pkg_update
        pkg_upgrade
    )
    assert_contains "$out" "[ DRY  ] pacman -Syu --noconfirm"
    assert_contains "$out" "[ SKIP ] System already upgraded during metadata refresh (pacman)"
    # exactly one -Syu command (the INFO line only mentions it)
    assert_eq "$(grep -c '^\[ DRY  \] pacman -Syu' <<<"$out")" "1"
}

test_pacman_skips_refresh_when_update_disabled() {
    local out
    out=$(dry_probe arch pacman false pkg_update)
    assert_contains "$out" "[ WARN ] pacman cannot refresh metadata without upgrading"
    assert_not_contains "$out" "[ DRY  ] pacman"
}

test_pkg_detect_requires_os_detection_first() {
    local out rc=0
    out=$(
        {
            source "$ROOT/lib/common.sh"
            source "$ROOT/lib/pkg.sh"
            unset OS_FAMILY
            pkg_detect
        } 2>&1
    ) || rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "has not been detected"
}

test_pkg_detect_on_this_host() {
    local out manager map_count
    out=$(
        set -Eeuo pipefail
        source "$ROOT/lib/common.sh"
        source "$ROOT/lib/os.sh"
        source "$ROOT/lib/pkg.sh"
        detect_os
        pkg_detect
        printf '%s|%s' "$PKG_MANAGER" "${#PKG_MAP[@]}"
    )
    manager=${out%%|*}
    map_count=${out##*|}
    case "$manager" in
        apt | dnf | pacman | zypper | apk) ;;
        *)
            printf 'unexpected package manager: %s\n' "$manager"
            return 1
            ;;
    esac
    if [[ $map_count -lt 5 ]]; then
        printf 'package map unexpectedly small: %s\n' "$map_count"
        return 1
    fi
}

test_is_installed_with_mocked_rpm() {
    local mock="$TMP_TEST/bin-rpm"
    mkdir -p "$mock"
    cat >"$mock/rpm" <<'MOCK'
#!/usr/bin/env bash
if [[ ${1:-} == -q && ${2:-} == git ]]; then
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock/rpm"

    local out
    out=$(
        set -Eeuo pipefail
        source "$ROOT/lib/common.sh"
        source "$ROOT/lib/pkg.sh"
        PATH="$mock:$PATH"
        OS_FAMILY=rhel
        PKG_MANAGER=dnf
        PKG_CMD=dnf
        pkg_load_map rhel
        if pkg_is_installed git; then printf 'git=yes\n'; else printf 'git=no\n'; fi
        if pkg_is_installed vim; then printf 'vim=yes\n'; else printf 'vim=no\n'; fi
    )
    assert_eq "$out" $'git=yes\nvim=no'
}

test_is_installed_with_mocked_dpkg_query() {
    local mock="$TMP_TEST/bin-dpkg"
    mkdir -p "$mock"
    cat >"$mock/dpkg-query" <<'MOCK'
#!/usr/bin/env bash
pkg=${@: -1}
if [[ $pkg == curl ]]; then
    printf 'install ok installed'
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock/dpkg-query"

    local out
    out=$(
        set -Eeuo pipefail
        source "$ROOT/lib/common.sh"
        source "$ROOT/lib/pkg.sh"
        PATH="$mock:$PATH"
        OS_FAMILY=debian
        PKG_MANAGER=apt
        PKG_CMD=apt-get
        pkg_load_map debian
        if pkg_is_installed curl; then printf 'curl=yes\n'; else printf 'curl=no\n'; fi
        if pkg_is_installed wget; then printf 'wget=yes\n'; else printf 'wget=no\n'; fi
    )
    assert_eq "$out" $'curl=yes\nwget=no'
}

t_run \
    test_family_to_manager_mapping \
    test_rhel_package_map_resolution \
    test_dedupe_after_resolution \
    test_debian_package_map_resolution \
    test_arch_package_map_resolution \
    test_unknown_logical_name_passes_through \
    test_dry_install_apt \
    test_dry_install_dnf \
    test_dry_install_pacman \
    test_dry_install_zypper \
    test_dry_install_apk \
    test_dry_update_per_manager \
    test_dry_upgrade_per_manager \
    test_pacman_refresh_and_upgrade_are_one_operation \
    test_pacman_skips_refresh_when_update_disabled \
    test_pkg_detect_requires_os_detection_first \
    test_pkg_detect_on_this_host \
    test_is_installed_with_mocked_rpm \
    test_is_installed_with_mocked_dpkg_query

t_summary
