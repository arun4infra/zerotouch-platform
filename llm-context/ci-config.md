# CI Configuration Reference

This document explains each configuration option in `ci/config.yaml` and its impact on the CI pipeline.

## Configuration Structure

```yaml
service:
  name: "my-service"
  namespace: "intelligence-myservice"

build:
  dockerfile: "Dockerfile"
  context: "."
  tag: "ci-test"

test:
  timeout: 600
  parallel: true
  
deployment:
  wait_timeout: 300
  health_endpoint: "/ready"
  liveness_endpoint: "/health"
  
dependencies:
  - postgres
  - redis
  - deepagents-runtime

env:
  USE_MOCK_LLM: "true"
  LOG_LEVEL: "debug"

diagnostics:
  pre_deploy:
    check_dependencies: true
    check_platform_apis: true
  post_deploy:
    test_health_endpoint: true
    test_database_connection: true
    test_service_connectivity: true

platform:
  branch: "main"
```

## Configuration Sections

### `service` (Required)

Defines basic service metadata used throughout the CI pipeline.

| Field | Type | Required | Default | Impact |
|-------|------|----------|---------|---------|
| `name` | string | ✅ | - | Used for deployment names, secret names, Kubernetes labels |
| `namespace` | string | ✅ | - | Target Kubernetes namespace for deployment |

**CI Impact:**
- `name` becomes the deployment name, service name, and secret prefix
- `namespace` determines where all resources are created
- Used in all kubectl commands and resource lookups

**Example:**
```yaml
service:
  name: "deepagents-runtime"
  namespace: "intelligence-deepagents"
```

### `build` (Optional)

Controls Docker image building during CI.

| Field | Type | Required | Default | Impact |
|-------|------|----------|---------|---------|
| `dockerfile` | string | ❌ | `"Dockerfile"` | Path to Dockerfile for building |
| `context` | string | ❌ | `"."` | Docker build context directory |
| `tag` | string | ❌ | `"ci-test"` | Image tag used in CI environment |

**CI Impact:**
- Platform runs: `docker build -f ${dockerfile} -t ${name}:${tag} ${context}`
- Image is loaded into Kind cluster for testing
- Deployment uses `${name}:${tag}` image reference

**Example:**
```yaml
build:
  dockerfile: "docker/Dockerfile.ci"  # Custom Dockerfile location
  context: "."
  tag: "test-v1.0"
```

### `test` (Optional)

Controls test execution behavior.

| Field | Type | Required | Default | Impact |
|-------|------|----------|---------|---------|
| `timeout` | number | ❌ | `600` | Test job timeout in seconds |
| `parallel` | boolean | ❌ | `true` | Whether to run tests in parallel |

**CI Impact:**
- Test jobs will timeout after `timeout` seconds
- `parallel: false` runs tests sequentially (slower but more stable)
- Used in Kubernetes Job `activeDeadlineSeconds`

**Example:**
```yaml
test:
  timeout: 300    # 5 minutes for faster feedback
  parallel: false # Sequential execution for stability
```

### `deployment` (Optional)

Controls deployment behavior and health checks.

| Field | Type | Required | Default | Impact |
|-------|------|----------|---------|---------|
| `wait_timeout` | number | ❌ | `300` | Deployment readiness timeout in seconds |
| `health_endpoint` | string | ❌ | `"/ready"` | Readiness probe endpoint |
| `liveness_endpoint` | string | ❌ | `"/health"` | Liveness probe endpoint |

**CI Impact:**
- Platform waits up to `wait_timeout` seconds for deployment to be ready
- Post-deploy diagnostics test `health_endpoint` and `liveness_endpoint`
- Kubernetes probes use these endpoints in production

**Example:**
```yaml
deployment:
  wait_timeout: 600           # Wait longer for complex services
  health_endpoint: "/api/health"  # Custom health endpoint
  liveness_endpoint: "/health"
```

### `dependencies` (Optional)

Declares three types of dependencies that are handled at different CI stages.

#### Structure
```yaml
dependencies:
  # Platform services (checked in platform readiness)
  platform:
    - cnpg-operator
    - external-secrets
    - nats
    - keda
  
  # External services (deployed before this service)
  external:
    - deepagents-runtime
    - user-service
  
  # Internal services (validated after deployment)
  internal:
    - postgres
    - redis
    - nats-streams
```

