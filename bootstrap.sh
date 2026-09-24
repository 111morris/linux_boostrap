#!/usr/bin/env bash
#
# linux-bootstrap — cross-distribution Linux workstation provisioning.
#
# Stage 1 (current): core infrastructure — OS/package-manager detection,
# logical package-name abstraction, configuration with explicit precedence,
# full CLI, dry-run machinery and logging. Component modules arrive in
# later stages (see README "Roadmap").
#
# Run:  ./bootstrap.sh --help

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_VERSION="0.1.0"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/os.sh
source "$SCRIPT_DIR/lib/os.sh"
# shellcheck source=lib/pkg.sh
source "$SCRIPT_DIR/lib/pkg.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

# ---------------------------------------------------------------------------
# Component registry — entries are "name:tier".
# Tiers: essential | runtime | optional | apps
# Populated stage by stage; Stage 2 adds "system".
# ---------------------------------------------------------------------------
MODULE_REGISTRY=()

SELECTED_MODULES=()

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
linux-bootstrap ${BOOTSTRAP_VERSION} — cross-distribution workstation provisioning

Usage: ./bootstrap.sh [OPTIONS]

Options:
  -h, --help              Show this help and exit
  -V, --version           Print the version and exit
  -n, --dry-run           Show planned actions without changing the system
      --non-interactive   Never prompt; use configuration defaults
      --interactive       Request the component menu (available in Stage 8)
      --all               Enable every registered component
      --minimal           Enable only essential components
      --skip-update       Skip metadata refresh / upgrade (UPDATE_SYSTEM=false)
      --modules LIST      Enable only the comma-separated components (see --list)
      --list              Show environment, components and effective configuration

