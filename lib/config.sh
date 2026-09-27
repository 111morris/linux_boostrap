#!/usr/bin/env bash
#
# lib/config.sh — central configuration with explicit precedence:
#
#   built-in defaults  <  config/*.conf files  <  environment  <  command line
#
# CONFIG_KEYS registers every known key and its type:
#
#   boolean  normalised to true/false; invalid values abort the run
#   string   free-form; validated by the component that consumes it
#
# Assignments in config files that are not registered produce a warning
# (catches typos). The command line layer is applied by bootstrap.sh after
# config_load returns.
#
# shellcheck shell=bash

CONFIG_KEYS=(
    'UPDATE_SYSTEM:boolean'
    'BASELINE_PACKAGES:string'
    'INSTALL_GIT:boolean'
    'GIT_USER_NAME:string'
    'GIT_USER_EMAIL:string'
    'GIT_DEFAULT_BRANCH:string'
    'GIT_EDITOR:string'
    'GIT_PULL_REBASE:string'
    'GIT_COLOR_UI:string'
    'INSTALL_SSH:boolean'
    'SSH_KEY_TYPE:string'
    'SSH_KEY_BITS:string'
    'SSH_KEY_COMMENT:string'
    'SSH_GENERATE_KEY:boolean'
    'INSTALL_DOCKER:boolean'
    'INSTALL_NEOVIM:boolean'
    'INSTALL_RUST:boolean'
    'INSTALL_GO:boolean'
    'INSTALL_PYTHON_TOOLS:boolean'
    'INSTALL_NODE_TOOLS:boolean'
    'INSTALL_DATABASES:boolean'
)

config_keys() {
    local entry
    for entry in "${CONFIG_KEYS[@]}"; do
        printf '%s\n' "${entry%%:*}"
    done
}

config_key_count() {
    printf '%s\n' "${#CONFIG_KEYS[@]}"
}

config_get() {
    local key=$1
    if [[ -v $key ]]; then
        printf '%s' "${!key}"
    fi
}

config_is_true() {
    is_truthy "$(config_get "$1")"
}

_config_key_registered() {
    local entry candidate
    for entry in "${CONFIG_KEYS[@]}"; do
        candidate=${entry%%:*}
        if [[ $candidate == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

# Normalises yes/no/1/0/true/false to true|false; returns 1 when invalid.
_normalize_bool() {
    case "${1,,}" in
        true | yes | y | 1) printf 'true' ;;
        false | no | n | 0) printf 'false' ;;
        *) return 1 ;;
    esac
}

# Configuration values are cross-file globals: modules and bootstrap.sh read
# them by name after loading.
# shellcheck disable=SC2034
config_load() {
    local conf_dir="${CONFIG_DIR:-${SCRIPT_DIR:-.}/config}"
    local entry name kind value norm f line key
    local -A env_snapshot=()

    # 1. remember values that came from the environment
    for entry in "${CONFIG_KEYS[@]}"; do
        name=${entry%%:*}
        if [[ -v $name ]]; then
            env_snapshot[$name]=${!name}
        fi
    done

    # 2. built-in defaults
    UPDATE_SYSTEM=true
    BASELINE_PACKAGES='git curl wget ca-certificates unzip zip tar gzip xz ssh-client build-essential make cc jq tree tmux htop ripgrep fd findutils vim'
    INSTALL_GIT=true
    GIT_USER_NAME=''
    GIT_USER_EMAIL=''
    GIT_DEFAULT_BRANCH='main'
    GIT_EDITOR=''
    GIT_PULL_REBASE='true'
    GIT_COLOR_UI='true'
    INSTALL_SSH=true
    SSH_KEY_TYPE='ed25519'
    SSH_KEY_BITS=''
    SSH_KEY_COMMENT=''
    SSH_GENERATE_KEY=false
    INSTALL_DOCKER=false
    INSTALL_NEOVIM=false
    INSTALL_RUST=false
    INSTALL_GO=false
    INSTALL_PYTHON_TOOLS=true
    INSTALL_NODE_TOOLS=true
    INSTALL_DATABASES=false

    if [[ ! -d $conf_dir ]]; then
        log_warn "Configuration directory not found: ${conf_dir} (using defaults)"
    else
        # 3. warn about unregistered keys before anything reads them
        for f in "$conf_dir"/*.conf; do
            [[ -e $f ]] || continue
            while IFS= read -r line; do
                [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
                key=${BASH_REMATCH[1]}
                if ! _config_key_registered "$key"; then
                    log_warn "Unknown configuration key: ${key} (${f})"
                fi
            done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$f" || true)
        done

        # 4. layer the files on top of the defaults (sorted order)
        for f in "$conf_dir"/*.conf; do
            [[ -e $f ]] || continue
            # shellcheck source=/dev/null
            source "$f"
        done
    fi

    # 5. environment beats files
    for name in "${!env_snapshot[@]}"; do
        printf -v "$name" '%s' "${env_snapshot[$name]}"
    done

    # 6. validate and normalise (the command line layer is applied later)
    for entry in "${CONFIG_KEYS[@]}"; do
        name=${entry%%:*}
        kind=${entry##*:}
        value=${!name:-}
        # boolean keys must normalise (fatal when invalid);
        # string keys pass through unchanged to their consumer
        if [[ $kind == boolean ]]; then
            if ! norm=$(_normalize_bool "$value"); then
                die "Invalid boolean for ${name}: '${value}' (expected true or false)"
            fi
            printf -v "$name" '%s' "$norm"
        fi
    done
}