#### Platform Dependencies
**When:** Platform readiness check (before any service deployment)  
**Purpose:** Validate required optional platform components exist  
**Impact:** CI fails fast if declared optional services are not available

**Foundation Services (Always Available):**
These services are always deployed and don't need to be declared:
- `external-secrets` - Secret management (sync-wave 0)
- `crossplane-operator` - Infrastructure provisioning (sync-wave 1)
- `kagent-crds` - AI platform CRDs (sync-wave 1)
- `cnpg` - PostgreSQL operator (sync-wave 2)
- `foundation-config` - Platform configuration (sync-wave 3)

**Optional Services (Declare Only If Used):**

| Value | Impact |
|-------|---------|
| `kagent` | Validates Kagent AI platform is available (CPU intensive - only for AI services) |
| `nats` | Validates NATS messaging platform is available |
| `keda` | Validates KEDA autoscaling platform is available |
| `prometheus` | Validates Prometheus monitoring platform is available |
| `istio` | Validates Istio service mesh is available |

**Important:** Only declare optional services your service actually uses. Undeclared optional services are automatically disabled to save CI resources.

#### External Dependencies  
**When:** After platform ready, before service deployment  
**Purpose:** Deploy other services this service depends on  
**Impact:** Platform deploys external services first, waits for them to be ready

| Value | Impact |
|-------|---------|
| `deepagents-runtime` | Clones, builds, deploys deepagents-runtime service |
| `user-service` | Deploys user-service before this service |

#### Internal Dependencies
**When:** Post-deploy diagnostics (after service deployment)  
**Purpose:** Validate infrastructure created by this service's platform claims  
**Impact:** Post-deploy diagnostics test these components

| Value | Impact |
|-------|---------|
| `postgres` | Validates `${service-name}-db` PostgreSQL cluster exists and is accessible |
| `redis` | Validates `${service-name}-cache` Redis/Dragonfly exists and is accessible |
| `nats-streams` | Validates NATS streams and consumers are created |
| `keda-scaler` | Validates KEDA ScaledObject is created and ready |

**CI Flow:**
1. **Platform Readiness:** Check `platform` dependencies exist
2. **External Setup:** Deploy `external` dependencies first  
3. **Service Deploy:** Deploy this service (creates internal infrastructure)
4. **Internal Validation:** Check `internal` dependencies work

**Auto-Generated Resources:**
```bash
# Internal postgres dependency creates:
${service-name}-db cluster + ${service-name}-db-conn secret

# Internal redis dependency creates:  
${service-name}-cache StatefulSet + ${service-name}-cache-conn secret
```

### `env` (Optional)

Environment variables injected during CI testing.

**CI Impact:**
- Variables are exported before running tests
- Available in test containers and diagnostic scripts
- Used to configure service behavior in CI environment

**Example:**
```yaml
env:
  USE_MOCK_LLM: "true"      # Avoid real LLM API calls in CI
  LOG_LEVEL: "debug"        # Verbose logging for debugging
  FEATURE_FLAGS: "experimental_api,new_ui"
```

### `diagnostics` (Optional)

Controls which diagnostic checks run during CI.

#### `pre_deploy` Diagnostics

Run before service deployment to validate infrastructure readiness.

| Field | Type | Default | Impact |
|-------|------|---------|---------|
| `check_dependencies` | boolean | `true` | Validates each dependency is healthy |
| `check_platform_apis` | boolean | `true` | Validates required XRDs and compositions exist |

**CI Impact:**
- `check_dependencies: true` → Validates PostgreSQL clusters, cache instances, dependent services
- `check_platform_apis: true` → Validates Crossplane XRDs, compositions, providers
- Failed checks stop deployment with clear error messages

#### `post_deploy` Diagnostics

Run after service deployment to validate service health.

| Field | Type | Default | Impact |
|-------|------|---------|---------|
| `test_health_endpoint` | boolean | `true` | Tests readiness and liveness endpoints |
| `test_database_connection` | boolean | `true` | Tests database connectivity from service pod |
| `test_service_connectivity` | boolean | `true` | Tests service is accessible via cluster IP |

**CI Impact:**
- `test_health_endpoint: true` → Tests `health_endpoint` and `liveness_endpoint` respond
- `test_database_connection: true` → Validates database connection using auto-generated secrets
- `test_service_connectivity: true` → Validates service is reachable within cluster

