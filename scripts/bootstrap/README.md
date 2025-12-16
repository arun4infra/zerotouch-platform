# Bootstrap Scripts

These scripts are for **one-time cluster initialization only**. After bootstrap, everything is managed via GitOps (ArgoCD).

## Documentation

- **[Deployment Modes](../../docs/DEPLOYMENT-MODES.md)** - Production vs Preview modes, environment variables, patches
- **[Tenant Repository Setup](../../docs/TENANT-REPOSITORY.md)** - How to create and structure your tenant repository

## Quick Start

### Production Mode

```bash
# Bootstrap using environment name (fetches config from tenant repo)
./01-master-bootstrap.sh dev

# Or manual mode with explicit parameters
./01-master-bootstrap.sh <server-ip> <root-password> --worker-nodes worker01:95.216.151.243
```

### Preview Mode (CI/CD)

```bash
# Bootstrap in preview mode (Kind cluster)
./01-master-bootstrap.sh --mode preview
```

## Recommended: Use Makefile

The easiest way to bootstrap is via the Makefile:

```bash
# Bootstrap dev environment
make bootstrap ENV=dev

# Or use shortcuts
make dev-bootstrap
make staging-bootstrap
make prod-bootstrap
```

The Makefile automatically:
- Reads environment-specific config from tenant repository
- Extracts IPs, passwords, and worker node configuration
- Calls the master bootstrap script with correct parameters

## Essential Scripts

### 1. `01-master-bootstrap.sh`
**Purpose:** Complete cluster setup (control plane + optional workers)  
**Usage:** `./01-master-bootstrap.sh <server-ip> <root-password> [--worker-nodes <list>]`  
**When:** First time cluster creation (usually called via Makefile)  
**What it does:**
- Installs Talos on control plane node
- Bootstraps Kubernetes cluster (etcd + 180s stabilization wait)
- Installs ArgoCD (with control-plane tolerations via kustomize)
- Waits for platform-bootstrap Application to sync
- Verifies all child Applications are created
- Optionally installs worker nodes
- **Auto-injects ESO credentials** from AWS CLI (`aws configure`)
- **Auto-configures private Git repositories** from `.env.ssm`
- Generates credentials file with all access information

**Key Features:**
- `kubectl_retry` with exponential backoff (20 attempts, 5min max)
- Fails fast if tenant ApplicationSet exists but no GitHub credentials
- Warns if cluster already exists (prevents destructive re-runs)

### 2. `02-install-talos-rescue.sh`
**Purpose:** Install Talos OS on a rescue-mode server  
**Usage:** Called by master bootstrap script  
**When:** Provisioning new nodes (manual, outside GitOps)

### 3. `03-install-argocd.sh`
**Purpose:** Install ArgoCD with control-plane tolerations  
**Usage:** Called by master bootstrap script  
**When:** Initial cluster setup  
**What it does:**
- Uses kustomize to apply ArgoCD with toleration patches
- Applies root Application (`bootstrap/root.yaml`)
- Waits for ArgoCD to become ready
- Retrieves admin password

### 4. `05-inject-secrets.sh`
**Purpose:** Inject AWS credentials for External Secrets Operator  
**Usage:** 
- `./05-inject-secrets.sh` (auto-fetches from AWS CLI)
- `./05-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>` (manual)  
**When:** Called automatically by master bootstrap, or run manually  
**What it does:**
- Reads AWS credentials from `aws configure` by default
- Creates `aws-access-token` secret in `external-secrets` namespace
- Enables ESO to sync secrets from AWS SSM Parameter Store

### 5. `06-inject-ssm-parameters.sh`
**Purpose:** Inject secrets from `.env.ssm` to AWS SSM Parameter Store  
**Usage:** `./06-inject-ssm-parameters.sh`  
**When:** Before bootstrap, to populate SSM with secrets  
**What it does:**
- Reads `.env.ssm` file
- Creates/updates parameters in AWS SSM Parameter Store
- All parameters created as SecureString (encrypted)

### 6. `07-add-private-repo.sh`
**Purpose:** ⚠️ **DEPRECATED** - Emergency fallback for adding repository credentials
**Usage:** `./07-add-private-repo.sh <repo-url> <username> <token>`
**When:** Emergency use only (credentials should be managed via ExternalSecrets)
**What it does:**
- Creates ArgoCD repository secret imperatively
- ⚠️ Not GitOps-native - use only if ExternalSecrets fail

**Normal workflow:** Repository credentials are synced from AWS SSM via ExternalSecrets.
See: [Private Repository Architecture](../../docs/architecture/private-repository-architecture.md)

