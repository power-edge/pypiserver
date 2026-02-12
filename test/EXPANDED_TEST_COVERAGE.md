# Expanded Test Coverage Plan

## Current Coverage Gaps

### What We Test Now ✅
- ✅ Package upload with `twine`
- ✅ Package download with `pip install`
- ✅ Package appears in `/simple/` index
- ✅ Package can be imported in Python
- ✅ Basic HTTP connectivity
- ✅ Storage accessibility

### What We DON'T Test Yet ❌

#### 1. Publishing Tools
- ❌ `uv publish` - Modern alternative to twine
- ❌ `poetry publish` - Another popular tool
- ❌ `hatch publish` - Modern build system
- ❌ Direct HTTP upload (REST API)

#### 2. Web UI
- ❌ Root URL serves HTML (not just 404)
- ❌ Package listing page works
- ❌ Package detail pages show versions
- ❌ UI is not broken (500 errors)
- ❌ Package download links work

#### 3. Package Variations
- ❌ Multiple versions (1.0.0, 1.0.1, 2.0.0)
- ❌ Pre-release versions (1.0.0rc1, 1.0.0b1)
- ❌ Binary wheels (.whl) vs source (.tar.gz)
- ❌ Multiple distributions (py3-none-any, py39-linux_x86_64)
- ❌ Large packages (>100MB)
- ❌ Packages with dependencies

#### 4. PyPI Server Features
- ❌ Package overwrite behavior (--overwrite flag)
- ❌ Package search (if supported)
- ❌ Fallback to PyPI.org (--disable-fallback)
- ❌ Version pinning (`pip install package==1.0.0`)
- ❌ Version ranges (`pip install "package>=1.0,<2.0"`)
- ❌ Latest version discovery

#### 5. Concurrent Operations
- ❌ Multiple simultaneous uploads
- ❌ Upload while downloading
- ❌ Multiple clients installing same package
- ❌ Thread safety / race conditions

#### 6. Error Handling
- ❌ Invalid package upload (malformed)
- ❌ Duplicate upload (same version twice)
- ❌ 404 for missing packages
- ❌ Auth failures (wrong credentials)
- ❌ Disk full scenarios
- ❌ Network timeout handling

#### 7. Different Installation Methods
- ❌ `pip install --extra-index-url` (fallback to PyPI.org)
- ❌ `pip install --index-url` (exclusive)
- ❌ `uv pip install`
- ❌ `poetry add`
- ❌ requirements.txt with private index

---

## Proposed Additions

### Priority 1: Critical Missing Tests

#### Test: uv publish
```yaml
# test-uv-publish.yaml
- name: uv-publish-test
  command: ['sh', '-c']
  args:
    - |
      # Install uv
      curl -LsSf https://astral.sh/uv/install.sh | sh

      # Create package
      uv init test-uv-package
      cd test-uv-package

      # Publish with uv
      uv publish --index-url http://pypi:8080/ || exit 1

      echo "✓ uv publish successful"
```

#### Test: Web UI
```yaml
# test-web-ui.yaml
- name: ui-test
  command: ['sh', '-c']
  args:
    - |
      # Test root URL
      curl -f http://pypi:8080/ || exit 1

      # Verify it's HTML (not JSON/plain text)
      curl -s http://pypi:8080/ | grep -q "<html>" || exit 1

      # Test package listing page
      curl -f http://pypi:8080/simple/ || exit 1

      # Verify package appears in UI
      curl -s http://pypi:8080/simple/ | grep -q "helm-test-package" || exit 1

      # Test package detail page
      curl -f http://pypi:8080/simple/helm-test-package/ || exit 1

      # Verify download link exists
      curl -s http://pypi:8080/simple/helm-test-package/ | \
        grep -q "helm_test_package-1.0.0.tar.gz" || exit 1

      echo "✓ Web UI tests passed"
```

#### Test: Multiple Versions
```yaml
# test-multiple-versions.yaml
- name: multi-version-test
  command: ['sh', '-c']
  args:
    - |
      # Upload v1.0.0, v1.0.1, v2.0.0
      for version in 1.0.0 1.0.1 2.0.0; do
        # Create package with version
        mkdir -p /tmp/pkg-$version/pkg
        cat > /tmp/pkg-$version/pyproject.toml << EOF
      [project]
      name = "multi-version-test"
      version = "$version"
      EOF

        cd /tmp/pkg-$version
        python -m build
        twine upload --repository-url http://pypi:8080/ dist/*
      done

      # Verify all versions in index
      curl -s http://pypi:8080/simple/multi-version-test/ | grep -q "1.0.0" || exit 1
      curl -s http://pypi:8080/simple/multi-version-test/ | grep -q "1.0.1" || exit 1
      curl -s http://pypi:8080/simple/multi-version-test/ | grep -q "2.0.0" || exit 1

      # Install specific version
      pip install --index-url http://pypi:8080/simple/ multi-version-test==1.0.1

      # Verify correct version installed
      python -c "import pkg; assert pkg.__version__ == '1.0.1'"

      # Install latest (should be 2.0.0)
      pip install --index-url http://pypi:8080/simple/ --upgrade multi-version-test
      python -c "import pkg; assert pkg.__version__ == '2.0.0'"

      echo "✓ Multiple versions test passed"
```

