# linux-bootstrap — developer tasks
#
#   make check   lint + test
#   make lint    static analysis (shellcheck)
#   make fmt     formatting check (shfmt)
#   make test    unit tests (zero-dependency runner)

PATH := $(HOME)/.local/bin:$(PATH)
SHELL := bash

SCRIPTS := bootstrap.sh \
	$(wildcard lib/*.sh) \
	$(wildcard packages/*.sh) \
	$(wildcard modules/*.sh) \
	tests/run_tests.sh \
	$(wildcard tests/test_*.sh) \
	tests/lib/helpers.sh

.PHONY: all check lint fmt test

all: check

check: lint test

lint:
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -x $(SCRIPTS) && echo "[  OK  ] shellcheck: no issues"; else echo "[ WARN ] shellcheck not installed (sudo dnf install shellcheck) - skipping lint"; fi

fmt:
	@if command -v shfmt >/dev/null 2>&1; then shfmt -d -i 4 -ci $(SCRIPTS); else echo "[ WARN ] shfmt not installed (sudo dnf install shfmt) - skipping format check"; fi

test:
	@bash tests/run_tests.sh
