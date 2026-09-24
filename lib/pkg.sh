#!/usr/bin/env bash
#
# lib/pkg.sh — package-manager abstraction.
#
# Modules never call apt/dnf/pacman/zypper/apk directly. They use:
#
#   pkg_detect               resolve manager for the detected OS family
#   pkg_resolve NAME...      logical name(s) -> distro package name(s)
#   pkg_update               refresh package metadata
#   pkg_upgrade              full system upgrade (when UPDATE_SYSTEM=true)
#   pkg_install NAME...      install logical packages (dry-run aware)
#   pkg_remove NAME...       remove logical packages (dry-run aware)
#   pkg_is_installed NAME    idempotency probe (no state change)
#
# Logical names are mapped per family in packages/<family>.sh. Anything not in
# the map falls through unchanged, so identical names need no mapping.
# All mutations go through run(), so --dry-run works everywhere.
#
# shellcheck shell=bash

pkg_manager_for_family() {
    case "${1:-}" in
        debian) printf 'apt' ;;
        rhel) printf 'dnf' ;;
        arch) printf 'pacman' ;;
        suse) printf 'zypper' ;;
        alpine) printf 'apk' ;;
        *) return 1 ;;
    esac
}

pkg_load_map() {
    local family="${1:-${OS_FAMILY:-}}"
    local map_file="${PACKAGES_DIR:-${SCRIPT_DIR:-.}/packages}/${family}.sh"

    if [[ ! -r $map_file ]]; then
        die "Package name map not found: ${map_file}"
    fi

    # shellcheck source=/dev/null
    source "$map_file"
}

pkg_detect() {
    if [[ -z ${OS_FAMILY:-} ]]; then
        die "pkg_detect: operating system has not been detected yet."
    fi

    local manager
    if ! manager=$(pkg_manager_for_family "$OS_FAMILY"); then
        die "No package manager known for OS family '${OS_FAMILY}'."
    fi

    PKG_MANAGER=$manager
    PKG_CMD=$manager
    if [[ $PKG_MANAGER == apt ]]; then
        PKG_CMD=apt-get
    fi

    if ! command -v "$PKG_CMD" >/dev/null 2>&1; then
        die "Package manager '${PKG_CMD}' not found on this system."
    fi

    pkg_load_map "$OS_FAMILY"
    PKG_UPDATED_AND_UPGRADED=${PKG_UPDATED_AND_UPGRADED:-false}
}

# Resolve logical package names to distro packages. Space-separated map values
# expand to several packages; duplicates are removed, order is preserved.
pkg_resolve() {
    local logical resolved r
    local out=''
    local -a parts=()

    for logical in "$@"; do
        resolved=${PKG_MAP[$logical]:-$logical}
        read -r -a parts <<<"$resolved"
        for r in "${parts[@]}"; do
            case " $out " in
                *" $r "*) ;;
                *) out="${out:+$out }$r" ;;
            esac
        done
    done

    printf '%s' "$out"
}

pkg_update() {
    case "$PKG_MANAGER" in
        apt)
            log_info "Refreshing package metadata (apt)"
            run "${SUDO[@]}" "$PKG_CMD" update
            ;;
        dnf)
            log_info "Refreshing package metadata (dnf)"
            run "${SUDO[@]}" "$PKG_CMD" -y makecache --refresh
            ;;
        zypper)
            log_info "Refreshing package metadata (zypper)"
            run "${SUDO[@]}" "$PKG_CMD" --non-interactive refresh
            ;;
        apk)
            log_info "Refreshing package metadata (apk)"
            run "${SUDO[@]}" "$PKG_CMD" update
            ;;
        pacman)
            # pacman cannot refresh metadata without upgrading (partial-upgrade
            # risk), so refresh + upgrade are one operation here.
            if is_truthy "${UPDATE_SYSTEM:-true}"; then
                log_info "Refreshing metadata and upgrading together (pacman -Syu)"
                run "${SUDO[@]}" "$PKG_CMD" -Syu --noconfirm
                PKG_UPDATED_AND_UPGRADED=true
            else
                log_warn "pacman cannot refresh metadata without upgrading (partial-upgrade risk); skipping refresh."
            fi
            ;;
        *)
            die "pkg_update: unknown package manager '${PKG_MANAGER:-unset}'"
            ;;
    esac
}

