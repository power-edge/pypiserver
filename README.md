# PyPI Server Helm Chart

Production-ready Helm chart for deploying a private PyPI server on Kubernetes.

This is a **public, reusable Helm chart** designed for self-hosted Kubernetes clusters where AWS/GCP managed PyPI services aren't available or desired.

## Features

✅ **Production-Ready** - HA support, autoscaling, Pod Disruption Budget
✅ **Secure** - Pod Security Standards, read-only filesystem, optional authentication
✅ **Flexible Storage** - Local PV (default), S3 CSI driver, or direct S3
✅ **Auto-TLS** - cert-manager integration for HTTPS
✅ **Monitoring** - Prometheus metrics & optional ServiceMonitor
✅ **Modern** - Follows Kubernetes best practices (2024)
✅ **Anti-AWS** - Optimized for self-hosted K8s, not AWS-specific

## Use Cases

- **Private Python packages** for internal libraries and applications
- **Air-gapped environments** where PyPI.org is not accessible
- **Cost-conscious teams** avoiding expensive managed artifact registries
- **Multi-tenancy** with separate PyPI per team/project
- **Release management** with support for pre-release versions (rc, alpha, beta)

## Quick Start

### Installation

```bash
# Add Helm repository (when published)
helm repo add power-edge https://power-edge.github.io/charts
helm repo update

# Or install from source
git clone https://github.com/power-edge/pypi.git
cd pypi

# Install with default values (local PV)
helm install pypi ./helm \
  --namespace pypi \
  --create-namespace \
  --set ingress.hosts[0].host=pypi.example.com \
  --set ingress.tls[0].hosts[0]=pypi.example.com
```

### Usage

#### Upload packages

```bash
# Build your package
python -m build  # or: uv build

# Upload to private PyPI
twine upload --repository-url https://pypi.example.com/ dist/*
```

#### Install packages

```bash
# Install from private PyPI (with fallback to PyPI.org)
pip install --extra-index-url https://pypi.example.com/simple/ mypackage

# Or configure globally
pip config set global.extra-index-url https://pypi.example.com/simple/
```

## Documentation

📖 **[Full Documentation](helm/README.md)** - Complete guide with all configuration options

