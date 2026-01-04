# Deployment Modes

ZeroTouch supports **Production** (bare-metal Talos) and **Preview** (GitHub Actions with Kind) modes.

## Quick Comparison

| Aspect | Production | Preview |
|--------|-----------|---------|
| **Infrastructure** | Bare-metal Talos | Kind (Docker) |
| **Networking** | Cilium | kindnet |
| **Storage** | Rook/local-path | Kind built-in |
| **Tenants** | Deployed | Excluded |
| **Config Source** | Tenant repo | Env vars |

**Why two modes?** Talos needs bare-metal/VMs. GitHub Actions uses Kind for CI/CD testing.

## Production Mode

**Bootstrap:** `./01-master-bootstrap.sh dev`

**Environment Variables:**
```bash
BOT_GITHUB_USERNAME=bot-user
BOT_GITHUB_TOKEN=ghp_xxx
TENANTS_REPO_NAME=org/tenant-repo
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=xxx
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

**Requires:** Private tenant repository with server configs ([setup guide](TENANT-REPOSITORY.md))

## Preview Mode

**Bootstrap:** `./01-master-bootstrap.sh --mode preview`

**Environment Variables:**
```bash
AWS_ACCESS_KEY_ID=ASIA...
AWS_SECRET_ACCESS_KEY=xxx
AWS_SESSION_TOKEN=IQoJb3...  # Required for OIDC
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
BOT_GITHUB_USERNAME=bot-user
BOT_GITHUB_TOKEN=ghp_xxx
```

## Preview Mode Patches

Patches in `scripts/bootstrap/patches/` adapt platform for Kind:

**Run all:** `./patches/00-apply-all-patches.sh --force`

## Tenant Repository

Production needs private repo with server configs and tenant definitions.

**Structure:**
```
tenant-repo/
├── environments/<ENV>/talos-values.yaml
├── repositories/<name>-repo.yaml
└── tenants/<name>/config.yaml
```

**Environment config:**
```yaml
controlplane:
  name: cp01-main
  ip: "SERVER_IP"
  rescue_password: "auto-generated"
workers:
  - name: worker01
    ip: "WORKER_IP"
    labels:
      workload.zerotouch.dev/databases: "true"
cluster:
  name: zerotouch-dev-01
talos:
  version: v1.11.5
kubernetes:
  version: v1.34.2
```

**Complete guide:** [Tenant Repository Setup](TENANT-REPOSITORY.md)

## Key Differences

**Production:** Cilium CNI, persistent NATS, tenant apps, full resources  
**Preview:** kindnet, NATS memory-only, no tenants, reduced resources

**References:** [Tenant Repository Setup](TENANT-REPOSITORY.md) | [Bootstrap Scripts](../scripts/bootstrap/README.md)
