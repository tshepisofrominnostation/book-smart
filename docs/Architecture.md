# TrackBook — Multi-Tenant Cloud Architecture
## Principal Cloud Architect Review | Version 1.0 | June 2026

---

## 1. Multi-Tenancy Strategy Decision

### The Core Trade-Off

| Strategy | Data Isolation | Cost per School | Maintenance | Query Performance |
|---|---|---|---|---|
| **Database-per-tenant** | Perfect | Very High ($$$) | High | ✅ |
| **Schema-per-tenant** | Strong | Medium | Medium | ✅ |
| **Shared DB + tenant_id** | Logical (RLS) | Low ($) | Low | ⚠️ With indexes |

### Recommended: **Hybrid Pooled + Siloed**

**Phase 1 (0–200 schools):** Shared database with `school_id` column + PostgreSQL Row Level Security (RLS).

**Phase 2 (200–2,000 schools):** Pool schools by province into dedicated PostgreSQL clusters. Each province gets its own database cluster — this provides data residency compliance, better performance, and a natural blast radius limit.

**Phase 3 (2,000+ schools / Enterprise districts):** Option for dedicated schema or database per district (e.g., Western Cape Department of Education gets its own isolated instance).

---

## 2. Phase 1 Architecture (Shared Multi-Tenant)

```
                    ┌─────────────────────────────────────────────┐
                    │               INTERNET / CDN                │
                    │          (Cloudflare — DDoS + WAF)          │
                    └─────────────────┬───────────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────────┐
                    │            API GATEWAY / LB                 │
                    │    (AWS ALB or Cloudflare Workers routing)  │
                    │                                             │
                    │  /api/*  → API servers                      │
                    │  /       → Next.js frontend (Vercel/CDN)    │
                    └───────┬─────────────────┬───────────────────┘
                            │                 │
              ┌─────────────▼──┐       ┌──────▼──────────┐
              │   API Servers  │       │  Next.js SSR     │
              │  (Node.js /    │       │  (Vercel or      │
              │   FastAPI)     │       │   AWS Fargate)   │
              │  Auto-scaling  │       └─────────────────-┘
              │  ECS/Fargate   │
              └───────┬────────┘
                      │
        ┌─────────────┼─────────────────────────┐
        │             │                         │
┌───────▼───┐  ┌──────▼──────┐         ┌────────▼────────┐
│ Primary   │  │   Redis     │         │   S3 / R2       │
│ PostgreSQL│  │   Cache     │         │   Object Store  │
│ (RDS or  │  │  (sessions, │         │  (uploads,      │
│  Supabase)│  │   scan      │         │   PDFs,         │
│           │  │   lookups)  │         │   exports)      │
└───────────┘  └─────────────┘         └─────────────────┘
```

### Key Decisions

**Database:** PostgreSQL (AWS RDS Multi-AZ or Supabase Pro for rapid start)
- RLS policies enforce school_id isolation at the DB layer
- Every API request sets `SET app.current_school_id = ?` at connection time
- This is the last line of defense — even if application code has a bug, RLS blocks cross-tenant data access

**Caching (Redis):**
- Barcode → book info lookups cached for 1 hour (invalidated on inventory update)
- Student CEMIS lookups cached per school
- JWT session data
- Rate limiting counters per school

**Connection Pooling:** PgBouncer in transaction mode — prevents 1,000 schools × N connections exhausting PostgreSQL's connection limit.

---

## 3. Phase 2 Architecture (Province-Sharded)

```
                         ┌─────────────────────────────┐
                         │     ROUTING LAYER           │
                         │  Maps school_id → cluster   │
                         │  (Redis routing table)      │
                         └─────┬──────────┬────────────┘
                               │          │
                 ┌─────────────▼─┐    ┌───▼─────────────┐
                 │  WC Cluster   │    │  GP Cluster      │
                 │ (Western Cape)│    │  (Gauteng)       │
                 │               │    │                  │
                 │  PostgreSQL   │    │  PostgreSQL       │
                 │  + Read       │    │  + Read          │
                 │  Replica      │    │  Replica         │
                 └───────────────┘    └──────────────────┘
```

**Routing Table (Redis):**
```json
{
  "school_id:uuid-wc001": "cluster:western-cape",
  "school_id:uuid-gp042": "cluster:gauteng",
  "school_id:uuid-kzn007": "cluster:kwazulu-natal"
}
```

This allows:
- Data residency compliance per province
- Independent scaling per province
- Province-level database maintenance without affecting others
- Province-level backup and disaster recovery

---

## 4. Government Procurement API Integration

### Overview

The goal is to allow TrackBook to:
1. **Sync inventory data** to a government procurement portal (e.g., when books are received or written off)
2. **Place automated purchase orders** for replacement stock (e.g., when audit shows 50 missing books)

### Architecture: Outbound API Integration

