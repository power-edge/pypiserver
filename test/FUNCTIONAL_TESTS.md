# PyPI Server Functional Test Requirements

## What We're Actually Testing

We're deploying a **Python Package Index server**. The tests should verify **PyPI-specific functionality**, not just Kubernetes infrastructure.

## Core PyPI Operations

### 1. Package Upload
**What**: Upload a Python package using twine
**How**: `twine upload --repository-url http://pypi:8080/ dist/package-1.0.0.tar.gz`
**Success criteria**:
- HTTP 200/201 response
- Package appears in `/simple/` index
- Package file exists in storage

### 2. Package Download
**What**: Install a package using pip
**How**: `pip install --index-url http://pypi:8080/simple/ package==1.0.0`
**Success criteria**:
- HTTP 200 response for package metadata
- Package downloads successfully
- Package imports in Python

### 3. Package Listing
**What**: List available packages via /simple/ index
**How**: `curl http://pypi:8080/simple/`
**Success criteria**:
- Returns HTML with package links
- Shows all uploaded packages
- Package URLs are correct

### 4. Multiple Versions
**What**: Upload and manage multiple versions of same package
**How**: Upload v1.0.0, then v1.0.1, then v2.0.0
**Success criteria**:
- All versions appear in `/simple/package-name/`
- pip can install specific version
- pip installs latest version by default

### 5. Authentication (if enabled)
**What**: Verify auth works for uploads and downloads
**How**:
- Upload without auth → should fail
- Upload with auth → should succeed
- Download with/without auth based on config
**Success criteria**:
- 401/403 for unauthorized requests
- 200 for authorized requests

### 6. Storage Persistence
**What**: Packages survive pod restarts
**How**:
- Upload package
- Delete pod (trigger restart)
- Verify package still exists
**Success criteria**:
- Package still in `/simple/` index
- Package still downloadable

### 7. Concurrent Operations (HA mode)
**What**: Multiple clients can upload/download simultaneously
**How**:
- Upload 3 different packages in parallel
- Download 3 packages in parallel
**Success criteria**:
- All uploads succeed
- All downloads succeed
- No file corruption

## Test Implementation Priority

### P0 (Critical - Must Have)
✅ **Connection test** - PyPI server responds
✅ **Simple index test** - /simple/ endpoint works
⚠️ **Upload test** - Can upload a package
⚠️ **Download test** - Can install a package
⚠️ **List packages test** - Uploaded packages appear in index

### P1 (Important - Should Have)
⚠️ **Multiple versions test** - Can upload v1.0.0, v1.0.1, v2.0.0
⚠️ **Persistence test** - Packages survive pod restart
⚠️ **Storage test** - /packages directory accessible (DONE)

### P2 (Nice to Have)
❌ **Auth test** - Authentication works (if enabled)
❌ **Concurrent uploads** - Parallel operations work
❌ **Overwrite test** - Verify overwrite policy (--overwrite flag)
❌ **Large package test** - Can upload 100MB+ packages
❌ **Load test** - 100 sequential uploads/downloads

## Current Test Coverage

| Test | What It Checks | PyPI Relevance | Status |
|------|----------------|----------------|--------|
| `test-connection.yaml` | HTTP connectivity | Infrastructure | ✅ Done |
| `test-simple-index.yaml` | /simple/ endpoint exists | **PyPI Core** | ✅ Done |
| `test-storage.yaml` | /packages directory | Infrastructure | ✅ Done |
| **test-upload.yaml** | **Can upload package** | **PyPI Core** | ⚠️ **MISSING** |
| **test-download.yaml** | **Can install package** | **PyPI Core** | ⚠️ **MISSING** |
| **test-persistence.yaml** | **Packages survive restart** | **PyPI Core** | ⚠️ **MISSING** |

## Gaps in Current Testing

**Critical gaps:**
1. ❌ **No package upload test** - We don't verify twine upload works
2. ❌ **No package download test** - We don't verify pip install works
3. ❌ **No persistence test** - We don't verify packages survive restarts

