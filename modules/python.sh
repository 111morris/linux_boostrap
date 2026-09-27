#!/usr/bin/env bash
#
# modules/python.sh — Python developer-runtime component (spec Phase 9):
#
#   1. ensure Python 3 exists
#   2. ensure pip is available
#   3. ensure virtual environments can be created
#   4. never replace the system Python (/usr/bin/python3)
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   python_enabled   return 0 when the component should run by default
#   python_check     print the idempotency state: "installed" / "missing: ..."
#   python_run       do the work; stop at the first failure (return non-zero)
#   python_verify    print a confirmation; return non-zero when broken
#
# The component installs distribution packages only — it never touches
# /usr/bin/python3 or replaces the system interpreter. Version pinning
# (PYTHON_VERSION) is reserved for a future user-space version manager.
#
# shellcheck shell=bash

python_enabled() {
    is_truthy "${INSTALL_PYTHON_TOOLS:-true}"
}

# Print missing Python items (python3 / pip / venv), one line.
_python_missing() {
    local -a missing=()

    if ! command -v python3 >/dev/null 2>&1; then
        missing+=("python3")
    else
        if ! python3 -m pip --version >/dev/null 2>&1; then
            missing+=("pip")
        fi
        if ! python3 -m venv --help >/dev/null 2>&1; then
            missing+=("venv")
        fi
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

python_check() {
    local missing
    missing=$(_python_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

python_run() {
    # 1. Install Python 3 + pip + venv when the interpreter itself is missing
    if ! command -v python3 >/dev/null 2>&1; then
        pkg_install python python-pip python-venv || return 1
        return 0
    fi

    # 2. Ensure pip is available
    if ! python3 -m pip --version >/dev/null 2>&1; then
        pkg_install python-pip || return 1
    fi

    # 3. Ensure venv module is available
    if ! python3 -m venv --help >/dev/null 2>&1; then
        pkg_install python-venv || return 1
    fi
}

python_verify() {
    if ! command -v python3 >/dev/null 2>&1; then
        printf 'python3 not found after install\n'
        return 1
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        printf 'pip not available after install\n'
        return 1
    fi

    if ! python3 -m venv --help >/dev/null 2>&1; then
        printf 'venv not available after install\n'
        return 1
    fi

    local version
    version=$(python3 --version 2>&1)
    printf 'python configured (%s)\n' "$version"
}
