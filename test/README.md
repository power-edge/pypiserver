# Helm Chart Testing

Comprehensive local testing setup for the PyPI Helm chart with multiple configurations.

## Test Matrix

We test the following configurations:

| Test Case | Storage | Auth | Ingress | S3 Backend |
|-----------|---------|------|---------|------------|
| **minimal** | Local PV | Off | Off | - |
| **local-pv-auth** | Local PV | On | On | - |
| **minio-s3** | S3 CSI | Off | On | MinIO |
| **ha-config** | Local PV | On | On | - (2 replicas) |

## Prerequisites

Install testing tools:

```bash
# Helm
brew install helm

# k3d (Kubernetes in Docker)
brew install k3d

# chart-testing (Helm community tool)
brew install chart-testing

# kubectl
brew install kubectl

# Optional: MinIO client (for S3 testing)
brew install minio/stable/mc
```

## Quick Start

```bash
# Run all tests
make test-all

# Test specific configuration
make test-minimal
make test-local-pv-auth
make test-minio-s3
make test-ha-config

# Clean up
make test-clean
```

## Manual Testing

### 1. Create Local k3d Cluster

```bash
# Create cluster with port mapping for ingress
k3d cluster create pypi-test \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer"

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

### 2. Install Dependencies

```bash
# Install ingress controller (nginx)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Wait for ingress to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### 3. Test Basic Installation (Local PV)

```bash
# Install chart
helm install pypi ../helm \
  -f values/test-minimal.yaml \
  --namespace pypi-test \
  --create-namespace \
  --wait --timeout 5m

# Verify installation
helm test pypi -n pypi-test

# Check pods
kubectl get pods -n pypi-test

# Port-forward and test
kubectl port-forward -n pypi-test svc/pypi-pypiserver 8080:8080
curl http://localhost:8080/
```

### 4. Test with MinIO (S3 Mock)

```bash
# Install MinIO
kubectl apply -f fixtures/minio-deployment.yaml

# Wait for MinIO
kubectl wait --for=condition=ready pod -l app=minio -n pypi-test --timeout=120s

# Create bucket
kubectl run -n pypi-test minio-client --rm -it --restart=Never \
  --image=minio/mc:latest -- \
  /bin/sh -c "mc alias set myminio http://minio:9000 minioadmin minioadmin && mc mb myminio/pypi-packages"

# Install CSI-S3 driver (for S3 CSI tests)
kubectl apply -f fixtures/csi-s3-driver.yaml

# Install chart with S3 backend
helm install pypi ../helm \
  -f values/test-minio-s3.yaml \
  --namespace pypi-test \
  --create-namespace \
  --wait --timeout 5m

# Run tests
helm test pypi -n pypi-test
```

### 5. Test Package Upload/Download

```bash
# Port-forward PyPI server
kubectl port-forward -n pypi-test svc/pypi-pypiserver 8080:8080 &

# Create test package
cd fixtures/test-package
python -m build

# Upload package
twine upload --repository-url http://localhost:8080/ dist/* --skip-existing

# Download/install package
pip install --index-url http://localhost:8080/simple/ test-package --no-cache-dir

# Verify package was stored
kubectl exec -n pypi-test deployment/pypi-pypiserver -- ls -lh /packages
```

### 6. Test HA Configuration

```bash
# Install with 2 replicas
helm install pypi ../helm \
  -f values/test-ha-config.yaml \
  --namespace pypi-test \
  --create-namespace \
  --wait --timeout 5m

# Verify multiple pods
kubectl get pods -n pypi-test -l app.kubernetes.io/name=pypiserver

# Test pod failure (kill one pod, verify service continues)
kubectl delete pod -n pypi-test -l app.kubernetes.io/name=pypiserver --field-selector status.phase=Running --wait=false
kubectl port-forward -n pypi-test svc/pypi-pypiserver 8080:8080
curl http://localhost:8080/  # Should still work
```

### 7. Cleanup

```bash
# Uninstall chart
helm uninstall pypi -n pypi-test

# Delete namespace
kubectl delete namespace pypi-test

# Delete cluster
k3d cluster delete pypi-test
```

## Automated Testing with chart-testing (ct)

The `chart-testing` tool is the Helm community standard for testing charts.

```bash
# Lint chart
ct lint --config test/ct-config.yaml --charts helm/

# Lint and test in k3d cluster
ct lint-and-install --config test/ct-config.yaml --charts helm/
```

This will:
1. Lint the chart
2. Create test clusters
3. Install chart with each values file in `test/values/`
4. Run `helm test`
5. Cleanup

## GitHub Actions CI

Tests run automatically on every PR and push to main. See `.github/workflows/test.yaml`.

## Test Values Files

All test configurations are in `test/values/`:

- `test-minimal.yaml` - Minimal config (no ingress, no auth)
- `test-local-pv-auth.yaml` - Local PV with authentication
- `test-minio-s3.yaml` - S3 CSI with MinIO backend
- `test-ha-config.yaml` - High availability (2 replicas, autoscaling)

## Test Fixtures

Test fixtures in `test/fixtures/`:

- `test-package/` - Sample Python package for upload testing
- `minio-deployment.yaml` - MinIO for S3 testing
- `csi-s3-driver.yaml` - CSI-S3 driver installation

## Troubleshooting

### Chart doesn't install

```bash
# Check events
kubectl get events -n pypi-test --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n pypi-test -l app.kubernetes.io/name=pypiserver

# Describe pod
kubectl describe pod -n pypi-test -l app.kubernetes.io/name=pypiserver
```

### MinIO not accessible

```bash
# Check MinIO pod
kubectl get pods -n pypi-test -l app=minio

# Port-forward MinIO console
kubectl port-forward -n pypi-test svc/minio 9001:9001
# Open http://localhost:9001 (minioadmin/minioadmin)
```

### Tests fail

```bash
# View test pod logs
kubectl logs -n pypi-test pypi-pypiserver-test-connection

# Re-run tests
helm test pypi -n pypi-test --logs
```

## Writing New Tests

Add new test cases in `helm/templates/tests/`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "pypiserver.fullname" . }}-test-upload"
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: test
      image: python:3.11-slim
      command: ['sh', '-c', 'pip install twine && twine upload --help']
  restartPolicy: Never
```

## Performance Testing

For load testing:

```bash
# Install with higher resources
helm install pypi ../helm \
  -f values/test-ha-config.yaml \
  --set pypiserver.resources.limits.memory=2Gi \
  --namespace pypi-test

# Run load test with hey or k6
hey -n 1000 -c 10 http://localhost:8080/simple/
```

## Resources

- [Helm Testing](https://helm.sh/docs/topics/chart_tests/)
- [chart-testing](https://github.com/helm/chart-testing)
- [k3d](https://k3d.io/)
- [MinIO](https://min.io/)
