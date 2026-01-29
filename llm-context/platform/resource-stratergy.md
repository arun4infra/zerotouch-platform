Here is the Architecture Decision Record (ADR) documenting the finalized strategy for the MVP phase.

---

# Architecture Decision Record: Hybrid Resource Strategy (MVP)

**Status:** Finalized  
**Context:** Solo Founder / Zero-Touch Operations  
**Date:** January 2025

## 1. The Core Decision
To minimize operational risk and maximize development velocity for a team of one, we have adopted a **Strict Hybrid Architecture**:
The Platform's primary role is **Connectivity Injection**, not just hosting. It must support three distinct resource lifecycles, allowing users to balance convenience, cost, and control.

> **"Rent the State, Own the Compute."**

*   **Stateful Resources (High Risk)** must be offloaded to **Managed Services** (SaaS/PaaS).
*   **Stateless/Ephemeral Resources (Low Risk)** will be hosted on the **Internal Platform** (Kubernetes/Talos).

## 2. Resource Segmentation

| Resource Category | Hosting Strategy | Provider Examples | Rationale |
| :--- | :--- | :--- | :--- |
| **User Identity** | **Managed** | Neon Auth, Auth0 | Security critical. Identity is hard to secure; vendor manages compliance (SOC2/GDPR) and attack mitigation. |
| **Primary Database** | **Managed** | Neon Tech, AWS RDS | Data loss is fatal. We need vendor-guaranteed backups, HA, and Point-in-Time Recovery (PITR) without manual DBA work. |
| **Blob Storage** | **Managed** | AWS S3, Hetzner object storage | Durability guarantees (99.999999999%) are impossible to replicate on self-hosted disks reliably. |
| **Application Logic** | **Internal** | Python 3.11+ on K8s (Node.js for Identity Service) | High churn code. We need instant deployments and full control over the runtime environment. Python standard for platform services. |
| **Ingress/Routing** | **Internal** | AgentGateway (external framework) | Critical path for performance. Low maintenance overhead once configured. |
| **Ephemeral Cache** | **Internal** | Dragonfly/Redis | Data is reconstructable. If the cache crashes, the app slows down but doesn't break. Acceptable operational risk. |

## 3. The "Solo Founder" Rationale

### A. Liability Transfer
By using Managed Services for stateful components, we transfer the liability of **Data Durability** and **Uptime** to the vendor.
*   *Scenario:* The database corrupts at 3:00 AM.
*   *Self-Hosted:* I wake up, attempt file-system recovery, potential data loss.
*   *Managed:* The vendor's automated failover handles it, or I restore from a 5-minute-old backup via UI.

### B. The "Crash-Only" Platform
Because the Internal Platform hosts only **Stateless** workloads (Compute + Ephemeral Cache), the Kubernetes cluster becomes **disposable**.
*   If the cluster enters a bad state, we do not debug it. We nuke it and re-bootstrap from Git.
*   Recovery time is minutes, not days, because there is no persistent user data trapped inside the cluster volumes.

### C. Cost vs. Complexity Trade-off
While Managed Services (like RDS or Neon) carry a premium cost compared to raw VPS storage:
*   The cost is significantly lower than hiring a DevOps engineer/DBA.
*   The cost is lower than the reputational damage of losing customer data.
*   **Decision:** We pay money to save time and reduce anxiety.

## 4. Implementation Pattern

### The Connectivity Layer
Since the Platform does not *host* the data, it acts as a **Connectivity Engine**.

1.  **Provisioning:** Platform provisioning service (Python) calls Vendor APIs (e.g., Neon API) to create resources on demand.
2.  **Secret Management:** Credentials are encrypted and stored in the Platform's Meta-DB, then injected into Application Pods at runtime.
3.  **Isolation:** Logic ensures Tenant A's compute container is injected *only* with Tenant A's managed database credentials.

## 5. The Three Resource Models

### Type 1: Bring Your Own Credentials (MVP Scope)
**"The Automated Operator"**
*   **Workflow:** User provides Neon API key once during platform initialization. Platform provisions databases automatically via Neon API.
*   **Platform Role:** Lifecycle Manager (Provision, Deprovision).
*   **Mechanism:**
    1.  User provides Neon API key during platform setup (stored in AWS SSM).
    2.  When service is deployed, platform calls Neon API to create database.
    3.  Platform captures connection string from Neon API response.
    4.  Platform stores `DATABASE_URL` in AWS SSM at `/zerotouch/{env}/service-name/database_url`.
    5.  ExternalSecrets Operator syncs from SSM to Kubernetes Secret.
    6.  Service container receives `DATABASE_URL` via environment variable.
