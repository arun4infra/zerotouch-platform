# Platform Validation Patterns

## Validation Philosophy

The ZeroTouch Platform uses **environment-level integration tests** rather than unit tests to ensure reliability. Validation scripts test actual functionality in live environments, not isolated components.

## Script Architecture Principles

### Modular Design Requirements

**All platform scripts MUST follow modular architecture:**

1. **Main Scripts** - Orchestrators that call helper scripts for specific tasks
2. **Helper Scripts** - Single-purpose utilities that handle specific phases
3. **Library Functions** - Shared utilities for common operations

### Modular Script Patterns

#### Pattern 1: Phase-Based Helpers
```bash
# Main script calls phase-specific helpers
main-script.sh → pre-phase.sh → execute-phase.sh → post-phase.sh
```

**Example: Release Pipeline**
```bash
ci-pipeline.sh → build-and-test.sh → helpers/pre-build.sh
                                   → helpers/build.sh  
                                   → helpers/post-build.sh
```

#### Pattern 2: Component-Based Helpers
```bash
# Main script calls component-specific helpers
main-script.sh → component-a.sh → component-b.sh → component-c.sh
```

**Benefits of Modular Design:**
- **Testability**: Each helper can be tested independently
- **Reusability**: Helpers can be used by multiple main scripts
- **Maintainability**: Changes isolated to specific components
- **Debugging**: Easy to isolate and fix specific phases
- **Extensibility**: New helpers can be added without changing main scripts

### Helper Script Requirements

**Each helper script MUST:**
1. **Single Responsibility**: Handle one specific task or phase
2. **Self-Contained**: Include all necessary validation and error handling
3. **Standardized Interface**: Accept consistent parameters (--tenant, --trigger, etc.)
4. **Export Results**: Set environment variables for use by calling scripts
5. **Proper Logging**: Use platform logging utilities with step tracking
6. **Error Propagation**: Return appropriate exit codes (0=success, 1=failure)

**Helper Script Template:**
```bash
#!/bin/bash
set -euo pipefail

# helper-name.sh - Brief description of what this helper does

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-discovery.sh"
source "${SCRIPT_DIR}/../lib/logging.sh"

# Parse arguments, validate inputs, execute task, export results
```

### Integration with Existing Infrastructure

**CRITICAL RULE**: Never reinvent existing platform functionality

1. **Reuse Existing Scripts**: Call proven platform scripts (e.g., `in-cluster-test.sh`)
2. **Leverage Build Infrastructure**: Use existing `build-service.sh` for container operations
3. **Extend, Don't Replace**: Add orchestration layers, don't duplicate functionality
4. **Validate Integration**: Ensure new scripts work with existing CI patterns

**Anti-Patterns to Avoid:**
- ❌ Custom Docker build logic when `build-service.sh` exists
- ❌ Custom Kind cluster setup when `setup-preview.sh` exists  
- ❌ Duplicate artifact creation when existing build handles it
- ❌ Monolithic scripts that handle multiple phases internally

## Validation Types

### 1. Post-Deployment Integration Tests
- **Location**: `scripts/bootstrap/validation/`
- **Purpose**: Validate deployed services work end-to-end
- **Pattern**: Apply real configurations to running clusters and verify results
- **Examples**: ArgoCD apps synced, External Secrets accessible, Platform APIs functional

### 2. Release Pipeline Validation
- **Location**: `scripts/release/validation/`
- **Purpose**: Validate release workflows work with real tenant repositories
- **Pattern**: Test actual CI/PR/main workflows using filesystem contract
- **Examples**: Configuration discovery, artifact creation, GitOps deployment
- **Modular Requirement**: Test each helper script independently before testing full workflow

### 3. Platform API Validation
- **Location**: `scripts/bootstrap/validation/apis/`
- **Purpose**: Validate Crossplane XRDs and Compositions work correctly
- **Pattern**: Create test claims, verify resources provisioned, test functionality

### 4. Helper Script Validation
- **Location**: `scripts/release/validation/`
- **Purpose**: Validate individual helper scripts work correctly in isolation
- **Pattern**: Mock inputs, test single helper, verify outputs and side effects
- **Examples**: Test post-build helper with mock artifact variables

## CHECKPOINT Verification Requirements

When a task specifies **CHECKPOINT**, it means:

### Mandatory Elements
1. **Deliverable**: Specific working system component
2. **Verification**: Executable test that proves functionality
3. **Success Criteria**: Clear pass/fail conditions
4. **Environment Test**: Must test in live environment, not isolated
5. **Modular Validation**: Test both individual helpers and integrated workflow