### 7. `04-add-worker-node.sh`
**Purpose:** Add a worker node to existing cluster  
**Usage:** `./04-add-worker-node.sh --node-name worker01 --node-ip <IP> --node-role database --server-password <PASS>`  
**When:** Scaling cluster capacity (infrastructure operation)  
**What it does:**
- Installs Talos on new server
- Applies worker configuration
- Joins node to cluster

### 8. `08-verify-agent-executor-deployment.sh`
**Purpose:** Comprehensive verification of agent-executor deployment  
**Usage:** `./08-verify-agent-executor-deployment.sh`  
**When:** After bootstrap completes  
**What it does:**
- Verifies ApplicationSet and Application status
- Checks namespace, ExternalSecrets, Crossplane claims
- Validates NATS stream, deployment, service, KEDA ScaledObject
- Checks pod health and logs

## What's NOT Here (By Design)

### ❌ Foundation/Database Deployment
**Why removed:** These are managed by ArgoCD via `platform-bootstrap` Application.  
**How to deploy:** Commit manifests to Git, ArgoCD syncs automatically.

### ❌ Post-Reboot Verification
**Why removed:** Use `scripts/validate-cluster.sh` instead.

## GitOps Workflow

After bootstrap:
1. All changes go through Git commits
2. ArgoCD syncs automatically
3. No manual kubectl/helm commands
4. Validation via `scripts/validate-cluster.sh`

## Configuration Files

### `.env.ssm` (gitignored)
Contains secrets for SSM Parameter Store:
```bash
# SSM Parameters
/zerotouch/prod/kagent/openai_api_key=sk-...
/zerotouch/prod/agent-executor/openai_api_key=sk-...
/zerotouch/prod/agent-executor/anthropic_api_key=sk-ant-...
/zerotouch/prod/platform/ghcr/username=your-github-username
/zerotouch/prod/platform/ghcr/password=ghp_...

# ArgoCD Private Repository Credentials (synced via ExternalSecrets)
/zerotouch/prod/argocd/repos/zerotouch-tenants/url=https://github.com/arun4infra/zerotouch-tenants.git
/zerotouch/prod/argocd/repos/zerotouch-tenants/username=arun4infra
/zerotouch/prod/argocd/repos/zerotouch-tenants/password=ghp_xxxxx

/zerotouch/prod/argocd/repos/bizmatters/url=https://github.com/arun4infra/bizmatters.git
/zerotouch/prod/argocd/repos/bizmatters/username=arun4infra
/zerotouch/prod/argocd/repos/bizmatters/password=ghp_xxxxx
```

**Note:** Repository credentials are managed via ExternalSecrets, not imperative scripts.
See: [Private Repository Architecture](../../docs/architecture/private-repository-architecture.md)

### `environments/<ENV>/talos-values.yaml` (gitignored)
Environment-specific configuration:
```yaml
controlplane:
  name: cp01-main
  ip: "46.62.218.181"
  rescue_password: "..."

workers:
  - name: worker01
    ip: "95.216.151.243"
    rescue_password: "..."
    labels:
      workload.bizmatters.dev/intelligence: "true"
      workload.bizmatters.dev/databases: "true"
```

### `bootstrap/config.yaml`
Centralized Git repository and branch configuration:
```yaml
REPO_URL: https://github.com/arun4infra/zerotouch-platform.git
TARGET_REVISION: feature/agent-executor
```

## Directory Structure

```
scripts/
├── bootstrap/          # One-time cluster initialization
│   ├── 01-master-bootstrap.sh         # Orchestrates entire bootstrap
│   ├── 02-install-talos-rescue.sh     # Talos OS installation
│   ├── 03-install-argocd.sh           # ArgoCD with kustomize
│   ├── 04-add-worker-node.sh          # Add worker nodes
│   ├── 05-inject-secrets.sh           # ESO credentials (auto-fetch from AWS CLI)
│   ├── 06-inject-ssm-parameters.sh    # Populate SSM from .env.ssm
│   ├── 07-add-private-repo.sh         # ArgoCD private repo credentials
│   ├── 08-verify-agent-executor-deployment.sh  # Deployment verification
│   ├── embed-cilium.sh                # Embed Cilium in Talos config
│   ├── update-target-revision.sh      # Update Git branch across Applications
│   └── *-examples.md                  # Usage examples for each script
├── validate-cluster.sh                # Post-sync validation
├── wait-for-pods.sh                   # Wait for pods to be ready
└── wait-for-sync.sh                   # Wait for ArgoCD sync
```
