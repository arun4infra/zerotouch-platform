# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an **Agentic-Native Infrastructure Platform** - a self-healing, GitOps-driven Kubernetes platform that leverages AI agents to automate infrastructure operations. Designed for solo founders/small teams to operate production infrastructure without a dedicated ops team.

**Core Philosophy:** Zero-touch operations. No SSH access. Git is the single source of truth. Entire platform reconstructible from Git in <30 minutes.

## Architecture Principles (The 5-Point Constitution)

Every change must pass these checks:

1. **Zero-Touch:** OS (Talos) and cluster are immutable. All changes via API or Git only.
2. **Day 2 Simplicity:** Reject tools requiring dedicated ops teams (no Kafka, Vault, or Elasticsearch).
3. **Crash-Only Recovery:** Entire state reconstructible from Git in <30 minutes.
4. **Buy the Critical Path:** Don't self-host DNS or critical secrets (use Cloudflare, GitHub Secrets).
5. **Agent-Compatible Complexity:** Use standard APIs (Gateway API, Crossplane) that AI agents can understand.

## Technology Stack

- **OS:** Talos Linux (immutable, API-only)
- **GitOps:** ArgoCD (automated sync with prune + selfHeal)
- **IaC:** Crossplane (Kubernetes-native infrastructure API)
- **Networking:** Cilium + Gateway API (NOT Nginx Ingress)
- **Database:** CloudNativePG Operator (PostgreSQL)
- **Cache:** Dragonfly (Redis-compatible)
- **Observability:** Prometheus + Loki + Tempo + Grafana + Robusta
- **Scaling:** KEDA (event-driven, scale-to-zero)
- **Secrets:** External Secrets Operator (syncs from GitHub Secrets)
- **Intelligence:** Kagent (K8s AI agents) + Qdrant (vector DB) + docs-mcp (MCP server)

## Common Commands

### Building Crossplane Packages

```bash
cd platform/03-intelligence/

# Initialize submodules (first time only)
make submodules

# Build the intelligence layer package
make build

# Build docs-mcp Docker image
make build-docs-mcp

# Run E2E tests
make e2e-intelligence
```

### Validation Scripts

```bash
# Validate documentation (runs in CI on PRs)
python scripts/detect_prose.py docs/

# Validate deployment configurations
python scripts/validate_deployment.py
```

### GitOps Workflow

```bash
# Bootstrap cluster (Day 0 - manual setup required first)
kubectl apply -f bootstrap/root.yaml

# Make infrastructure changes
# 1. Edit YAML files in platform/, tenants/, or services/
# 2. Commit to Git
# 3. Push to GitHub
# 4. ArgoCD automatically syncs (or trigger manual sync in ArgoCD UI)

# Check ArgoCD sync status
kubectl get applications -n argocd

# View application details
kubectl describe application <app-name> -n argocd
```

**NEVER use `kubectl edit` or direct `kubectl apply` for managed resources.** Always commit to Git and let ArgoCD sync.

## Directory Structure (High-Level)

```
bizmatters-infra/
├── .kiro/                    # AI agent specifications & metadata
│   ├── agnets/               # Agent role definitions (platform-architect.md)
│   └── specs/                # Feature specifications
├── artifacts/                # Agent-maintained documentation (owned by @bizmatters-bot)
├── bootstrap/                # Day 0 setup (root.yaml, Talos configs)
├── docs/                     # Human-maintained documentation
│   ├── architecture/         # ADRs and design decisions
│   └── dev/                  # Developer guides
├── platform/                 # Platform layer (ArgoCD Applications)
│   ├── 01-foundation/        # Core (Cilium, KEDA, secrets, storage)
│   ├── 02-observability/     # Monitoring (Prometheus, Loki, Tempo, Robusta)
│   ├── 03-intelligence/      # AI layer (Crossplane package: Qdrant, agents, MCP)
│   ├── 04-apis/              # Platform APIs (Crossplane compositions)
│   └── 99-tenants.yaml       # Tenant applications
├── services/                 # Custom services (docs-mcp MCP server)
└── tenants/                  # Actual workloads (production namespaces)
```

## Architecture Patterns

### Layered Deployment (Sync Wave Ordering)

Platform components deploy in order via ArgoCD sync waves:

```
Wave -1: Cilium (networking foundation)
Wave  0: Foundation (KEDA, secrets, storage)
Wave  2: Observability (Prometheus, Loki, Tempo, Robusta)
Wave  3: Intelligence (Qdrant, AI agents, MCP servers)
Wave  4: Platform APIs (Crossplane compositions)
Wave  5+: Tenant applications
```

### GitOps App-of-Apps Pattern

- `bootstrap/root.yaml` → ArgoCD root application
- Points to `platform/` directory
- Each `platform/XX-*.yaml` is an ArgoCD Application
- ArgoCD recursively deploys all platform applications
- All apps have `automated: {prune: true, selfHeal: true}`

### Crossplane Composition Pattern

Platform abstractions defined as Crossplane Compositions:

```yaml
# Example: WebService abstraction
apiVersion: bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: my-app
spec:
  image: ghcr.io/org/app:v1.0
  replicas: 3
  scaling:
    minReplicas: 1
    maxReplicas: 10
```

This single 10-line claim creates: Deployment + Service + HTTPRoute + KEDA ScaledObject.

