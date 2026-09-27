#!/usr/bin/env bash
#
# modules/go.sh — Go developer-runtime component (spec Phase 11):
#
#   1. detect whether Go is already installed
#   2. install go when missing
#   3. never replace a system Go installation
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   go_enabled   return 0 when the component should run by default
#   go_check     print the idempotency state: "installed" / "missing: ..."
#   go_run       do the work; stop at the first failure (return non-zero)
#   go_verify    print a confirmation; return non-zero when broken
#
# The component installs distribution packages only — it never replaces a
# system Go installation. Version pinning is reserved for a future
# user-space version manager.
#
# shellcheck shell=bash

go_enabled() {
    is_truthy "${INSTALL_GO:-true}"
}

# Print missing Go items, one line.
_go_missing() {
    local -a missing=()

    if ! pkg_is_installed go >/dev/null 2>&1; then
        missing+=("go")
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

go_check() {
    local missing
    missing=$(_go_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

go_run() {
    # Install Go if missing
    if ! pkg_is_installed go >/dev/null 2>&1; then
        pkg_install go || return 1
    fi
}

go_verify() {
    if ! pkg_is_installed go >/dev/null 2>&1; then
        printf 'go not found after install\n'
        return 1
    fi

    local version
    version=$(go version 2>&1)
    printf 'go configured (%s)\n' "$version"
}
