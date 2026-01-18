# Tenant Creation Template

## Overview

This template guides you through creating a new tenant service in the ZeroTouch platform using the GitOps pattern with ArgoCD, Crossplane, and Kustomize.

---

## Prerequisites

- Access to `zerotouch-tenants` repository
- AWS SSM Parameter Store access (for secrets)
- External resources provisioned (if using Type 1: BYO Connection pattern)

---

## Step 1: Define Tenant Metadata

**Tenant Name:** `<service-name>` (kebab-case, e.g., `identity-service`)  
**Namespace:** `<namespace>` (e.g., `platform-identity`)  
**Purpose:** `<brief description>`

---

## Step 2: Create Service Repository Structure

**Core Service Repository:** `<service-name>/` (separate from deployment)
**Deployment Repository:** `zerotouch-tenants/tenants/<service-name>/`

### 2.1 Core Service Repository Structure

```bash
# Create core service repository
mkdir <service-name>
cd <service-name>

# Initialize service structure
mkdir -p {src,migrations,scripts/ci,tests}
```

**Core Service Directory Layout:**
```
<service-name>/
├── src/                          # Source code
├── migrations/                   # Database migrations
├── scripts/
│   └── ci/
│       ├── run-migrations.sh     # Migration script for ArgoCD
│       └── in-cluster-test.sh    # Platform CI integration
├── tests/                        # Unit and integration tests
├── ci/
│   └── config.yaml              # Platform CI configuration
├── package.json                 # Dependencies and scripts
├── Dockerfile                   # Multi-stage build
├── tsconfig.json               # TypeScript configuration
└── README.md                   # Service documentation
```

### 2.2 Deployment Repository Structure

```bash
cd zerotouch-tenants/tenants

# Create tenant directory structure
mkdir -p <service-name>/{base/{claims,external-secrets},overlays/{dev,staging,production}}

# Create namespace file
touch <service-name>/00-namespace.yaml
```

**Deployment Directory Layout:**
```
zerotouch-tenants/tenants/<service-name>/
├── 00-namespace.yaml
├── base/
│   ├── kustomization.yaml
│   ├── claims/
│   │   ├── dragonfly-claim.yaml (optional)
│   │   └── postgres-claim.yaml (optional)
│   └── external-secrets/
│       ├── <service-name>-secret1-es.yaml
│       ├── <service-name>-secret2-es.yaml
│       └── <service-name>-secret3-es.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── webservice-claim.yaml
    │   └── migration-job.yaml (if database migrations needed)
    ├── staging/
    │   ├── kustomization.yaml
    │   └── webservice-claim.yaml
    └── production/
        ├── kustomization.yaml
        └── webservice-claim.yaml
```

---

## Step 3: Create Core Service CI Scripts

### 3.1 Migration Script

**File:** `<service-name>/scripts/ci/run-migrations.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Database Migrations Script - <service-name>
# ==============================================================================
# Runs database migrations for <service-name>
# Used by ArgoCD PreSync hooks and CI workflows
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

main() {
    log_info "Starting database migrations for <service-name>..."
    
    # Validate required environment variables
    if [[ -z "${DATABASE_URL:-}" ]]; then
        log_error "Required environment variable not set: DATABASE_URL"
        return 1
    fi
    
    log_info "Database connection configured via DATABASE_URL"
    
    # Set migration directory
    MIGRATION_DIR="${MIGRATION_DIR:-/app/migrations}"
    
    if [[ ! -d "$MIGRATION_DIR" ]]; then
        log_error "Migration directory not found: $MIGRATION_DIR"
        return 1
    fi
    
    log_info "Running migrations from: $MIGRATION_DIR"
    
    # Run service-specific migration command
    npm run migrate
    
    log_success "Database migrations completed for <service-name>"
}

main "$@"
```

### 3.2 Platform CI Integration Script

**File:** `<service-name>/scripts/ci/in-cluster-test.sh`

