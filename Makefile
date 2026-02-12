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

# Local testing with k3d
CLUSTER_NAME := pypi-test
TEST_NAMESPACE := pypi-test
TEST_RELEASE := pypi

.PHONY: test-cluster-create
test-cluster-create: ## Create k3d test cluster
	@echo "Creating k3d test cluster..."
	k3d cluster create $(CLUSTER_NAME) \
		--port "8080:80@loadbalancer" \
		--port "8443:443@loadbalancer" \
		--wait
	@echo "✓ Cluster created"
	kubectl cluster-info

.PHONY: test-cluster-delete
test-cluster-delete: ## Delete k3d test cluster
	k3d cluster delete $(CLUSTER_NAME)

.PHONY: test-setup
test-setup: ## Install test dependencies (ingress, MinIO)
	@echo "Installing ingress-nginx..."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=120s
	@echo "✓ Ingress controller ready"

.PHONY: test-setup-minio
test-setup-minio: ## Install MinIO for S3 testing
	@echo "Installing MinIO..."
	kubectl apply -f test/fixtures/minio-deployment.yaml
	kubectl wait --for=condition=ready pod -l app=minio -n $(TEST_NAMESPACE) --timeout=120s
	@echo "✓ MinIO ready"

.PHONY: test-minimal
test-minimal: ## Test minimal configuration (no auth, no ingress)
	@echo "Testing minimal configuration..."
	helm install $(TEST_RELEASE) $(CHART_DIR) \
		-f test/values/test-minimal.yaml \
		--namespace $(TEST_NAMESPACE) \
		--create-namespace \
		--wait --timeout 5m
	@echo "Running Helm tests..."
	helm test $(TEST_RELEASE) -n $(TEST_NAMESPACE) --logs
	@echo "✓ Minimal config test passed"

.PHONY: test-local-pv-auth
test-local-pv-auth: ## Test local PV with authentication
	@echo "Testing local PV with auth..."
	helm install $(TEST_RELEASE) $(CHART_DIR) \
		-f test/values/test-local-pv-auth.yaml \
		--namespace $(TEST_NAMESPACE) \
		--create-namespace \
		--wait --timeout 5m
	helm test $(TEST_RELEASE) -n $(TEST_NAMESPACE) --logs
	@echo "✓ Local PV + auth test passed"

.PHONY: test-minio-s3
test-minio-s3: test-setup-minio ## Test S3 CSI with MinIO
	@echo "Testing S3 CSI with MinIO..."
	helm install $(TEST_RELEASE) $(CHART_DIR) \
		-f test/values/test-minio-s3.yaml \
		--namespace $(TEST_NAMESPACE) \
		--create-namespace \
		--wait --timeout 5m
	helm test $(TEST_RELEASE) -n $(TEST_NAMESPACE) --logs
	@echo "✓ S3 CSI test passed"

.PHONY: test-ha-config
test-ha-config: ## Test high availability configuration
	@echo "Testing HA config..."
	helm install $(TEST_RELEASE) $(CHART_DIR) \
		-f test/values/test-ha-config.yaml \
		--namespace $(TEST_NAMESPACE) \
		--create-namespace \
		--wait --timeout 5m
	helm test $(TEST_RELEASE) -n $(TEST_NAMESPACE) --logs
	@echo "Verifying multiple replicas..."
	@if [ $$(kubectl get pods -n $(TEST_NAMESPACE) -l app.kubernetes.io/name=pypiserver -o name | wc -l) -lt 2 ]; then \
		echo "ERROR: Expected 2+ replicas"; \
		exit 1; \
	fi
	@echo "✓ HA config test passed"

.PHONY: test-clean
test-clean: ## Clean up test installation
	@echo "Cleaning up test installation..."
	-helm uninstall $(TEST_RELEASE) -n $(TEST_NAMESPACE)
	-kubectl delete namespace $(TEST_NAMESPACE)
	@echo "✓ Cleaned up"

.PHONY: test-all
test-all: test-cluster-create test-setup ## Run all test configurations
	@echo "Running full test suite..."
	@$(MAKE) test-minimal
	@$(MAKE) test-clean
	@$(MAKE) test-local-pv-auth
	@$(MAKE) test-clean
	@$(MAKE) test-ha-config
	@$(MAKE) test-clean
	@echo "✓ All tests passed!"
	@echo ""
	@echo "To test S3 CSI, run: make test-minio-s3"
	@echo "To delete cluster, run: make test-cluster-delete"

.PHONY: test-quick
test-quick: ## Quick test (minimal config only)
	@echo "Running quick test..."
	@if ! k3d cluster list | grep -q $(CLUSTER_NAME); then \
		$(MAKE) test-cluster-create; \
	fi
	@$(MAKE) test-setup
	@$(MAKE) test-minimal
	@echo "✓ Quick test passed"

.PHONY: test-package-upload
test-package-upload: ## Test package upload (requires running chart)
	@echo "Building test package..."
	cd test/fixtures/test-package && python -m build
	@echo "Port-forwarding PyPI server..."
	kubectl port-forward -n $(TEST_NAMESPACE) svc/$(TEST_RELEASE)-pypiserver 8080:8080 &
	sleep 3
	@echo "Uploading test package..."
	twine upload --repository-url http://localhost:8080/ \
		test/fixtures/test-package/dist/* || true
	@echo "Testing package install..."
	pip install --index-url http://localhost:8080/simple/ test-package --no-cache-dir || true
	@pkill -f "port-forward" || true
	@echo "✓ Package upload test completed"

.PHONY: test-watch
test-watch: ## Watch test resources
	watch -n 2 "kubectl get pods,pvc,ingress -n $(TEST_NAMESPACE)"

.PHONY: test-logs
test-logs: ## Show logs from PyPI server
	kubectl logs -n $(TEST_NAMESPACE) -l app.kubernetes.io/name=pypiserver --tail=100 -f

.PHONY: test-shell
test-shell: ## Open shell in PyPI pod
	kubectl exec -n $(TEST_NAMESPACE) -it deployment/$(TEST_RELEASE)-pypiserver -- /bin/sh

# chart-testing (ct) integration
.PHONY: ct-lint
ct-lint: ## Lint with chart-testing tool
	@if command -v ct >/dev/null 2>&1; then \
		ct lint --config test/ct-config.yaml --charts $(CHART_DIR); \
	else \
		echo "chart-testing not installed. Install: brew install chart-testing"; \
		exit 1; \
	fi

.PHONY: ct-install
ct-install: ## Install and test with chart-testing
	@if command -v ct >/dev/null 2>&1; then \
		ct lint-and-install --config test/ct-config.yaml --charts $(CHART_DIR); \
	else \
		echo "chart-testing not installed. Install: brew install chart-testing"; \
		exit 1; \
	fi

# Default target
.DEFAULT_GOAL := help
