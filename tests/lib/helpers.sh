#!/usr/bin/env bash
#
# tests/lib/helpers.sh — tiny zero-dependency test framework.
#
# Tests are functions run in isolated subshells under `set -Eeuo pipefail`;
# the first failed assertion aborts that test. Output is systemd/Fedora-style:
#
#   [  OK  ] test_name
#   [ FAIL ] test_name
#            <indented failure detail>

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
# shellcheck disable=SC2034  # read by the sourced libs (repo root)
SCRIPT_DIR="$ROOT"
# shellcheck disable=SC2034  # fixture path used by the test files
FIX="$TESTS_DIR/fixtures"

t_total=0
t_failed=0

assert_eq() { # actual expected [label]
    if [[ "$1" != "$2" ]]; then
        printf 'assertion failed: %s\n  expected: <%s>\n  actual  : <%s>\n' \
            "${3:-values differ}" "$2" "$1" >&2
        return 1
    fi
}

assert_contains() { # haystack needle [label]
    if [[ "$1" != *"$2"* ]]; then
        printf 'assertion failed: %s\n  needle  : <%s>\n  haystack: %s\n' \
            "${3:-missing substring}" "$2" "$(printf '%s' "$1" | head -c 600)" >&2
        return 1
    fi
}

assert_not_contains() { # haystack needle [label]
    if [[ "$1" == *"$2"* ]]; then
        printf 'assertion failed: %s\n  should not contain: <%s>\n' \
            "${3:-unexpected substring}" "$2" >&2
        return 1
    fi
}

assert_file_exists() {
    if [[ ! -e $1 ]]; then
        printf 'assertion failed: file missing: %s\n' "$1" >&2
        return 1
    fi
}

assert_file_absent() {
    if [[ -e $1 ]]; then
        printf 'assertion failed: file should not exist: %s\n' "$1" >&2
        return 1
    fi
}

# Run each named test function in its own subshell.
t_run() {
    local name out
    for name in "$@"; do
        t_total=$((t_total + 1))
        if out=$( (
            set -Eeuo pipefail
            "$name"
        ) 2>&1); then
            printf '[  OK  ] %s\n' "$name"
        else
            printf '[ FAIL ] %s\n' "$name"
            if [[ -n $out ]]; then
                # indent every line by the width of "[ FAIL ] "
                printf '%s\n' "${out//$'\n'/$'\n'         }"
            fi
            t_failed=$((t_failed + 1))
        fi
    done
}

t_summary() {
    printf '\n%d passed, %d failed\n' "$t_total" "$t_failed"
    if [[ $t_failed -gt 0 ]]; then
        exit 1
    fi
    exit 0
}
