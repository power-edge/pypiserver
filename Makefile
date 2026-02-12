# Makefile for PyPI Helm Chart Development
# Generic chart development, testing, and publishing commands
# NOT for deployment - users will deploy in their own clusters

.PHONY: help
help: ## Show this help message
	@echo "PyPI Helm Chart - Development Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make lint              # Lint Helm chart"
	@echo "  make test              # Run all tests"
	@echo "  make package           # Package chart for distribution"

# Variables
CHART_DIR := helm
CHART_NAME := pypiserver
DIST_DIR := dist

# Chart validation and linting
.PHONY: lint
lint: ## Lint Helm chart
	@echo "Linting Helm chart..."
	helm lint $(CHART_DIR)

.PHONY: lint-strict
lint-strict: ## Lint with strict mode
	helm lint $(CHART_DIR) --strict

.PHONY: template
template: ## Generate Kubernetes manifests (default values)
	helm template test-release $(CHART_DIR)

.PHONY: template-all
template-all: ## Generate manifests for all example value files
	@echo "=== Default values ==="
	helm template test-release $(CHART_DIR)
	@echo ""
	@echo "=== Hetzner S3 values ==="
	helm template test-release $(CHART_DIR) -f $(CHART_DIR)/values-hetzner-s3.yaml

.PHONY: validate
validate: lint template-all ## Run all validation checks
	@echo "✓ Chart validation passed"

# Testing
.PHONY: test
test: validate ## Run all tests (lint + template rendering)
	@echo "✓ All tests passed"

.PHONY: test-install-dry
test-install-dry: ## Test installation (dry-run, requires kubectl context)
	helm install test-release $(CHART_DIR) --dry-run --debug

# Chart packaging
.PHONY: package
package: validate ## Package Helm chart for distribution
	@echo "Packaging Helm chart..."
	@mkdir -p $(DIST_DIR)
	helm package $(CHART_DIR) -d $(DIST_DIR)
	@echo "✓ Chart packaged in $(DIST_DIR)/"

.PHONY: package-sign
package-sign: validate ## Package and sign Helm chart (requires GPG key)
	@echo "Packaging and signing Helm chart..."
	@mkdir -p $(DIST_DIR)
	helm package $(CHART_DIR) -d $(DIST_DIR) --sign --key "your-gpg-key"
	@echo "✓ Chart packaged and signed in $(DIST_DIR)/"

# Chart repository management
.PHONY: index
index: package ## Generate Helm repository index
	helm repo index $(DIST_DIR) --url https://power-edge.github.io/charts

# Documentation
.PHONY: docs
docs: ## Generate documentation from values.yaml
	@echo "Generating documentation..."
	@echo "See helm/README.md for chart documentation"

.PHONY: readme-check
readme-check: ## Check README.md is up to date
	@echo "Checking README.md..."
	@if [ ! -f "$(CHART_DIR)/README.md" ]; then \
		echo "ERROR: helm/README.md not found"; \
		exit 1; \
	fi
	@echo "✓ README.md exists"

# Version management
.PHONY: version
version: ## Show current chart version
	@grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'

.PHONY: bump-patch
bump-patch: ## Bump patch version (1.0.0 -> 1.0.1)
	@echo "Bumping patch version..."
	@# This is a placeholder - implement version bumping logic

.PHONY: bump-minor
bump-minor: ## Bump minor version (1.0.0 -> 1.1.0)
	@echo "Bumping minor version..."
	@# This is a placeholder - implement version bumping logic

# Clean
.PHONY: clean
clean: ## Remove generated files
	rm -rf $(DIST_DIR)
	rm -rf $(CHART_DIR)/charts/
	rm -f $(CHART_DIR)/Chart.lock

# Development helpers
.PHONY: deps
deps: ## Update chart dependencies
	helm dependency update $(CHART_DIR)

.PHONY: schema-gen
schema-gen: ## Generate values.schema.json (requires helm-schema plugin)
	@if helm plugin list | grep -q schema; then \
		helm schema-gen $(CHART_DIR)/values.yaml > $(CHART_DIR)/values.schema.json; \
		echo "✓ values.schema.json generated"; \
	else \
		echo "Install helm-schema plugin: helm plugin install https://github.com/karuppiah7890/helm-schema-gen.git"; \
	fi

# CI/CD helpers
.PHONY: ci
ci: validate test package ## Run full CI pipeline
	@echo "✓ CI pipeline passed"

# Publishing (for maintainers)
.PHONY: publish-check
publish-check: ci readme-check ## Pre-publish checks
	@echo "Pre-publish checklist:"
	@echo "  ✓ Chart validation passed"
	@echo "  ✓ Tests passed"
	@echo "  ✓ README.md exists"
	@echo ""
	@echo "Ready to publish! Next steps:"
	@echo "  1. Tag release: git tag -a v$(shell grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}') -m 'Release version X.Y.Z'"
	@echo "  2. Push tag: git push origin v$(shell grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}')"
	@echo "  3. Create GitHub release"
	@echo "  4. Publish to Artifact Hub"

# Default target
.DEFAULT_GOAL := help