**Key Topics:**
- [Storage Backends](helm/README.md#storage-backends) - Local PV, S3 CSI, Direct S3
- [Authentication](helm/README.md#authentication) - htpasswd, LDAP
- [High Availability](helm/README.md#high-availability) - Multi-replica, autoscaling
- [Monitoring](helm/README.md#monitoring) - Prometheus metrics, Grafana dashboards
- [S3 CSI Setup](helm/README.md#s3-backend-csi-driver---recommended) - Unlimited storage with S3

## Research & Analysis

This repository includes comprehensive research on package registry strategies:

- **[PACKAGE_REGISTRY_STRATEGY.md](PACKAGE_REGISTRY_STRATEGY.md)** - Universal vs. specialized registries (85% cost savings with specialized approach)
- **[STORAGE_BACKEND_ANALYSIS.md](STORAGE_BACKEND_ANALYSIS.md)** - Comparison of storage backends (S3 vs DB vs Redis vs PV)
- **[S3_CSI_IMPLEMENTATION.md](S3_CSI_IMPLEMENTATION.md)** - How S3 CSI driver is implemented in the chart

**TL;DR**: Use specialized registries (this chart for PyPI, Verdaccio for npm, etc.) instead of expensive universal registries like JFrog Artifactory ($22k/year → $3k/year).

## Development

```bash
# Lint chart
make lint

# Test template rendering
make template

# Run all tests
make test

# Package chart
make package
```

See [Makefile](Makefile) for all available commands.

## Configuration Examples

### Local PersistentVolume (Default)

```yaml
storage:
  backend: local
  local:
    enabled: true
    size: 10Gi
    storageClass: standard
```

### S3 CSI Driver (Production - Recommended)

Best for production: unlimited storage, ReadWriteMany, highly available.

```yaml
storage:
  backend: s3
  local:
    enabled: false
  s3:
    enabled: true
    bucket: my-pypi-packages
    region: us-east-1
    accessKeyId: YOUR_KEY
    secretAccessKey: YOUR_SECRET
    csi:
      enabled: true
      endpoint: "https://s3.amazonaws.com"
      # Or Hetzner: "https://fsn1.your-objectstorage.com"
      size: "1Ti"  # Nominal size, grows dynamically
```

See [values-hetzner-s3.yaml](helm/values-hetzner-s3.yaml) for complete Hetzner Object Storage example.

## Why This Chart?

### Problem: Expensive Managed Registries

- **AWS CodeArtifact**: $5-50/month + $0.05 per request (!)
- **JFrog Artifactory**: $6,000-10,000+/year
- **Nexus Repository**: $3,000+/year
- **Cloudsmith**: $900-6,000/year

### Solution: Self-Hosted PyPI

- **Cost**: ~$2-5/month (storage only)
- **Control**: Full ownership of your packages
- **Privacy**: No data leaves your infrastructure
- **Flexibility**: Customize to your needs

### Why Not Universal Registry?

See [PACKAGE_REGISTRY_STRATEGY.md](PACKAGE_REGISTRY_STRATEGY.md) for full analysis.

**Short answer**: Specialized registries are:
- 85% cheaper ($3.2k vs $22k/year)
- Simpler to operate (one focused tool vs complex universal system)
- Better performance (optimized for each ecosystem)
- Easier to troubleshoot (large community support)

## Requirements

- **Kubernetes**: 1.23+
- **Helm**: 3.8+
- **Ingress Controller**: nginx, traefik, or similar
- **cert-manager**: (optional) for automatic TLS certificates
- **CSI-S3 driver**: (optional) for S3-backed storage

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `pypiserver.image.tag` | `v2.0.1` | PyPI server version |
| `pypiserver.replicaCount` | `1` | Number of replicas |
| `storage.backend` | `local` | Storage backend: `local`, `s3` |
| `storage.local.size` | `10Gi` | PersistentVolume size |
| `auth.enabled` | `true` | Enable authentication |
| `ingress.enabled` | `true` | Enable ingress |
| `ingress.hosts[0].host` | `pypi.example.com` | Hostname |
| `monitoring.prometheus.enabled` | `true` | Enable Prometheus metrics |

See [values.yaml](helm/values.yaml) for complete configuration reference.

## Contributing

Contributions welcome! This chart is designed to be **generic and reusable** for any Kubernetes cluster.

Please:
- Keep the chart vendor-agnostic (no AWS/GCP/Azure specific code)
- Follow Helm best practices
- Update documentation for any new features
- Test with both local PV and S3 CSI backends

## License

MIT License - See LICENSE file

## Support

- 📖 [Documentation](helm/README.md)
- 🐛 [Issues](https://github.com/power-edge/pypi/issues)
- 💬 [Discussions](https://github.com/power-edge/pypi/discussions)

## Related Projects

- **[pypiserver](https://github.com/pypiserver/pypiserver)** - The upstream PyPI server (what this chart deploys)
- **[Verdaccio](https://verdaccio.org/)** - Private npm registry (for JavaScript packages)
- **[ChartMuseum](https://chartmuseum.com/)** - Private Helm chart repository
- **[Athens](https://github.com/gomods/athens)** - Go module proxy

## Roadmap

- [ ] Publish to Artifact Hub
- [ ] Add values.schema.json for validation
- [ ] Add example NetworkPolicy
- [ ] Add Grafana dashboard ConfigMap
- [ ] Add multi-arch Docker images
- [ ] Add backup/restore documentation
- [ ] Add migration guide from other PyPI servers

## Acknowledgments

- **pypiserver team** for the excellent PyPI server implementation
- **CSI-S3 contributors** for the S3 CSI driver
- **Helm community** for best practices and tooling