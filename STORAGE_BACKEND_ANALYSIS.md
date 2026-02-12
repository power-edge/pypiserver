# Storage Backend Analysis for PyPI Packages

## Question

**Should we store Python packages in:**
1. Database (compressed binary/zip)
2. Redis (in-memory cache)
3. Local PersistentVolume
4. S3/Object Storage

## TL;DR Recommendation

**Use S3 for package files** + PostgreSQL for metadata + Redis for caching.

This separation of concerns gives you:
- **Cheap storage** ($0.023/GB/month)
- **High availability** (99.99% durability)
- **Native pypiserver support** (no custom code)
- **Scalability** (unlimited storage)
- **Performance** (CDN-ready)

---

## Detailed Analysis

### Option 1: Database (PostgreSQL) Storage

**Implementation**: Store package files as compressed BYTEA or BLOB columns.

**Pros**:
- ✅ Transactional integrity
- ✅ Single source of truth
- ✅ Backup/restore is simple

**Cons**:
- ❌ **3-13x more expensive than S3**
  - PostgreSQL: $0.10-0.30/GB/month (managed RDS/Cloud SQL)
  - S3: $0.023/GB/month
- ❌ **Slower performance** - Database queries are slower than object storage
- ❌ **Not native pypiserver support** - Requires custom backend implementation
- ❌ **Database bloat** - Large binary data slows down queries/backups
- ❌ **Scalability limits** - Database size limits (terabytes, not petabytes)

**Cost Example** (1TB of packages):
```
PostgreSQL: 1000GB × $0.20/GB = $200/month
S3:         1000GB × $0.023/GB = $23/month

Difference: $177/month ($2,124/year) 💸
```

**Verdict**: ❌ **Don't store packages in database** - too expensive, not optimized for large blobs.

---

### Option 2: Redis Storage

**Implementation**: Store package files as binary strings in Redis keys.

**Pros**:
- ✅ Extremely fast reads (in-memory)
- ✅ Simple API (GET/SET)

**Cons**:
- ❌ **20-40x more expensive than S3**
  - Redis: $0.50-1.00/GB/month (managed ElastiCache/Redis Cloud)
  - S3: $0.023/GB/month
- ❌ **Wasteful** - Redis is designed for small, hot data (cache), not large blobs
- ❌ **Not native pypiserver support**
- ❌ **Memory constraints** - Limited by RAM (expensive to scale)
- ❌ **Volatility risk** - Redis is often configured as cache (eviction policies)
- ❌ **Persistence overhead** - RDB/AOF for large datasets is slow

**Cost Example** (1TB of packages):
```
Redis:  1000GB × $0.75/GB = $750/month
S3:     1000GB × $0.023/GB = $23/month

Difference: $727/month ($8,724/year) 💸💸💸
```

**Verdict**: ❌ **Don't store packages in Redis** - designed for caching, not bulk storage.

---

### Option 3: Local PersistentVolume (PV)

**Implementation**: Kubernetes PersistentVolumeClaim backed by local disk or cloud block storage.

**Pros**:
- ✅ **Native pypiserver support** - Default backend
- ✅ Fast local I/O
- ✅ Simple setup (no external services)
- ✅ Good for development/testing

**Cons**:
- ⚠️ **Not highly available** - Single node failure = downtime
- ⚠️ **Hard to scale** - Limited by node disk size
- ⚠️ **No multi-replica support** - ReadWriteOnce access mode only
- ⚠️ **Manual backups** - Need custom backup strategy
- ⚠️ **Cost** - Block storage is more expensive than object storage
  - AWS EBS: $0.10/GB/month
  - GCP Persistent Disk: $0.17/GB/month
  - S3: $0.023/GB/month

**Cost Example** (1TB of packages):
```
EBS (gp3): 1000GB × $0.08/GB = $80/month
S3:        1000GB × $0.023/GB = $23/month

Difference: $57/month ($684/year)
```

**Verdict**: ⚠️ **Use for dev/test only** - not production-ready without HA setup.

---

### Option 4: S3/Object Storage (Recommended)

**Implementation**: pypiserver with S3 backend (native support).

**Pros**:
- ✅ **Cheapest option** - $0.023/GB/month
- ✅ **99.99% durability** - Built-in redundancy
- ✅ **Unlimited scalability** - No size limits
- ✅ **Native pypiserver support** - Just set environment variables
- ✅ **CDN-ready** - CloudFront/CloudFlare integration
- ✅ **Multi-region** - Global distribution
- ✅ **Versioning** - Built-in object versioning
- ✅ **Lifecycle policies** - Auto-archive old versions

