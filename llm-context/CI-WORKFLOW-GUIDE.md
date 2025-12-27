# CI Workflow Guide

## Overview

The platform provides a centralized CI workflow that services consume through a filesystem contract. Services declare their requirements in `ci/config.yaml`, and the platform handles all execution complexity.

## Why This Approach?

**Problem:** Each service had duplicate CI scripts with hardcoded values, making maintenance difficult and inconsistent.

**Solution:** Platform owns execution, services own configuration. This ensures:
- Consistent CI behavior across all services
- No duplicate script maintenance
- Easy platform-wide improvements
- Service autonomy through configuration

## How It Works

### Three-Tier Dependency Model

**Why three tiers?** Different dependencies are needed at different CI stages and have different failure characteristics.

1. **Platform Dependencies** - Infrastructure APIs the service expects from the platform
2. **External Dependencies** - Other services this service depends on  
3. **Internal Dependencies** - Infrastructure created by this service's own claims

### CI Workflow Stages

**Infrastructure Setup (CI Environment Only):**
- **Stage 0a:** Setup Platform Environment
  - **Why:** Create Kind cluster and build service image
  - **What:** Creates Kind cluster, builds Docker image, loads image, applies platform patches
  - **Script:** `setup-platform-environment.sh`

- **Stage 0b:** Master Bootstrap
  - **Why:** Deploy platform infrastructure and ArgoCD
  - **What:** Bootstraps ArgoCD, deploys platform services, validates platform APIs
  - **Script:** `01-master-bootstrap.sh --mode preview`

**Service CI Workflow:**
- **Stage 1: Platform Readiness**
  - **Why:** Fail fast if platform isn't ready
  - **What:** Validates platform components service needs exist
  - **Script:** `check-platform-readiness.sh`

- **Stage 2: External Dependencies**  
  - **Why:** Deploy dependencies before dependent services
  - **What:** Sets up other services this service needs
  - **Script:** `setup-external-dependencies.sh`

- **Stage 3: Service Deployment**
  - **Why:** Build, patch, and deploy the service after dependencies are ready
  - **What:** Builds service image (auto-detects mode), patches deployment manifests, applies platform claims, runs migrations
  - **Scripts:** `build-service.sh`, `patch-service-images.sh`, `deploy.sh`, `run-migrations.sh`

- **Stage 4: Internal Validation**
  - **Why:** Verify service's own infrastructure works
  - **What:** Tests databases, caches, health endpoints created by service
  - **Script:** `post-deploy-diagnostics.sh`

## Build System

The platform provides a centralized build system that auto-detects the environment and builds appropriate images:

### Build Modes (Auto-Detected)

| Mode | Environment | Image Tag | Registry Push | Use Case |
|------|-------------|-----------|---------------|----------|
| `test` | Local development | `service:ci-test` | ❌ No | Local CI, developer testing |
| `pr` | GitHub CI (PR) | `service:branch-sha` | ✅ Yes | PR testing, staging |
| `prod` | GitHub CI (main) | `service:latest` + `service:main-sha` | ✅ Yes | Production deployment |

### Image Strategy

**Default State (Git Repository):**
- Deployment files contain production-ready image references: `service:latest`
- Git repository always represents production state

**CI Patching:**
- Local CI: Patches to `service:ci-test` (locally built)
- PR CI: Patches to `ghcr.io/org/service:branch-sha` (registry)
- Production: Uses default `service:latest` (no patching needed)

## How Services Use It

**Step 1:** Create `ci/config.yaml` with three dependency types
**Step 2:** Call platform script: `./zerotouch-platform/scripts/bootstrap/preview/tenants/scripts/in-cluster-test.sh`
**Step 3:** Platform handles everything based on configuration

## Key Files

**Service Contract:**
- `ci/config.yaml` - Service declares all requirements
- `ci-config.md` - Configuration reference

**Platform Scripts:**
- `setup-platform-environment.sh` - Infrastructure setup (Kind cluster, Docker build, platform patches)
- `01-master-bootstrap.sh` - Platform bootstrap (ArgoCD, platform services)
- `build-service.sh` - Service image building (auto-detects test/pr/prod mode)
- `patch-service-images.sh` - Deployment manifest patching based on build mode
- `check-platform-readiness.sh` - Platform readiness validation
- `setup-external-dependencies.sh` - External dependency setup
- `pre-deploy-diagnostics.sh` - External dependency validation  
- `deploy.sh` - Service deployment
- `run-migrations.sh` - Database migrations
- `post-deploy-diagnostics.sh` - Internal dependency validation
- `in-cluster-test.sh` - Main orchestration script (calls all above scripts)

**Examples:**
- `examples/deepagents-runtime-ci-config.yaml` - Complex service with all dependency types
- `examples/ide-orchestrator-ci-config.yaml` - Service with external dependencies

## Benefits

**For Services:**
- No CI script maintenance
- Declare requirements, platform handles execution
- Consistent behavior across environments

**For Platform:**
- Single place to improve CI for all services
- Enforce standards and best practices
- Easy to add new capabilities

**For Teams:**
- Faster onboarding - just provide config
- Reduced debugging - consistent execution
- Better reliability - battle-tested scripts

## Migration Path

1. **Analyze** existing service CI scripts
2. **Extract** requirements into `ci/config.yaml`
3. **Test** with platform script
4. **Remove** old service scripts
5. **Benefit** from centralized improvements

The platform handles complexity, services focus on business logic.