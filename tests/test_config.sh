#!/usr/bin/env bash
#
# tests for lib/config.sh — precedence (defaults < files < environment),
# unknown-key warnings, boolean validation, BASELINE_PACKAGES.

set -uo pipefail
export NO_COLOR=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/helpers.sh"

# run_config [ENV=VALUE ...] — loads config in a fresh shell and prints
# the effective values as a stable "RESULT ..." line.
# shellcheck disable=SC2016  # the single-quoted script must expand at inner runtime
run_config() {
    env "$@" bash -c '
        set -uo pipefail
        source "$1/lib/common.sh"
        source "$1/lib/config.sh"
        config_load
        printf "RESULT update=%s docker=%s rust=%s baseline=%s\n" \
            "${UPDATE_SYSTEM}" "${INSTALL_DOCKER}" "${INSTALL_RUST}" \
            "${BASELINE_PACKAGES}"
        printf "COUNT %s\n" "$(config_key_count)"
    ' bash "$ROOT" 2>&1
}

test_defaults_when_config_dir_missing() {
    local out rc=0
    out=$(run_config CONFIG_DIR="$FIX/config/does-not-exist") || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "[ WARN ] Configuration directory not found"
    assert_contains "$out" "RESULT update=true docker=false rust=false"
    assert_contains "$out" "baseline=git curl wget"
    assert_contains "$out" "COUNT 23"
}

test_config_files_override_defaults() {
    local out rc=0
    out=$(run_config CONFIG_DIR="$FIX/config/full") || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "RESULT update=false docker=true rust=false"
}

test_environment_beats_config_files() {
    local out rc=0
    # file says false; environment says yes -> environment wins, normalised
    out=$(run_config CONFIG_DIR="$FIX/config/full" UPDATE_SYSTEM=yes) || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "RESULT update=true docker=true rust=false"
}

test_baseline_packages_env_override() {
    local out rc=0
    out=$(run_config CONFIG_DIR="$FIX/config/full" BASELINE_PACKAGES="git jq") || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "baseline=git jq"
}

test_unknown_key_warns_but_still_loads() {
    local out rc=0
    out=$(run_config CONFIG_DIR="$FIX/config/warn") || rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "[ WARN ] Unknown configuration key: MYSTERY_KEY"
    assert_contains "$out" "RESULT update=true"
}

test_invalid_boolean_is_fatal() {
    local out rc=0
    out=$(run_config CONFIG_DIR="$FIX/config/bad") || rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "[ FAIL ] Invalid boolean for UPDATE_SYSTEM: 'maybe'"
}

test_invalid_environment_boolean_is_fatal() {
    local out rc=0
    out=$(run_config CONFIG_DIR="$FIX/config/full" INSTALL_GO=perhaps) || rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "Invalid boolean for INSTALL_GO: 'perhaps'"
}

t_run \
    test_defaults_when_config_dir_missing \
    test_config_files_override_defaults \
    test_environment_beats_config_files \
    test_baseline_packages_env_override \
    test_unknown_key_warns_but_still_loads \
    test_invalid_boolean_is_fatal \
    test_invalid_environment_boolean_is_fatal

t_summary