**Cons**:
- ⚠️ Network latency (mitigated by CDN)
- ⚠️ Egress costs (but only when downloading packages)

**Native pypiserver support**:
```bash
# Environment variables
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_S3_BUCKET=my-pypi-packages
export AWS_REGION=us-east-1

# pypiserver automatically uses S3
pypiserver run -p 8080 /packages
```

**Cost Example** (1TB of packages, 100GB egress/month):
```
Storage:  1000GB × $0.023/GB = $23/month
Egress:   100GB × $0.09/GB = $9/month
Total:    $32/month ($384/year)

vs. PostgreSQL: $200/month ($2,400/year)
vs. Redis:      $750/month ($9,000/year)

Savings: $2,016-8,616/year 💰
```

**Verdict**: ✅ **Use S3 for production** - cheap, scalable, HA, native support.

---

## Recommended Architecture

### **Hybrid Approach: S3 + PostgreSQL + Redis**

Each storage layer serves a different purpose:

```
┌─────────────────────────────────────────────────────────────┐
│                    Package Registry                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐                                           │
│  │  pypiserver  │                                           │
│  └───────┬──────┘                                           │
│          │                                                   │
│          ├──────────────────────────────┐                   │
│          │                              │                   │
│    ┌─────▼─────┐              ┌────────▼────────┐          │
│    │    S3     │              │   PostgreSQL    │          │
│    │ (Packages)│              │   (Metadata)    │          │
│    └───────────┘              └─────────────────┘          │
│    - Binary files             - Package names               │
│    - Versions                 - Upload timestamps           │
│    - Checksums                - User/auth data              │
│    - $0.023/GB/month          - Download stats              │
│                               - Search index                │
│                                                              │
│                     ┌─────────────┐                         │
│                     │    Redis    │                         │
│                     │  (Cache)    │                         │
│                     └─────────────┘                         │
│                     - Metadata cache                        │
│                     - Session data                          │
│                     - Rate limiting                         │
│                     - $0.50/GB/month                        │
│                     (hot data only)                         │
└─────────────────────────────────────────────────────────────┘
```

**Separation of Concerns**:

1. **S3 (Package Files)**:
   - Store `.whl`, `.tar.gz` package files
   - Cheap, durable, scalable
   - Versioning enabled
   - Lifecycle: archive to Glacier after 90 days

2. **PostgreSQL (Metadata)**:
   - Package index (name, version, author, etc.)
   - Upload/download history
   - User accounts, permissions
   - Search functionality
   - Small dataset (KB per package, not MB)

3. **Redis (Cache)**:
   - Cache metadata queries (hot packages)
   - Session management
   - Rate limiting
   - Small, hot data only (10-100MB typical)

**Why this works**:
- **Cost-optimized**: Store bulk data in S3, metadata in PostgreSQL, hot data in Redis
- **Performance**: Cache speeds up metadata queries, S3 serves large files
- **Scalability**: S3 scales infinitely, PostgreSQL handles structured queries
- **Native support**: pypiserver supports S3 out-of-the-box

---

## Configuration Examples

### Helm Chart Values (S3 Backend)

```yaml
# values.yaml
storage:
  backend: s3
  s3:
    enabled: true
    bucket: my-pypi-packages
    region: us-east-1
    # Use IAM role (recommended)
    iamRole: arn:aws:iam::123456789:role/pypi-s3-access
    # Or use credentials (not recommended)
    # accessKeyId: AKIAIOSFODNN7EXAMPLE
    # secretAccessKey: wJalrXUtnFEMI/K7MDENG/bPxRfiCY

# Optional: Add CloudFront CDN
cdn:
  enabled: true
  domain: packages.tech-screen.com
  certificateArn: arn:aws:acm:us-east-1:123456789:certificate/...
```

### Docker Compose (S3 Backend)

```yaml
# compose.yaml
services:
  pypi:
    image: pypiserver/pypiserver:v2.0.1
    environment:
      # S3 configuration
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_S3_BUCKET=my-pypi-packages
      - AWS_REGION=us-east-1
    command:
      - run
      - -p
      - "8080"
      - -P
      - /auth/htpasswd
      - /packages  # S3 bucket will be mounted here
```

---

## Advanced: S3 + CloudFront CDN

For **high-traffic scenarios** (> 1TB egress/month), add CloudFront CDN:

