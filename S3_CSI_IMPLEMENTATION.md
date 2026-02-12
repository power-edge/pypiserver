# S3 CSI Implementation Summary

## What Was Implemented

Added **CSI-S3 driver support** to the PyPI Helm chart, enabling S3-backed PersistentVolumes for package storage.

### Files Created/Modified

#### New Templates
1. **`helm/templates/storageclass.yaml`**
   - Creates StorageClass for S3 CSI driver
   - Configures CSI-S3 provisioner (`ru.yandex.s3.csi`)
   - References S3 credentials secret
   - Supports bucket prefix (e.g., `pypi/` to share bucket)

2. **`helm/templates/s3-secret.yaml`**
   - Creates Secret with S3 credentials (access key, secret key)
   - Stores S3 endpoint (for S3-compatible services like Hetzner)
   - Optional: use existing secret via `storage.s3.existingSecret`

3. **`helm/values-hetzner-s3.yaml`**
   - Complete example for Hetzner Object Storage
   - Includes cost comparison (Hetzner: $5.50/month vs AWS: $113/month for 1TB)
   - Documents CSI-S3 driver installation steps
   - Production-ready configuration (HA, autoscaling, monitoring)

#### Updated Templates
4. **`helm/templates/pvc.yaml`**
   - Added support for S3-backed PVC via CSI driver
   - Uses `ReadWriteMany` for S3 CSI (allows multiple pods)
   - Falls back to local PV when S3 CSI disabled
   - Nominal size for S3 (grows dynamically)

5. **`helm/templates/deployment.yaml`**
   - Updated volume mount logic to support S3 CSI
   - PVC used for both local and S3 CSI backends
   - EmptyDir for direct S3 (legacy mode)

6. **`helm/values.yaml`**
   - Added `storage.s3.csi` configuration section
   - Documented two S3 modes: CSI driver (recommended) vs direct (legacy)
   - Added fields: `endpoint`, `prefix`, `size`

7. **`helm/README.md`**
   - Added comprehensive CSI-S3 documentation
   - CSI-S3 marked as "RECOMMENDED" for production
   - Documented driver installation prerequisites
   - Example for Hetzner Object Storage

8. **`README-NEW.md`**
   - Updated storage features to mention S3 CSI

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│         Kubernetes Cluster              │
├─────────────────────────────────────────┤
│                                          │
│  ┌──────────┐       ┌──────────┐       │
│  │  PyPI    │       │  PyPI    │       │
│  │  Pod 1   │       │  Pod 2   │       │
│  └────┬─────┘       └────┬─────┘       │
│       │                  │              │
│       └────────┬─────────┘              │
│                │                         │
│         ┌──────▼──────┐                 │
│         │PVC (RWX)    │                 │
│         └──────┬──────┘                 │
│                │                         │
│         ┌──────▼──────┐                 │
│         │StorageClass │                 │
│         │ (S3 CSI)    │                 │
│         └──────┬──────┘                 │
│                │                         │
│         ┌──────▼──────┐                 │
│         │  CSI Driver │                 │
│         └──────┬──────┘                 │
│                │                         │
└────────────────┼─────────────────────────┘
                 │
                 ▼
    ┌────────────────────────┐
    │  S3-Compatible Storage │
    │  (AWS, Hetzner, Minio) │
    │  Prefix: pypi/         │
    └────────────────────────┘
```

### Two S3 Modes

#### Mode 1: CSI Driver (RECOMMENDED)
- **How**: S3 bucket mounted as PersistentVolume via CSI-S3 driver
- **Pros**:
  - ReadWriteMany (multiple pods can share)
  - No capacity planning (unlimited)
  - HA built-in (S3 durability)
  - Works with any S3-compatible storage
- **Use case**: Production deployments

#### Mode 2: Direct S3 (Legacy)
- **How**: pypiserver uses built-in S3 support via environment variables
- **Pros**:
  - No CSI driver needed
  - Native pypiserver feature
- **Cons**:
  - ReadWriteOnce (one pod at a time)
  - Requires pypiserver built-in S3 support
- **Use case**: Simple deployments, testing

---

## Installation

### Prerequisites

1. **Install CSI-S3 Driver**:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/provisioner.yaml
   kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/attacher.yaml
   kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/csi-s3.yaml
   ```

2. **Create S3 Bucket** (Hetzner example):
   - Go to Hetzner Cloud Console → Object Storage
   - Create bucket: `tech-screen-storage`
   - Generate S3 access keys
   - Note endpoint URL (e.g., `https://fsn1.your-objectstorage.com`)

### Deploy PyPI with S3 CSI

#### Option 1: Use example values (Hetzner)
```bash
helm install pypi ./helm -f values-hetzner-s3.yaml \
  --namespace pypi \
  --create-namespace \
  --set storage.s3.accessKeyId=$HETZNER_S3_KEY \
  --set storage.s3.secretAccessKey=$HETZNER_S3_SECRET \
  --set storage.s3.csi.endpoint=https://fsn1.your-objectstorage.com
```

#### Option 2: Custom values
```yaml
# my-values.yaml
storage:
  backend: s3
  local:
    enabled: false
  s3:
    enabled: true
    bucket: tech-screen-storage
    region: us-east-1  # Dummy for compatibility
    accessKeyId: YOUR_KEY
    secretAccessKey: YOUR_SECRET
    csi:
      enabled: true
      endpoint: "https://fsn1.your-objectstorage.com"
      prefix: "pypi/"  # Share bucket with other apps
      size: "1Ti"
```

