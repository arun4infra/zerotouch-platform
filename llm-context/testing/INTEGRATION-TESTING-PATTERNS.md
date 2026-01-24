# Integration Testing Patterns for ZeroTouch Platform

## Platform Integration Testing Infrastructure

The ZeroTouch platform provides centralized workflows and infrastructure that make integration testing possible:

**Key Platform Files:**
- `zerotouch-platform/.github/workflows/ci-build.yml` - Builds Docker images and pushes to registry
- `zerotouch-platform/.github/workflows/ci-test.yml` - Runs integration tests in Kubernetes cluster
- `service/platform/argocd-application.yaml` - Claims that deploy real internal infrastructure services (PostgreSQL, Redis, NATS)

**How It Works:**
1. **Build Stage**: Platform builds your service container with test data included
2. **Test Stage**: Platform deploys your service + real infrastructure to Kind cluster
3. **Infrastructure**: Your platform claims automatically provision PostgreSQL, Redis, etc.
4. **Execution**: Your integration tests run against real infrastructure with mocked external dependencies

## Core Philosophy

**"Test Real Infrastructure, Mock External Dependencies, Use Production Code Paths"**

Integration tests validate your service against real internal platform infrastructure (PostgreSQL, Redis, NATS) while mocking external service dependencies to ensure deterministic, fast, and reliable CI execution.

## Dependency Classification Framework

**How to Identify What to Mock vs Use Real Infrastructure:**

1. **Check your service's `ci/config.yaml` file**
2. **Look at the `dependencies` section:**
   - `external:` - Services listed here should be mocked (third-party APIs, external services)
   - `internal:` - Services listed here use real platform infrastructure (PostgreSQL, Redis, NATS)
   - `platform:` - Platform services use real infrastructure (APIs, databases, crossplane)

**Golden Rule:** Only mock what's listed under `external:` in your `ci/config.yaml`

**Example ci/config.yaml:**
```yaml
dependencies:
  external:
    - third-party-api      # Mock this
    - external-webhook     # Mock this
  internal:
    - postgres            # Use real PostgreSQL
    - redis               # Use real Redis
  platform:
    - apis                # Use real platform APIs
    - databases           # Use real database provisioning
```

## Production Code Path Requirements

**What is a Production Code Path:**
- Same service classes used in production (`WorkflowService`, `AuthService`, etc.)
- Same dependency injection functions (`get_database_url()`, `get_workflow_service()`)
- Same API endpoints and routing
- Same database connections and queries
- Same business logic execution
- Same WebSocket proxies and internal communication

**What is NOT a Production Code Path:**
- Test-only service classes or database access patterns
- Direct database queries bypassing service layer
- Mock implementations of internal services
- Separate test configuration that changes business logic
- Test-specific dependency injection or service initialization

**Critical Principle: Same Code Paths as Production**
- Tests must use the exact same service classes, dependency injection, and business logic as production
- Never create separate test-only database access patterns or service implementations
- This ensures maximum code coverage and validates actual production behavior
- Internal services (PostgreSQL, Redis, NATS) are already available in the cluster - use them directly

## Mock Boundaries

**ONLY Mock External Dependencies:**
- Services listed in `ci/config.yaml` under `external:`
- Third-party APIs outside your platform
- External webhooks or callbacks
- Services not controlled by your platform

**NEVER Mock Internal Components:**
- Your own service's business logic
- Internal API endpoints
- Database connections to platform-provided databases
- WebSocket proxies within your service
- Authentication/authorization within your service
- Internal message queues or event streams
- Platform-provided infrastructure services

## Integration vs Unit Test Identification

**You're Writing Integration Tests When:**
- Testing complete business workflows end-to-end
- Using real platform infrastructure (PostgreSQL, Redis, NATS)
- Making HTTP requests to your service's API endpoints
- Validating data persistence across service boundaries
- Testing WebSocket connections and streaming
- Validating authentication and authorization flows

**You're Writing Unit Tests When:**
- Testing individual functions or methods
- Mocking internal dependencies
- Testing business logic in isolation
- Using test doubles for database access
- Testing single components without external dependencies

## Directory Structure Standards

