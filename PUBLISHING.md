# Publishing the Helm Chart

This chart is published to **two channels** for maximum reach:

1. **GitHub Pages** - Automatic via GitHub Actions (every commit to `main`)
2. **Artifact Hub** - One-time submission, auto-crawls GitHub Pages

## Publishing Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Push to main branch (helm/ changes)                  │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│ 2. GitHub Actions (automatic)                            │
│    • Packages chart                                      │
│    • Creates GitHub Release                              │
│    • Updates gh-pages branch                             │
└─────────────────┬───────────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌───────────────┐   ┌───────────────────┐
│ GitHub Pages  │   │  Artifact Hub     │
│ (Helm repo)   │   │  (auto-crawls)    │
├───────────────┤   ├───────────────────┤
│ Users:        │   │ Users:            │
│ helm repo add │   │ Browse & search   │
└───────────────┘   └───────────────────┘
```

Both channels stay in sync automatically after initial setup.

## How It Works

When you push changes to the `helm/` directory on the `main` branch:

1. **GitHub Actions** automatically runs (see `.github/workflows/release.yaml`)
2. **chart-releaser** packages the chart and creates a GitHub Release
3. The packaged chart is published to the **gh-pages** branch
4. Users can access it at: `https://power-edge.github.io/charts`

## Initial Setup (One-Time)

### 1. Enable GitHub Pages

Go to your repository settings:
- **Settings** → **Pages**
- **Source**: Deploy from a branch
- **Branch**: `gh-pages` / `root`
- **Save**

GitHub will create the `gh-pages` branch automatically on first release.

### 2. Verify Workflow Permissions

Ensure GitHub Actions has write permissions:
- **Settings** → **Actions** → **General**
- Scroll to **Workflow permissions**
- Select: **Read and write permissions**
- Check: **Allow GitHub Actions to create and approve pull requests**
- **Save**

## Making a Release

### Automatic Release (Recommended)

Just push changes to the `helm/` directory:

```bash
# Make changes to chart
vim helm/Chart.yaml  # Bump version to 1.0.1
vim helm/templates/deployment.yaml

# Commit and push
git add helm/
git commit -m "feat: add new feature to chart"
git push origin main
```

GitHub Actions will automatically:
- Package the chart
- Create a GitHub Release with the new version
- Update the chart repository index

### Manual Release (Alternative)

If you want more control, you can create releases manually:

```bash
# 1. Bump chart version
vim helm/Chart.yaml  # Change version: 1.0.1

# 2. Commit changes
git add helm/Chart.yaml
git commit -m "chore: bump chart version to 1.0.1"

# 3. Create git tag
git tag -a helm-v1.0.1 -m "Release pypiserver Helm chart v1.0.1"

# 4. Push tag (triggers GitHub Actions)
git push origin helm-v1.0.1
```

## Using the Published Chart

Once published, users can install your chart with:

```bash
# Add the Helm repository
helm repo add power-edge https://power-edge.github.io/charts

# Update repository index
helm repo update

# Search for charts
helm search repo power-edge

# Install chart
helm install pypi power-edge/pypiserver \
  --namespace pypi \
  --create-namespace \
  -f values.yaml
```

## Versioning

