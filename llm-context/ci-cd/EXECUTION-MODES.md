# Execution Modes

ZeroTouch supports **Production** (bare-metal Talos) and **Preview** (GitHub Actions with Kind) modes.

## Quick Comparison

| Aspect | Production | Preview |
|--------|-----------|---------|
| **Infrastructure** | Bare-metal Talos | Kind (Docker) |
| **Networking** | Cilium | kindnet |
| **Storage** | Rook/local-path | Kind built-in |
| **Tenants** | Deployed | Excluded |
| **Config Source** | Tenant repo | Env vars |
| **Deployment** | GitOps (ArgoCD) | Manual (CI scripts) |

**Why two modes?** Talos needs bare-metal/VMs. GitHub Actions uses Kind for CI/CD testing.

## Deployment Flow Comparison

### Production Mode Deployment
```
1. Code → Git Repository
2. ArgoCD syncs from tenant repository
3. ArgoCD applies platform claims automatically
4. Crossplane provisions resources
5. Applications deployed via GitOps
```
**Key:** Fully automated, declarative, no manual intervention

### Preview Mode Deployment  
```
1. CI builds image with specific tag (sha-abc123)
2. CI calls deploy.sh with built image tag
3. deploy.sh updates platform claims with CI tag
4. deploy.sh applies platform claims manually
5. Applications deployed for testing
```
**Key:** Manual simulation of GitOps for testing purposes

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

### Production Flow
- **GitOps-driven:** ArgoCD automatically syncs from tenant repository
- **Declarative:** All changes via Git commits, no manual kubectl
- **Image management:** Tenant kustomization overlays handle image tags
- **Persistent:** Long-running clusters with proper lifecycle management

### Preview/CI Flow  
- **Script-driven:** Manual kubectl apply simulates ArgoCD behavior
- **Imperative:** CI scripts directly modify and apply manifests
- **Image management:** deploy.sh replaces hardcoded tags with CI-built images
- **Ephemeral:** Temporary Kind clusters destroyed after testing

**References:** [Tenant Repository Setup](TENANT-REPOSITORY.md) | [Bootstrap Scripts](../scripts/bootstrap/README.md)