```
service-repo/
├── tests/
│   ├── testdata/           # Static fixtures only (JSON, SQL, config files)
│   ├── mock/              # Mock servers, fakes, helpers (Go/Python code)
│   └── integration/       # Integration test files
```

**Rules:**
- `testdata/` - No executable code, only data files
- `mock/` - Reusable mock implementations and test helpers
- `integration/` - Test files that validate end-to-end workflows

## Mock Strategy Patterns

### 1. Environment Variable Override Pattern (Primary Integration Method)

**How Integration Tests Work:**
1. Production code reads URLs from environment variables
2. Tests set environment variables to point to mock servers
3. Production code automatically uses mocks without code changes
4. No special test configuration or dependency injection needed

**Example Implementation:**
```go
// Production code (no changes needed for tests)
externalURL := os.Getenv("EXTERNAL_SERVICE_URL") // Test sets this to mock URL
if externalURL == "" {
    externalURL = "http://external-service.namespace.svc.cluster.local" // Production default
}
```

**Benefits:**
- No container orchestration needed
- Fast startup and deterministic behavior
- Production code remains unchanged for testing
- Clear separation between production and test configuration

### 2. In-Process HTTP Mocks
**When:** Mocking HTTP/WebSocket APIs of external services
**How:** Use language-native test servers (`httptest` in Go, `pytest-httpserver` in Python)

```go
// tests/mock/external_service_mock.go
type MockExternalService struct {
    server *httptest.Server
    testData map[string]interface{}
}

func NewMockExternalService(dataFile string) *MockExternalService {
    // Read from tests/testdata/service_responses.json
    // Return httptest.Server with realistic endpoints
}
```

### 3. Source of Truth Data
**Rule:** Mock data must come from real service outputs, not invented payloads
**Implementation:**
- Export actual JSON responses from real services
- Store in `tests/testdata/` with descriptive names
- Version control these files as test fixtures

### 4. Configuration Override Pattern
**Problem:** Services hardcode external service URLs for production
**Solution:** Environment variable override in test configuration

```go
// Allow test to override production URLs
if mockURL := os.Getenv("MOCK_SERVICE_URL"); mockURL != "" {
    config.ExternalServiceURL = mockURL
} else {
    // Use production Kubernetes DNS
    config.ExternalServiceURL = "http://external-service.namespace.svc.cluster.local"
}
```

### 4. Fallback/Mock guidlines

- you should never add fallback or mock the instructions. Do no not deviate from actual logic. 
- Do not deviate or over-engineer the solution. 
- I would expect the test cases to fail if there are issues or during its first run as we are following TDD and implementations will be missing which is known already. 
- Do not bloat or deviate from actual logics. Add only what is required.  
- If necesary implementations are missing, then before creating the test files, get my approval and build the missing implementations. - Test cases should not enrich or enhance the value produced by the source file. It should write or display the artifacts as it is produced.


## Database Testing Patterns

### 1. Real Database, Production Code Paths
**Rule:** Use real PostgreSQL/Redis instances with the same service classes as production
**Critical:** Tests must use identical dependency injection and service layer code as production

**Implementation:**
- Use actual service classes (`WorkflowService`, `AuthService`, etc.) in tests
- Get dependencies through the same `get_database_url()`, `get_workflow_service()` functions
- Never create test-only database access patterns or duplicate service logic
- This maximizes code coverage by testing actual production code paths

```go
// ✅ CORRECT: Use production service classes
func TestWorkflowCreation(t *testing.T) {
    // Use same dependency injection as production
    dbURL := dependencies.GetDatabaseURL()
    workflowService := services.NewWorkflowService(dbURL)
    
    // Test through actual service layer
    result := workflowService.CreateWorkflow(input)
    
    // Validate persistence through direct database query
    var dbRecord WorkflowRecord
    db.First(&dbRecord, "workflow_id = ?", result.WorkflowID)
}

// ❌ WRONG: Creating test-only database access
func TestWorkflowCreation(t *testing.T) {
    testDB := NewTestDatabase() // Don't create separate test database classes
    // This bypasses production code paths and reduces code coverage
}
```

### 2. Service Layer Validation Pattern