pkg_upgrade() {
    if [[ ${PKG_UPDATED_AND_UPGRADED:-false} == true ]]; then
        log_skip "System already upgraded during metadata refresh (pacman)"
        return 0
    fi

    log_info "Upgrading system packages (${PKG_CMD})"
    case "$PKG_MANAGER" in
        apt) run "${SUDO[@]}" "$PKG_CMD" -y upgrade ;;
        dnf) run "${SUDO[@]}" "$PKG_CMD" -y upgrade ;;
        zypper) run "${SUDO[@]}" "$PKG_CMD" --non-interactive upgrade ;;
        apk) run "${SUDO[@]}" "$PKG_CMD" upgrade ;;
        pacman) run "${SUDO[@]}" "$PKG_CMD" -Syu --noconfirm ;;
        *) die "pkg_upgrade: unknown package manager '${PKG_MANAGER:-unset}'" ;;
    esac
}

pkg_install() {
    if [[ $# -eq 0 ]]; then
        log_skip "pkg_install called with no packages"
        return 0
    fi

    local resolved
    resolved=$(pkg_resolve "$@")
    if [[ -z $resolved ]]; then
        log_skip "Nothing to install"
        return 0
    fi

    local -a pkgs=()
    read -r -a pkgs <<<"$resolved"

    log_info "Installing: ${resolved}"
    case "$PKG_MANAGER" in
        apt) run "${SUDO[@]}" "$PKG_CMD" install -y "${pkgs[@]}" ;;
        dnf) run "${SUDO[@]}" "$PKG_CMD" -y install "${pkgs[@]}" ;;
        pacman) run "${SUDO[@]}" "$PKG_CMD" -S --needed --noconfirm "${pkgs[@]}" ;;
        zypper) run "${SUDO[@]}" "$PKG_CMD" --non-interactive install "${pkgs[@]}" ;;
        apk) run "${SUDO[@]}" "$PKG_CMD" add "${pkgs[@]}" ;;
        *) die "pkg_install: unknown package manager '${PKG_MANAGER:-unset}'" ;;
    esac
}

pkg_remove() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local resolved
    resolved=$(pkg_resolve "$@")
    local -a pkgs=()
    read -r -a pkgs <<<"$resolved"

    log_info "Removing: ${resolved}"
    case "$PKG_MANAGER" in
        apt) run "${SUDO[@]}" "$PKG_CMD" remove -y "${pkgs[@]}" ;;
        dnf) run "${SUDO[@]}" "$PKG_CMD" -y remove "${pkgs[@]}" ;;
        pacman) run "${SUDO[@]}" "$PKG_CMD" -Rns --noconfirm "${pkgs[@]}" ;;
        zypper) run "${SUDO[@]}" "$PKG_CMD" --non-interactive remove "${pkgs[@]}" ;;
        apk) run "${SUDO[@]}" "$PKG_CMD" del "${pkgs[@]}" ;;
        *) die "pkg_remove: unknown package manager '${PKG_MANAGER:-unset}'" ;;
    esac
}

# Read-only idempotency probe: succeeds when every resolved package is present.
pkg_is_installed() {
    [[ $# -gt 0 ]] || return 0

    local resolved p
    resolved=$(pkg_resolve "$@")
    local -a pkgs=()
    read -r -a pkgs <<<"$resolved"

    for p in "${pkgs[@]}"; do
        case "$PKG_MANAGER" in
            apt)
                dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || return 1
                ;;
            dnf | zypper)
                rpm -q "$p" >/dev/null 2>&1 || return 1
                ;;
            pacman)
                pacman -Q "$p" >/dev/null 2>&1 || return 1
                ;;
            apk)
                apk info -e "$p" >/dev/null 2>&1 || return 1
                ;;
            *)
                return 1
                ;;
        esac
    done

    return 0
}
