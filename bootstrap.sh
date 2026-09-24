#!/usr/bin/env bash
#
# linux-bootstrap — cross-distribution Linux workstation provisioning.
#
# Stage 2 (current): core infrastructure (detection, package abstraction,
# configuration, CLI, dry-run, logging) plus the first component — "system"
# (metadata refresh, configurable upgrade, baseline development packages).
# Later stages register more components (see README "Roadmap").
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
# One line per component; loading validates that modules/<name>.sh exists and
# defines the full contract (enabled / check / run / verify).
# ---------------------------------------------------------------------------
MODULE_REGISTRY=(
    'system:essential'
)

SELECTED_MODULES=()
declare -A MODULE_LOADED=()
declare -A MODULE_STATUS=()

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
  ./bootstrap.sh --modules system --skip-update
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
# Component selection: --modules > --all > --minimal > <name>_enabled()
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

    local entry name
    case "$MODE" in
        all)
            # Explicit flags force the selection (an explicit --all or
            # --modules overrides the component's own config toggles).
            for entry in "${MODULE_REGISTRY[@]}"; do
                SELECTED_MODULES+=("${entry%%:*}")
            done
            ;;
        minimal)
            for entry in "${MODULE_REGISTRY[@]}"; do
                if [[ ${entry##*:} == essential ]]; then
                    SELECTED_MODULES+=("${entry%%:*}")
                fi
            done
            ;;
        *)
            # Default mode: every component that enables itself through its
            # own <name>_enabled() function (which honours config toggles).
            for entry in "${MODULE_REGISTRY[@]}"; do
                name=${entry%%:*}
                if "${name}_enabled"; then
                    SELECTED_MODULES+=("$name")
                fi
            done
            ;;
    esac
}

_module_selected() {
    local s
    for s in "${SELECTED_MODULES[@]}"; do
        if [[ $s == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Component loading and execution
#
# Contract: modules/<name>.sh defines <name>_enabled, <name>_check,
# <name>_run and <name>_verify. check prints the idempotency state
# ("installed" or "missing: ..."); run performs the work, stopping at the
# first failure; verify prints a confirmation and fails when broken.
# ---------------------------------------------------------------------------

load_module() {
    local name=$1
    local file="$SCRIPT_DIR/modules/${name}.sh"
    local suffix

    if [[ -n ${MODULE_LOADED[$name]:-} ]]; then
        return 0
    fi
    [[ -r $file ]] || die "Component file not found: ${file}"

    # shellcheck source=/dev/null
    source "$file"
    for suffix in enabled check run verify; do
        if ! declare -F "${name}_${suffix}" >/dev/null; then
            die "Component '${name}' (${file}) does not define ${name}_${suffix}()"
        fi
    done
    MODULE_LOADED[$name]=true
}

load_all_modules() {
    local entry
    for entry in "${MODULE_REGISTRY[@]}"; do
        load_module "${entry%%:*}"
    done
}

run_components() {
    local name state detail

    section_header "Components"

    if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        log_info "No components selected."
        return 0
    fi

    for name in "${SELECTED_MODULES[@]}"; do
        MODULE_STATUS[$name]=planned
        log_info "Component: ${name}"

        # Idempotency probe — read-only. A failing probe is a warning, not
        # an error: the run itself is idempotent.
        if ! state=$("${name}_check"); then
            log_warn "${name}: state check failed; continuing (operations are idempotent)"
            state='unknown'
        fi
        case "$state" in
            installed*) log_ok "${name}: ${state}" ;;
            *) log_info "${name}: ${state}" ;;
        esac

        if ! "${name}_run"; then
            MODULE_STATUS[$name]=failed
            log_fail "${name}: component failed (see messages above)"
            continue
        fi

        if is_truthy "$DRY_RUN"; then
            MODULE_STATUS[$name]=planned
            log_dry "${name}: verification skipped in dry run"
            continue
        fi

        if detail=$("${name}_verify"); then
            MODULE_STATUS[$name]=ok
            log_ok "${name}: ${detail}"
        else
            MODULE_STATUS[$name]=failed
            log_fail "${name}: ${detail}"
        fi
    done
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
    local entry cname
    for entry in "${MODULE_REGISTRY[@]}"; do
        cname=${entry%%:*}
        if _module_selected "$cname"; then
            printf '  %-12s %-9s %s\n' "$cname" "${entry##*:}" "selected"
        else
            printf '  %-12s %-9s %s\n' "$cname" "${entry##*:}" "not selected"
        fi
    done

    section_header "Effective configuration"
    local name
    while IFS= read -r name; do
        cfg_print "$name" "$(config_get "$name")"
    done < <(config_keys)

    section_header "Notes"
    kv_print "Precedence" "defaults < config files < environment < CLI"
    kv_print "Log file" "${LOG_FILE:-console only}"
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

print_results() {
    local name status tag color

    if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        return 0
    fi

    section_header "Results"
    for name in "${SELECTED_MODULES[@]}"; do
        status=${MODULE_STATUS[$name]:-not run}
        case "$status" in
            ok)
                tag='[  OK  ]'
                color=$C_OK
                ;;
            failed)
                tag='[ FAIL ]'
                color=$C_FAIL
                ;;
            planned)
                tag='[ DRY  ]'
                color=$C_DRY
                status='planned (dry run)'
                ;;
            *)
                tag='[ SKIP ]'
                color=$C_SKIP
                status='not run'
                ;;
        esac
        printf '  %s%s%s %-12s %s\n' "$color" "$tag" "$C_RESET" "$name" "$status"
    done
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

    log_info "Loading components (${#MODULE_REGISTRY[@]} registered)"
    load_all_modules
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

    run_components

    print_summary
    print_results

    local failed=0 name
    for name in "${SELECTED_MODULES[@]}"; do
        if [[ ${MODULE_STATUS[$name]:-} == failed ]]; then
            failed=$((failed + 1))
        fi
    done

    if is_truthy "$DRY_RUN"; then
        log_ok "Dry run complete — no changes were made"
    elif ((failed > 0)); then
        log_fail "Bootstrap completed with ${failed} failed component(s)"
        if [[ -n ${LOG_FILE:-} ]]; then
            log_fail "See log: ${LOG_FILE}"
        fi
        exit 1
    else
        log_ok "Bootstrap completed — all selected components verified"
    fi
}

main "$@"