```bash
#!/bin/bash
set -euo pipefail

# ==============================================================================
# Service CI Entry Point for <service-name>
# ==============================================================================
# Purpose: Standardized entry point for platform-based CI testing
# Usage: ./scripts/ci/in-cluster-test.sh
# ==============================================================================

# Get platform branch from service config
if [[ -f "ci/config.yaml" ]]; then
    if command -v yq &> /dev/null; then
        PLATFORM_BRANCH=$(yq eval '.platform.branch // "main"' ci/config.yaml)
    else
        PLATFORM_BRANCH="main"
    fi
else
    PLATFORM_BRANCH="main"
fi

# Always ensure fresh platform checkout
if [[ -d "zerotouch-platform" ]]; then
    echo "Removing existing platform checkout for fresh clone..."
    rm -rf zerotouch-platform
fi

echo "Cloning fresh zerotouch-platform repository (branch: $PLATFORM_BRANCH)..."
git clone -b "$PLATFORM_BRANCH" https://github.com/arun4infra/zerotouch-platform.git zerotouch-platform

# Run platform script
./zerotouch-platform/scripts/bootstrap/preview/tenants/in-cluster-test.sh
```

### 3.3 Platform CI Configuration

**File:** `<service-name>/ci/config.yaml`

```yaml
service:
  name: "<service-name>"
  namespace: "<namespace>"

build:
  dockerfile: "Dockerfile"
  context: "."
  tag: "ci-test"

test:
  timeout: 600
  parallel: true

deployment:
  wait_timeout: 300
  health_endpoint: "/health"
  liveness_endpoint: "/health"

dependencies:
  platform:
    - cnpg-operator
    - external-secrets
    - crossplane-providers
  external: []
  internal:
    - redis  # or postgres, depending on service needs

env:
  NODE_ENV: "test"
  LOG_LEVEL: "debug"

diagnostics:
  pre_deploy:
    check_dependencies: true
    check_platform_apis: true
  post_deploy:
    test_health_endpoint: true
    test_database_connection: false
    test_service_connectivity: true

platform:
  branch: "main"
```

---

## Step 4: Create Namespace

**File:** `00-namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <namespace>
  labels:
    tenant: <service-name>
    managed-by: zerotouch-platform
```

---

## Step 4: Provision External Resources (Type 1 Pattern)

### 4.1 Provision External Services

**Examples:**
- AWS Cognito User Pool (for OIDC)
- Neon PostgreSQL (for database)
- AWS RDS (for database)
- External API keys

### 4.2 Inject Secrets to AWS SSM

**Create `.env.ssm` file:**
```bash
# Format: /zerotouch/<env>/<service-name>/<key>=<value>
/zerotouch/prod/<service-name>/database_url=postgresql://user:pass@host:5432/db
/zerotouch/prod/<service-name>/api_key=secret123
/zerotouch/prod/<service-name>/jwt_private_key=-----BEGIN RSA PRIVATE KEY-----...
```

**Inject to SSM:**
```bash
cd zerotouch-platform
./scripts/bootstrap/install/08-inject-ssm-parameters.sh
```

---

## Step 5: Create ExternalSecrets

### 5.1 ExternalSecret Template

**File:** `base/external-secrets/<service-name>-<secret-name>-es.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: <service-name>-<secret-name>
  namespace: <namespace>
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: <service-name>-<secret-name>
  data:
  - secretKey: <ENV_VAR_NAME>
    remoteRef:
      key: /zerotouch/prod/<service-name>/<key>
```

**Example:** Database connection secret
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-db
  namespace: my-namespace
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: my-service-db
  data:
  - secretKey: DATABASE_URL
    remoteRef:
      key: /zerotouch/prod/my-service/database_url
```

---

## Step 6: Create Infrastructure Claims (Optional)

### 6.1 DragonflyInstance (Cache)

**File:** `base/claims/dragonfly-claim.yaml`

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: <service-name>-cache
  namespace: <namespace>
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  size: small  # small, medium, large
  storageGB: 10
```

**Auto-Generated:**
- Secret: `<service-name>-cache-conn`
- Keys: `endpoint`, `port`, `password`

### 6.2 PostgresInstance (Database)

**File:** `base/claims/postgres-claim.yaml`

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: <service-name>-db
  namespace: <namespace>
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  size: medium  # small, medium, large
  version: "16"
  storageGB: 20
```

**Auto-Generated:**
- Secret: `<service-name>-db-conn`
- Keys: `endpoint`, `port`, `database`, `username`, `password`

---

## Step 7: Create Base Kustomization

**File:** `base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # External Secrets (Wave 0)
  - external-secrets/<service-name>-secret1-es.yaml
  - external-secrets/<service-name>-secret2-es.yaml
  
  # Infrastructure Claims (Wave 0) - Optional
  - claims/dragonfly-claim.yaml
  - claims/postgres-claim.yaml

