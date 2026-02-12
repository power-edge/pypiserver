# PyPI Helm Chart Test Matrix

## Test Coverage Grid

### Current Test Configurations

| Test Config | Storage | Auth | Ingress | Replicas | Purpose |
|-------------|---------|------|---------|----------|---------|
| **test-minimal** | Local PV | ❌ Off | ❌ Off | 1 | Quick smoke test |
| **test-local-pv-auth** | Local PV | ✅ On | ✅ On | 1 | Auth validation |
| **test-minio-s3** | S3 CSI | ❌ Off | ✅ On | 1 | S3 integration |
| **test-ha-config** | Local PV | ✅ On | ✅ On | 2+ | HA resilience |

### Test Matrix Coverage

```
                    Storage Backend
                    ┌─────────┬─────────┐
                    │ Local PV│  S3 CSI │
         ┌──────────┼─────────┼─────────┤
         │ No Auth  │    ✅   │    ✅   │  Single Replica
Auth     │ 1 replica│ minimal │ minio-s3│
         ├──────────┼─────────┼─────────┤
         │ Auth     │    ✅   │    ❌   │  Single Replica
         │ 1 replica│local-pv │ missing │
         │          │  -auth  │         │
─────────┼──────────┼─────────┼─────────┤
         │ No Auth  │    ❌   │    ❌   │  Multi Replica (HA)
HA       │ 2+ replic│ missing │ missing │
         ├──────────┼─────────┼─────────┤
         │ Auth     │    ✅   │    ❌   │  Multi Replica (HA)
         │ 2+ replic│ha-config│ missing │
         └──────────┴─────────┴─────────┘
```

### What We're Testing

**✅ = Tested   ❌ = Not Tested**

| Configuration | Local PV | S3 CSI |
|---------------|----------|--------|
| **Single replica, no auth** | ✅ test-minimal | ✅ test-minio-s3 |
| **Single replica, with auth** | ✅ test-local-pv-auth | ❌ **missing** |
| **Multi replica, no auth** | ❌ **missing** | ❌ **missing** |
| **Multi replica, with auth** | ✅ test-ha-config | ❌ **missing** |

### Gaps in Coverage

**Critical gaps:**
1. ❌ **S3 CSI + Auth** - Important production scenario
2. ❌ **S3 CSI + HA** - S3 supports ReadWriteMany, this should work!

**Less critical:**
3. ❌ Local PV + HA + No Auth - Rare scenario (HA without auth?)

### Recommended: Complete the Grid

Add these test configurations:

#### test-s3-auth.yaml
```yaml
# S3 CSI with authentication
storage:
  backend: s3
  s3:
    enabled: true
    csi:
      enabled: true

auth:
  enabled: true

replicaCount: 1
```

#### test-s3-ha.yaml
```yaml
# S3 CSI with HA (takes advantage of ReadWriteMany)
storage:
  backend: s3
  s3:
    enabled: true
    csi:
      enabled: true

auth:
  enabled: true

replicaCount: 2

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 4
```

### Test Execution Matrix (CI)

For CI, we run these in parallel:

```
┌─────────────────────────────────────────┐
│           GitHub Actions Jobs           │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────┐  ┌────────────┐          │
│  │   Lint   │  │ Test-Minimal│          │
│  │          │  │ (local, no  │          │
│  │          │  │   auth)     │          │
│  └──────────┘  └────────────┘          │
│       │              │                  │
│       │        ┌─────┴──────┐          │
│       │        │            │          │
│  ┌────▼────┐  ┌▼────────┐ ┌▼────────┐ │
│  │Test-Auth│  │Test-HA  │ │Test-S3  │ │
│  │(local+  │  │(local+  │ │(minio+  │ │
│  │ auth)   │  │ auth+HA)│ │ s3-csi) │ │
│  └─────────┘  └─────────┘ └─────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

### What Each Test Validates

| Test | Infrastructure | Functional | Validates |
|------|----------------|------------|-----------|
| **test-minimal** | Pod runs, service exists | Upload, download | Basic PyPI works |
| **test-local-pv-auth** | Auth secret, ingress | Auth upload, auth download | Auth works |
| **test-minio-s3** | MinIO, S3 CSI, PVC | Upload to S3, download from S3 | S3 backend works |
| **test-ha-config** | 2+ pods, PDB, anti-affinity | Upload, download, pod failure | HA resilience |

### Functional Test Coverage

All test configurations run the same functional tests:

| Test | What It Does | Pass Criteria |
|------|--------------|---------------|
| `test-connection` | HTTP connectivity | PyPI responds |
| `test-simple-index` | /simple/ endpoint | Index returns HTML |
| `test-storage` | Storage accessible | /packages mounted |
| `test-upload-package` | twine upload | Package uploaded, in index |
| `test-download-package` | pip install | Package downloaded, imports |

**Key insight**: Every configuration validates **upload + download works** - the core PyPI operations!

### Local Testing Workflow

```bash
# Test all configurations locally
make test-cluster-create   # Create k3d cluster
make test-setup           # Install ingress-nginx

# Run each test configuration
make test-minimal         # ✅ Quick smoke test
make test-clean

make test-local-pv-auth   # ✅ Auth validation
make test-clean

make test-ha-config       # ✅ HA resilience
make test-clean

make test-setup-minio     # Install MinIO
make test-minio-s3        # ✅ S3 integration
make test-clean

# Delete cluster
make test-cluster-delete
```

### What We Should Add

To have **complete coverage**, add:

1. **test-s3-auth.yaml** - S3 CSI with authentication
2. **test-s3-ha.yaml** - S3 CSI with HA (2+ replicas)

This would give us:

```
Complete Coverage Grid:
                    Storage Backend
                    ┌─────────┬─────────┐
                    │ Local PV│  S3 CSI │
         ┌──────────┼─────────┼─────────┤
         │ No Auth  │    ✅   │    ✅   │
Auth     │ 1 replica│ minimal │ minio-s3│
         ├──────────┼─────────┼─────────┤
         │ Auth     │    ✅   │    ✅   │  ← NEW!
         │ 1 replica│local-pv │s3-auth  │
         │          │  -auth  │         │
─────────┼──────────┼─────────┼─────────┤
         │ Auth     │    ✅   │    ✅   │  ← NEW!
         │ 2+ replic│ha-config│ s3-ha   │
         └──────────┴─────────┴─────────┘
```

### Production Deployment Scenarios

Real-world usage maps to our tests:

| Scenario | Test Config | Notes |
|----------|-------------|-------|
| **Dev/Test** | test-minimal | Quick setup, no security |
| **Small Team** | test-local-pv-auth | Simple, persistent |
| **Production (cost-conscious)** | test-s3-auth | S3 storage, auth |
| **Production (HA)** | test-s3-ha | S3 + multiple replicas |

### Summary

**Current status:**
- ✅ 4 test configurations
- ✅ 5 functional tests per configuration
- ✅ CI automation ready
- ⚠️ Missing 2 important scenarios (S3+Auth, S3+HA)

**Coverage:**
- ✅ Storage: Local PV, S3 CSI
- ✅ Auth: Enabled, Disabled
- ✅ HA: Single replica, Multi replica
- ✅ Functional: Upload, Download, Persistence

**Recommendation:**
- Add `test-s3-auth.yaml` and `test-s3-ha.yaml` for complete coverage
- Keep minimal, local-pv-auth, ha-config, and minio-s3 as-is
- These 6 configs would cover all important production paths
