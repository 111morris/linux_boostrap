#!/usr/bin/env bash
#
# modules/system.sh — system baseline component (spec Phases 5 and 6):
#
#   1. refresh package metadata
#   2. full system upgrade when UPDATE_SYSTEM=true (skipped otherwise)
#   3. install the missing baseline development packages — logical names,
#      resolved per distribution through packages/<family>.sh
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   system_enabled   return 0 when the component should run by default
#   system_check     print the idempotency state: "installed" / "missing: ..."
#   system_run       do the work; stop at the first failure (return non-zero)
#   system_verify    print a confirmation; return non-zero when broken
#
# Every mutation goes through run(), so --dry-run prints the exact commands.
#
# shellcheck shell=bash

system_enabled() {
    # The baseline is core: always eligible in default mode.
    return 0
}

# Prints the still-missing baseline packages (logical names), one line.
_system_missing_packages() {
    local p
    local -a pkgs=() missing=()
    read -r -a pkgs <<<"${BASELINE_PACKAGES:-}"
    for p in "${pkgs[@]}"; do
        if ! pkg_is_installed "$p"; then
            missing+=("$p")
        fi
    done
    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

system_check() {
    local missing
    missing=$(_system_missing_packages)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

system_run() {
    # 1. refresh metadata (keeps later installs reliable)
    pkg_update || return 1

    # 2. full upgrade — configurable through UPDATE_SYSTEM
    if is_truthy "${UPDATE_SYSTEM:-true}"; then
        pkg_upgrade || return 1
    else
        log_skip "System upgrade disabled (UPDATE_SYSTEM=false)"
    fi

    # 3. baseline packages — only those actually missing (idempotent)
    local missing
    missing=$(_system_missing_packages)
    if [[ -z $missing ]]; then
        log_skip "Baseline packages already installed"
        return 0
    fi

    local -a pkgs=()
    read -r -a pkgs <<<"$missing"
    pkg_install "${pkgs[@]}" || return 1
}

system_verify() {
    local -a pkgs=()
    local missing
    read -r -a pkgs <<<"${BASELINE_PACKAGES:-}"

    missing=$(_system_missing_packages)
    if [[ -n $missing ]]; then
        printf 'missing after install: %s\n' "$missing"
        return 1
    fi

    printf 'baseline verified (%d packages present)\n' "${#pkgs[@]}"
}