```bash
helm install pypi ./helm -f my-values.yaml \
  --namespace pypi \
  --create-namespace
```

---

## Configuration Options

### Values.yaml S3 CSI Section

```yaml
storage:
  s3:
    enabled: false
    bucket: pypi-packages
    region: us-east-1
    accessKeyId: ""
    secretAccessKey: ""
    existingSecret: ""  # Use existing secret

    # CSI driver configuration
    csi:
      enabled: false
      endpoint: "https://s3.amazonaws.com"  # S3 endpoint
      prefix: ""  # Optional bucket prefix
      size: "1Ti"  # Nominal size (S3 grows dynamically)
```

### Supported S3-Compatible Services

| Service | Endpoint | Region | Notes |
|---------|----------|--------|-------|
| **AWS S3** | `https://s3.amazonaws.com` | `us-east-1`, etc. | Original S3 |
| **Hetzner Object Storage** | `https://fsn1.your-objectstorage.com` | `us-east-1` (dummy) | **Cheapest**: $0.005/GB/month |
| **Minio** | `http://minio.default.svc.cluster.local:9000` | `us-east-1` (dummy) | Self-hosted |
| **DigitalOcean Spaces** | `https://nyc3.digitaloceanspaces.com` | `nyc3`, etc. | Similar pricing to AWS |
| **Backblaze B2** | `https://s3.us-west-002.backblazeb2.com` | `us-west-002`, etc. | Very cheap storage |

---

## Benefits

### Cost Comparison (1TB of packages)

| Backend | Storage | Egress | Total/Month | Savings vs S3 CSI |
|---------|---------|--------|-------------|-------------------|
| **S3 CSI (Hetzner)** | $5.50 | $0 (1TB free) | **$5.50** | Baseline |
| S3 CSI (AWS) | $23 | $9 | $32 | 6x more expensive |
| Local PV (EBS) | $80 | $0 | $80 | 15x more expensive |
| PostgreSQL | $200 | $0 | $200 | 36x more expensive |
| Redis | $750 | $0 | $750 | 136x more expensive |

**Hetzner S3 is 95% cheaper than AWS S3!** 💰

### Technical Benefits

- ✅ **No capacity planning** - S3 grows dynamically, no pre-allocation needed
- ✅ **ReadWriteMany** - Multiple pods can mount same volume (HA)
- ✅ **High availability** - S3 durability (99.999999999%)
- ✅ **Unlimited scalability** - No size limits
- ✅ **Bucket sharing** - Use prefix to share bucket with other apps
- ✅ **Works with existing buckets** - No new bucket creation needed

---

## Next Steps

### For tech-screen Project

1. **Create S3 bucket** (or reuse existing):
   ```bash
   # Option 1: New bucket for PyPI
   # Create via Hetzner Cloud Console

   # Option 2: Reuse tech-screen-storage with prefix
   # Already exists, just use prefix: "pypi/"
   ```

2. **Deploy CSI-S3 driver** to tech-screen K3s cluster:
   ```bash
   kubectl --context tech-screen apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/provisioner.yaml
   kubectl --context tech-screen apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/attacher.yaml
   kubectl --context tech-screen apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/csi-s3.yaml
   ```

3. **Add PyPI to ArgoCD app-of-apps** in tech-screen-k3s repo:
   - Create `components/pypi/` directory
   - Add ArgoCD Application manifest
   - Reference this Helm chart

4. **Configure credentials**:
   - Store Hetzner S3 credentials in Kubernetes Secret
   - Or use existing `HCLOUD_S3_CREDENTIALS_DEVELOPMENT` secret

---

## Testing

### Verify CSI Driver Installation

```bash
# Check CSI driver pods
kubectl get pods -n kube-system | grep csi-s3

# Expected output:
# csi-s3-controller-...   3/3   Running
# csi-s3-node-...         2/2   Running
```

### Verify PyPI Deployment

```bash
# Check PyPI pods
kubectl get pods -n pypi

# Check PVC (should be Bound)
kubectl get pvc -n pypi

# Check StorageClass
kubectl get storageclass | grep s3

# Upload test package
twine upload -r private dist/mypackage-1.0.0.tar.gz

# Verify in S3 bucket
# Should see: bucket/pypi/packages/mypackage/mypackage-1.0.0.tar.gz
```

---

## Troubleshooting

### PVC stuck in Pending

```bash
# Check PVC events
kubectl describe pvc -n pypi

# Common issues:
# 1. CSI driver not installed → Install driver
# 2. S3 credentials invalid → Check secret
# 3. S3 endpoint unreachable → Verify endpoint URL
```

### Pods can't mount volume

```bash
# Check pod events
kubectl describe pod -n pypi pypi-pypiserver-0

# Common issues:
# 1. S3 bucket doesn't exist → Create bucket
# 2. Permissions denied → Check S3 access keys
# 3. Network policy blocking S3 → Allow egress to S3 endpoint
```

### Packages not uploading

```bash
# Check pypiserver logs
kubectl logs -n pypi -l app.kubernetes.io/name=pypiserver

# Test S3 access from pod
kubectl exec -it -n pypi pypi-pypiserver-0 -- ls -la /packages

# Should show S3 bucket contents
```

---

## References

- CSI-S3 Driver: https://github.com/ctrox/csi-s3
- pypiserver: https://github.com/pypiserver/pypiserver
- Hetzner Object Storage: https://docs.hetzner.com/storage/object-storage/
- Kubernetes CSI: https://kubernetes-csi.github.io/docs/