```
┌────────────────────────────────────────────────────────┐
│                  Global Distribution                    │
├────────────────────────────────────────────────────────┤
│                                                          │
│  Users (US) ──────┐                                    │
│                   │                                     │
│  Users (EU) ──────┼───►  CloudFront CDN               │
│                   │      (Edge Locations)              │
│  Users (Asia) ────┘           │                        │
│                               │                        │
│                               ▼                        │
│                        ┌─────────────┐                │
│                        │  S3 Bucket  │                │
│                        │  (Origin)   │                │
│                        └─────────────┘                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Benefits**:
- **Faster downloads** - Edge locations near users
- **Lower egress costs** - $0.085/GB vs $0.09/GB (S3 direct)
- **DDoS protection** - CloudFront shields origin
- **Caching** - Reduces S3 requests

**Cost Example** (1TB egress/month via CloudFront):
```
CloudFront: 1000GB × $0.085/GB = $85/month
S3 Direct:  1000GB × $0.09/GB = $90/month

Savings: $5/month (plus faster performance)
```

**Terraform Example**:
```hcl
# CloudFront distribution for PyPI
resource "aws_cloudfront_distribution" "pypi" {
  origin {
    domain_name = aws_s3_bucket.pypi_packages.bucket_regional_domain_name
    origin_id   = "S3-pypi-packages"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.pypi.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "S3-pypi-packages"
    viewer_protocol_policy = "redirect-to-https"

    # Cache packages for 1 day (they're immutable)
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.certificate_arn
    ssl_support_method  = "sni-only"
  }
}
```

---

## Migration Path

### Phase 1: Start with Local PV (Dev/Test)
```bash
# Quick start for development
helm install pypi ./helm \
  --namespace pypi \
  --create-namespace
```

### Phase 2: Move to S3 (Production)
```bash
# Create S3 bucket
aws s3 mb s3://my-pypi-packages --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-pypi-packages \
  --versioning-configuration Status=Enabled

# Upgrade Helm chart
helm upgrade pypi ./helm \
  --namespace pypi \
  --set storage.backend=s3 \
  --set storage.s3.bucket=my-pypi-packages \
  --set storage.s3.region=us-east-1

# Migrate existing packages
aws s3 sync /mnt/packages s3://my-pypi-packages/
```

### Phase 3: Add CloudFront (High Traffic)
```bash
# Create CloudFront distribution
terraform apply -target=aws_cloudfront_distribution.pypi

# Update pypiserver to use CDN URL
helm upgrade pypi ./helm \
  --set cdn.enabled=true \
  --set cdn.domain=packages.tech-screen.com
```

---

## Cost Summary (1TB packages, 100GB egress/month)

| Backend | Storage | Egress | Total/Month | Total/Year |
|---------|---------|--------|-------------|------------|
| **S3 (Recommended)** | $23 | $9 | **$32** | **$384** |
| S3 + CloudFront | $23 | $9 | $32 | $384 |
| Local PV (EBS) | $80 | $0 | $80 | $960 |
| PostgreSQL | $200 | $0 | $200 | $2,400 |
| Redis | $750 | $0 | $750 | $9,000 |

**Savings vs. alternatives**:
- S3 vs. Local PV: **$576/year** (60% cheaper)
- S3 vs. PostgreSQL: **$2,016/year** (83% cheaper)
- S3 vs. Redis: **$8,616/year** (96% cheaper)

---

## Final Recommendation

**Use this architecture**:

1. **S3 for package files** (binary `.whl`, `.tar.gz`)
   - Cheap: $0.023/GB/month
   - Native pypiserver support
   - Scalable, durable, HA

2. **PostgreSQL for metadata** (package index, search, auth)
   - Small dataset (KB per package)
   - Structured queries
   - Transactional integrity

3. **Redis for caching** (hot metadata, sessions)
   - 10-100MB typical
   - Fast reads
   - Reduces PostgreSQL load

4. **Optional: CloudFront CDN** (for high traffic)
   - Faster downloads
   - Lower egress costs
   - DDoS protection

**Why this works**:
- ✅ **Cost-optimized**: Store bulk data where it's cheapest (S3)
- ✅ **Performance**: Cache hot data (Redis), CDN for global distribution
- ✅ **Scalability**: S3 scales infinitely, PostgreSQL handles metadata
- ✅ **Native support**: pypiserver works with S3 out-of-the-box
- ✅ **Separation of concerns**: Each layer optimized for its purpose

**Don't do**:
- ❌ Store packages in database (3-13x more expensive)
- ❌ Store packages in Redis (20-40x more expensive)
- ❌ Use local PV for production (not HA)

---

## Next Steps

1. **Update Helm chart** to include S3 + CloudFront configuration examples
2. **Test S3 backend** with pypiserver to verify performance
3. **Document migration** from local PV → S3
4. **Add Terraform module** for S3 bucket + IAM role + CloudFront
5. **Benchmark performance** (local PV vs S3 vs S3+CloudFront)
