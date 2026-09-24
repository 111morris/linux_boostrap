#!/usr/bin/env bash
#
# tests for lib/os.sh — /etc/os-release parsing and family detection.

set -uo pipefail
export NO_COLOR=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/os.sh"

# probe_os <fixture> -> "ID|FAMILY|VERSION_ID|PRETTY_NAME"
probe_os() {
    (
        OS_RELEASE_FILE="$FIX/os-release/$1"
        detect_os
        printf '%s|%s|%s|%s' "$OS_ID" "$OS_FAMILY" "$OS_VERSION_ID" "$OS_PRETTY"
    )
}

test_detect_fedora() {
    assert_eq "$(probe_os fedora.conf)" \
        "fedora|rhel|44|Fedora Linux 44 (Workstation Edition)"
}

test_detect_ubuntu_as_debian_family() {
    assert_eq "$(probe_os ubuntu.conf)" \
        "ubuntu|debian|24.04|Ubuntu 24.04.1 LTS"
}

test_detect_debian() {
    assert_eq "$(probe_os debian.conf)" \
        "debian|debian|12|Debian GNU/Linux 12 (bookworm)"
}

test_detect_linuxmint_as_debian_family() {
    assert_eq "$(probe_os linuxmint.conf)" \
        "linuxmint|debian|21.3|Linux Mint 21.3"
}

test_detect_rocky_with_quoted_id_as_rhel_family() {
    assert_eq "$(probe_os rocky.conf)" \
        "rocky|rhel|9.4|Rocky Linux 9.4 (Blue Onyx)"
}

test_detect_arch_without_version_id() {
    assert_eq "$(probe_os arch.conf)" "arch|arch||Arch Linux"
}

test_detect_manjaro_via_id_like_arch() {
    assert_eq "$(probe_os manjaro.conf)" "manjaro|arch|24.0|Manjaro Linux"
}

test_detect_opensuse_tumbleweed_as_suse_family() {
    assert_eq "$(probe_os opensuse-tumbleweed.conf)" \
        "opensuse-tumbleweed|suse|20240905|openSUSE Tumbleweed"
}

test_detect_sles_as_suse_family() {
    assert_eq "$(probe_os sles.conf)" \
        "sles|suse|15.5|SUSE Linux Enterprise Server 15 SP5"
}

test_detect_alpine() {
    assert_eq "$(probe_os alpine.conf)" "alpine|alpine|3.20.2|Alpine Linux v3.20"
}

test_id_like_fallback_with_single_quoted_id() {
    assert_eq "$(probe_os idlike-fedora.conf)" \
        "custom|rhel|9|Custom Enterprise Linux 9"
}

test_unsupported_distribution_fails_clearly() {
    local out rc=0
    out=$(OS_RELEASE_FILE="$FIX/os-release/weirdos.conf" detect_os 2>&1) || rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "[ FAIL ] Unsupported distribution: ID='weirdos'"
}

test_missing_os_release_file_fails_clearly() {
    local out rc=0
    out=$(OS_RELEASE_FILE="$FIX/os-release/does-not-exist.conf" detect_os 2>&1) || rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "Cannot read"
}

t_run \
    test_detect_fedora \
    test_detect_ubuntu_as_debian_family \
    test_detect_debian \
    test_detect_linuxmint_as_debian_family \
    test_detect_rocky_with_quoted_id_as_rhel_family \
    test_detect_arch_without_version_id \
    test_detect_manjaro_via_id_like_arch \
    test_detect_opensuse_tumbleweed_as_suse_family \
    test_detect_sles_as_suse_family \
    test_detect_alpine \
    test_id_like_fallback_with_single_quoted_id \
    test_unsupported_distribution_fails_clearly \
    test_missing_os_release_file_fails_clearly

t_summary
