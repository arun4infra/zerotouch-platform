# Stateful Resources Strategy

## Decision: Hybrid Approach

We use **different strategies based on data criticality**, not a one-size-fits-all approach.

---

## The Rule

```
IF data loss = catastrophic THEN managed service
ELSE self-hosted via Crossplane
```

---

## Implementation

| Resource Type | Environment | Strategy | Rationale |
|--------------|-------------|----------|-----------|
| **User Databases** | Production | **Managed (RDS/Neon)** | Data loss unacceptable, solo founder can't handle 3 AM failures |
| **User Databases** | Dev/Preview | **Self-hosted (CloudNativePG)** | Ephemeral data, cost-effective, GitOps-native |
| **Caches (Redis/Dragonfly)** | All | **Self-hosted** | Data reconstructable from DB, failure = temporary slowdown |
| **Application Services** | All | **Stateless** | No persistent state |

---

## Why Hybrid?

### Production User Data → Managed Service
- **Risk**: User data loss is business-ending
- **Reality**: Solo founder cannot guarantee 24/7 availability
- **Cost**: $100/month extra saves 5 hours/month of operational work
- **SLA**: Professional support and 99.95% uptime guarantee

### Dev/Preview → Self-Hosted
- **Risk**: Low (data is ephemeral, can recreate from fixtures)
- **Benefit**: Full GitOps compliance via Crossplane
- **Cost**: Significantly cheaper for multiple environments
- **Learning**: Understand PostgreSQL operations without production risk

### Caches → Always Self-Hosted
- **Risk**: Minimal (cache miss = DB query, not data loss)
- **Cost**: ElastiCache is expensive, Dragonfly on K8s is cheap
- **Recovery**: Automatic warm-up from application traffic

## GitOps Exception

**Production databases are the ONE exception to "GitOps is Law":**
- Managed via Terraform in separate repository
- Terraform state stored in S3 with locking
- Automated apply via GitHub Actions
- Connection secrets synced to cluster via External Secrets Operator

**Justification**: Operational reliability > architectural purity for user data.

## Key Takeaway

**Not all stateful resources are equal.** Optimize for:
- **User data**: Maximum reliability (managed)
- **Reconstructable data**: Cost efficiency (self-hosted)
- **Solo founder time**: Automate the critical, self-host the safe
