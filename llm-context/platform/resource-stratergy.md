Here is the Architecture Decision Record (ADR) documenting the finalized strategy for the MVP phase.

---

# Architecture Decision Record: Hybrid Resource Strategy (MVP)

**Status:** Finalized  
**Context:** Solo Founder / Zero-Touch Operations  
**Date:** January 2025

## 1. The Core Decision
To minimize operational risk and maximize development velocity for a team of one, we have adopted a **Strict Hybrid Architecture**:

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

## 5. Summary
We treat **Compute** as a commodity we control, and **Data** as a precious asset we entrust to specialists. This allows the solo founder to focus entirely on building product features rather than managing backups, replication lags, and disk upgrades.