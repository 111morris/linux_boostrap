#!/usr/bin/env bash
#
# lib/common.sh — logging, output formatting, dry-run execution, error handling.
#
# Output style: systemd/Fedora-like status tags with muted colours:
#
#   [  OK  ] success        [ INFO ] informational
#   [ WARN ] warning        [ SKIP ] intentionally not done
#   [ FAIL ] error          [ DRY  ] planned action (dry run)
#
# Colours are disabled automatically when stdout is not a terminal or when
# NO_COLOR is set. After logging_init has run, every message is also appended
# (with a timestamp) to the log file.
#
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# Colours (muted, non-bold; disabled when not a TTY or NO_COLOR is set)
# ---------------------------------------------------------------------------

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_OK=$'\033[0;32m'
    C_INFO=$'\033[0;36m'
    C_WARN=$'\033[0;33m'
    C_FAIL=$'\033[0;31m'
    C_SKIP=$'\033[0;37m'
    C_DRY=$'\033[0;35m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_OK=''
    C_INFO=''
    C_WARN=''
    C_FAIL=''
    C_SKIP=''
    C_DRY=''
    C_DIM=''
    C_RESET=''
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_log_file_write() {
    local tag=$1
    local msg=$2
    [[ -n ${LOG_FILE:-} ]] || return 0
    printf '%s [%s] %s\n' "$(date -Is)" "$tag" "$msg" >>"$LOG_FILE" 2>/dev/null || true
}

_emit() {
    local tag=$1
    local color=$2
    shift 2
    printf '%s[%s]%s %s\n' "$color" "$tag" "$C_RESET" "$*"
    _log_file_write "$tag" "$*"
}

log_info() { _emit ' INFO ' "$C_INFO" "$@"; }
log_ok() { _emit '  OK  ' "$C_OK" "$@"; }
log_warn() { _emit ' WARN ' "$C_WARN" "$@"; }
log_fail() { _emit ' FAIL ' "$C_FAIL" "$@"; }
log_skip() { _emit ' SKIP ' "$C_SKIP" "$@"; }
log_dry() { _emit ' DRY  ' "$C_DRY" "$@"; }

die() {
    log_fail "$@"
    exit 1
}

# ---------------------------------------------------------------------------
# Formatted output helpers
# ---------------------------------------------------------------------------

section_header() {
    printf '\n%s\n' "$1"
}

# Label/value line:   Distribution : Fedora Linux 44
kv_print() {
    printf '  %-13s: %s\n' "$1" "$2"
}

# Config dump line:   UPDATE_SYSTEM       = true
cfg_print() {
    printf '  %-20s = %s\n' "$1" "$2"
}

print_rule() {
    printf '%s%s%s\n' "$C_DIM" '────────────────────────────────────────────────────────' "$C_RESET"
}

# ---------------------------------------------------------------------------
# Dry-run aware execution — every mutating command goes through run()
# ---------------------------------------------------------------------------

is_truthy() {
    case "${1:-}" in
        true | TRUE | True | yes | YES | y | Y | 1) return 0 ;;
        *) return 1 ;;
    esac
}

run() {
    if is_truthy "${DRY_RUN:-false}"; then
        log_dry "$*"
        return 0
    fi

    # Real execution: report the failing command clearly, then propagate the
    # exit status so the caller (module) can stop at the first failure.
    local rc=0
    "$@" || rc=$?
    if ((rc != 0)); then
        log_fail "Command failed (exit ${rc}): $*"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------
# Persistent logging (~/.local/state/linux-bootstrap/bootstrap.log by default)
# ---------------------------------------------------------------------------

logging_init() {
    local dir="${BOOTSTRAP_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/linux-bootstrap}"
    LOG_FILE="${BOOTSTRAP_LOG_FILE:-$dir/bootstrap.log}"

    if ! mkdir -p "$dir" 2>/dev/null || ! (: >>"$LOG_FILE") 2>/dev/null; then
        local failed_path=$LOG_FILE
        LOG_FILE=''
        log_warn "Cannot write to ${failed_path}; logging to console only."
        return 0
    fi

    printf '%s === linux-bootstrap %s | pid %s | dry-run=%s ===\n' \
        "$(date -Is)" "${BOOTSTRAP_VERSION:-dev}" "$$" "${DRY_RUN:-false}" >>"$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

_on_err() {
    local status=$1
    local line=$2
    local cmd=$3
    log_fail "Unexpected failure (exit ${status}) at line ${line}: ${cmd}"
    if [[ -n ${LOG_FILE:-} ]]; then
        log_fail "See log: ${LOG_FILE}"
    fi
    exit "$status"
}

install_error_trap() {
    trap '_on_err "$?" "$LINENO" "$BASH_COMMAND"' ERR
}

# ---------------------------------------------------------------------------
# Privileges — run as the normal user; elevate only per system operation.
# SUDO/PRIVILEGE_MODE are cross-file globals consumed by lib/pkg.sh and
# bootstrap.sh.
# shellcheck disable=SC2034
init_privileges() {
    declare -g -a SUDO=()

    if [[ $EUID -eq 0 ]]; then
        PRIVILEGE_MODE='root'
    elif command -v sudo >/dev/null 2>&1; then
        SUDO=(sudo)
        if sudo -n true >/dev/null 2>&1; then
            PRIVILEGE_MODE='sudo (passwordless)'
        else
            PRIVILEGE_MODE='sudo (password required)'
            log_warn "sudo needs a password; you will be prompted when system changes begin."
        fi
    else
        die "Not running as root and 'sudo' is not available."
    fi
}
