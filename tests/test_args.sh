#!/usr/bin/env bash
#
# tests for bootstrap.sh — CLI parsing, exit codes, precedence, dry-run and
# component selection. Real (non-dry) runs are covered by test_system.sh
# against a fully mocked package layer.

set -uo pipefail
export NO_COLOR=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/helpers.sh"

STATE=$(mktemp -d)
trap 'rm -rf "$STATE"' EXIT

run_bs() {
    BOOTSTRAP_STATE_DIR="$STATE" bash "$ROOT/bootstrap.sh" "$@" 2>&1
}

test_help_flag() {
    local out rc=0
    out=$(run_bs --help) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "Usage: ./bootstrap.sh [OPTIONS]"
    assert_contains "$out" "--dry-run"
    assert_contains "$out" "--modules LIST"
    assert_contains "$out" "Configuration precedence"
    assert_not_contains "$out" "[ INFO ]" "help should not log"
}

test_version_flag() {
    local out rc=0
    out=$(run_bs --version) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "linux-bootstrap 0.1.0"
}

test_unknown_option_exits_2() {
    local out rc=0
    out=$(run_bs --bogus) || rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "[ FAIL ] Unknown option: --bogus"
    assert_contains "$out" '--help'
}

test_unexpected_argument_exits_2() {
    local out rc=0
    out=$(run_bs frobnicate) || rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "Unexpected argument: frobnicate"
}

test_list_shows_environment_and_config() {
    local out rc=0
    out=$(run_bs --list) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "System"
    assert_contains "$out" "Distribution"
    assert_contains "$out" "Package mgr"
    assert_contains "$out" "Effective configuration"
    assert_contains "$out" "$(printf '%-20s = %s' UPDATE_SYSTEM true)"
    assert_contains "$out" "BASELINE_PACKAGES"
    assert_contains "$out" "Components"
    assert_contains "$out" "system"
    assert_contains "$out" "essential"
    assert_contains "$out" "selected"
    assert_not_contains "$out" "not selected" # default mode selects system
}

test_cli_beats_environment() {
    local out rc=0
    out=$(BOOTSTRAP_STATE_DIR="$STATE" UPDATE_SYSTEM=true \
        bash "$ROOT/bootstrap.sh" --skip-update --list 2>&1) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "$(printf '%-20s = %s' UPDATE_SYSTEM false)"
}

test_environment_beats_config_file() {
    local out rc=0
    # config/system.conf says true; environment says false -> false wins
    out=$(BOOTSTRAP_STATE_DIR="$STATE" UPDATE_SYSTEM=false \
        bash "$ROOT/bootstrap.sh" --list 2>&1) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "$(printf '%-20s = %s' UPDATE_SYSTEM false)"
}

test_dry_run_shows_plan_and_changes_nothing() {
    local out rc=0
    out=$(run_bs --dry-run) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "Components"
    assert_contains "$out" "[ DRY  ]"
    assert_contains "$out" "system: verification skipped in dry run"
    assert_contains "$out" "$(printf '  %-13s: %s' Components system)"
    assert_contains "$out" "no changes were made"
    assert_contains "$out" "[  OK  ]"
    assert_not_contains "$out" "[ FAIL ]"
}

test_unknown_module_exits_2() {
    local out rc=0
    out=$(run_bs --modules nope) || rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "Unknown component: nope (see --list)"
    assert_contains "$out" '--help'
}

test_all_selects_every_registered_component() {
    local out rc=0
    out=$(run_bs --all --dry-run) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "$(printf '  %-13s: %s' Components system)"
    assert_not_contains "$out" "no components registered"
}

test_minimal_selects_essential_components() {
    local out rc=0
    out=$(run_bs --minimal --dry-run) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "$(printf '  %-13s: %s' Components system)"
}

test_modules_flag_selects_named_component() {
    local out rc=0
    out=$(run_bs --modules system --dry-run) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "$(printf '  %-13s: %s' Components system)"
    assert_contains "$out" "[ DRY  ] system: verification skipped in dry run"
}

test_interactive_flag_notes_stage8() {
    local out rc=0
    out=$(run_bs --interactive --dry-run) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "Interactive menu is not available yet"
}

test_log_file_is_created() {
    local out rc=0
    out=$(run_bs --list) || rc=$?
    assert_eq "$rc" "0"
    assert_file_exists "$STATE/bootstrap.log"
    assert_contains "$(cat "$STATE/bootstrap.log")" "=== linux-bootstrap"
}

t_run \
    test_help_flag \
    test_version_flag \
    test_unknown_option_exits_2 \
    test_unexpected_argument_exits_2 \
    test_list_shows_environment_and_config \
    test_cli_beats_environment \
    test_environment_beats_config_file \
    test_dry_run_shows_plan_and_changes_nothing \
    test_unknown_module_exits_2 \
    test_all_selects_every_registered_component \
    test_minimal_selects_essential_components \
    test_modules_flag_selects_named_component \
    test_interactive_flag_notes_stage8 \
    test_log_file_is_created

t_summary
