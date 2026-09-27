#!/usr/bin/env bash
#
# modules/docker.sh — Docker component (spec Phase 12):
#
#   1. detect whether Docker is already installed
#   2. install docker when missing
#   3. never replace a system Docker installation
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   docker_enabled   return 0 when the component should run by default
#   docker_check     print the idempotency state: "installed" / "missing: ..."
#   docker_run       do the work; stop at the first failure (return non-zero)
#   docker_verify    print a confirmation; return non-zero when broken
#
# The component installs distribution packages only — it never replaces a
# system Docker installation. Adding the user to the docker group is
# reserved for a future stage (requires logout/login to take effect).
#
# shellcheck shell=bash

docker_enabled() {
    is_truthy "${INSTALL_DOCKER:-true}"
}

# Print missing Docker items, one line.
_docker_missing() {
    local -a missing=()

    if ! pkg_is_installed docker >/dev/null 2>&1; then
        missing+=("docker")
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

docker_check() {
    local missing
    missing=$(_docker_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

docker_run() {
    # Install Docker if missing
    if ! pkg_is_installed docker >/dev/null 2>&1; then
        pkg_install docker || return 1
    fi
}

docker_verify() {
    if ! pkg_is_installed docker >/dev/null 2>&1; then
        printf 'docker not found after install\n'
        return 1
    fi

    local version
    version=$(docker --version 2>&1)
    printf 'docker configured (%s)\n' "$version"
}