**Correct Validation Approach:**
1. Execute operations through production service layer
2. Validate results through production API endpoints
3. Use production service methods for state verification
4. Only query database directly for final persistence validation

**Example:**
```go
// ✅ CORRECT: Use production services for validation
result := workflowService.CreateWorkflow(input)
proposal := proposalService.GetProposal(result.ProposalID)
assert.Equal(t, "completed", proposal.Status)

// Final persistence check (optional)
var dbRecord ProposalRecord
db.First(&dbRecord, "proposal_id = ?", result.ProposalID)
assert.Equal(t, expectedData, dbRecord.GeneratedFiles)

// ❌ WRONG: Direct database access bypassing services
var dbRecord ProposalRecord
db.Query("SELECT * FROM proposals WHERE id = ?", proposalID)
assert.Equal(t, "completed", dbRecord.Status) // Bypasses service layer
```

### 3. Persistence Validation
**Critical:** Integration tests must validate data persistence through direct database queries
**Pattern:** Execute through production services, validate through database
```go
// 1. Execute workflow through production service
result := workflowService.ProcessWorkflow(input)

// 2. Validate immediate response
assert.Equal(t, "success", result.Status)

// 3. Query database directly to validate persistence
var dbRecord WorkflowRecord
db.First(&dbRecord, "workflow_id = ?", result.WorkflowID)
assert.Equal(t, expectedData, dbRecord.GeneratedFiles)
```

### 4. Clean State Management
**Rule:** Ensure clean state per test while using production services
**Implementation:**
- Run migrations before each test
- Truncate tables after each test
- Use test-specific database schemas when possible
- But always use production service classes for data access

## Test Isolation Patterns

### 1. Per-Test Mock Servers
**Rule:** Start fresh mock server for each test function
**Reason:** Prevents test interference and state leakage

```go
func TestWorkflowProcessing(t *testing.T) {
    mockServer := mock.NewExternalService("testdata/workflow_events.json")
    defer mockServer.Close()
    
    // Configure service to use mock
    os.Setenv("MOCK_SERVICE_URL", mockServer.URL)
    defer os.Unsetenv("MOCK_SERVICE_URL")
    
    // Run test
}
```

### 2. Database Transaction Rollback
**Alternative:** Wrap each test in database transaction, rollback at end
**Use When:** Migration overhead is expensive

## Container Integration Patterns

### 1. Test Data in Container
**Rule:** Test containers must include test data
**Implementation:**
```dockerfile
# Dockerfile.test
COPY tests/testdata ./tests/testdata
COPY tests/mock ./tests/mock
```

### 2. Environment Variable Injection
**Pattern:** CI injects mock URLs via environment variables
**Benefit:** Same test code works locally and in CI

## Validation Patterns

### 1. End-to-End Workflow Validation
**Scope:** Test complete business workflows, not individual functions
**Example:** User creates workflow → Service processes → Database updated → External API called

### 2. Protocol Fidelity
**Rule:** Mocks must implement the same protocols as real services
**Implementation:**
- HTTP endpoints with correct status codes
- WebSocket upgrades and message streaming
- Authentication headers and error responses

### 3. Timing Independence
**Rule:** Tests must not depend on specific timing or delays
**Implementation:**
- Use deterministic event ordering
- Poll database for state changes instead of `time.Sleep()`
- Mock servers respond immediately

## CI Integration Patterns

### 1. Dependency Declaration
**Rule:** Declare external dependencies in `ci/config.yaml` for tracking
**Note:** Platform may not deploy them if mocked, but declaration maintains visibility

```yaml
dependencies:
  external:
    - external-service  # Tracked but not deployed if mocked
  internal:
    - postgres         # Always deployed and tested against
```

### 2. Test Suite Organization
**Pattern:** Organize tests by business capability, not technical layer
**Example:**
- `test-auth` - Authentication and authorization workflows
- `test-workflow` - Core business workflow processing
- `test-integration` - Cross-service integration scenarios

### 3. Cleanup Automation
**Rule:** Remove connectivity checks for mocked services
**Implementation:** CI scripts should not wait for services that are mocked

## Anti-Patterns to Avoid