**Why this matters:**
- Current tests only verify **infrastructure** (pod runs, /simple/ responds)
- They don't verify **functionality** (can I actually use this as a PyPI server?)
- A user could deploy this chart and discover uploads don't work!

## Proposed New Tests

### test-upload-package.yaml
```yaml
# Create a real Python package and upload it via twine
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "pypiserver.fullname" . }}-test-upload"
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-weight": "10"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: upload-test
      image: python:3.11-slim
      command: ['sh', '-c']
      args:
        - |
          # Install twine and build tools
          pip install --quiet twine build

          # Create minimal test package
          mkdir -p /tmp/testpkg/testpkg
          cat > /tmp/testpkg/pyproject.toml << 'EOF'
          [build-system]
          requires = ["setuptools"]
          build-backend = "setuptools.build_meta"
          [project]
          name = "helm-test-package"
          version = "1.0.0"
          EOF

          echo '__version__ = "1.0.0"' > /tmp/testpkg/testpkg/__init__.py

          # Build package
          cd /tmp/testpkg
          python -m build --quiet

          # Upload to PyPI server
          twine upload \
            --repository-url http://{{ include "pypiserver.fullname" . }}:{{ .Values.service.port }}/ \
            --disable-progress-bar \
            dist/*.tar.gz || exit 1

          echo "✓ Package upload successful!"
```

### test-download-package.yaml
```yaml
# Download and install the package we just uploaded
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "pypiserver.fullname" . }}-test-download"
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-weight": "20"  # Runs after upload
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: download-test
      image: python:3.11-slim
      command: ['sh', '-c']
      args:
        - |
          # Install package from PyPI server
          pip install --quiet \
            --index-url http://{{ include "pypiserver.fullname" . }}:{{ .Values.service.port }}/simple/ \
            helm-test-package==1.0.0 || exit 1

          # Verify import works
          python -c "import testpkg; print(f'Version: {testpkg.__version__}')" || exit 1

          echo "✓ Package download and import successful!"
```

### test-persistence.yaml
```yaml
# Verify packages survive pod restart
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{ include "pypiserver.fullname" . }}-test-persistence"
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-weight": "30"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: {{ include "pypiserver.fullname" . }}-test
      containers:
        - name: persistence-test
          image: bitnami/kubectl:latest
          command: ['sh', '-c']
          args:
            - |
              # Delete PyPI pod to trigger restart
              kubectl delete pod -l app.kubernetes.io/name=pypiserver --wait=false

              # Wait for new pod to be ready
              kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=pypiserver --timeout=120s

              # Verify package still exists
              kubectl run test-curl --rm -i --restart=Never --image=curlimages/curl -- \
                curl -f http://{{ include "pypiserver.fullname" . }}:{{ .Values.service.port }}/simple/helm-test-package/ || exit 1

              echo "✓ Package persisted across pod restart!"
```

## Test Execution Order

```
1. test-connection.yaml (weight: 0)
   ↓ Verify PyPI server is running

2. test-simple-index.yaml (weight: 5)
   ↓ Verify /simple/ endpoint works

3. test-storage.yaml (weight: 5)
   ↓ Verify storage is mounted

4. test-upload-package.yaml (weight: 10)
   ↓ Upload a test package

5. test-download-package.yaml (weight: 20)
   ↓ Download and install the package

6. test-persistence.yaml (weight: 30)
   ↓ Verify package survives restart
```

## What About S3 Backend?

For S3 CSI testing, we need to verify:

1. **S3 bucket connectivity** - Can PyPI connect to MinIO/S3?
2. **Package upload to S3** - Do packages end up in S3 bucket?
3. **Package download from S3** - Can pip download from S3-backed PyPI?

**Current gap**: Storage test only checks if `/packages` is mounted, not if S3 actually works!

## Summary

**What we have**: Infrastructure tests (pod runs, /simple/ responds, storage mounted)

**What we need**: Functional tests (upload works, download works, packages persist)

**Next steps**:
1. Add `test-upload-package.yaml`
2. Add `test-download-package.yaml`
3. Add `test-persistence.yaml` (with RBAC for kubectl access)
4. Update test values to ensure tests are enabled
5. Document that these tests verify **actual PyPI functionality**
