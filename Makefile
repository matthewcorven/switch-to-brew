# switch-to-brew — Makefile

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/switch-to-brew

.PHONY: install uninstall lint test help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install switch-to-brew to $(PREFIX)
	@echo "Installing switch-to-brew to $(BINDIR)..."
	@mkdir -p "$(BINDIR)"
	@mkdir -p "$(DATADIR)/lib"
	@mkdir -p "$(DATADIR)/data"
	@cp lib/*.sh "$(DATADIR)/lib/"
	@cp data/known_casks.tsv "$(DATADIR)/data/"
	@sed 's|STB_SCRIPT_DIR="$$(cd "$$(dirname "$${BASH_SOURCE\[0\]}")" && pwd)"|STB_SCRIPT_DIR="$(DATADIR)"|' \
		switch-to-brew > "$(BINDIR)/switch-to-brew"
	@chmod +x "$(BINDIR)/switch-to-brew"
	@echo "✔ Installed. Run 'switch-to-brew' to get started."

uninstall: ## Remove switch-to-brew from $(PREFIX)
	@echo "Removing switch-to-brew..."
	@rm -f "$(BINDIR)/switch-to-brew"
	@rm -rf "$(DATADIR)"
	@echo "✔ Uninstalled."

lint: ## Run shellcheck on all scripts
	@echo "Running shellcheck..."
	@shellcheck -x switch-to-brew lib/*.sh
	@echo "✔ All checks passed."

test: ## Run the discover command as a smoke test
	@echo "Running smoke test..."
	@bash switch-to-brew discover --no-color 2>&1 | head -20
	@echo ""
	@echo "✔ Smoke test passed."
