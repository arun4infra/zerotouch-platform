# AgentSandboxService API Test Suite

This directory contains the comprehensive test suite for validating AgentSandboxService functionality, including live cluster integration tests and property-based testing.

## Test Structure

```
tests/
├── README.md                          # This file
├── 01-verify-controller.sh            # Agent-sandbox controller validation
├── 02-verify-xrd.sh                   # XRD validation and API parity
├── 03-verify-composition.sh           # Crossplane composition validation
├── 04-verify-persistence.sh           # Hybrid S3+PVC persistence validation
├── 05-verify-scaling.sh               # KEDA autoscaling validation
├── 06-verify-http.sh                  # HTTP service validation
├── 07-verify-secrets.sh               # Secret injection validation
├── 08-verify-properties.sh            # Property-based testing suite
├── 09-verify-e2e.sh                   # End-to-end integration test
└── helpers/                           # Test helper modules
    ├── 09-verify-e2e/                 # E2E test helpers
    │   ├── prerequisites.sh           # Prerequisites validation
    │   ├── deployment.sh              # Deployment helpers
    │   ├── validation.sh              # Validation helpers
    │   ├── load-testing.sh            # Load testing helpers
    │   └── cleanup.sh                 # Cleanup helpers
    └── 08-verify-properties/          # Property test helpers
        ├── generators.sh              # Test data generators
        ├── validators.sh              # Property validators
        └── cleanup.sh                 # Property test cleanup
```

## Running Tests

### Individual Component Tests

```bash
# From project root
./platform/apis/agentsandbox/tests/01-verify-controller.sh
./platform/apis/agentsandbox/tests/02-verify-xrd.sh
./platform/apis/agentsandbox/tests/03-verify-composition.sh
./platform/apis/agentsandbox/tests/04-verify-persistence.sh
./platform/apis/agentsandbox/tests/05-verify-scaling.sh
./platform/apis/agentsandbox/tests/06-verify-http.sh
./platform/apis/agentsandbox/tests/07-verify-secrets.sh
```

### Property-Based Testing

```bash
# Comprehensive property validation (100 iterations per property)
./platform/apis/agentsandbox/tests/08-verify-properties.sh

# Custom iteration count
./platform/apis/agentsandbox/tests/08-verify-properties.sh --iterations 50
```

### End-to-End Integration Test

```bash
# Complete system validation with real deepagents-runtime workload
./platform/apis/agentsandbox/tests/09-verify-e2e.sh

# With verbose logging
./platform/apis/agentsandbox/tests/09-verify-e2e.sh --verbose

# Skip cleanup for debugging
./platform/apis/agentsandbox/tests/09-verify-e2e.sh --cleanup
```

## Test Categories

### 1. Infrastructure Tests (01-07)
**Purpose:** Validate individual components work correctly in isolation  
**Approach:** Live cluster testing with real Kubernetes resources  
**Coverage:** Controller, XRD, Composition, Persistence, Scaling, HTTP, Secrets

### 2. Property-Based Tests (08)
**Purpose:** Validate universal correctness properties across all inputs  
**Approach:** Generate random test data and verify properties hold  
**Coverage:** API parity, resource provisioning, persistence, scaling, connectivity

### 3. End-to-End Test (09)
**Purpose:** Validate complete system works with real workloads  
**Approach:** Deploy actual AgentSandboxService claim and test all functionality  
**Coverage:** Full integration with deepagents-runtime container

## Key Test Features

### Hybrid Persistence Testing
The persistence tests validate the unique S3+PVC hybrid storage:
- **Workspace Hydration:** InitContainer downloads from S3 on startup
- **Continuous Backup:** Sidecar uploads changes every 30 seconds  
- **Final Sync:** PreStop hook ensures no data loss on termination
- **Resurrection Test:** Files survive complete pod recreation

### KEDA Scaling Integration
The scaling tests validate KEDA integration with agent-sandbox controller:
- **ScaledObject Creation:** Targets SandboxWarmPool with correct API version
- **NATS JetStream Trigger:** Monitors consumer lag for scaling decisions
- **Live Scaling:** Tests actual scaling behavior under load

### API Parity Validation
All tests ensure complete API compatibility with EventDrivenService:
- **Field Compatibility:** All EventDrivenService fields accepted
- **Secret Injection:** Identical envFrom pattern (secret1Name → envFrom[1])
- **Resource Sizing:** Same micro/small/medium/large resource allocations
- **HTTP Configuration:** Identical port, health, and session affinity options

## Prerequisites

The test suite requires:
- **Live Kubernetes Cluster:** Tests run against actual cluster resources
- **Agent-Sandbox Controller:** Must be deployed and running
- **NATS System:** JetStream must be available with AGENT_EXECUTION stream
- **AWS Credentials:** S3 access for persistence testing
- **KEDA:** Autoscaling functionality requires KEDA operator

### Required Secrets
```bash
# In intelligence-deepagents namespace
kubectl get secret aws-access-token                    # S3 access
kubectl get secret deepagents-runtime-db-conn         # Database credentials  
kubectl get secret deepagents-runtime-cache-conn      # Cache credentials
kubectl get secret deepagents-runtime-llm-keys        # LLM API keys
```