### ❌ Don't Mock Infrastructure
- Never mock PostgreSQL, Redis, NATS (use real instances)
- Never mock Kubernetes APIs (use real cluster)

### ❌ Don't Create Test-Only Code Paths
- Never create separate test database classes or service implementations
- Never bypass production dependency injection patterns
- Always use the same service classes, database connections, and business logic as production
- Test-only code paths reduce code coverage and don't validate production behavior
- Never mock internal WebSocket proxies, API endpoints, or business logic

### ❌ Don't Mock Internal Services
- Internal services (PostgreSQL, Redis, NATS) are already available in the cluster
- Don't create mock versions of internal platform services
- Use the real services directly through production code paths
- Don't mock your own service's internal components (WebSocket proxies, business logic)

### ❌ Don't Use Hardcoded Test Data
- Never invent JSON payloads in test code
- Always use exported real service data

### ❌ Don't Test Implementation Details
- Test business outcomes, not internal function calls
- Validate database state, not service logs

### ❌ Don't Create Timing Dependencies
- Never use fixed `sleep()` calls
- Never assume specific execution order without synchronization

### ❌ Don't Duplicate Internal Services
- Internal services (PostgreSQL, Redis, NATS) are already available in the cluster
- Don't create mock versions of internal platform services
- Use the real services directly through production code paths

## Best Practices Summary

1. **Check ci/config.yaml First**: Always check your service's `ci/config.yaml` to identify external vs internal dependencies
2. **Real Infrastructure**: Test against actual PostgreSQL, Redis, NATS (internal dependencies)
3. **Production Code Paths**: Use identical service classes and dependency injection as production
4. **Mock External Services Only**: Use in-process HTTP mocks with real data for external dependencies only
5. **Environment Variable Override**: Primary integration method - let production code use mocks via environment variables
6. **Service Layer Validation**: Execute through production services, validate through production APIs
7. **Clean State**: Ensure each test starts with clean database state
8. **Validate Persistence**: Always check database after workflow completion (final validation step)
9. **Container Ready**: Include test data in Docker images
10. **Protocol Complete**: Implement full protocol compatibility in mocks
11. **Deterministic**: Remove timing dependencies and race conditions
12. **Maximum Code Coverage**: Test through production services to validate actual business logic

This pattern ensures integration tests are fast, reliable, validate real business value, and achieve maximum code coverage by testing the exact same code paths used in production.

## LOCAL-IN-CLUSTER-TESTING-PATTERN

## Create ./scripts/ci/in-cluster-test.sh

```bash
#!/bin/bash
set -euo pipefail

# ==============================================================================
# Service CI Entry Point for ide-orchestrator
# ==============================================================================
# Purpose: Standardized entry point for platform-based CI testing
# Usage: ./scripts/ci/in-cluster-test.sh
# ==============================================================================

# Get platform branch from service config
if [[ -f "ci/config.yaml" ]]; then
    if command -v yq &> /dev/null; then
        PLATFORM_BRANCH=$(yq eval '.platform.branch // "main"' ci/config.yaml)
    else
        PLATFORM_BRANCH="main"
    fi
else
    PLATFORM_BRANCH="main"
fi

# Always ensure fresh platform checkout
if [[ -d "zerotouch-platform" ]]; then
    echo "Removing existing platform checkout for fresh clone..."
    rm -rf zerotouch-platform
fi

echo "Cloning fresh zerotouch-platform repository (branch: $PLATFORM_BRANCH)..."
git clone -b "$PLATFORM_BRANCH" https://github.com/arun4infra/zerotouch-platform.git zerotouch-platform

# Run platform script
./zerotouch-platform/scripts/bootstrap/preview/tenants/in-cluster-test.sh

```

## Update .env file

```bash
# AWS Credentials (dummy values for local preview mode)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
BOT_GITHUB_USERNAME=
BOT_GITHUB_TOKEN=
TENANTS_REPO_NAME=zerotouch-tenants
ANTHROPIC_API_KEY=12345567
AWS_ROLE_ARN=
```

## Run below command only if cluster is not running in local machine

```bash
export CLEANUP_CLUSTER=false && export $(grep -v '^#' .env | grep -v '^$' | xargs) && ./scripts/ci/in-cluster-test.sh
```

