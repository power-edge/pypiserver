# CLAUDE.md — power-edge/pypi

Guidance for Claude Code when working in this repository.

## Project Overview

Self-hosted private PyPI server packaged as a production-ready **Helm chart**.
The chart wraps [pypiserver](https://github.com/pypiserver/pypiserver) v2.0.1 with
Kubernetes-native features: autoscaling, S3-backed storage via CSI driver, cert-manager
TLS, Prometheus metrics, and full Helm test coverage.

**Goal**: Publish the chart to GitHub Pages / ArtifactHub so `power-edge` internal
packages (e.g. `pymlb-statsapi`) can be installed from a private PyPI index.

---

## Repository Layout

```
power-edge/pypi/
├── helm/                         # The Helm chart (primary artifact)
│   ├── Chart.yaml                # Chart metadata: name=pypiserver, version=1.0.0
│   ├── values.yaml               # Default values (local PV, auth enabled)
│   ├── values-hetzner-s3.yaml    # Example: Hetzner Object Storage via CSI-S3
│   ├── README.md                 # User-facing chart documentation
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── pvc.yaml              # Local PV claim
│       ├── hpa.yaml              # HorizontalPodAutoscaler
│       ├── auth-secret.yaml      # htpasswd secret
│       ├── s3-secret.yaml        # S3 credentials secret
│       ├── storageclass.yaml     # CSI-S3 StorageClass
│       └── tests/                # 9 helm test pods
│           ├── test-connection.yaml
│           ├── test-simple-index.yaml
│           ├── test-upload-package.yaml
│           ├── test-download-package.yaml
│           ├── test-web-ui.yaml
│           ├── test-storage.yaml
│           ├── test-multiple-versions.yaml
│           ├── test-concurrent-uploads.yaml
│           └── test-uv-publish.yaml
├── test/
│   ├── ct-config.yaml            # chart-testing tool config
│   ├── fixtures/
│   │   ├── minio-deployment.yaml # MinIO for S3 CI tests
│   │   └── test-package/         # Minimal Python package for upload tests
│   └── values/                   # Per-scenario test value files
│       ├── test-minimal.yaml     # No auth, no ingress, local PV
│       ├── test-local-pv-auth.yaml
│       ├── test-ha-config.yaml
│       ├── test-minio-s3.yaml
│       ├── test-s3-auth.yaml
│       └── test-s3-ha.yaml
├── .github/workflows/
│   ├── test.yaml                 # CI: lint + 6 K8s job matrix + docker-compose job
│   └── release.yaml              # CD: chart-releaser → GitHub Pages
├── docker-compose.test.yaml      # Standalone test (no K8s required)
├── Makefile                      # Dev commands (see Quick Reference below)
└── CLAUDE.md                     # This file
```

---

## Architecture Decisions

### Storage: CSI-S3 (recommended) vs Local PV

| Mode | Use case | Notes |
|------|----------|-------|
| Local PV | Dev / single-node | `ReadWriteOnce` — no HA |
| CSI-S3 (yandex-cloud/k8s-csi-s3) | Production | `ReadWriteMany`, unlimited, durable |

CSI-S3 uses [geesefs](https://github.com/yuri-rs/geesefs) as the FUSE backend.
**Limitation**: k3d CI runners lack FUSE support, so CSI is disabled in CI with
`--set storage.s3.csi.enabled=false`. Real CSI tests require a cluster with
privileged nodes (Hetzner / AWS).

### Authentication

htpasswd via bcrypt (`-B` flag). The chart mounts the htpasswd file as a Secret.
When `auth.enabled=false`, pypiserver is started with `-P . -a .` to prevent crash.

### HA

Requires S3 CSI storage (ReadWriteMany). HPA is defined in `helm/templates/hpa.yaml`.
PodDisruptionBudget available via `podDisruptionBudget.enabled=true`.

---

## Current Status

| Area | Status | Notes |
|------|--------|-------|
| Chart templates | ✅ Done | All 9 templates complete |
| Helm tests (9 pods) | ✅ Done | Connection, index, upload, download, web-ui, storage, versions, concurrent, uv-publish |
| CI: lint job | ✅ Done | helm lint + ct lint |
| CI: test-minimal | ✅ Done | Passing |
| CI: test-auth | ✅ Done | Passing |
| CI: test-ha | ✅ Done | Passing |
| CI: test-minio-s3 | ✅ Done | CSI disabled in CI (FUSE limitation) |
| CI: test-s3-auth | ✅ Done | CSI disabled in CI |
| CI: test-s3-ha | ✅ Done | CSI disabled in CI |
| CI: docker-compose | ✅ Done | Standalone smoke test |
| Release pipeline | ✅ Done | chart-releaser → gh-pages branch |
| ArtifactHub listing | ⬜ TODO | Submit chart metadata to artifacthub.io |
| values.schema.json | ⬜ TODO | JSON Schema for values validation |
| Grafana dashboard | ⬜ TODO | ConfigMap with dashboard JSON |
| NetworkPolicy template | ⬜ TODO | Restrict ingress/egress |
| LDAP auth | ⬜ TODO | Stub exists in values.yaml, no template yet |

---

## Known Issues / Decisions Log

- **CSI-S3 in CI**: geesefs requires FUSE (privileged node). k3d containers don't
  support it. CI overrides `storage.s3.csi.enabled=false` and uses emptyDir.
  Full CSI path is tested only in real clusters.

- **htpasswd hash in test values**: Test values use a pre-computed bcrypt hash for
  user `pypi` / password `test1234`. Re-generate with:
  ```bash
  docker run --rm httpd:alpine htpasswd -nB pypi
  ```

- **pypiserver crash without `-P . -a .`**: When auth is disabled, pypiserver v2
  requires explicit `-P . -a .` flags or it exits. Handled in `deployment.yaml`.

- **HPA and replicaCount**: When HPA is enabled, `replicaCount` in the Deployment
  is intentionally not set (HPA manages it). The CI HA test waits up to 2 minutes
  for HPA to bring replicas to minReplicas.

---

## Quick Reference

```bash
# Validate chart
make lint           # helm lint
make validate       # lint + template rendering for all value files

# Local K8s testing (requires k3d)
make test-cluster-create    # Create k3d cluster 'pypi-test'
make test-minimal           # Install minimal config and run helm tests
make test-local-pv-auth     # Local PV + htpasswd auth
make test-ha-config         # HA with HPA
make test-minio-s3          # S3 CSI via MinIO
make test-s3-auth           # S3 + auth
make test-s3-ha             # S3 + HA
make test-clean             # Uninstall release and delete namespace
make test-cluster-delete    # Delete k3d cluster

# Run all 6 K8s configs end-to-end
make test-all

# Standalone (no K8s)
make test-docker-compose

# Package and publish
make package        # Builds dist/pypiserver-1.0.0.tgz
make publish-check  # Pre-publish checklist
```

## Deployment to Hetzner (production)

```bash
# 1. Install CSI-S3 driver on cluster
kubectl apply -f https://raw.githubusercontent.com/yandex-cloud/k8s-csi-s3/master/deploy/kubernetes/provisioner.yaml
kubectl apply -f https://raw.githubusercontent.com/yandex-cloud/k8s-csi-s3/master/deploy/kubernetes/driver.yaml
kubectl apply -f https://raw.githubusercontent.com/yandex-cloud/k8s-csi-s3/master/deploy/kubernetes/csi-s3.yaml

# 2. Install chart with Hetzner Object Storage
helm install pypi ./helm \
  -f helm/values-hetzner-s3.yaml \
  --set storage.s3.accessKeyId=$HETZNER_S3_KEY \
  --set storage.s3.secretAccessKey=$HETZNER_S3_SECRET \
  --set ingress.hosts[0].host=pypi.your-domain.com \
  --namespace pypi \
  --create-namespace

# 3. Verify
helm test pypi -n pypi
```

## Using the Private PyPI

```bash
# ~/.pypirc
[distutils]
index-servers = private
[private]
repository = https://pypi.your-domain.com
username = pypi
password = <password>

# Publish a package
uv publish --publish-url https://pypi.your-domain.com pymlb_statsapi-*.whl

# Install from private PyPI
uv pip install --index-url https://pypi:pass@pypi.your-domain.com/simple/ pymlb-statsapi
pip install --index-url https://pypi:pass@pypi.your-domain.com/simple/ pymlb-statsapi
```

## Next Steps

1. **ArtifactHub**: Add `artifacthub-repo.yml` to repo root and register at artifacthub.io
2. **values.schema.json**: Generate with `make schema-gen` (requires `helm-schema` plugin)
3. **Grafana dashboard**: Create ConfigMap with pypiserver metrics dashboard
4. **NetworkPolicy**: Add optional `NetworkPolicy` template to restrict pod-level traffic
5. **Real CSI test**: Run `make test-minio-s3` against a real cluster (not k3d) to validate
   full FUSE mount path end-to-end