*   **Pros:** "Magical" UX. Centralized provisioning. Zero manual database creation. No financial liability (bills go to user's Neon account).
*   **Cons:** Requires Neon API integration. State reconciliation needed (track which databases exist).

### Type 2: Internal Platform Provisioned (Future Scope)
**"The Self-Hosted Cloud"**
*   **Workflow:** The user selects "Internal Postgres" and pays the Platform directly.
*   **Platform Role:** Hoster & DBA.
*   **Mechanism:**
    1.  Platform triggers Crossplane to spin up a **CloudNativePG** cluster on local Kubernetes nodes.
    2.  Data lives on local NVMe/SSD via OpenEBS/Longhorn.
*   **Pros:** Cheapest for the user (no AWS markup). High margins for the Platform.
*   **Cons:** High operational risk (backups, disk resizing, HA). Not implemented in MVP.

### Type 3: Bring Your Own Connection (Future Scope)
**"The Connectivity Vault"**
*   **Workflow:** User manually provisions database (Neon UI, AWS Console), copies connection string, pastes into Platform Dashboard.
*   **Platform Role:** Secure Storage & Injection.
*   **Mechanism:**
    1.  User saves `postgres://user:pass@host:5432/db` in Platform UI.
    2.  Platform encrypts and stores in AWS SSM.
    3.  ExternalSecrets syncs to Kubernetes Secret.
    4.  Platform injects as `DATABASE_URL` into service container.
*   **Pros:** Maximum flexibility. User controls database configuration.
*   **Cons:** Higher friction (manual provisioning). Not implemented in MVP.
**"The Automated Operator"**
*   **Workflow:** The user provides a high-privilege API Key (e.g., AWS IAM User, Neon API Key) to the Platform.
*   **Platform Role:** Lifecycle Manager (Provision, Deprovision).
*   **Mechanism:**
    1.  User clicks "Create DB" in Platform UI.
    2.  Platform uses User's API Key to call Provider API (e.g., `aws rds create-db-instance`).
    3.  Platform captures the resulting connection string automatically.
*   **Pros:** "Magical" UX. No financial liability (bills go to user).
*   **Cons:** Complex state reconciliation (Drift Detection) required.

## 3. MVP Implementation Strategy

For the **MVP Launch**, we will implement **Type 1 (Bring Your Own Credentials)** exclusively.

**Rationale:**
1.  **Automated Provisioning:** Platform provisions databases via Neon API automatically. No manual database creation.
2.  **Centralized Management:** Single Neon API key provisions all service databases. Simplified credential management.
3.  **Zero Liability:** Databases billed to user's Neon account. Platform doesn't host data.
4.  **Service Autonomy:** Each service gets its own isolated Neon database, provisioned on-demand.

## 4. Architecture Implications

To support this evolution without rewriting the core later, the **Identity & Resource Broker** service will be designed with the following abstraction:

### The `Resource` Entity
The database schema for `resources` will support a `kind` discriminator:

```typescript
type ResourceKind = 'neon_provisioned' | 'internal_hosted' | 'external_link';

interface Resource {
  id: string;
  org_id: string;
  kind: ResourceKind;
  
  // Type 1 (MVP): Platform-provisioned via Neon API
  neon_project_id?: string;           // Neon project ID
  neon_database_name?: string;        // Database name in Neon
  connection_details?: EncryptedString;  // Generated connection string
  
  // Type 2 & 3: Dynamic references (Future)
  provisioning_job_id?: string;
  provider_resource_id?: string;
}
```

*   **For MVP (Type 1):** Platform calls Neon API to create database, stores connection string in AWS SSM, syncs via ExternalSecrets.
*   **For Future (Type 2):** Platform provisions CloudNativePG clusters via Crossplane.
*   **For Future (Type 3):** User manually provides connection strings via Platform UI.

## 6. Summary
We treat **Compute** as a commodity we control, and **Data** as a precious asset we entrust to specialists. This allows the solo founder to focus entirely on building product features rather than managing backups, replication lags, and disk upgrades.

We prioritize **Connectivity** over **Creation** for the MVP. This allows the platform to be useful immediately ("It manages my secrets and connects my apps") while reserving the complex "Infrastructure-as-a-Service" features for a post-revenue phase.