## Test Parameters

All test scripts accept standard parameters:

```bash
--tenant <name>      # Specify tenant for testing (default: deepagents-runtime)
--namespace <name>   # Override namespace (default: intelligence-deepagents)  
--verbose           # Enable detailed logging
--cleanup           # Clean up test resources after validation
--iterations <num>  # Property test iterations (08-verify-properties.sh only)
```

## Property-Based Testing Details

### Correctness Properties Validated

1. **API Parity Preservation:** EventDrivenService → AgentSandboxService conversion succeeds
2. **Resource Provisioning Completeness:** All expected managed resources created
3. **Workspace Persistence Round-Trip:** Files survive pod recreation via S3
4. **KEDA Scaling Responsiveness:** ScaledObject created and configured correctly
5. **HTTP Service Connectivity:** Services route traffic to ready instances
6. **Secret Injection Consistency:** Environment variables follow platform patterns

### Property Test Configuration
- **Default Iterations:** 100 per property (due to randomization)
- **Test Data Generation:** Random but valid claim specifications
- **Failure Analysis:** Detailed counterexample reporting
- **Resource Cleanup:** Automatic cleanup of generated test resources

## End-to-End Test Validation

The E2E test performs comprehensive system validation:

### Prerequisites Validation
- ✅ Namespace exists and is accessible
- ✅ AgentSandboxService XRD is installed
- ✅ Agent-sandbox controller is running and healthy
- ✅ Required secrets exist and are accessible
- ✅ NATS stream exists and is accessible

### Deployment Validation  
- ✅ AgentSandboxService claim deploys successfully
- ✅ Claim is processed by Crossplane composition
- ✅ Sandbox instances start and become ready
- ✅ All managed resources are created correctly

### Functionality Validation
- ✅ NATS environment variables configured correctly
- ✅ NATS service connectivity verified
- ✅ Workspace persistence across pod restarts (resurrection test)
- ✅ HTTP endpoints respond with proper status codes
- ✅ KEDA ScaledObject monitors NATS queue correctly
- ✅ Complete API parity with EventDrivenService maintained

## Error Handling

### Red-to-Green Testing Philosophy
All tests follow strict red-to-green methodology:
- **Fail Fast:** Tests fail immediately when components are missing
- **No Warnings:** Warnings are treated as failures for strict validation
- **Real Testing:** Tests use actual functionality, not mocked responses
- **Comprehensive Coverage:** Tests validate end-to-end workflows

### Common Failure Scenarios
- **Missing Controller:** Test fails if agent-sandbox controller not running
- **NATS Unavailable:** Test fails if NATS system not accessible  
- **Secret Missing:** Test fails if required secrets not found
- **S3 Access:** Test fails if AWS credentials invalid or S3 inaccessible
- **Resource Limits:** Test fails if cluster resources insufficient

## CI Integration

The test suite is designed for CI/CD integration:

```yaml
- name: Validate AgentSandboxService System
  run: |
    # Run component tests
    ./platform/apis/agentsandbox/tests/01-verify-controller.sh
    ./platform/apis/agentsandbox/tests/02-verify-xrd.sh
    ./platform/apis/agentsandbox/tests/03-verify-composition.sh
    
    # Run property-based tests
    ./platform/apis/agentsandbox/tests/08-verify-properties.sh --iterations 50
    
    # Run end-to-end integration test
    ./platform/apis/agentsandbox/tests/09-verify-e2e.sh --cleanup
```

## Test Output

### Success Output
```
[SUCCESS] ✅ End-to-end integration testing completed successfully!
[SUCCESS] AgentSandboxService system is operational and ready for production use
```

### Failure Output
```
[ERROR] NATS connectivity failed - cannot connect to nats.nats.svc:4222
[ERROR] ❌ End-to-end integration testing failed
```

### Property Test Output
```
[PROPERTY] Testing Property 1: API Parity Preservation
[SUCCESS] Property 1 (API Parity Preservation): PASSED (100/100)
```

## Troubleshooting

### Agent-Sandbox Controller Issues
```bash
# Check controller status
kubectl get pods -n agent-sandbox-system

# Check controller logs
kubectl logs -n agent-sandbox-system -l app=agent-sandbox-controller
```

### NATS Connectivity Issues
```bash
# Check NATS pods
kubectl get pods -n nats

# Test NATS connectivity
kubectl exec -n nats nats-box-xxx -- nats stream info AGENT_EXECUTION
```

### S3 Persistence Issues
```bash
# Check AWS credentials
kubectl get secret aws-access-token -n intelligence-deepagents -o yaml

# Test S3 access
kubectl run aws-test --image=amazon/aws-cli:latest --rm -it -- \
  aws s3 ls s3://zerotouch-workspaces/
```

## Related Documentation

- [AgentSandboxService Requirements](../../../../.kiro/specs/agentsandbox-support/requirements.md)
- [AgentSandboxService Design](../../../../.kiro/specs/agentsandbox-support/design.md)
- [Implementation Tasks](../../../../.kiro/specs/agentsandbox-support/tasks.md)
- [EventDrivenService Tests](../../event-driven-service/tests/README.md)