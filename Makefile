.PHONY: help install test lint fmt run image scan tf-fmt tf-validate tag-check-demo lead-time

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

install: ## Install dev dependencies for the app and the action
	pip install -r app/requirements-dev.txt

test: ## Run all unit tests
	cd app && pytest --cov --cov-report=term-missing
	cd actions/require-tags && pytest --cov=require_tags

lint: ## Lint and format-check Python
	cd app && ruff check . && ruff format --check .
	cd actions/require-tags && ruff check . && ruff format --check .

fmt: ## Format Python and Terraform
	cd app && ruff format .
	cd actions/require-tags && ruff format .
	terraform fmt -recursive infra

run: ## Run the sample API locally on :8000
	cd app && PYTHONPATH=src uvicorn sample_api.main:app --reload --port 8000

image: ## Build the app image
	docker build --build-arg GIT_SHA=$$(git rev-parse HEAD 2>/dev/null || echo local) -t sample-api:local app

scan: image ## Trivy scan of repo and image, same gates as the pipeline
	trivy fs --ignorefile .trivyignore.yaml --scanners vuln,secret,misconfig --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 .
	trivy image --ignorefile .trivyignore.yaml --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 sample-api:local

tf-fmt: ## Check Terraform formatting
	terraform fmt -check -recursive -diff infra

tf-validate: ## Validate all Terraform roots without a backend
	for d in infra/bootstrap infra/modules/container-app infra/service; do \
	  (cd $$d && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done

tag-check-demo: ## Run the require-tags checker on the failing sample plan
	cd actions/require-tags && PYTHONPATH=src python -m require_tags \
	  --plan-json tests/fixtures/plan_violations.json \
	  --allowed-values "environment=staging|production" || true

lead-time: ## Print repo-to-running and commit-to-running times from GitHub
	python3 scripts/lead_time.py
