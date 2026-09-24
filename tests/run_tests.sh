#!/usr/bin/env bash
#
# tests/run_tests.sh — discovers and runs every tests/test_*.sh file.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NO_COLOR=1

total=0
failed_names=()

for file in "$TESTS_DIR"/test_*.sh; do
    [[ -e $file ]] || continue
    total=$((total + 1))
    printf '── %s ──\n' "$(basename "$file")"
    if ! bash "$file"; then
        failed_names+=("$(basename "$file")")
    fi
    printf '\n'
done

if [[ $total -eq 0 ]]; then
    printf '[ FAIL ] no test files found\n'
    exit 1
fi

if [[ ${#failed_names[@]} -eq 0 ]]; then
    printf '[  OK  ] all test files passed (%d/%d)\n' "$total" "$total"
    exit 0
fi

printf '[ FAIL ] %d of %d test file(s) failed: %s\n' \
    "${#failed_names[@]}" "$total" "${failed_names[*]}"
exit 1