```
TrackBook Backend
      │
      │  (internal event: books_written_off or audit_completed)
      ▼
┌─────────────────────────────────────────────────────────┐
│              EVENT BUS (AWS EventBridge / SQS)          │
│                                                         │
│  Event: school.audit.completed                          │
│  Payload: {school_id, audit_id, discrepancies: [...]}   │
└─────────────────────────┬───────────────────────────────┘
                          │
             ┌────────────▼──────────────────┐
             │  INTEGRATION SERVICE          │
             │  (Lambda / Fargate worker)    │
             │                               │
             │  1. Transform payload to      │
             │     government API format     │
             │  2. Sign request (OAuth 2.0   │
             │     or API key)               │
             │  3. POST to Gov Portal API    │
             │  4. Handle retry on failure   │
             │  5. Log response              │
             └────────────┬──────────────────┘
                          │
             ┌────────────▼──────────────────┐
             │  GOVERNMENT PROCUREMENT       │
             │  PORTAL (e.g., e-Procurement) │
             │  Endpoint: POST /inventory/   │
             │             sync              │
             └───────────────────────────────┘
```

### Public API for Government Systems (Inbound)

Expose a read-only, authenticated API for government systems to query school inventory:

```yaml
# OpenAPI spec fragment
paths:
  /public/v1/schools/{emis_code}/inventory/summary:
    get:
      summary: Get school inventory summary
      security:
        - GovAPIKey: []
      parameters:
        - name: emis_code
          in: path
          required: true
      responses:
        '200':
          content:
            application/json:
              schema:
                type: object
                properties:
                  school_emis: string
                  total_books: integer
                  books_assigned: integer
                  books_available: integer
                  books_lost: integer
                  books_damaged: integer
                  last_audit_date: string (ISO 8601)
                  outstanding_billing: number

  /public/v1/schools/{emis_code}/purchase-orders:
    post:
      summary: Create automated purchase order for replacement books
      security:
        - GovAPIKey: []
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                triggered_by_audit_id: string
                items:
                  type: array
                  items:
                    properties:
                      isbn: string
                      quantity_requested: integer
                      reason: string   # "lost" | "damaged" | "shortage"
```

### Security Measures for Public API

1. **Authentication:** OAuth 2.0 Client Credentials flow — each government department gets its own `client_id` + `client_secret`. No human in the loop.

2. **Authorization Scopes:**
   - `inventory:read` — can query inventory summary
   - `inventory:write` — can push procurement confirmation
   - `orders:create` — can trigger purchase orders

3. **Rate Limiting:** 1,000 requests/hour per government client (via API Gateway)

4. **Audit Logging:** Every API call from a government system is logged with timestamp, IP, scopes used, payload hash (for non-repudiation)

5. **mTLS (Phase 2):** For high-security integrations, require client certificates in addition to OAuth tokens

6. **IP Allowlisting:** Government portal IPs whitelisted at infrastructure level

---

## 5. Infrastructure as Code (Key Resources)

```hcl
# Terraform excerpt — key resources

# RDS PostgreSQL (Multi-AZ for high availability)
resource "aws_db_instance" "trackbook_primary" {
  engine               = "postgres"
  engine_version       = "16.2"
  instance_class       = "db.t3.medium"   # Scale up as needed
  multi_az             = true
  storage_encrypted    = true
  deletion_protection  = true
  
  backup_retention_period = 30            # 30 days of daily backups
  performance_insights_enabled = true
}

# Elasticache Redis (session + scan cache)
resource "aws_elasticache_cluster" "trackbook_cache" {
  engine         = "redis"
  node_type      = "cache.t3.micro"
  num_cache_nodes = 1
}

# S3 bucket for uploads/exports (encrypted + versioned)
resource "aws_s3_bucket" "trackbook_assets" {
  bucket = "trackbook-school-assets-prod"
}
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.trackbook_assets.id
  versioning_configuration { status = "Enabled" }
}
```

---

## 6. Scaling Checklist (0 → 1,000 Schools)

| Milestone | Action |
|---|---|
| **0–50 schools** | Single PostgreSQL instance (Supabase or RDS t3.small). Monolithic Node.js API. No sharding. |
| **50–200 schools** | Add Read Replica for reporting queries. Redis cluster for barcode cache. |
| **200–500 schools** | Extract Import Service to separate worker. Add PgBouncer connection pooler. CDN for barcode label PDFs. |
| **500–1,000 schools** | Begin province sharding. Separate audit/reporting database from transactional DB. Consider read replicas per province. |
| **1,000+ schools** | Full province clusters. Dedicated enterprise tenants for large districts. GraphQL federation layer for unified reporting. |

---

## 7. POPIA Compliance Architecture

| Requirement | Implementation |
|---|---|
| **Data minimization** | CEMIS numbers stored but only surfaced to authorized roles |
| **Encryption at rest** | AES-256 on RDS + S3 |
| **Encryption in transit** | TLS 1.3 enforced at load balancer |
| **Right to access** | Parent portal allows data export (GDPR-style) |
| **Data deletion** | Soft delete + automated hard-delete after 7 years (school records retention) |
| **Breach notification** | AWS GuardDuty + automated alert → Legal team SLA < 72 hours |
| **Data residency** | All data stored in `af-south-1` (AWS Cape Town) region |
