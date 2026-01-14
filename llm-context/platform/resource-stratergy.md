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
| **User Identity** | **Managed** | AWS Cognito, Auth0 | Security critical. Identity is hard to secure; vendor manages compliance (SOC2/GDPR) and attack mitigation. |
| **Primary Database** | **Managed** | Neon Tech, AWS RDS | Data loss is fatal. We need vendor-guaranteed backups, HA, and Point-in-Time Recovery (PITR) without manual DBA work. |
| **Blob Storage** | **Managed** | AWS S3, Hetzner object storage | Durability guarantees (99.999999999%) are impossible to replicate on self-hosted disks reliably. |
| **Application Logic** | **Internal** | Node.js/Python on K8s | High churn code. We need instant deployments and full control over the runtime environment. |
| **Ingress/Routing** | **Internal** | AgentGateway (Cilium) | Critical path for performance. Low maintenance overhead once configured. |
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

1.  **Provisioning:** The "Provisioning Worker" (Node.js) calls Vendor APIs (e.g., Neon API) to create resources on demand.
2.  **Secret Management:** Credentials are encrypted and stored in the Platform's Meta-DB, then injected into Application Pods at runtime.
3.  **Isolation:** Logic ensures Tenant A's compute container is injected *only* with Tenant A's managed database credentials.

## 5. The Three Resource Models

### Type 1: Bring Your Own Connection (MVP Scope)
**"The Connectivity Vault"**
*   **Workflow:** The user provisions a database externally (e.g., AWS Console, Neon UI), copies the connection string, and pastes it into our Platform Dashboard.
*   **Platform Role:** Secure Storage & Injection.
*   **Mechanism:**
    1.  User saves `postgres://user:pass@host:5432/db`.
    2.  Platform encrypts and stores it in the Internal Meta-DB.
    3.  Platform injects it as `DATABASE_URL` into the user's application container at runtime.
*   **Pros:** Lowest engineering effort for MVP. Zero liability for data persistence (user owns the backup).
*   **Cons:** Higher friction for the user (context switching).

### Type 2: Bring Your Own Credentials (BYO-Key) (Future Scope)
**"The Automated Operator"**
*   **Workflow:** The user provides a high-privilege API Key (e.g., AWS IAM User, Neon API Key) to the Platform.
*   **Platform Role:** Lifecycle Manager (Provision, Deprovision).
*   **Mechanism:**
    1.  User clicks "Create DB" in Platform UI.
    2.  Platform uses User's API Key to call Provider API (e.g., `aws rds create-db-instance`).
    3.  Platform captures the resulting connection string automatically.
*   **Pros:** "Magical" UX. No financial liability (bills go to user).
*   **Cons:** Complex state reconciliation (Drift Detection) required.

### Type 3: Internal Platform Provisioned (Future Scope)
**"The Self-Hosted Cloud"**
*   **Workflow:** The user selects "Internal Postgres" and pays the Platform directly.
*   **Platform Role:** Hoster & DBA.
*   **Mechanism:**
    1.  Platform triggers Crossplane to spin up a **CloudNativePG** cluster on local Kubernetes nodes.
    2.  Data lives on local NVMe/SSD via OpenEBS/Longhorn.
*   **Pros:** Cheapest for the user (no AWS markup). High margins for the Platform. Good for dev/preview environments.
*   **Cons:** High operational risk for the solo founder (backups, disk resizing, HA are your problem).

## 3. MVP Implementation Strategy

For the **MVP Launch**, we will implement **Type 1 (Connection String)** exclusively.

**Rationale:**
1.  **Speed to Market:** We avoid writing complex Terraform/Crossplane wrappers for AWS/Azure/Neon immediately.
2.  **Safety:** We eliminate the risk of "Runaway Cloud Bills" or "Accidental Deletion" caused by bugs in our provisioning logic during the early days.
3.  **Universal Compatibility:** Any resource that has a URL (Redis, Mongo, Postgres, API Services) works immediately without custom code.

## 4. Architecture Implications

To support this evolution without rewriting the core later, the **Identity & Resource Broker** service will be designed with the following abstraction:

### The `Resource` Entity
The database schema for `resources` will support a `kind` discriminator:

```typescript
type ResourceKind = 'external_link' | 'managed_integration' | 'internal_hosted';

interface Resource {
  id: string;
  org_id: string;
  kind: ResourceKind;
  
  // Type 1: Static data provided by user
  connection_details?: EncryptedString; 
  
  // Type 2 & 3: Dynamic references (Future)
  provisioning_job_id?: string;
  provider_resource_id?: string;
}
```

*   **For MVP:** The logic simply reads `connection_details`, decrypts it, and injects it.
*   **For Future:** The logic will trigger a Worker to fill `connection_details` after an API call (Type 2) or CRD apply (Type 3).

## 6. Summary
We treat **Compute** as a commodity we control, and **Data** as a precious asset we entrust to specialists. This allows the solo founder to focus entirely on building product features rather than managing backups, replication lags, and disk upgrades.

We prioritize **Connectivity** over **Creation** for the MVP. This allows the platform to be useful immediately ("It manages my secrets and connects my apps") while reserving the complex "Infrastructure-as-a-Service" features for a post-revenue phase.