**Example:**
```yaml
diagnostics:
  pre_deploy:
    check_dependencies: true    # Validate postgres, redis are ready
    check_platform_apis: false # Skip XRD validation (faster CI)
  post_deploy:
    test_health_endpoint: true     # Test /ready and /health endpoints
    test_database_connection: true # Test database connectivity
    test_service_connectivity: false # Skip connectivity test
```

### `platform` (Optional)

Platform-specific configuration.

| Field | Type | Default | Impact |
|-------|------|---------|---------|
| `branch` | string | `"main"` | Which platform branch to use for CI scripts |

**CI Impact:**
- Platform clones `zerotouch-platform` repository using this branch
- Allows testing against platform feature branches
- Production should always use `"main"`

**Example:**
```yaml
platform:
  branch: "feature/new-diagnostics"  # Test against platform feature branch
```

## Configuration Examples

### Minimal Service (API Only)
```yaml
service:
  name: "simple-api"
  namespace: "intelligence-simple"

dependencies:
  platform:
    - cnpg-operator
    - external-secrets
  external: []
  internal: []

diagnostics:
  pre_deploy:
    check_platform_apis: true
  post_deploy:
    test_health_endpoint: true
    test_service_connectivity: true
```

### Database Service
```yaml
service:
  name: "user-service"
  namespace: "intelligence-users"

dependencies:
  platform:
    - cnpg-operator
    - external-secrets
    - crossplane-providers
  external: []
  internal:
    - postgres

env:
  LOG_LEVEL: "info"

diagnostics:
  pre_deploy:
    check_dependencies: true
    check_platform_apis: true
  post_deploy:
    test_health_endpoint: true
    test_database_connection: true
    test_service_connectivity: true
```

### Complex Service with All Dependency Types
```yaml
service:
  name: "deepagents-runtime"
  namespace: "intelligence-deepagents"

deployment:
  health_endpoint: "/ready"
  wait_timeout: 600

dependencies:
  platform:
    - cnpg-operator
    - external-secrets
    - crossplane-providers
    - nats
    - keda
  external: []
  internal:
    - postgres
    - redis
    - nats-streams
    - keda-scaler

env:
  USE_MOCK_LLM: "true"
  LOG_LEVEL: "debug"

diagnostics:
  pre_deploy:
    check_dependencies: true
    check_platform_apis: true
  post_deploy:
    test_health_endpoint: true
    test_database_connection: true
    test_service_connectivity: true
```

### Service with External Dependencies
```yaml
service:
  name: "ide-orchestrator"
  namespace: "intelligence-orchestrator"

deployment:
  health_endpoint: "/api/health"  # Custom endpoint

dependencies:
  platform:
    - cnpg-operator
    - external-secrets
    - crossplane-providers
  external:
    - deepagents-runtime          # Deploy this first
  internal:
    - postgres

env:
  JWT_SECRET: "test-secret"

diagnostics:
  pre_deploy:
    check_dependencies: true
    check_platform_apis: true
  post_deploy:
    test_health_endpoint: true
    test_database_connection: true
    test_service_connectivity: true
```

## Best Practices

### ✅ Do
- Use standard health endpoints (`/health`, `/ready`) when possible
- Enable all diagnostics for comprehensive validation
- Set appropriate timeouts based on service complexity
- Use mock configurations in CI environment variables
- Declare all infrastructure dependencies explicitly

### ❌ Don't
- Hardcode secrets or credentials in config
- Disable diagnostics without good reason
- Use very short timeouts (causes flaky tests)
- Mix production and CI configuration
- Skip dependency declarations

## Troubleshooting

### Common Issues

**Deployment Timeout:**
```yaml
deployment:
  wait_timeout: 600  # Increase timeout
```

**Health Check Failures:**
```yaml
deployment:
  health_endpoint: "/api/health"  # Check correct endpoint
```

**Dependency Issues:**
```yaml
diagnostics:
  pre_deploy:
    check_dependencies: true  # Enable to see what's failing
```

**Test Timeouts:**
```yaml
test:
  timeout: 900  # Increase test timeout
  parallel: false  # Try sequential execution
```

## Migration from Service Scripts

When migrating from service-specific CI scripts to platform configuration:

1. **Extract hardcoded values** from scripts into config
2. **Map script behavior** to diagnostic flags
3. **Identify dependencies** and declare them
4. **Test configuration** with platform scripts
5. **Remove old scripts** after validation

The platform scripts will handle all the complexity while your service just provides the configuration!