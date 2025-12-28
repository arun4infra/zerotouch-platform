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

**"Test Real Infrastructure, Mock External Dependencies"**

Integration tests validate your service against real internal platform infrastructure (PostgreSQL, Redis, NATS) while mocking external service dependencies to ensure deterministic, fast, and reliable CI execution.

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

### 1. In-Process HTTP Mocks
**When:** Mocking HTTP/WebSocket APIs of external services
**How:** Use language-native test servers (`httptest` in Go, `pytest-httpserver` in Python)
**Benefits:** No container orchestration, fast startup, deterministic

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

### 2. Source of Truth Data
**Rule:** Mock data must come from real service outputs, not invented payloads
**Implementation:**
- Export actual JSON responses from real services
- Store in `tests/testdata/` with descriptive names
- Version control these files as test fixtures

### 3. Configuration Override Pattern
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

## Database Testing Patterns

### 1. Real Database, Clean State
**Rule:** Use real PostgreSQL/Redis instances, ensure clean state per test
**Implementation:**
- Run migrations before each test
- Truncate tables after each test
- Use test-specific database schemas when possible

### 2. Persistence Validation
**Critical:** Integration tests must validate data persistence
**Pattern:**
```go
// 1. Execute workflow
result := orchestrator.ProcessWorkflow(input)

// 2. Validate immediate response
assert.Equal(t, "success", result.Status)

// 3. Query database directly to validate persistence
var dbRecord WorkflowRecord
db.First(&dbRecord, "workflow_id = ?", result.WorkflowID)
assert.Equal(t, expectedData, dbRecord.GeneratedFiles)
```

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

### ❌ Don't Use Hardcoded Test Data
- Never invent JSON payloads in test code
- Always use exported real service data

### ❌ Don't Test Implementation Details
- Test business outcomes, not internal function calls
- Validate database state, not service logs

### ❌ Don't Create Timing Dependencies
- Never use fixed `sleep()` calls
- Never assume specific execution order without synchronization

## Best Practices Summary

1. **Real Infrastructure**: Test against actual PostgreSQL, Redis, NATS
2. **Mock External Services**: Use in-process HTTP mocks with real data
3. **Clean State**: Ensure each test starts with clean database state
4. **Validate Persistence**: Always check database after workflow completion
5. **Environment Override**: Allow test configuration to override production URLs
6. **Container Ready**: Include test data in Docker images
7. **Protocol Complete**: Implement full protocol compatibility in mocks
8. **Deterministic**: Remove timing dependencies and race conditions

This pattern ensures integration tests are fast, reliable, and validate real business value while maintaining CI/CD pipeline efficiency.