**When adding infrastructure capabilities:**
- Create Crossplane Compositions in `platform/04-apis/compositions/`
- Define XRDs (Custom Resource Definitions) in `platform/04-apis/definitions/`
- Put example claims in `examples/`
- Actual claims go in `tenants/production/`

### Intelligence Layer Architecture (Two-Zone Documentation)

**Human Zone (`docs/`):**
- Free-form notes and architecture documents
- Human-maintained, not indexed by agents
- Source material for agent distillation

**Agent Zone (`artifacts/`):**
- Structured, machine-readable documentation
- Owned by `@bizmatters-bot` (enforced via CODEOWNERS)
- Indexed in Qdrant vector database
- Templates for runbooks, specs, ADRs

### Agentic Feedback Loop

```
Station 1 (Input): Human/Agent → Git (GitHub)
Station 2 (Guard): CI (GitHub Actions) → Reviewer Agent
Station 3 (Cluster): ArgoCD → Kubernetes → Crossplane → Resources
Station 4 (Feedback): Robusta → Kagent → Qdrant → Opens PR in Git
```

Example: Database disk >90% → Robusta alert → Kagent queries Qdrant → Agent opens PR to increase storage → Human reviews → ArgoCD syncs.

## Special Files & Directories

### `.kiro/agnets/platform-architect.md`

System prompt defining the Platform Architect agent role. Contains the 5-Point Constitution and operational guidelines. Read this to understand the architectural constraints and decision-making framework.

### `platform/03-intelligence/`

The only platform layer that's a full Crossplane Configuration package. Has its own:
- Makefile with build commands
- Submodule (upbound/build) for Crossplane packaging
- Compositions for Qdrant, docs-mcp, librarian-agent
- Can be distributed as a package to other clusters

### `CODEOWNERS`

Enforces ownership boundaries:
- `artifacts/` → `@bizmatters-bot` (only agent can modify)
- `docs/` → `@platform-team` (humans maintain)

### Documentation Standards (ADR-003)

**No-Fluff Policy:**
- Use tables and lists, not prose paragraphs
- YAML frontmatter schemas required for all docs in `artifacts/`
- Validation enforced by `scripts/detect_prose.py` in CI
- Filename conventions: lowercase, hyphens only

## Development Workflows

### Adding a New Platform Component

1. Create ArgoCD Application in appropriate `platform/0X-*/` directory
2. Set sync wave annotation (`argocd.argoproj.io/sync-wave`)
3. Configure Helm chart or point to manifests
4. Commit and push - ArgoCD syncs automatically
5. Verify: `kubectl get applications -n argocd`

### Creating a New Crossplane Composition

1. Define XRD in `platform/04-apis/definitions/`
2. Create Composition in `platform/04-apis/compositions/`
3. Add example claim in `examples/`
4. Update `platform/04-apis/crossplane.yaml` if needed
5. Commit and push
6. Test with example: `kubectl apply -f examples/<your-claim>.yaml`

### Modifying the Intelligence Layer

1. `cd platform/03-intelligence/`
2. Edit compositions, definitions, or functions
3. Run `make build` to validate package
4. Run `make e2e-intelligence` to test
5. Commit changes
6. ArgoCD syncs the package to cluster

### Troubleshooting Infrastructure Issues

**DO:**
- Check Robusta alerts for context-rich error information
- Review ArgoCD UI for sync status and health
- Query Prometheus/Grafana for metrics
- Check Loki for logs
- Look at Git history to understand what changed
- Draft Pull Requests to fix issues

**DON'T:**
- Use `kubectl edit` on managed resources
- SSH into nodes (Talos doesn't allow it anyway)
- Manually apply YAML outside of Git
- Trust cluster state over Git (Git is source of truth)

## Testing

### CI/CD (GitHub Actions)

`.github/workflows/validate-docs.yaml` runs on PRs:
- Validates YAML frontmatter schemas in `artifacts/`
- Detects prose paragraphs (enforces tables/lists)
- Validates filename conventions
- Future: Qdrant sync on merge, twin doc generation

### Local Testing

```bash
# Validate documentation locally
python scripts/detect_prose.py docs/

# Test Crossplane package build
cd platform/03-intelligence/
make build

# E2E test intelligence layer
make e2e-intelligence
```

## Key Design Decisions

### ADR-002: Qdrant as Index, Not Store

Git remains the source of truth. Qdrant only indexes `artifacts/` for semantic search. Agents query Qdrant but create PRs to modify Git.

### ADR-003: Documentation Standards

No-fluff policy enforced via CI. Agent-maintained docs require YAML frontmatter schemas. Human docs can be free-form but still prefer structured formats.

### Why No Ingress Controllers?

Using **Gateway API** (implemented by Cilium) instead of traditional Ingress. Gateway API is the successor to Ingress with better multi-tenancy, more expressive routing, and standardized across implementations.

### Why Crossplane vs Terraform?

Crossplane is Kubernetes-native (declarative, GitOps-compatible, continuous reconciliation). Terraform requires separate state management and lacks continuous drift detection. Crossplane fits the "Agent-Compatible Complexity" principle - agents can read/write K8s resources directly.

## Repository Context

**Git Repository:** `https://github.com/arun4infra/bizmatters-infra.git`

**Current Branch Pattern:** Feature branches (e.g., `feat/intelligence-layer`) merge to main

**ArgoCD Configuration:** Watches `platform/` directory, auto-syncs with prune + selfHeal enabled
