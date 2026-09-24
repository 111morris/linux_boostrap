#!/usr/bin/env bash
#
# tests for lib/common.sh — log format, truthiness, dry-run, log file.

set -uo pipefail
export NO_COLOR=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/helpers.sh"
source "$ROOT/lib/common.sh"

TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT

test_is_truthy_accepts_true_values() {
    is_truthy true
    is_truthy TRUE
    is_truthy yes
    is_truthy 1
}

test_is_truthy_rejects_false_values() {
    if is_truthy false; then return 1; fi
    if is_truthy no; then return 1; fi
    if is_truthy ''; then return 1; fi
    if is_truthy nonsense; then return 1; fi
}

test_log_format_info() {
    assert_eq "$(log_info 'Detecting operating system')" \
        "[ INFO ] Detecting operating system"
}

test_log_format_ok() {
    assert_eq "$(log_ok 'done')" "[  OK  ] done"
}

test_log_format_warn() {
    assert_eq "$(log_warn 'careful')" "[ WARN ] careful"
}

test_log_format_fail() {
    assert_eq "$(log_fail 'broken')" "[ FAIL ] broken"
}

test_log_format_skip() {
    assert_eq "$(log_skip 'already fine')" "[ SKIP ] already fine"
}

test_log_format_dry() {
    assert_eq "$(log_dry 'would do')" "[ DRY  ] would do"
}

test_tags_are_fixed_width() {
    local info ok warn fail skip dry
    info=$(log_info x)
    ok=$(log_ok x)
    warn=$(log_warn x)
    fail=$(log_fail x)
    skip=$(log_skip x)
    dry=$(log_dry x)
    # every tag block is "[xxxxxx]" — 8 characters before the space
    assert_eq "${#info}" "${#ok}" "INFO/OK line length"
    assert_eq "${#warn}" "${#ok}" "WARN/OK line length"
    assert_eq "${#fail}" "${#ok}" "FAIL/OK line length"
    assert_eq "${#skip}" "${#ok}" "SKIP/OK line length"
    assert_eq "${#dry}" "${#ok}" "DRY/OK line length"
}

test_run_executes_when_not_dry() {
    local marker="$TMP_TEST/marker-real"
    DRY_RUN=false
    run touch "$marker"
    assert_file_exists "$marker"
}

test_run_prints_instead_of_executing_when_dry() {
    local marker="$TMP_TEST/marker-dry"
    local out
    DRY_RUN=true
    out=$(run touch "$marker")
    assert_file_absent "$marker"
    assert_contains "$out" "[ DRY  ] touch "
}

test_logging_init_creates_log_file() {
    local dir="$TMP_TEST/state"
    BOOTSTRAP_STATE_DIR=$dir
    DRY_RUN=false
    logging_init
    assert_file_exists "$dir/bootstrap.log"
    assert_contains "$(cat "$dir/bootstrap.log")" "=== linux-bootstrap"
}

t_run \
    test_is_truthy_accepts_true_values \
    test_is_truthy_rejects_false_values \
    test_log_format_info \
    test_log_format_ok \
    test_log_format_warn \
    test_log_format_fail \
    test_log_format_skip \
    test_log_format_dry \
    test_tags_are_fixed_width \
    test_run_executes_when_not_dry \
    test_run_prints_instead_of_executing_when_dry \
    test_logging_init_creates_log_file

t_summary