Follow [Semantic Versioning](https://semver.org/):

- **Major** (1.0.0 → 2.0.0): Breaking changes
- **Minor** (1.0.0 → 1.1.0): New features, backward compatible
- **Patch** (1.0.0 → 1.0.1): Bug fixes, backward compatible

Update version in `helm/Chart.yaml`:

```yaml
version: 1.0.1  # Chart version
appVersion: "2.0.1"  # PyPI server version
```

## Checking Release Status

### View GitHub Actions

- Go to **Actions** tab in your repository
- Check the **Release Charts** workflow
- View logs to see what was published

### View Releases

- Go to **Releases** in your repository
- Each chart version should have a release with the packaged `.tgz` file

### View gh-pages Branch

```bash
# Checkout gh-pages branch
git fetch origin gh-pages
git checkout gh-pages

# View index.yaml (chart repository index)
cat index.yaml
```

## Troubleshooting

### Workflow Not Running

Check:
- `.github/workflows/release.yaml` is committed
- Workflow permissions are set to "Read and write"
- Changes were made to `helm/` directory

### GitHub Pages Not Working

Check:
- GitHub Pages is enabled in Settings
- `gh-pages` branch exists
- Wait a few minutes for DNS propagation

### Chart Not Appearing

Check:
- Chart version was bumped in `helm/Chart.yaml`
- GitHub Actions workflow succeeded
- `index.yaml` in `gh-pages` branch contains your chart

## Publishing to Artifact Hub

For discoverability, submit your chart to [Artifact Hub](https://artifacthub.io/). This is a **one-time setup** - Artifact Hub will automatically crawl your GitHub Pages repository for updates.

### One-Time Setup

1. **Go to Artifact Hub**: https://artifacthub.io/
2. **Sign in** with your GitHub account
3. **Click "Control Panel"** (top-right)
4. **Click "Add Repository"**
5. **Fill in details**:
   - **Kind**: Helm charts
   - **Name**: `power-edge-charts` (or any name)
   - **Display name**: `Power Edge Charts`
   - **URL**: `https://power-edge.github.io/charts`
   - **Repository**: Select your GitHub repo (optional, for verified badge)
6. **Click "Add"**

### What Happens Next

- Artifact Hub crawls your chart repository every few hours
- Your chart appears in search results: https://artifacthub.io/packages/search?kind=0&q=pypiserver
- Users can browse versions, README, values, and install instructions
- You get a verified publisher badge if you linked your GitHub repo

### Chart Metadata

The chart already has Artifact Hub annotations in `helm/Chart.yaml`:

```yaml
annotations:
  artifacthub.io/changes: |
    - kind: added
      description: Production-ready PyPI server
    - kind: added
      description: S3 backend support
  artifacthub.io/license: MIT
  artifacthub.io/links: |
    - name: Documentation
      url: https://github.com/power-edge/pypi/blob/main/helm/README.md
```

When you release new versions, update the `artifacthub.io/changes` annotation to document what changed.

### Verification

After submitting to Artifact Hub:
1. Wait 10-15 minutes for initial crawl
2. Search for your chart: https://artifacthub.io/packages/search?q=pypiserver
3. Verify metadata, README, and values are displayed correctly

### Benefits of Artifact Hub

- **Discoverability**: Users find your chart via search
- **Documentation**: README rendered beautifully
- **Version history**: All versions listed with changelogs
- **Security scanning**: CVE alerts for base images
- **Verified publisher**: GitHub badge shows authenticity
- **Install instructions**: One-click copy for `helm repo add`

## Local Testing Before Publishing

Test your chart locally before publishing:

```bash
# Lint chart
make lint

# Test template rendering
make template

# Package locally
make package

# Test installation (dry-run)
helm install test-pypi ./helm --dry-run --debug
```

## Chart Repository URL

Once set up, your chart repository will be available at:

**https://power-edge.github.io/charts**

Users will be able to browse it and see `index.yaml` with all available chart versions.

## Example: Full Release Workflow

```bash
# 1. Make changes to chart
vim helm/templates/deployment.yaml
vim helm/values.yaml

# 2. Bump version
vim helm/Chart.yaml  # version: 1.1.0

# 3. Update README/docs if needed
vim helm/README.md

# 4. Test locally
make test

# 5. Commit and push
git add helm/
git commit -m "feat: add autoscaling support"
git push origin main

# 6. GitHub Actions automatically:
#    - Packages chart
#    - Creates GitHub Release
#    - Updates chart repository

# 7. Users can now install:
helm repo update
helm upgrade pypi power-edge/pypiserver --version 1.1.0
```

## Security: Signing Charts (Optional)

For additional security, you can sign your charts with GPG:

```bash
# Generate GPG key
gpg --full-generate-key

# Export public key
gpg --armor --export your-email@example.com > pubkey.asc

# Sign and package chart
helm package --sign --key 'your-key-name' --keyring ~/.gnupg/secring.gpg helm/

# Users can verify:
helm verify pypiserver-1.0.0.tgz --keyring pubkey.asc
```

Add to `.github/workflows/release.yaml` to enable signing in CI.

## Resources

- [Helm Chart Releaser](https://github.com/helm/chart-releaser)
- [chart-releaser-action](https://github.com/helm/chart-releaser-action)
- [GitHub Pages Docs](https://docs.github.com/en/pages)
- [Artifact Hub](https://artifacthub.io/)
- [Helm Docs](https://helm.sh/docs/topics/chart_repository/)
