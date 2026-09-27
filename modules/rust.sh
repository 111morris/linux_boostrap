#!/usr/bin/env bash
#
# modules/rust.sh — Rust developer-runtime component (spec Phase 11):
#
#   1. detect whether Rust is already installed
#   2. install rustc + cargo when missing
#   3. never replace a system Rust installation
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   rust_enabled   return 0 when the component should run by default
#   rust_check     print the idempotency state: "installed" / "missing: ..."
#   rust_run       do the work; stop at the first failure (return non-zero)
#   rust_verify    print a confirmation; return non-zero when broken
#
# The component installs distribution packages only — it never replaces a
# system Rust installation. Version pinning is reserved for a future
# user-space version manager (e.g. rustup).
#
# shellcheck shell=bash

rust_enabled() {
    is_truthy "${INSTALL_RUST:-true}"
}

# Print missing Rust items (rustc / cargo), one line.
_rust_missing() {
    local -a missing=()

    if ! pkg_is_installed rustc >/dev/null 2>&1; then
        missing+=("rustc")
    fi
    if ! pkg_is_installed cargo >/dev/null 2>&1; then
        missing+=("cargo")
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

rust_check() {
    local missing
    missing=$(_rust_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

rust_run() {
    # Install Rust when either rustc or cargo is missing
    if ! pkg_is_installed rustc >/dev/null 2>&1 || ! pkg_is_installed cargo >/dev/null 2>&1; then
        pkg_install rustc cargo || return 1
    fi
}

rust_verify() {
    if ! pkg_is_installed rustc >/dev/null 2>&1; then
        printf 'rustc not found after install\n'
        return 1
    fi
    if ! pkg_is_installed cargo >/dev/null 2>&1; then
        printf 'cargo not found after install\n'
        return 1
    fi

    local version
    version=$(rustc --version 2>&1)
    printf 'rust configured (%s)\n' "$version"
}