## Example - IN-Cluster Testing single test locally

```bash
kubectl run integration-test-manual --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "integration-test-manual",
        "image": "ide-orchestrator:ci-test",
        "command": ["python", "-m", "pytest", "tests/integration/test_workflow_integration.py::test_complete_workflow_lifecycle", "-v"],
        "env": [
          {"name": "POSTGRES_HOST", "value": "ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},
          {"name": "POSTGRES_PORT", "value": "5432"},
          {"name": "POSTGRES_USER", "value": "ide-orchestrator-db"},
          {"name": "POSTGRES_PASSWORD", "value": "0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},
          {"name": "POSTGRES_DB", "value": "ide-orchestrator-db"},
          {"name": "JWT_SECRET", "value": "test-secret-key-for-testing"},
          {"name": "REDIS_URL", "value": "redis://redis:6379"},
          {"name": "API_BASE_URL", "value": "http://ide-orchestrator:8000"}
        ]
      }
    ]
  }
}'
```

## Example - IN-Cluster Testing all tests locally

```bash
kubectl run integration-test-all --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "integration-test-all",
        "image": "ide-orchestrator:ci-test",
        "command": ["python", "-m", "pytest", "tests/integration/", "-v"],
        "env": [
          {"name": "POSTGRES_HOST", "value": "ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},
          {"name": "POSTGRES_PORT", "value": "5432"},
          {"name": "POSTGRES_USER", "value": "ide-orchestrator-db"},
          {"name": "POSTGRES_PASSWORD", "value": "0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},
          {"name": "POSTGRES_DB", "value": "ide-orchestrator-db"},
          {"name": "JWT_SECRET", "value": "test-secret-key-for-testing"},
          {"name": "REDIS_URL", "value": "redis://redis:6379"},
          {"name": "API_BASE_URL", "value": "http://ide-orchestrator:8000"}
        ]
      }
    ]
  }
}'
```

```bash
kubectl run integration-test-lifecycle --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='{"spec":{"containers":[{"name":"integration-test-lifecycle","image":"ide-orchestrator:ci-test","command":["bash","-c","cd /app && python -m pytest tests/integration/test_refinement_lifecycle.py::test_refinement_approved_lifecycle -v"],"env":[{"name":"POSTGRES_HOST","value":"ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},{"name":"POSTGRES_PORT","value":"5432"},{"name":"POSTGRES_USER","value":"ide-orchestrator-db"},{"name":"POSTGRES_PASSWORD","value":"0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},{"name":"POSTGRES_DB","value":"ide-orchestrator-db"},{"name":"JWT_SECRET","value":"test-secret-key-for-integration-tests"}]}]}}'
```

```bash
kubectl run integration-test-full --image=ide-orchestrator:ci-test --rm -i --restart=Never -n intelligence-orchestrator --overrides='{"spec":{"containers":[{"name":"integration-test-full","image":"ide-orchestrator:ci-test","command":["python","-m","pytest","tests/integration/","-v","--tb=short"],"env":[{"name":"POSTGRES_HOST","value":"ide-orchestrator-db-rw.intelligence-orchestrator.svc.cluster.local"},{"name":"POSTGRES_PORT","value":"5432"},{"name":"POSTGRES_USER","value":"ide-orchestrator-db"},{"name":"POSTGRES_PASSWORD","value":"0KNzcnnKO1NlJgSrdCX3ORbybFFMrd2TuUGr8kkTsQjrdogAv908QuOgZb7T5Zmy"},{"name":"POSTGRES_DB","value":"ide-orchestrator-db"},{"name":"JWT_SECRET","value":"test-secret-key-for-integration-tests"}]}]}}'
```

## After fix a test case bug, build and load to local cluster for testing else your changes will not get reflected in cluster
```bash
docker build -t ide-orchestrator:ci-test ide-orchestrator/ && kind load docker-image ide-orchestrator:ci-test --name zerotouch-preview
```

## Occassionally you might need to delete the pod and restart after loading the image
```bash
kubectl rollout restart deployment ide-orchestrator -n intelligence-orchestrator
```

## Do NOT run locally like below, it will not work
```bash
python -m pytest tests/integration/
```