commonLabels:
  app.kubernetes.io/name: <service-name>
  tenant: <service-name>

commonAnnotations:
  managed-by: "zerotouch-platform"
  tenant: "<service-name>"
```

---

## Step 8: Create WebService Claim

### 8.1 WebService Template

**File:** `overlays/dev/webservice-claim.yaml`

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: <service-name>
  namespace: <namespace>
  annotations:
    argocd.argoproj.io/sync-wave: "6"
spec:
  image: "ghcr.io/<org>/<service-name>:latest"
  port: 8080
  size: medium  # micro, small, medium, large
  replicas: 3
  
  # Secret injection (envFrom pattern)
  secret1Name: <service-name>-secret1  # ExternalSecret or auto-generated
  secret2Name: <service-name>-secret2  # ExternalSecret or auto-generated
  secret3Name: <service-name>-cache-conn  # Auto-generated by DragonflyInstance
  
  # Health checks
  healthPath: /health
  readyPath: /ready
  
  # Optional: External ingress
  # hostname: "api.example.com"
  # pathPrefix: "/api"
  
  # Optional: Database (creates internal PostgresInstance)
  # databaseName: "<service-name>"
  # databaseSize: medium
```

### 8.2 Resource Coupling Pattern

**Platform Principle: Loose Coupling**

Services MUST be loosely coupled with resources. Services receive connection details via environment variables and should work regardless of where the resource is hosted.

**For Databases:**
1. Provision database (external: Neon/RDS, or internal: PostgresInstance claim)
2. Store connection string in SSM (external) or use auto-generated secret (internal)
3. Create ExternalSecret to sync to K8s (external only)
4. Reference secret via `secret2Name` in WebService

**External Database Example:**
```yaml
spec:
  # NO databaseName field!
  secret2Name: <service-name>-db  # Points to ExternalSecret
```

**Internal Database Example:**
```yaml
# Create PostgresInstance claim separately in base/claims/
# Reference auto-generated secret
spec:
  secret1Name: <service-name>-db-conn  # Auto-generated by PostgresInstance
```

**Key Principle:** Service code receives `DATABASE_URL` environment variable and doesn't care if it's Neon, RDS, or CloudNativePG. Provider migration = update secret only.

---

## Step 9: Create Migration Job (If Database Required)

### 9.1 Migration Job Template

**File:** `overlays/dev/migration-job.yaml`

```yaml
# Database migration job - runs after database is ready, before app deployment
apiVersion: batch/v1
kind: Job
metadata:
  name: <service-name>-migrations
  namespace: <namespace>
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
    argocd.argoproj.io/sync-wave: "2"
spec:
  template:
    metadata:
      name: <service-name>-migrations
    spec:
      restartPolicy: Never
      imagePullSecrets:
      - name: ghcr-pull-secret
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: migrations
        image: ghcr.io/<org>/<service-name>:latest
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        command: ["./scripts/ci/run-migrations.sh"]
        envFrom:
        - secretRef:
            name: <service-name>-db
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
  backoffLimit: 3
  activeDeadlineSeconds: 600
```

### 9.2 Update Overlay Kustomization

**File:** `overlays/dev/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - webservice-claim.yaml
  - migration-job.yaml  # Add if database migrations needed

commonLabels:
  app.kubernetes.io/instance: dev

namespace: <namespace>
```

---

## Step 10: Create Overlay Kustomization

**File:** `overlays/dev/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - webservice-claim.yaml

commonLabels:
  app.kubernetes.io/instance: dev

namespace: <namespace>
```

**Repeat for `staging` and `production` overlays with environment-specific values.**

---

## Step 10: Sync Wave Order

**Wave 0: Foundation (Secrets & Infrastructure)**
- ExternalSecrets
- DragonflyInstance (if used)
- PostgresInstance (if used)
- Auto-generated secrets

**Wave 6: Platform APIs & Applications**
- WebService claim
- Auto-generated: Deployment, Service, ServiceAccount

**Annotation:**
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # or "6"
```

---

## Step 11: Commit and Deploy

```bash
cd zerotouch-tenants

# Add all files
git add tenants/<service-name>/

# Commit
git commit -m "Add <service-name> tenant"

# Push
git push origin main
```

**ArgoCD will automatically:**
1. Detect new tenant
2. Create ArgoCD Application
3. Deploy Wave 0 resources (secrets, infrastructure)
4. Wait for Wave 0 to be healthy
5. Deploy Wave 6 resources (application)

---

## Step 12: Verify Deployment

```bash
# Check namespace
kubectl get namespace <namespace>

