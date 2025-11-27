# zerotouch-infra: The Agentic-Native Platform

**A "Digital Assembly Line" for the Solo Founder.**

> **The Philosophy:** We treat infrastructure as a software product managed by AI Agents, not as a collection of servers managed by humans. If you have to SSH into a node, the platform has failed.

---

## 1. The "Solo Founder" Constitution

We are building a scalable SAAS/PAAS with a team of **one**. To achieve this, we adhere to five non-negotiable architectural principles:

1.  **Zero-Touch Operations:** We use **Talos Linux**. No SSH, no patching, no mutable state. The OS is an API.
2.  **The "Crash-Only" Rule:** Disaster recovery is instant. If the cluster explodes, we rebuild it from Git in < 15 minutes. We do not "fix" servers; we replace them.
3.  **GitOps is Law:** If it's not in Git, it doesn't exist. **ArgoCD** is the only entity allowed to apply changes to the cluster. We do not run `kubectl apply` manually.
4.  **The "Silent Partner" Model:** Alerts go to **Kagent** (AI), not the human. The Agent investigates, fixes via Pull Request, and only notifies the human for approval or high-risk escalation.
5.  **Data as a Time Machine:** We use **CloudNativePG** with continuous WAL archiving to S3 (Object Lock enabled). We can restore the database to any specific *second* in time to counter developer errors.

---

## 2. The Architecture

The platform functions as a feedback loop between Code, State, and Intelligence.

```mermaid
graph TD
    subgraph "The Input (You)"
        Human[Solo Founder] -->|Push Code| Git[GitHub Monorepo]
        Human -->|Chat/Query| Slack[Slack Interface]
    end

    subgraph "The Brain (Intelligence Layer)"
        Slack <--> Kagent[Kagent (The SRE)]
        Kagent <-->|RAG| Qdrant[Vector DB (Docs/Runbooks)]
        Kagent -->|Opens PR| Git
        Git -->|Trigger| Librarian[Librarian Agent (Doc Sync)]
    end

    subgraph "The Engine (GitOps)"
        Git -->|Sync| ArgoCD[ArgoCD]
        ArgoCD -->|Applies| Cluster[Talos Kubernetes]
    end

    subgraph "The Machinery (Platform)"
        Cluster -->|Network| Cilium[Cilium + Gateway API]
        Cluster -->|Data| CNPG[CloudNativePG (Enterprise Spec)]
        Cluster -->|Events| NATS[NATS JetStream]
        Cluster -->|Scaling| KEDA[KEDA Autoscaler]
    end

    subgraph "The Feedback"
        Cluster -->|Alerts| Robusta[Robusta]
        Robusta -->|Webhook| Kagent
    end
```

---

## 3. The Tech Stack (The "Why")

We chose specific tools to minimize "Day 2" complexity.

| Component | Tool | Why this choice? |
| :--- | :--- | :--- |
| **OS** | **Talos Linux** | Immutable, API-driven, maintenance-free. |
| **GitOps** | **ArgoCD** | Standardizes deployment. Handles "App-of-Apps" pattern. |
| **Secrets** | **External Secrets** | Syncs from GitHub Secrets. No local `.env` files or decryption keys. |
| **Provisioning** | **Crossplane** | Allows us to define "Legos" (XRDs) like `XPostgres` or `XWebService`. |
| **Database** | **CloudNativePG** | Enterprise-grade HA, automated failover, and Point-In-Time Recovery. |
| **Messaging** | **NATS** | Simpler than Kafka, lighter than RabbitMQ. Ideal for agentic control planes. |
| **Agent** | **Kagent** | The AI operator that understands Kubernetes and our documentation. |

---

## 4. Repository Structure

This monorepo acts as the Single Source of Truth for both Code and Knowledge.

```text
bizmatters-infra/
├── .github/               # Automation (Librarian, Ingestion)
├── bootstrap/             # The "Big Bang" (App-of-Apps)
├── docs/                  # The Brain (Indexed by Vector DB)
│   ├── architecture/      # Decision Records (The "Why")
│   ├── runbooks/          # Operational Guides (The "How")
│   └── specs/             # API Schemas (The "What")
├── platform/              # The Infrastructure Layers
│   ├── 00-crds/           # Large CRDs (Kagent, etc)
│   ├── 01-foundation/     # Plumbing (Cilium, ESO, NATS)
│   ├── 02-observability/  # Eyes (Prometheus, Robusta)
│   ├── 03-intelligence/   # Brain (Kagent, Vector DB)
│   └── 04-apis/           # Legos (Crossplane XRDs/Compositions)
└── tenants/               # Customer Workloads
```

---

## 5. Workflows

### How to Deploy (The "Zero-Touch" Way)
We do not use shell scripts to deploy services.
1.  **Define:** Create a Claim YAML (e.g., `agent-executor-claim.yaml`) in `platform/03-intelligence/` or `tenants/`.
2.  **Commit:** Push to Git.
3.  **Wait:** ArgoCD detects the change and syncs the cluster.

### How to Communicate
*   **Synchronous (Consultant):** Ask Kagent in Slack: *"How do I add a Dragonfly cache?"* It queries the Vector DB and provides the approved architectural pattern.
*   **Asynchronous (SRE):** Kagent monitors alerts. If a fix is needed, it opens a **Pull Request**. You review the code and the auto-generated documentation update, then merge.

---

## 6. Data Protection Standards

We adhere to an **Aerospace-Grade** data safety specification:
1.  **Triple Redundancy:** Databases run 3-node clusters with synchronous replication.
2.  **Time Machine:** Continuous WAL archiving to S3 allows recovery to any specific transaction timestamp (RPO ≈ 0).
3.  **Fat-Finger Proof:**
    *   Crossplane `deletionPolicy: Orphan` (Deleting Git YAML leaves DB running).
    *   StorageClass `reclaimPolicy: Retain` (Deleting Cluster leaves EBS volume intact).
    *   S3 **Object Lock** (Prevents deletion of backups even if credentials are stolen).

---

## 7. Getting Started

### Prerequisites
*   Talos Cluster (Running)
*   `kubectl` (For initial bootstrap only)
*   GitHub Repository Secrets configured

### Bootstrap
We use a single script to install the GitOps engine. After that, the engine installs the rest.

```bash
# 1. Install ArgoCD
./scripts/bootstrap/install-argocd.sh

# 2. Apply the Root Application
kubectl apply -f bootstrap/root-app.yaml

# 3. Watch the Magic
watch kubectl get applications -n argocd
```