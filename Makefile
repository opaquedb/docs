# OpaqueDB documentation — common tasks.
# Run `make` or `make help` to list targets.

.DEFAULT_GOAL := help

VENV    := .venv
PYTHON  := python3
BIN     := $(VENV)/bin
WRANGLER := npx wrangler
PROJECT := opaquedb-docs

.PHONY: help venv install serve build clean deploy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

$(VENV)/bin/activate:
	$(PYTHON) -m venv $(VENV)

venv: $(VENV)/bin/activate ## Create the Python virtual environment

install: venv ## Install Python dependencies into the venv
	$(BIN)/pip install -r requirements.txt

serve: ## Live-preview the docs at http://127.0.0.1:8000
	$(BIN)/mkdocs serve -a 0.0.0.0:8000

build: ## Render the static site into site/
	$(BIN)/mkdocs build

clean: ## Remove the built site and caches
	rm -rf site .cache

deploy: build ## Build and deploy to Cloudflare Pages (needs wrangler auth)
	$(WRANGLER) pages deploy site --project-name $(PROJECT)
