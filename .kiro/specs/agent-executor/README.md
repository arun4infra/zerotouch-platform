# Agent Executor Deployment Specifications

This directory contains two separate specifications for deploying the agent_executor service following the **Provider-Consumer** model.

## Overview

The agent_executor deployment is split into two distinct concerns:

1. **Platform API** (Public) - Defines the infrastructure capabilities
2. **Service Deployment** (Private) - Uses the platform to deploy the actual service

## Specifications

### 1. Agent Executor Platform API

**Location:** `agent-executor-platform-api/`

**Repository:** zerotouch-platform (Public)

**Purpose:** Create reusable infrastructure API for event-driven services

**What it provides:**
- NATS with JetStream for message streaming
- AgentExecutor XRD (the API contract)
- AgentExecutor Composition (the provisioning machinery)
- Platform documentation and standards

**Checkpoints:**
1. Deploy NATS with JetStream
2. Create and deploy XRD and Composition
3. Create documentation and test with example claim

**Audience:** Platform engineers, open-source consumers

---

### 2. Agent Executor Service Deployment

**Location:** `agent-executor-service-deployment/`

**Repository:** bizmatters (Private) - **This spec should be moved there**

**Purpose:** Deploy the agent_executor service using the platform API

**What it provides:**
- Application code changes (NATS consumer, remove Vault)
- Integration tests (Dragonfly, NATS)
- Deployment manifests (namespace, secrets, claim)
- ArgoCD configuration for private repo

**Checkpoints:**
1. Update application code for NATS architecture
2. Update integration tests
3. Configure secrets and create deployment manifests
4. Deploy and verify agent executor

**Audience:** Application developers (bizmatters team)

---

## Architecture: Provider-Consumer Model

```
┌─────────────────────────────────────────────────────────────┐
│         Public Platform Repo (zerotouch-platform)           │
│                                                               │
│  Provides:                                                    │
│  - NATS infrastructure                                        │
│  - AgentExecutor XRD (API definition)                         │
│  - AgentExecutor Composition (provisioning logic)             │
│  - Documentation and standards                                │
│                                                               │
│  Does NOT contain:                                            │
│  - Application code                                           │
│  - Private images                                             │
│  - Service instances (claims)                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Defines API
                            ▼
┌─────────────────────────────────────────────────────────────┐
│           Private Application Repo (bizmatters)             │
│                                                               │
│  Provides:                                                    │
│  - Agent executor Python code                                 │
│  - Private container images                                   │
│  - AgentExecutor claim (uses platform API)                    │
│  - ExternalSecrets (reference to AWS SSM)                     │
│  - ArgoCD Application (for this repo)                         │
│                                                               │
│  Does NOT contain:                                            │
│  - Infrastructure definitions                                 │
│  - Platform components                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ ArgoCD Syncs
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                               │
│  Crossplane sees Claim → Provisions Resources                │
│  - Deployment (with private image)                            │
│  - Service                                                    │
│  - KEDA ScaledObject                                          │
│  - ServiceAccount                                             │
└─────────────────────────────────────────────────────────────┘
```

## Execution Order

### Phase 1: Platform Setup (Public Repo)
Execute `agent-executor-platform-api/tasks.md` in zerotouch-platform repository:
1. Deploy NATS
2. Create XRD and Composition
3. Document and test

**Result:** Platform API is available for consumers

### Phase 2: Service Deployment (Private Repo)
Move `agent-executor-service-deployment/` to bizmatters repository, then execute `tasks.md`:
1. Update application code
2. Update integration tests
3. Create deployment manifests
4. Deploy via GitOps

**Result:** Agent executor service running on platform

## Key Principles

### Separation of Concerns
- **Platform** defines HOW to run services (infrastructure)
- **Application** defines WHAT to run (business logic)

### GitOps Workflow
- Platform changes: Commit to zerotouch-platform → ArgoCD syncs
- Application changes: Commit to bizmatters → ArgoCD syncs

### Security
- Platform repo: Public (no sensitive data)
- Application repo: Private (code, images, claims)
- Secrets: AWS SSM Parameter Store (not in Git)

### Reusability
- Platform API can be used by any consumer
- Other services can use AgentExecutor API
- Platform is open-source, applications are private

## Testing Strategy

### Platform Testing (Public)
- Deploy NATS and verify JetStream
- Deploy XRD/Composition and verify installation
- Create test claim with public nginx image
- Verify resources provisioned correctly
- Verify cleanup works

### Application Testing (Private)
- Unit tests for code changes
- Integration tests with Dragonfly and NATS
- Deployment verification in cluster
- End-to-end message processing
- KEDA autoscaling verification

## Documentation

### Platform Documentation
- `platform/04-apis/README.md` - AgentExecutor API reference
- `docs/standards/namespace-naming-convention.md` - Namespace standards
- `docs/standards/nats-stream-configuration.md` - NATS configuration guide

### Application Documentation
- Service-specific documentation in bizmatters repo
- Deployment runbooks
- Troubleshooting guides

## Next Steps

1. **Execute Platform Spec First**
   - Work through `agent-executor-platform-api/tasks.md`
   - Complete all 3 checkpoints
   - Verify platform API is working

2. **Move Application Spec to Private Repo**
   - Copy `agent-executor-service-deployment/` to `bizmatters/.kiro/specs/`
   - Update any paths if needed

3. **Execute Application Spec**
   - Work through `agent-executor-deployment/tasks.md` in bizmatters repo
   - Complete all 4 checkpoints
   - Verify service is deployed and working

4. **Iterate and Improve**
   - Update documentation based on learnings
   - Refine platform API based on usage
   - Add more examples and use cases

## Questions?

If you have questions about:
- **Platform API**: Check `agent-executor-platform-api/requirements.md` and `design.md`
- **Service Deployment**: Check `agent-executor-service-deployment/requirements.md` and `design.md`
- **Architecture**: Review this README and the design documents