#### Test: Concurrent Uploads
```yaml
# test-concurrent-uploads.yaml
- name: concurrent-test
  command: ['sh', '-c']
  args:
    - |
      # Create 5 different packages
      for i in 1 2 3 4 5; do
        mkdir -p /tmp/pkg$i/pkg$i
        cat > /tmp/pkg$i/pyproject.toml << EOF
      [project]
      name = "concurrent-pkg-$i"
      version = "1.0.0"
      EOF
        cd /tmp/pkg$i
        python -m build
      done

      # Upload all 5 packages in parallel (background jobs)
      for i in 1 2 3 4 5; do
        (cd /tmp/pkg$i && twine upload --repository-url http://pypi:8080/ dist/*) &
      done

      # Wait for all uploads to complete
      wait

      # Verify all packages uploaded successfully
      for i in 1 2 3 4 5; do
        curl -f http://pypi:8080/simple/concurrent-pkg-$i/ || exit 1
      done

      echo "✓ Concurrent uploads successful"
```

### Priority 2: Docker Compose Testing

Create standalone `docker-compose.test.yaml`:

```yaml
# docker-compose.test.yaml
version: '3.8'

services:
  pypi:
    image: pypiserver/pypiserver:v2.0.1
    ports:
      - "8080:8080"
    volumes:
      - pypi-packages:/data/packages
    command: run -p 8080 -a . /data/packages

  test-runner:
    image: python:3.11-slim
    depends_on:
      - pypi
    volumes:
      - ./test/fixtures/test-package:/workspace
    environment:
      - PYPI_URL=http://pypi:8080
    command: >
      sh -c "
        pip install twine build &&
        cd /workspace &&
        python -m build &&
        twine upload --repository-url $$PYPI_URL dist/* &&
        pip install --index-url $$PYPI_URL/simple/ test-package &&
        python -c 'import test_package; print(test_package.hello())'
      "

volumes:
  pypi-packages:
```

**Usage:**
```bash
# Run standalone test
docker compose -f docker-compose.test.yaml up --abort-on-container-exit

# Clean up
docker compose -f docker-compose.test.yaml down -v
```

### Priority 3: Installation Methods

#### Test: Different pip install patterns
```yaml
# test-install-methods.yaml
- name: install-methods-test
  command: ['sh', '-c']
  args:
    - |
      PYPI_URL="http://pypi:8080"

      # Method 1: --index-url (exclusive)
      pip install --index-url $PYPI_URL/simple/ helm-test-package
      pip uninstall -y helm-test-package

      # Method 2: --extra-index-url (fallback to PyPI.org)
      pip install --extra-index-url $PYPI_URL/simple/ helm-test-package
      pip uninstall -y helm-test-package

      # Method 3: pip config
      pip config set global.index-url $PYPI_URL/simple/
      pip install helm-test-package
      pip config unset global.index-url
      pip uninstall -y helm-test-package

      # Method 4: requirements.txt
      echo "helm-test-package==1.0.0" > /tmp/requirements.txt
      pip install --index-url $PYPI_URL/simple/ -r /tmp/requirements.txt

      echo "✓ All installation methods work"
```

#### Test: uv install
```yaml
# test-uv-install.yaml
- name: uv-install-test
  command: ['sh', '-c']
  args:
    - |
      # Install uv
      curl -LsSf https://astral.sh/uv/install.sh | sh
      export PATH="$HOME/.cargo/bin:$PATH"

      # Install via uv
      uv pip install \
        --index-url http://pypi:8080/simple/ \
        helm-test-package

      # Verify
      uv pip list | grep helm-test-package || exit 1

      echo "✓ uv install successful"
```

### Priority 4: Error Scenarios

#### Test: Auth failures
```yaml
# test-auth-errors.yaml (only if auth enabled)
{{- if .Values.auth.enabled }}
- name: auth-error-test
  command: ['sh', '-c']
  args:
    - |
      # Should fail without credentials
      twine upload --repository-url http://pypi:8080/ dist/* 2>&1 | \
        grep -q "401\|403" || exit 1

      # Should fail with wrong credentials
      TWINE_USERNAME=wrong TWINE_PASSWORD=wrong \
      twine upload --repository-url http://pypi:8080/ dist/* 2>&1 | \
        grep -q "401\|403" || exit 1

      echo "✓ Auth errors work correctly"
{{- end }}
```

