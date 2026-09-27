#!/usr/bin/env bash
#
# modules/git.sh — Git component (spec Phase 7):
#
#   1. install git when missing
#   2. configure user settings from config/git.conf
#   3. never overwrite existing configuration
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   git_enabled   return 0 when the component should run by default
#   git_check     print the idempotency state: "installed" / "missing: ..."
#   git_run       do the work; stop at the first failure (return non-zero)
#   git_verify    print a confirmation; return non-zero when broken
#
# Settings with an empty config value are skipped — the component only
# manages what the user explicitly configured.
#
# shellcheck shell=bash

git_enabled() {
    is_truthy "${INSTALL_GIT:-true}"
}

# Print missing git items (package or config keys), one line.
_git_missing() {
    local -a missing=()

    if ! command -v git >/dev/null 2>&1; then
        missing+=("git")
    else
        if [[ -n ${GIT_USER_NAME:-} ]]; then
            local current
            current=$(git config --get user.name 2>/dev/null || true)
            [[ $current == "$GIT_USER_NAME" ]] || missing+=("user.name")
        fi

        if [[ -n ${GIT_USER_EMAIL:-} ]]; then
            local current
            current=$(git config --get user.email 2>/dev/null || true)
            [[ $current == "$GIT_USER_EMAIL" ]] || missing+=("user.email")
        fi

        if [[ -n ${GIT_DEFAULT_BRANCH:-} ]]; then
            local current
            current=$(git config --get init.defaultBranch 2>/dev/null || true)
            [[ $current == "$GIT_DEFAULT_BRANCH" ]] || missing+=("init.defaultBranch")
        fi

        if [[ -n ${GIT_EDITOR:-} ]]; then
            local current
            current=$(git config --get core.editor 2>/dev/null || true)
            [[ $current == "$GIT_EDITOR" ]] || missing+=("core.editor")
        fi

        if [[ -n ${GIT_PULL_REBASE:-} ]]; then
            local current
            current=$(git config --get pull.rebase 2>/dev/null || true)
            [[ $current == "$GIT_PULL_REBASE" ]] || missing+=("pull.rebase")
        fi

        if [[ -n ${GIT_COLOR_UI:-} ]]; then
            local current
            current=$(git config --get color.ui 2>/dev/null || true)
            [[ $current == "$GIT_COLOR_UI" ]] || missing+=("color.ui")
        fi
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

git_check() {
    local missing
    missing=$(_git_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

git_run() {
    # 1. Install git if missing
    if ! command -v git >/dev/null 2>&1; then
        pkg_install git || return 1
    fi

    # 2. Apply settings that don't match (idempotent — read before write)
    if [[ -n ${GIT_USER_NAME:-} ]]; then
        local current
        current=$(git config --get user.name 2>/dev/null || true)
        if [[ $current != "$GIT_USER_NAME" ]]; then
            run git config --global user.name "$GIT_USER_NAME" || return 1
        fi
    fi

    if [[ -n ${GIT_USER_EMAIL:-} ]]; then
        local current
        current=$(git config --get user.email 2>/dev/null || true)
        if [[ $current != "$GIT_USER_EMAIL" ]]; then
            run git config --global user.email "$GIT_USER_EMAIL" || return 1
        fi
    fi

    if [[ -n ${GIT_DEFAULT_BRANCH:-} ]]; then
        local current
        current=$(git config --get init.defaultBranch 2>/dev/null || true)
        if [[ $current != "$GIT_DEFAULT_BRANCH" ]]; then
            run git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH" || return 1
        fi
    fi

    if [[ -n ${GIT_EDITOR:-} ]]; then
        local current
        current=$(git config --get core.editor 2>/dev/null || true)
        if [[ $current != "$GIT_EDITOR" ]]; then
            run git config --global core.editor "$GIT_EDITOR" || return 1
        fi
    fi

    if [[ -n ${GIT_PULL_REBASE:-} ]]; then
        local current
        current=$(git config --get pull.rebase 2>/dev/null || true)
        if [[ $current != "$GIT_PULL_REBASE" ]]; then
            run git config --global pull.rebase "$GIT_PULL_REBASE" || return 1
        fi
    fi

    if [[ -n ${GIT_COLOR_UI:-} ]]; then
        local current
        current=$(git config --get color.ui 2>/dev/null || true)
        if [[ $current != "$GIT_COLOR_UI" ]]; then
            run git config --global color.ui "$GIT_COLOR_UI" || return 1
        fi
    fi
}

git_verify() {
    if ! command -v git >/dev/null 2>&1; then
        printf 'git not found after install\n'
        return 1
    fi

    local missing
    missing=$(_git_missing)
    if [[ -n $missing ]]; then
        printf 'settings not applied: %s\n' "$missing"
        return 1
    fi

    printf 'git configured\n'
}