# Check ExternalSecrets synced
kubectl get externalsecret -n <namespace>

# Check infrastructure claims (if used)
kubectl get dragonflyinstance -n <namespace>
kubectl get postgresinstance -n <namespace>

# Check auto-generated secrets
kubectl get secret -n <namespace>

# Check WebService deployed
kubectl get webservice -n <namespace>

# Check application running
kubectl get deployment -n <namespace>
kubectl get pods -n <namespace>

# Check service created
kubectl get service -n <namespace>
```

---

## Step 13: Update AgentGateway (If Needed)

**File:** `zerotouch-platform/platform/agentgateway/config.yaml`

```yaml
routes:
  - path: /<service-path>/*
    backend: http://<service-name>.<namespace>.svc.cluster.local:<port>
```

**Apply:**
```bash
cd zerotouch-platform
kubectl apply -f platform/agentgateway/config.yaml
```

---

## Common Patterns

### Pattern 1: Stateless Service (No Database)

```yaml
# No database claims
# Only ExternalSecrets for API keys, JWT keys, etc.
spec:
  secret1Name: <service-name>-api-keys
  secret2Name: <service-name>-jwt-keys
```

### Pattern 2: Service with External Database (Neon/RDS)

```yaml
# Provision database externally
# Create ExternalSecret for connection
# Reference in WebService
spec:
  secret1Name: <service-name>-db  # ExternalSecret from SSM
```

### Pattern 3: Service with Internal Database (PostgresInstance)

```yaml
# Create PostgresInstance claim in base/claims/
# Reference auto-generated secret in WebService
spec:
  secret1Name: <service-name>-db-conn  # Auto-generated by PostgresInstance
```

### Pattern 4: Service with Cache (Dragonfly)

```yaml
# Create DragonflyInstance claim in base/claims/
# Reference auto-generated secret in WebService
spec:
  secret1Name: <service-name>-cache-conn  # Auto-generated by DragonflyInstance
```

### Pattern 5: Service with External Ingress

```yaml
spec:
  hostname: "api.example.com"
  pathPrefix: "/v1"
```

**Note:** All patterns follow loose coupling - services receive connection details via environment variables and work regardless of resource location.

---

## Troubleshooting

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret <name> -n <namespace>

# Force sync
kubectl annotate externalsecret <name> \
  force-sync=$(date +%s) -n <namespace>

# Check ClusterSecretStore
kubectl get clustersecretstore aws-parameter-store
```

### WebService Not Deploying

```bash
# Check WebService status
kubectl describe webservice <name> -n <namespace>

# Check Crossplane logs
kubectl logs -n crossplane-system deployment/crossplane

# Check if secrets exist
kubectl get secret -n <namespace>
```

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

---

## Checklist

### Core Service Repository
- [ ] Service repository created (`<service-name>/`)
- [ ] Source code structure created (`src/`, `tests/`, `migrations/`)
- [ ] CI scripts created (`scripts/ci/run-migrations.sh`, `scripts/ci/in-cluster-test.sh`)
- [ ] Platform CI config created (`ci/config.yaml`)
- [ ] Dockerfile created with multi-stage build
- [ ] Package.json with migration script (`npm run migrate`)
- [ ] Scripts made executable (`chmod +x scripts/ci/*.sh`)

### Deployment Repository
- [ ] Tenant name defined (kebab-case)
- [ ] Namespace defined
- [ ] Directory structure created
- [ ] Namespace manifest created
- [ ] External resources provisioned (if Type 1)
- [ ] Secrets injected to SSM
- [ ] ExternalSecrets created with Wave 0 annotation
- [ ] Infrastructure claims created (if needed) with Wave 0 annotation
- [ ] Base kustomization.yaml created
- [ ] WebService claim created with Wave 6 annotation
- [ ] Migration job created (if database required) with Wave 2 annotation
- [ ] Overlay kustomizations created (dev, staging, production)
- [ ] Committed and pushed to zerotouch-tenants
- [ ] ArgoCD detected and deployed tenant
- [ ] Deployment verified (pods running)
- [ ] AgentGateway updated (if needed)

---

## Example: Complete Identity Service

See `bizmatters/.kiro/specs/platform/pending/phase0-authentication/00-platform-login/resources/resource-strategy-application.md` for a complete example of the Identity Service tenant following this template.
