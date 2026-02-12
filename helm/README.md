# PyPI Server Helm Chart

Production-ready Helm chart for deploying a private PyPI server on Kubernetes.

## Features

✅ **Production-Ready** - HA support, autoscaling, PDB
✅ **Secure** - Pod Security Standards, read-only filesystem
✅ **Flexible Storage** - Local PV, S3, or GCS backend
✅ **Auto-TLS** - cert-manager integration
✅ **Monitoring** - Prometheus metrics & Grafana dashboards
✅ **Authentication** - htpasswd or LDAP
✅ **Modern** - Follows Kubernetes best practices (2024)

## Quick Start

### Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- Ingress controller (nginx, traefik, etc.)
- cert-manager (for TLS)

### Installation

```bash
# Add the Helm repository (if published)
helm repo add power-edge https://power-edge.github.io/charts
helm repo update

# Or install from local directory
cd helm

# Install with default values
helm install pypi . \
  --namespace pypi \
  --create-namespace

# Install with custom domain
helm install pypi . \
  --namespace pypi \
  --create-namespace \
  --set ingress.hosts[0].host=pypi.example.com \
  --set ingress.tls[0].secretName=pypi-tls \
  --set ingress.tls[0].hosts[0]=pypi.example.com
```

### Usage

#### Upload packages

```bash
# Create .pypirc
cat > ~/.pypirc << EOF
[distutils]
index-servers =
    private

[private]
repository = https://pypi.example.com
username = pypi
password = your-password
EOF

# Upload with twine
python -m twine upload -r private dist/*
```

#### Install packages

```bash
# Install from private PyPI
pip install --index-url https://pypi:password@pypi.example.com/simple/ mypackage

# Or configure pip
pip config set global.index-url https://pypi:password@pypi.example.com/simple/
pip install mypackage
```

## Configuration

### Storage Backends

#### Local PersistentVolume (default)

```yaml
storage:
  backend: local
  local:
    enabled: true
    size: 10Gi
    storageClass: standard
```

#### S3 Backend (CSI Driver - RECOMMENDED)

**Best option for production**: S3-backed PersistentVolume via CSI driver

**Features**:
- ✅ No capacity planning (unlimited, grows dynamically)
- ✅ ReadWriteMany (multiple pods can share)
- ✅ Works with AWS S3, Hetzner Object Storage, Minio, etc.
- ✅ Highly available (S3 durability)
- ✅ Cost-effective (Hetzner: $0.005/GB/month)

**Prerequisites**:
```bash
# Install CSI-S3 driver
kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/provisioner.yaml
kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/attacher.yaml
kubectl apply -f https://raw.githubusercontent.com/ctrox/csi-s3/master/deploy/kubernetes/csi-s3.yaml
```

**Configuration**:
```yaml
storage:
  backend: s3
  local:
    enabled: false  # Disable local PV
  s3:
    enabled: true
    bucket: my-pypi-packages
    region: us-east-1  # Dummy for S3-compatible services
    accessKeyId: YOUR_ACCESS_KEY
    secretAccessKey: YOUR_SECRET_KEY

    # CSI driver configuration
    csi:
      enabled: true
      endpoint: "https://s3.amazonaws.com"  # Or Hetzner endpoint
      prefix: "pypi/"  # Optional: bucket prefix to share bucket
      size: "1Ti"  # Nominal size (S3 grows dynamically)
```

**Example for Hetzner Object Storage**:
```bash
# Install with Hetzner S3
helm install pypi ./helm -f values-hetzner-s3.yaml \
  --set storage.s3.accessKeyId=$HETZNER_S3_KEY \
  --set storage.s3.secretAccessKey=$HETZNER_S3_SECRET \
  --set storage.s3.csi.endpoint=https://fsn1.your-objectstorage.com
```

See `values-hetzner-s3.yaml` for complete example.

#### S3 Backend (Direct - Legacy)

**Note**: Direct S3 support via environment variables. CSI driver (above) is recommended instead.

```yaml
storage:
  backend: s3
  s3:
    enabled: true
    bucket: my-pypi-packages
    region: us-east-1
    accessKeyId: AKIAIOSFODNN7EXAMPLE
    secretAccessKey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    csi:
      enabled: false  # Disable CSI driver
```

### Authentication

#### htpasswd (default)

```bash
# Generate password hash
docker run --rm httpd:alpine htpasswd -nB myuser

# Add to values.yaml
auth:
  enabled: true
  method: htpasswd
  htpasswd:
    content: |
      myuser:$2y$05$...hash...
```

### High Availability

```yaml
pypiserver:
  replicaCount: 3

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80

podDisruptionBudget:
  enabled: true
  minAvailable: 2

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - pypiserver
          topologyKey: kubernetes.io/hostname
```

### Monitoring

```yaml
monitoring:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true  # Requires Prometheus Operator

  grafana:
    enabled: true
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `pypiserver.image.repository` | string | `pypiserver/pypiserver` | PyPI server image |
| `pypiserver.image.tag` | string | `v2.0.1` | Image tag |
| `pypiserver.replicaCount` | int | `1` | Number of replicas |
| `pypiserver.resources.requests.memory` | string | `128Mi` | Memory request |
| `storage.backend` | string | `local` | Storage backend: local, s3, gcs |
| `storage.local.size` | string | `10Gi` | PV size |
| `auth.enabled` | boolean | `true` | Enable authentication |
| `auth.method` | string | `htpasswd` | Auth method: htpasswd, ldap |
| `ingress.enabled` | boolean | `true` | Enable ingress |
| `ingress.className` | string | `nginx` | Ingress class |
| `ingress.hosts[0].host` | string | `pypi.example.com` | Hostname |
| `monitoring.prometheus.enabled` | boolean | `true` | Enable Prometheus metrics |

See `values.yaml` for full configuration options.

## Upgrade

```bash
# Upgrade to new version
helm upgrade pypi . \
  --namespace pypi \
  --reuse-values \
  --values custom-values.yaml
```

## Uninstall

```bash
# Delete release (preserves PVC)
helm uninstall pypi --namespace pypi

# Delete PVC
kubectl delete pvc -n pypi -l app.kubernetes.io/name=pypiserver
```

## Security Considerations

1. **Authentication** - Always enable auth in production
2. **TLS** - Use cert-manager for automatic TLS
3. **Network Policies** - Restrict access to PyPI server
4. **Pod Security** - Chart enforces Pod Security Standards
5. **Read-Only Root** - Container filesystem is read-only

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n pypi

# Check events
kubectl describe pod -n pypi pypi-pypiserver-0

# Check logs
kubectl logs -n pypi -l app.kubernetes.io/name=pypiserver
```

### Upload fails

```bash
# Check authentication
curl -u user:pass https://pypi.example.com/

# Check storage
kubectl exec -n pypi -it pypi-pypiserver-0 -- df -h /packages
```

### Certificate issues

```bash
# Check cert-manager certificate
kubectl get certificate -n pypi

# Check certificate status
kubectl describe certificate -n pypi pypi-tls
```

## Publishing to ArtifactHub

This chart can be published to [ArtifactHub.io](https://artifacthub.io/):

1. Add chart to GitHub repository
2. Create GitHub Release with chart package
3. Submit to ArtifactHub

See: https://artifacthub.io/docs/topics/repositories/

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - See LICENSE file

## Sources

- [PyPI Server](https://github.com/pypiserver/pypiserver)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)