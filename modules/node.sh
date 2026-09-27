#!/usr/bin/env bash
#
# modules/node.sh — Node.js developer-runtime component (spec Phase 10):
#
#   1. detect whether Node.js is already installed
#   2. detect the installed version
#   3. ensure npm is available
#   4. avoid replacing an existing Node installation
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   node_enabled   return 0 when the component should run by default
#   node_check     print the idempotency state: "installed" / "missing: ..."
#   node_run       do the work; stop at the first failure (return non-zero)
#   node_verify    print a confirmation; return non-zero when broken
#
# The component installs distribution packages only — it never replaces a
# system Node installation. Version pinning (NODE_VERSION) is reserved for
# a future user-space version manager.
#
# shellcheck shell=bash

node_enabled() {
    is_truthy "${INSTALL_NODE_TOOLS:-true}"
}

# Print missing Node items (node / npm), one line.
_node_missing() {
    local -a missing=()

    if ! command -v node >/dev/null 2>&1; then
        missing+=("node")
    else
        if ! command -v npm >/dev/null 2>&1; then
            missing+=("npm")
        fi
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

node_check() {
    local missing
    missing=$(_node_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

node_run() {
    # 1. Install Node.js if missing
    if ! command -v node >/dev/null 2>&1; then
        pkg_install node || return 1
    fi

    # 2. Ensure npm is available
    if ! command -v npm >/dev/null 2>&1; then
        pkg_install npm || return 1
    fi
}

node_verify() {
    if ! command -v node >/dev/null 2>&1; then
        printf 'node not found after install\n'
        return 1
    fi

    if ! command -v npm >/dev/null 2>&1; then
        printf 'npm not available after install\n'
        return 1
    fi

    local version
    version=$(node --version 2>&1)
    printf 'node configured (%s)\n' "$version"
}