Configuration precedence:
  built-in defaults  <  config/*.conf  <  environment  <  command line

Examples:
  ./bootstrap.sh --dry-run
  ./bootstrap.sh --non-interactive --all
  ./bootstrap.sh --modules system,git --skip-update
  ./bootstrap.sh --list
EOF
}

usage_error() {
    log_fail "$1"
    printf 'Try "./bootstrap.sh --help" for more information.\n'
    exit 2
}

parse_args() {
    DRY_RUN=false
    INTERACTIVE='auto'
    MODE='default'
    MODULES_ARG=''
    LIST_ONLY=false
    FLAG_SKIP_UPDATE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -V | --version)
                printf 'linux-bootstrap %s\n' "$BOOTSTRAP_VERSION"
                exit 0
                ;;
            -n | --dry-run)
                DRY_RUN=true
                ;;
            --non-interactive)
                INTERACTIVE='off'
                ;;
            --interactive)
                INTERACTIVE='on'
                ;;
            --all)
                MODE='all'
                ;;
            --minimal)
                MODE='minimal'
                ;;
            --skip-update)
                FLAG_SKIP_UPDATE=true
                ;;
            --modules)
                shift
                [[ $# -gt 0 ]] || usage_error "--modules requires a comma-separated value"
                MODULES_ARG=$1
                ;;
            --modules=*)
                MODULES_ARG=${1#--modules=}
                [[ -n $MODULES_ARG ]] || usage_error "--modules requires a comma-separated value"
                ;;
            --list)
                LIST_ONLY=true
                ;;
            --)
                shift
                [[ $# -eq 0 ]] || usage_error "Unexpected arguments after --: $*"
                break
                ;;
            -*)
                usage_error "Unknown option: $1"
                ;;
            *)
                usage_error "Unexpected argument: $1"
                ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Component selection (--modules > --all > --minimal > config defaults)
# ---------------------------------------------------------------------------

module_registry_names() {
    local entry
    for entry in "${MODULE_REGISTRY[@]}"; do
        printf '%s\n' "${entry%%:*}"
    done
}

compute_selection() {
    SELECTED_MODULES=()

    if [[ -n $MODULES_ARG ]]; then
        if [[ ${#MODULE_REGISTRY[@]} -eq 0 ]]; then
            usage_error "No components are registered yet (Stage 1 infrastructure only)."
        fi
        local -a requested=()
        IFS=',' read -r -a requested <<<"$MODULES_ARG"
        local req
        for req in "${requested[@]}"; do
            req=${req//[[:space:]]/}
            [[ -n $req ]] || continue
            if ! module_registry_names | grep -qx "$req"; then
                usage_error "Unknown component: ${req} (see --list)"
            fi
            SELECTED_MODULES+=("$req")
        done
        return 0
    fi

    local entry
    case "$MODE" in
        all)
            if [[ ${#MODULE_REGISTRY[@]} -eq 0 ]]; then
                log_warn "--all: no components registered yet."
            else
                for entry in "${MODULE_REGISTRY[@]}"; do
                    SELECTED_MODULES+=("${entry%%:*}")
                done
            fi
            ;;
        minimal)
            if [[ ${#MODULE_REGISTRY[@]} -eq 0 ]]; then
                log_warn "--minimal: no components registered yet."
            else
                for entry in "${MODULE_REGISTRY[@]}"; do
                    if [[ ${entry##*:} == essential ]]; then
                        SELECTED_MODULES+=("${entry%%:*}")
                    fi
                done
            fi
            ;;
        *)
            # Default mode: each component opts in through its own
            # configuration flag when it lands (Stage 2+).
            :
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

print_system_block() {
    section_header "System"
    kv_print "Distribution" "$OS_PRETTY"
    kv_print "Version" "${OS_VERSION_ID:-unknown}"
    kv_print "Family" "$OS_FAMILY"
    kv_print "Architecture" "$OS_ARCH"
    kv_print "Package mgr" "${PKG_MANAGER} (${PKG_CMD})"
    kv_print "Privileges" "${PRIVILEGE_MODE}"
}

print_list() {
    print_system_block

    section_header "Components"
    if [[ ${#MODULE_REGISTRY[@]} -eq 0 ]]; then
        printf '  (none registered yet — the "system" component arrives in Stage 2)\n'
    else
        local entry
        for entry in "${MODULE_REGISTRY[@]}"; do
            printf '  %-14s %s\n' "${entry%%:*}" "${entry##*:}"
        done
    fi

    section_header "Effective configuration"
    local name
    while IFS= read -r name; do
        cfg_print "$name" "$(config_get "$name")"
    done < <(config_keys)

    section_header "Notes"
    kv_print "Precedence" "defaults < config files < environment < CLI"
    kv_print "Log file" "${LOG_FILE:-console only}"
}

print_plan() {
    section_header "Plan (dry run)"
    log_dry "Read-only so far: OS detection, package-manager detection, privilege check, configuration validation"
    log_dry "No mutating actions exist yet — component actions (metadata refresh, upgrades, installs) arrive in Stage 2"
}

print_summary() {
    local sel='(none)'
    if [[ ${#SELECTED_MODULES[@]} -gt 0 ]]; then
        sel=$(
            IFS=,
            printf '%s' "${SELECTED_MODULES[*]}"
        )
    fi

    section_header "Summary"
    kv_print "Components" "$sel"
    kv_print "Config" "${CONFIG_DIR:-$SCRIPT_DIR/config} ($(config_key_count) keys)"
    kv_print "Log file" "${LOG_FILE:-console only}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"

    print_rule
    printf ' linux-bootstrap %s\n' "$BOOTSTRAP_VERSION"
    print_rule

    logging_init
    install_error_trap

    log_info "Loading configuration"
    config_load

    if [[ $FLAG_SKIP_UPDATE == true ]]; then
        UPDATE_SYSTEM=false
        log_info "--skip-update: UPDATE_SYSTEM=false"
    fi

    compute_selection

    log_info "Detecting operating system"
    detect_os
    log_ok "${OS_PRETTY} (${OS_ARCH})"

    init_privileges

    log_info "Detecting package manager"
    pkg_detect
    log_ok "${PKG_MANAGER} (via ${PKG_CMD})"

    if [[ $LIST_ONLY == true ]]; then
        print_list
        exit 0
    fi

    case "$INTERACTIVE" in
        on)
            log_warn "Interactive menu is not available yet (planned for Stage 8); continuing with the selected components."
            ;;
        auto)
            if [[ -t 0 ]]; then
                log_info "Interactive menu is not available yet (Stage 8); using configuration defaults."
            fi
            ;;
    esac

    print_system_block

    if is_truthy "$DRY_RUN"; then
        print_plan
    elif [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        log_info "Core infrastructure validated (read-only). No components registered yet — Stage 2 adds 'system'."
    fi

    print_summary

    if is_truthy "$DRY_RUN"; then
        log_ok "Dry run complete — no changes were made"
    else
        log_ok "Environment validated — no system changes made yet (components arrive in Stage 2)"
    fi
}

main "$@"
