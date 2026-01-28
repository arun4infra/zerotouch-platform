
### 2. Preview Architecture (PRs / CI Testing)
This document outlines the imperative flow used for ephemeral testing environments.

**File:** `docs/architecture/secrets-management-preview.md`

```markdown
# Platform Secret Management: Preview Architecture
**Scope:** Pull Requests (PRs), Local Testing (Kind), CI Pipelines

## Executive Summary
Preview environments prioritize **Speed** and **Isolation** over persistence. 
Instead of syncing from AWS SSM (which risks pollution and requires cloud permissions), secrets are injected **imperatively** at runtime by the build script.
Mock values are used by default, with an option to override for integration tests.

## Architecture Wireframe

```text
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                             PREVIEW SECRET LIFECYCLE                                │
└─────────────────────────────────────────────────────────────────────────────────────┘

   1. CONFIGURATION                     2. EXECUTION (in-cluster-test.sh)
   (Mock & Env Vars)                    (Imperative Injection)
┌───────────────────────────┐        ┌───────────────────────────┐
│ Service Repo              │        │ CI Runner (GitHub/Local)  │
│ ├── ci/config.yaml        │        │                           │
│ │   env:                  │ Reads  │ 1. Read config.yaml       │
│ │     USE_MOCK_LLM: true  │ ─────> │ 2. Detect Dependencies    │
│ │                         │        │ 3. Generate Mock Values   │
│ └── .env (Local Only)     │        │ 4. Run kubectl create     │
│     OPENAI_API_KEY=sk-..  │        └─────────────┬─────────────┘
└───────────────────────────┘                      │
                                                   │ Direct Apply
                                                   │ (Bypasses SSM/ESO)
                                                   ▼
┌────────────────────────────────────────────────────────────────┐
│ KIND CLUSTER (Ephemeral Namespace)                             │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│    ┌───────────────────┐       ┌──────────────────────────┐    │
│    │ K8s Secret        │ ────> │ Pod (Test Runner)        │    │
│    │ (Opaque)          │ Mount │ envFrom: secretRef       │    │
│    └───────────────────┘       └──────────────────────────┘    │
│                                                                │
│    * Note: External Secrets Operator is NOT used for           *
│            tenant secrets in Preview mode.                     │
└────────────────────────────────────────────────────────────────┘
```

## The Workflow Steps

### 1. Configuration (`ci/config.yaml`)
The service declares what secrets it *needs*, but not the values.

```yaml
service:
  name: "identity-service"
secrets:
  database: true    # Needs <service>-db-conn
  jwt_keys: true    # Needs <service>-jwt-keys
env:
  USE_MOCK_LLM: "true" # Logic flag to bypass real secrets
```

### 2. Generation Logic (`deploy.sh` / `in-cluster-test.sh`)
The CI script acts as the "Secret Generator".

*   **Database Secrets:** Since the CI spins up a fresh Postgres instance inside the cluster, the script *knows* the credentials (usually `postgres`/`postgres`) and generates the secret immediately.
*   **LLM Keys:** 
    *   If `USE_MOCK_LLM=true`: Injects dummy values (`sk-mock-key`).
    *   If Integration Test: Reads from GitHub Secrets (`OPENAI_API_KEY`) env var and injects directly.

### 3. Direct Application
The script runs `kubectl create secret generic ...` directly into the PR namespace.

**Why bypass ESO?**
1.  **Speed:** No waiting for AWS API calls or Operator reconciliation loop.
2.  **Cost:** Reduces API calls to AWS SSM.
3.  **Cleanliness:** Prevents thousands of PR-specific keys from polluting the `/zerotouch/` SSM hierarchy.

## Key Differences from Production

| Feature | Production (Main) | Preview (PR) |
| :--- | :--- | :--- |
| **Mechanism** | GitOps + External Secrets Operator | Shell Script + `kubectl create` |
| **Source** | AWS SSM Parameter Store | Generated Mocks or GH Env Vars |
| **Persistence** | Permanent | Deleted when PR closes |
| **Latency** | 10s - 60s (ESO Sync) | Instant (<1s) |
| **Auditing** | CloudTrail Logs | CI Logs |

## When to use Real Secrets in Preview?
Only during **Integration Tests** where mocking is impossible. In this case, secrets are passed as Environment Variables to the CI Runner, which then injects them as Kubernetes Secrets. They never touch AWS SSM.
```