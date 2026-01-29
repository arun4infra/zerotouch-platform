# DeepAgents Runtime - Platform Architecture

## Current Architecture (Managed Services + GitOps)

**ArgoCD Role:**
- Deploys application manifests (Deployments, Services, ConfigMaps)
- Manages External Secrets for application configuration
- Handles GitOps workflow and sync waves
- Syncs tenant applications from `zerotouch-tenants/` repository

**Crossplane Role:**
- Provisions ephemeral cache ONLY (DragonflyInstance)
- Creates cache connection secrets automatically
- Does NOT provision databases (external Neon)
- Does NOT generate application Deployments

**External Services:**
- Databases: Managed Neon PostgreSQL (external to cluster)
- Identity: Neon Auth (OAuth provider, external to cluster)
- Storage: AWS S3 or Hetzner Object Storage (external to cluster)

**Platform Abstraction:**
- Ephemeral Cache: Crossplane Claims (DragonflyInstance only)
- Applications: Standard Kubernetes manifests (Deployment, Service)
- Database Secrets: Services inject via CI workflows, synced from AWS SSM
- Application Secrets: ExternalSecrets Operator syncs from AWS SSM
- Overlays: Kustomize handles environment-specific configuration

---

## Platform Service Technology Standards

| Service | Language | Framework | Database | Cache | Notes |
|---------|----------|-----------|----------|-------|-------|
| **Identity Service** | Node.js 20 + TypeScript | Fastify 4.x | Neon PostgreSQL | Dragonfly | Exception: Uses Node.js for performance |
| **IDE Orchestrator** | Python 3.11+ | FastAPI | Neon PostgreSQL | Dragonfly | Standard platform language |
| **Deepagents runtime** | Python 3.11+ | FastAPI | Neon PostgreSQL | Dragonfly | Standard platform language |

**Platform Standard:** Python 3.11+ with FastAPI for all services except Identity Service (Node.js for authentication performance requirements).

**AgentGateway:** External framework (not platform-developed), language-agnostic from platform perspective.

## Resource Flow

1. **Platform Initialization** (one-time):
   ```bash
   # User provides Neon API key during platform setup
   # Stored in AWS SSM: /zerotouch/platform/neon_api_key
   ```

2. **Service Deployment** triggers database provisioning:
   ```bash
   # Platform calls Neon API to create database
   curl -X POST "https://console.neon.tech/api/v2/projects/${NEON_PROJECT_ID}/databases" \
     -H "Authorization: Bearer ${NEON_API_KEY}" \
     -d '{"name": "identity-service-dev"}'
   
   # Platform stores connection string in SSM
   aws ssm put-parameter \
     --name "/zerotouch/dev/identity-service/database_url" \
     --value "postgres://user:pass@ep-xxx.neon.tech/identity-service-dev"
   ```

3. **ArgoCD** deploys application resources:
   ```yaml
   # Cache Infrastructure (Crossplane provisions)
   apiVersion: cache.bizmatters.io/v1alpha1
   kind: DragonflyInstance
   metadata:
     name: identity-cache
   
   # Application Manifests (ArgoCD deploys)
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: identity-service
   spec:
     template:
       spec:
         containers:
         - name: identity-service
           envFrom:
           - secretRef:
               name: identity-service-db      # From ExternalSecret (Neon)
           - secretRef:
               name: identity-cache-conn      # From Crossplane
           - secretRef:
               name: identity-service-jwt     # From ExternalSecret (SSM)
   ```

4. **Crossplane** provisions ephemeral cache:
   - Creates DragonflyInstance (Redis-compatible cache)
   - Generates cache connection secrets (identity-cache-conn)
   - Does NOT provision databases

5. **External Secrets Operator** syncs from AWS SSM:
   - Database connection strings (platform-provisioned via Neon API)
   - JWT keys (jwt_private_key, jwt_public_key)
   - API keys (openai_api_key, anthropic_api_key)
   - Image pull secrets (ghcr-pull-secret)

6. **Service starts** with all connections:
   - Connects to platform-provisioned Neon database
   - Connects to Crossplane-provisioned Dragonfly cache
   - Uses JWT keys for authentication

## Key Benefits

- **Managed Databases:** Zero operational overhead for stateful data (Neon handles backups, HA, PITR)
- **Ephemeral Cache:** Crossplane provisions Dragonfly for fast, reconstructable data
- **Service Autonomy:** Each service manages its own secrets via CI workflows
- **GitOps:** ArgoCD handles application deployment from tenant repository
- **Crash-Only Platform:** Cluster is disposable (no persistent data inside)
- **Connectivity Injection:** Platform injects connection strings, doesn't host databases

Clear separation: Managed services (databases) + Internal platform (compute + cache).