### CHECKPOINT Pattern
```bash
# CHECKPOINT Structure:
- [ ] X.Y **CHECKPOINT N: System Name**
  - **Deliverable**: Working [system] that can [specific capability]
  - **Verification**: Run [test script] that validates [specific behavior]
  - **Success Criteria**: [Measurable outcomes that prove success]
  - **Helper Validation**: Test individual helpers with mock data
  - **Integration Validation**: Test full workflow with real environment
  - Ensure all tests pass, ask the user if questions arise.
```

### Validation Script Requirements
- **Executable**: Must be runnable script that returns 0/1 exit code
- **Comprehensive**: Tests all critical functionality of the deliverable
- **Real Environment**: Uses actual configurations, not mocks (for integration tests)
- **Mock Environment**: Uses controlled inputs for helper script testing
- **Clear Output**: Shows what passed/failed with specific details
- **Diagnostic**: Provides troubleshooting info on failures
- **Modular Testing**: Can test individual components and full workflows

## Release Pipeline Validation Standards

### Configuration Discovery Validation
- Test parsing of real tenant `ci/config.yaml` and `ci/release.yaml`
- Validate filesystem contract with actual repository structure
- Verify error handling for malformed configurations
- Test tenant name and environment validation rules

### Workflow Validation
- Test PR workflow: build → test → feedback only
- Test main workflow: build → test → artifact → deploy to dev
- Validate GitOps updates to tenant repositories
- Test promotion gate creation and approval workflows

### Helper Script Validation
- **Pre-build Helper**: Test environment variable setup with mock tenant configs
- **Build Helper**: Test platform CI integration without full cluster setup
- **Post-build Helper**: Test artifact extraction with mock build results
- **Isolated Testing**: Each helper tested independently with controlled inputs

### Integration Validation
- Test with real GitHub Actions environment variables
- Validate container registry authentication and push
- Test ArgoCD sync detection and monitoring
- Verify tenant isolation and concurrent execution

## Validation Script Naming Convention

### Bootstrap Validation
- `99-validate-cluster.sh` - Main orchestrator
- `NN-verify-[component].sh` - Specific component validation
- `04-apis/validate-apis.sh` - API validation orchestrator
- `04-apis/NN-verify-[api].sh` - Individual API validation

### Release Validation
- `validate-release-pipeline.sh` - Main release pipeline validation
- `validate-[helper-name].sh` - Individual helper validation
- `test-[component].sh` - Component-specific tests
- `verify-[workflow].sh` - Workflow validation scripts

### Helper Script Organization
- `scripts/release/helpers/` - All helper scripts
- `scripts/release/helpers/pre-build.sh` - Pre-build phase helper
- `scripts/release/helpers/build.sh` - Build execution helper
- `scripts/release/helpers/post-build.sh` - Post-build processing helper

## Error Handling Standards

### Retry Logic
- Network operations: 3 retries with exponential backoff
- Kubernetes operations: 20 retries with timeout
- External service calls: 5 retries with delay

### Diagnostic Output
- Show current state when validation fails
- Provide specific kubectl commands for debugging
- Include recent events and logs for context
- Suggest next steps for resolution

### Exit Codes
- `0` - All validations passed
- `1` - Critical validation failed
- `2` - Configuration error
- `3` - Environment not ready

## Integration with CI/CD

### GitHub Actions Integration
- Validation scripts run in CI for every change
- Use same scripts locally and in CI for consistency
- Provide clear pass/fail status for PR checks
- Generate artifacts for debugging failures

### Platform Bootstrap Integration
- Validation runs after each bootstrap phase
- Blocks progression until validation passes
- Provides confidence in platform stability
- Enables rapid iteration and debugging

## Best Practices

### Script Design
- **Modular First**: Always design scripts as composable helpers
- **Single Purpose**: Each script should do one thing well
- **Reuse Existing**: Never duplicate existing platform functionality
- **Test Independently**: Each helper must be testable in isolation
- **Standard Interface**: Use consistent parameter patterns across helpers
- Make scripts idempotent (safe to run multiple times)
- Use consistent logging and output formatting
- Provide verbose mode for debugging
- Handle partial failures gracefully

### Test Data
- Use real tenant configurations when possible
- Create minimal test fixtures for edge cases
- Use mock data for isolated helper testing
- Avoid hardcoded values that break in different environments
- Test both success and failure scenarios

### Maintenance
- Update validation when adding new features
- Remove validation for deprecated functionality
- Keep validation scripts in sync with implementation
- Document validation requirements for new components
- Maintain helper script documentation and interfaces

This validation approach ensures the platform maintains reliability through comprehensive environment-level testing while promoting modular, maintainable script architecture.