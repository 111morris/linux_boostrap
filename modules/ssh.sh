#!/usr/bin/env bash
#
# modules/ssh.sh — SSH component (spec Phase 8):
#
#   1. install the SSH client when missing
#   2. optionally generate a key pair (explicitly opt-in)
#   3. never overwrite an existing private key
#   4. ensure proper permissions on ~/.ssh
#
# Contract (README "Components"; bootstrap.sh validates it when loading):
#
#   ssh_enabled   return 0 when the component should run by default
#   ssh_check     print the idempotency state: "installed" / "missing: ..."
#   ssh_run       do the work; stop at the first failure (return non-zero)
#   ssh_verify    print a confirmation; return non-zero when broken
#
# shellcheck shell=bash

ssh_enabled() {
    is_truthy "${INSTALL_SSH:-true}"
}

# Determine the SSH key file path from configuration.
_ssh_key_file() {
    local type="${SSH_KEY_TYPE:-ed25519}"
    printf '%s/.ssh/id_%s' "${HOME:-$PWD}" "$type"
}

# Print missing SSH items, one line.
_ssh_missing() {
    local -a missing=()

    if ! pkg_is_installed ssh-client >/dev/null 2>&1; then
        missing+=("ssh-client")
    fi

    if is_truthy "${SSH_GENERATE_KEY:-false}"; then
        local key_file
        key_file=$(_ssh_key_file)
        [[ -f $key_file ]] || missing+=("ssh-key")
    fi

    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[*]}"
    fi
}

ssh_check() {
    local missing
    missing=$(_ssh_missing)
    if [[ -z $missing ]]; then
        printf 'installed\n'
    else
        printf 'missing: %s\n' "$missing"
    fi
}

ssh_run() {
    # 1. Install SSH client if missing
    if ! pkg_is_installed ssh-client >/dev/null 2>&1; then
        pkg_install ssh-client || return 1
    fi

    # 2. Ensure ~/.ssh exists with proper permissions
    local ssh_dir="${HOME:-$PWD}/.ssh"
    if [[ ! -d $ssh_dir ]]; then
        run mkdir -p "$ssh_dir" || return 1
    fi
    run chmod 700 "$ssh_dir" || return 1

    # 3. Generate key if requested and missing
    if is_truthy "${SSH_GENERATE_KEY:-false}"; then
        local key_file
        key_file=$(_ssh_key_file)
        if [[ ! -f $key_file ]]; then
            local type="${SSH_KEY_TYPE:-ed25519}"
            local comment="${SSH_KEY_COMMENT:-}"
            local -a gen_args=(-t "$type" -f "$key_file" -N "" -C "$comment")

            if [[ $type == rsa && -n ${SSH_KEY_BITS:-} ]]; then
                gen_args+=(-b "$SSH_KEY_BITS")
            fi

            run ssh-keygen "${gen_args[@]}" || return 1
        else
            log_skip "SSH key already exists: $key_file"
        fi

        run chmod 600 "$key_file" || return 1
        run chmod 644 "${key_file}.pub" || return 1
    fi
}

ssh_verify() {
    if ! pkg_is_installed ssh-client >/dev/null 2>&1; then
        printf 'ssh client not found after install\n'
        return 1
    fi

    if is_truthy "${SSH_GENERATE_KEY:-false}"; then
        local key_file
        key_file=$(_ssh_key_file)
        if [[ ! -f $key_file ]]; then
            printf 'ssh key missing after generation: %s\n' "$key_file"
            return 1
        fi
        if [[ ! -f ${key_file}.pub ]]; then
            printf 'ssh public key missing after generation: %s.pub\n' "$key_file"
            return 1
        fi
    fi

    printf 'ssh configured\n'
}
