# angie-ctl — developer tasks.
# Pure POSIX-sh project; this Makefile only orchestrates linters/tests/install.

SHELL := /bin/sh

# Tools (override on the command line, e.g. `make lint SHELLCHECK=shellcheck`).
SHELLCHECK ?= shellcheck
RUMDL      ?= rumdl
TYPOS      ?= typos

# Install layout (GNU/Debian conventions; supports DESTDIR for packaging).
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
INSTALL ?= install

# Inputs.
SCRIPTS  := angie-ctl.sh test.sh test-container.sh
MARKDOWN := README.md README.ru.md
BIN_NAME := angie-ctl

.DEFAULT_GOAL := help

.PHONY: help check check-all lint lint-md spell test test-container install uninstall

help: ## Show this help
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| sed 's/:.*## /\t/' \
		| awk -F '\t' '{ printf "  %-14s %s\n", $$1, $$2 }'

check: lint test ## Run the CI gate: shell lint + hermetic tests

check-all: check test-container ## CI gate plus the container integration test

lint: ## Lint shell scripts with shellcheck (POSIX sh)
	@command -v $(SHELLCHECK) >/dev/null 2>&1 \
		|| { echo "$(SHELLCHECK) not found; install ShellCheck" >&2; exit 1; }
	$(SHELLCHECK) -s sh $(SCRIPTS)

lint-md: ## Lint Markdown docs with rumdl (optional)
	@command -v $(RUMDL) >/dev/null 2>&1 \
		|| { echo "$(RUMDL) not found; skipping Markdown lint" >&2; exit 0; }
	$(RUMDL) check $(MARKDOWN)

spell: ## Spell-check sources with typos (optional)
	@command -v $(TYPOS) >/dev/null 2>&1 \
		|| { echo "$(TYPOS) not found; skipping spell check" >&2; exit 0; }
	$(TYPOS) $(SCRIPTS) $(MARKDOWN)

test: ## Run the hermetic integration suite (stubs angie -t)
	./test.sh

test-container: ## Integration test against real angie -t in the official image (needs Docker; self-skips)
	./test-container.sh

install: ## Install angie-ctl into BINDIR (honors DESTDIR/PREFIX)
	$(INSTALL) -d "$(DESTDIR)$(BINDIR)"
	$(INSTALL) -m 0755 angie-ctl.sh "$(DESTDIR)$(BINDIR)/$(BIN_NAME)"

uninstall: ## Remove the installed angie-ctl
	rm -f "$(DESTDIR)$(BINDIR)/$(BIN_NAME)"
