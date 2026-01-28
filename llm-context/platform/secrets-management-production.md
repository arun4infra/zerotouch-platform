# Platform Secret Management: Production Architecture
**Scope:** Development, Staging, Production Environments

## Executive Summary
Production secrets are managed through a **"Push-to-Parameter-Store, Pull-to-Cluster"** model. 
We strictly separate **Secret Values** (stored in AWS SSM) from **Secret Definitions** (stored in Git).
The CI/CD pipeline acts as the bridge, ensuring secrets are injected before deployment, while ESO handles synchronization.

## Architecture Wireframe

```text
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           PRODUCTION SECRET LIFECYCLE                               │
└─────────────────────────────────────────────────────────────────────────────────────┘

   1. DEFINITION (Git)                  2. INJECTION (GitHub Actions)
   (Structure & Metadata)               (Values & Payloads)
┌───────────────────────────┐        ┌───────────────────────────┐
│ zerotouch-tenants/        │        │ .github/workflows/        │
│ ├── base/                 │        │ └── release-pipeline.yml  │
│ │   └── db-es.yaml        │        │                           │
│ │       key: /.../_ENV_/  │        │   Step: Inject Secrets    │
│ └── overlays/prod/        │        │   Script: sync-ssm.sh     │
│     └── kustomization.yaml│        │                           │
│         [Patch: _ENV_→prod]        └─────────────┬─────────────┘
└─────────────┬─────────────┘                      │
              │ Git Push                           │ AWS API (PutParameter)
              ▼                                    ▼
┌───────────────────────────┐        ┌───────────────────────────┐
│ ARGOCD CONTROLLER         │        │ AWS SSM PARAMETER STORE   │
│ • Syncs ExternalSecret    │        │ • /zerotouch/prod/...     │
│   Manifest to Cluster     │        │ • /zerotouch/stg/...      │
│                           │        │ • Encrypted (SecureString)│
└─────────────┬─────────────┘        └─────────────┬─────────────┘
              │                                    │
              │ Apply CRD                          │ Fetch Value
              ▼                                    ▼
┌────────────────────────────────────────────────────────────────┐
│ KUBERNETES CLUSTER (Target Namespace)                          │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│    ┌───────────────────┐       ┌──────────────────────────┐    │
│    │ ExternalSecret    │ <──── │ ExternalSecrets Operator │    │
│    │ (The Request)     │       │ (The Worker)             │    │
│    └─────────┬─────────┘       └──────────────────────────┘    │
│              │                                                 │
│              ▼                                                 │
│    ┌───────────────────┐       ┌──────────────────────────┐    │
│    │ K8s Secret        │ ────> │ Pod (Deployment)         │    │
│    │ (The Result)      │ Mount │ envFrom: secretRef       │    │
│    └───────────────────┘       └──────────────────────────┘    │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## The Workflow Steps

### 1. Definition (The Placeholder Pattern)
In the `base` directory, we define *what* the secret is, but use a placeholder for the environment path.

**File:** `tenants/<service>/base/external-secrets/db-es.yaml`
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: service-db
  labels:
    zerotouch.io/managed: "true"  # Crucial for Force Sync
spec:
  data:
  - secretKey: DATABASE_URL
    remoteRef:
      # Placeholder prevents accidental prod access if overlay fails
      key: /zerotouch/_ENV_/service/database_url 
```

### 2. Contextualization (The Overlay)
The Kustomize overlay replaces the placeholder with the specific environment string.

**File:** `tenants/<service>/overlays/production/patches/secrets.yaml`
```yaml
- op: replace
  path: /spec/data/0/remoteRef/key
  value: /zerotouch/prod/service/database_url
```

### 3. Injection (The Pipeline)
The GitHub Actions runner executes `sync-secrets-to-ssm.sh` before deployment.
*   **Normalization:** Converts `DATABASE_URL` -> `database_url` (Lowercase).
*   **Validation:** Rejects keys with hyphens.
*   **Storage:** Pushes to `/zerotouch/<env>/<service>/<key>`.

### 4. Synchronization (The Force Refresh)
To avoid the default 1h refresh interval of ESO, the pipeline triggers an immediate sync post-deployment.

```bash
kubectl annotate externalsecret \
  -n <namespace> \
  -l zerotouch.io/managed=true \
  force-sync=$(date +%s) --overwrite

kubectl wait --for=condition=Ready externalsecret ...
```

## Security & Guardrails

| Risk | Mitigation Strategy |
| :--- | :--- |
| **Drift** | Pipeline forces sync immediately after injection. |
| **Leakage** | Secrets are `SecureString` in SSM; Git only holds references. |
| **Confusion** | Keys are strictly normalized to lowercase underscores. |
| **Blast Radius** | Sync is scoped by Namespace and Label Selectors. |
```

---
