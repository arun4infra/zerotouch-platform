# DeepAgents Runtime - Platform Architecture

## Current Architecture (Crossplane CRDs + ArgoCD)

**ArgoCD Role:**
- Deploys Crossplane claims + supporting resources
- Manages External Secrets, Jobs, Services
- Handles GitOps workflow and sync waves

**Crossplane Role:**
- Provisions infrastructure (PostgreSQL, Redis/Dragonfly)
- Generates application Deployments from EventDrivenService CRDs
- Creates connection secrets automatically

**Platform Abstraction:**
- Developers use simple CRDs (EventDrivenService, WebService)
- Crossplane compositions handle complex Kubernetes resources
- Overlays only handle image tags and environment labels (no patches needed)

## Resource Flow

1. **ArgoCD** reads kustomization and deploys ALL resources:
   ```yaml
   # Infrastructure Claims (Crossplane managed)
   apiVersion: database.bizmatters.io/v1alpha1
   kind: PostgresInstance
   
   # Application Claims (Crossplane managed)
   apiVersion: platform.bizmatters.io/v1alpha1
   kind: EventDrivenService
   ```

2. **Crossplane** sees the claims and:
   - Provisions PostgreSQL database infrastructure
   - Generates Kubernetes Deployment from EventDrivenService
   - Creates connection secrets (deepagents-runtime-db-conn)
   - Injects secrets into generated Deployment via envFrom

3. **External Secrets Operator** syncs secrets from AWS SSM:
   - Image pull secrets (ghcr-pull-secret)
   - Application secrets (deepagents-runtime-llm-keys)

## Key Benefits

- **Platform Team:** Provides abstractions via CRDs
- **Developers:** Use simple, declarative claims
- **GitOps:** ArgoCD handles deployment, Crossplane handles provisioning
- **No Manual Configuration:** Secrets and connections auto-generated

Both tools work together - ArgoCD as the deployment engine, Crossplane as the infrastructure + application provisioner.