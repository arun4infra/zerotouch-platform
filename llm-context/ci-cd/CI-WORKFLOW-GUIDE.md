# CI Workflow Guide: "Build Once, Validate Many, Release One"

## Architecture

**Problem Solved**: Each test building separate images, artifact drift, monolithic workflows

**Solution**: 3-stage reusable workflows with artifact reuse

```mermaid
graph LR
    A[Build Once] --> B[Test Many] --> C[Release One]
    
    subgraph "Reusable Workflows"
        A1[ci-build.yml]
        B1[ci-test.yml]
        C1[release-pipeline.yml]
    end
```

## Workflow Integration

### Service Implementation Pattern
Services create **single orchestration workflow** (`.github/workflows/main-pipeline.yml`):

```yaml
name: "Build Once, Validate Many, Release One"

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# REQUIRED: Permissions for reusable workflows
permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  # STAGE 1: Build artifact once
  build:
    uses: arun4infra/zerotouch-platform/.github/workflows/ci-build.yml@main
    with:
      service_name: my-service
    secrets: inherit
    
  # STAGE 2: Parallel tests using same artifact  
  test-nats:
    needs: build
    uses: arun4infra/zerotouch-platform/.github/workflows/ci-test.yml@main
    with:
      image_tag: ${{ needs.build.outputs.image_tag }}
      test_suite: "tests/integration/nats"
      test_name: "nats"
      timeout: 30
    secrets: inherit
      
  test-api:
    needs: build  
    uses: arun4infra/zerotouch-platform/.github/workflows/ci-test.yml@main
    with:
      image_tag: ${{ needs.build.outputs.image_tag }}
      test_suite: "tests/integration/api"
      test_name: "api"
      timeout: 30
    secrets: inherit
      
  # STAGE 3: Release only if ALL tests pass
  release:
    needs: [build, test-nats, test-api]
    if: github.ref == 'refs/heads/main'
    uses: arun4infra/zerotouch-platform/.github/workflows/release-pipeline.yml@main
    with:
      service_name: my-service
      image_tag: ${{ needs.build.outputs.image_tag }}
    secrets: inherit
```

### Required Permissions

The reusable workflows require specific permissions that must be granted at the workflow level:

- `contents: read` - Read repository contents and clone code
- `packages: write` - Push container images to GitHub Container Registry
- `pull-requests: write` - Comment on PRs with test results and deployment status
- `id-token: write` - Generate OIDC tokens for AWS authentication

**Critical**: Without these permissions, the workflow will fail with permission errors when calling reusable workflows.

## Artifact-Aware Testing

### ci-test.yml Integration
- Accepts `image_tag` input from build job
- Pulls pre-built image: `docker pull ${{ inputs.image_tag }}`
- Sets `OVERRIDE_IMAGE_TAG` environment variable
- Calls `in-cluster-test.sh` with artifact awareness

### Bootstrap Script Integration
`in-cluster-test.sh` detects `OVERRIDE_IMAGE_TAG` and:
- **Skips local build** when artifact provided
- **Uses pre-built image** for Kind cluster
- **Patches manifests** with correct image tag
- **Deploys exact tested artifact**

## Service Configuration

### Filesystem Contract
Services declare requirements in `ci/config.yaml`:

```yaml
service:
  name: "my-service"
  namespace: "intelligence-myservice"
  
dependencies:
  platform: [cnpg-operator, external-secrets]
  external: [deepagents-runtime]  
  internal: [postgres, redis]
  
env:
  USE_MOCK_LLM: "true"
  LOG_LEVEL: "debug"
```

### Runtime Bootstrapper (Required)
Services must provide `scripts/ci/run.sh` as the container entrypoint. This script serves as the runtime bootstrapper that bridges platform-provided environment variables and application startup requirements:

```bash
#!/bin/bash
set -euo pipefail

# Runtime Bootstrapper - handles environment transformation and startup
# Purpose: Bridge platform variables to application requirements
# Called by: Dockerfile CMD ["./scripts/ci/run.sh"]

# Transform platform variables to application format
if [[ -n "${POSTGRES_HOST:-}" ]]; then
    export DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"
fi

# Start application
exec ./bin/my-service
```

**Why Required**: The platform provides granular environment variables (POSTGRES_HOST, POSTGRES_USER, etc.) but applications often expect consolidated formats (DATABASE_URL). The run.sh script handles this transformation and ensures proper startup sequencing.

### Platform Execution
Platform handles all complexity:
1. **Platform Readiness**: Validates required components exist
2. **External Dependencies**: Deploys dependent services first
3. **Service Deployment**: Builds/patches/deploys service
4. **Internal Validation**: Tests service infrastructure

## Build System Evolution

### Old Pattern (Deprecated)
```yaml
# Multiple workflows, each building separately
nats-tests.yml    # Builds image, runs NATS tests
api-tests.yml     # Builds image, runs API tests
release.yml       # Builds image, deploys
```

### New Pattern (Current)
```yaml
# Single orchestration workflow
main-pipeline.yml # Build once → Test many → Release one
```

## Benefits

**Build Efficiency**:
- 1 build instead of N builds (N = test suites)
- Parallel tests using pre-built image
- Consistent artifacts across pipeline

**Test Visibility**:
- Granular failures (separate job per test suite)
- Parallel execution for speed
- Focused logs per test type

**Deployment Safety**:
- Exact tested image deployed
- All tests must pass gate
- Clear audit trail

## Migration Path

1. **Copy template**: Use `scripts/release/template/example-tenant-workflow.yml`
2. **Add test jobs**: One job per test suite
3. **Configure secrets**: GitHub tokens, AWS credentials
4. **Setup environments**: Create staging/production with approvers
5. **Archive old workflows**: Move to `archived/` directory

Platform handles complexity, services focus on business logic.