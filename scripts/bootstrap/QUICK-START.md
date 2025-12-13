# Quick Start Guide

## Prerequisites

1. **AWS CLI configured** with credentials:
   ```bash
   aws configure
   # The bootstrap will auto-fetch credentials from here
   ```

2. **Environment configuration** file created:
   ```bash
   cp environments/dev/talos-values.yaml.example environments/dev/talos-values.yaml
   # Edit with your actual IPs and passwords
   ```

3. **Secrets file** created (optional, for SSM parameters):
   ```bash
   cp .env.ssm.example .env.ssm
   # Edit with your actual secrets and private repo URLs
   ```

## New Cluster Setup

### Step 1: Populate SSM Parameters (Optional)

If you have secrets to inject into AWS SSM:
```bash
./scripts/bootstrap/06-inject-ssm-parameters.sh
```

### Step 2: Bootstrap Cluster

**Recommended: Use Makefile**
```bash
# Bootstrap dev environment
make bootstrap ENV=dev

# Or use shortcuts
make dev-bootstrap
make staging-bootstrap  
make prod-bootstrap
```

**Alternative: Direct script invocation**
```bash
# Single node cluster
./scripts/bootstrap/01-master-bootstrap.sh <server-ip> <root-password>

# Multi-node cluster with workers
./scripts/bootstrap/01-master-bootstrap.sh <server-ip> <root-password> \
  --worker-nodes worker01:95.216.151.243 \
  --worker-password <worker-password>
```

**What happens automatically:**
- ✅ Talos OS installation and cluster bootstrap
- ✅ ArgoCD installation with control-plane tolerations
- ✅ ESO credentials injected from AWS CLI
- ✅ Private Git repositories configured from `.env.ssm`
- ✅ Platform components deployed via ArgoCD
- ✅ Credentials file generated

### Step 3: Verify Deployment
```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Validate cluster
./scripts/validate-cluster.sh

# Access ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Add Worker Node (After Initial Setup)

```bash
./scripts/bootstrap/04-add-worker-node.sh \
  --node-name worker01 \
  --node-ip 95.216.151.243 \
  --node-role intelligence \
  --server-password <password>
```

## Bootstrap Script Sequence

1. **01-master-bootstrap.sh** - Orchestrates entire setup
   - Checks if cluster already exists (warns before destructive operations)
   - Calls 02-install-talos-rescue.sh (installs Talos)
   - Bootstraps Kubernetes cluster (etcd + 180s stabilization wait)
   - Calls 03-install-argocd.sh (installs ArgoCD with kustomize)
   - Applies root Application (platform-bootstrap)
   - **Waits for platform-bootstrap to sync** (with timeout)
   - **Verifies all child Applications are created**
   - Installs worker nodes (if specified)
   - **Auto-injects ESO credentials** from AWS CLI (`aws configure`)
   - **Waits for ESO to become ready**
   - **Auto-configures private Git repositories** from `.env.ssm` (ARGOCD_PRIVATE_REPO_*)
   - **Fails fast** if tenant ApplicationSet exists but no GitHub credentials
   - Generates credentials file with all access information

2. **05-inject-secrets.sh** - ESO credential injection
   - Auto-fetches from AWS CLI by default (no arguments needed)
   - Or accepts manual credentials: `./05-inject-secrets.sh <KEY_ID> <SECRET>`
   - Called automatically by master script
   - Enables secret sync from AWS SSM Parameter Store

3. **07-add-private-repo.sh** - Private repository configuration
   - Called automatically by master script (reads from `.env.ssm`)
   - Or run manually: `./07-add-private-repo.sh <repo-url> <username> <token>`
   - Enables ArgoCD to access private Git repositories

4. **04-add-worker-node.sh** - Optional, for scaling
   - Adds additional worker nodes
   - Calls 02-install-talos-rescue.sh internally

## What Gets Deployed by ArgoCD

After bootstrap, ArgoCD automatically deploys:
- External Secrets Operator (ESO)
- Crossplane (infrastructure provisioning)
- KEDA (event-driven autoscaling)
- Kagent (AI agent platform)
- Intelligence workloads
- Database layer (if workers exist)

## Troubleshooting

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check ArgoCD sync status
kubectl get applications -n argocd

# Check ESO status
kubectl get clustersecretstore
kubectl get externalsecret -A

# Validate everything
./scripts/validate-cluster.sh
```

## Important Files

**Generated during bootstrap:**
- `bootstrap/talos/talosconfig` - Talos cluster config
- `bootstrap/talos/nodes/*/config.yaml` - Node-specific Talos configs
- `~/.kube/config` - Kubernetes config
- `scripts/bootstrap/bootstrap-credentials/*.txt` - All access credentials

**Configuration (gitignored):**
- `environments/<ENV>/talos-values.yaml` - Environment-specific config (IPs, passwords)
- `.env.ssm` - Secrets and private repo URLs

**Centralized config (committed):**
- `bootstrap/config.yaml` - Git repo URL and TARGET_REVISION
- `bootstrap/argocd/kustomization.yaml` - ArgoCD with control-plane tolerations

## AWS SSM Parameters Required

Ensure these exist in AWS SSM Parameter Store (use `06-inject-ssm-parameters.sh`):
- `/zerotouch/prod/kagent/openai_api_key` - OpenAI API key for kagent
- `/zerotouch/prod/agent-executor/openai_api_key` - OpenAI API key for agent-executor
- `/zerotouch/prod/agent-executor/anthropic_api_key` - Anthropic API key
- `/zerotouch/prod/platform/ghcr/username` - GitHub username for GHCR
- `/zerotouch/prod/platform/ghcr/password` - GitHub token for GHCR
- `/zerotouch/prod/platform/github/username` - GitHub username for ArgoCD
- `/zerotouch/prod/platform/github/token` - GitHub token for ArgoCD

## Private Git Repositories

Configure in `.env.ssm`:
```bash
ARGOCD_PRIVATE_REPO_1=https://github.com/arun4infra/zerotouch-tenants.git
ARGOCD_PRIVATE_REPO_2=https://github.com/arun4infra/bizmatters.git
# Add more as needed: ARGOCD_PRIVATE_REPO_3, etc.
```

The master bootstrap script will automatically add these to ArgoCD.