#### Test: 404 handling
```yaml
# test-404-handling.yaml
- name: not-found-test
  command: ['sh', '-c']
  args:
    - |
      # Should return 404 for non-existent package
      curl -s -o /dev/null -w "%{http_code}" \
        http://pypi:8080/simple/does-not-exist/ | \
        grep -q "404" || exit 1

      # pip install should fail gracefully
      pip install --index-url http://pypi:8080/simple/ \
        does-not-exist-package 2>&1 | \
        grep -q "No matching distribution" || exit 1

      echo "✓ 404 handling works"
```

---

## Recommended Test Additions

### Immediate (Add Now)

1. **test-web-ui.yaml** - Validate web interface works
2. **test-uv-publish.yaml** - Test modern publishing tool
3. **test-multiple-versions.yaml** - Version management
4. **docker-compose.test.yaml** - Standalone testing

### Short-term (Next Sprint)

5. **test-concurrent-uploads.yaml** - Thread safety
6. **test-install-methods.yaml** - Various pip patterns
7. **test-s3-auth.yaml** - Missing matrix config
8. **test-s3-ha.yaml** - Missing matrix config

### Medium-term (Nice to Have)

9. **test-large-packages.yaml** - 100MB+ packages
10. **test-pre-release.yaml** - Alpha/beta/rc versions
11. **test-binary-wheels.yaml** - .whl distributions
12. **test-error-scenarios.yaml** - Auth errors, 404s

---

## CI Integration Strategy

Update `.github/workflows/test.yaml`:

```yaml
jobs:
  # Before tests: Build test package
  prepare:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build test package
        run: |
          cd test/fixtures/test-package
          python -m build
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: test-package
          path: test/fixtures/test-package/dist/

  # Run all test configurations in parallel
  test-matrix:
    needs: prepare
    strategy:
      matrix:
        config:
          - minimal
          - local-pv-auth
          - minio-s3
          - ha-config
          - s3-auth       # NEW
          - s3-ha         # NEW
    runs-on: ubuntu-latest
    steps:
      - name: Download test package
        uses: actions/download-artifact@v4

      - name: Run test-${{ matrix.config }}
        run: make test-${{ matrix.config }}

  # Standalone Docker Compose test
  test-docker-compose:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Test with Docker Compose
        run: |
          docker compose -f docker-compose.test.yaml up \
            --abort-on-container-exit \
            --exit-code-from test-runner

  # Only publish if all tests pass
  publish:
    needs: [test-matrix, test-docker-compose]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Package and publish chart
        run: make package
```

---

## Makefile Updates

```makefile
# Add new test targets

.PHONY: test-web-ui
test-web-ui: ## Test web UI accessibility
	@echo "Testing web UI..."
	helm test pypi -n $(TEST_NAMESPACE) --filter name=web-ui --logs

.PHONY: test-uv
test-uv: ## Test uv publish/install
	@echo "Testing uv..."
	helm test pypi -n $(TEST_NAMESPACE) --filter name=uv --logs

.PHONY: test-docker-compose
test-docker-compose: ## Test with Docker Compose (no K8s)
	docker compose -f docker-compose.test.yaml up --abort-on-container-exit
	docker compose -f docker-compose.test.yaml down -v

.PHONY: test-comprehensive
test-comprehensive: test-all test-docker-compose ## Run all tests including Docker Compose
	@echo "✓ Comprehensive test suite passed"
```

---

## Summary

### Current Coverage
- ✅ 4 Helm test configurations
- ✅ 5 functional tests (connection, index, storage, upload, download)
- ✅ GitHub Actions CI

### Recommended Additions
- 🎯 **Priority 1**: Web UI, uv publish, multiple versions, Docker Compose
- 🎯 **Priority 2**: Concurrent uploads, S3+Auth, S3+HA configs
- 🎯 **Priority 3**: Error scenarios, large packages, pre-releases

### Impact
- **Before**: Basic "does it work" testing
- **After**: Production-ready validation of real-world scenarios

### Next Steps
1. Add `test-web-ui.yaml` (validates HTML interface)
2. Add `test-uv-publish.yaml` (modern tool support)
3. Add `docker-compose.test.yaml` (standalone testing)
4. Update CI to run tests before publishing
5. Add missing matrix configs (S3+Auth, S3+HA)

Would you like me to implement these additions?
