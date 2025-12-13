# EventDrivenService API Test Suite

This directory contains the test suite for validating EventDrivenService claims against the published JSON schema.

## Test Structure

```
tests/
├── README.md                          # This file
├── schema-validation.test.sh          # Schema validation test suite
├── test-autoscaling.sh                # Cold-start autoscaling test
├── test-autoscaling-production.sh     # Production simulation autoscaling test
├── test-full-deployment.sh            # Full deployment test
├── test-minimal-deployment.sh         # Minimal deployment test
├── verify-composition.sh              # Composition verification
├── verify-keda-config.sh              # KEDA configuration verification
└── fixtures/                          # Test claim fixtures
    ├── valid-minimal.yaml             # Valid minimal claim
    ├── valid-full.yaml                # Valid full-featured claim
    ├── invalid-size.yaml              # Invalid size value test
    └── missing-stream.yaml            # Missing required field test
```

## Running Tests

### Schema Validation Tests

```bash
# From project root
./platform/04-apis/tests/schema-validation.test.sh
```

### Autoscaling Tests

```bash
# Cold-start test (demonstrates KEDA limitation with non-consuming workers)
./platform/04-apis/tests/test-autoscaling.sh

# Production simulation (demonstrates KEDA works with active consumers)
./platform/04-apis/tests/test-autoscaling-production.sh
```

**Note**: The cold-start test is expected to fail Check 2 due to a known KEDA limitation. See `../docs/KEDA-NATS-LIMITATIONS.md` for details. The production simulation test should pass all checks.

### Deployment Tests

```bash
# Test minimal deployment
./platform/04-apis/tests/test-minimal-deployment.sh

# Test full deployment with all features
./platform/04-apis/tests/test-full-deployment.sh
```

### Verification Tests

```bash
# Verify composition structure
./platform/04-apis/tests/verify-composition.sh

# Verify KEDA configuration
./platform/04-apis/tests/verify-keda-config.sh
```

### Prerequisites

The test suite requires:
- `yq` (YAML processor)
- `python3` with `jsonschema` module
- Published schema at `platform/04-apis/schemas/eventdrivenservice.schema.json`

If the schema is not published, run:
```bash
./scripts/publish-schema.sh
```

## Autoscaling Tests

### Cold-Start Test (`test-autoscaling.sh`)
**Purpose:** Demonstrates KEDA NATS JetStream scaler limitation in cold-start scenarios  
**Worker:** nginx (does not pull messages)  
**Expected:** Check 2 fails - pods don't scale up because `num_pending` = 0  
**Why:** KEDA uses `num_pending` (messages being pulled) not `unprocessed` (messages in stream)

### Production Simulation Test (`test-autoscaling-production.sh`)
**Purpose:** Validates KEDA autoscaling works correctly with active message consumers  
**Worker:** nats-box (actively pulls messages)  
**Expected:** All checks pass - pods scale up because `num_pending` > 0  
**Why:** Worker pulls messages, incrementing `num_pending`, triggering KEDA scale-up

**Key Insight**: The cold-start test failure is expected and documents a known KEDA limitation. The production test confirms autoscaling works correctly in real-world scenarios. See `../docs/KEDA-NATS-LIMITATIONS.md` for detailed analysis.

## Schema Validation Test Cases

### Test 1: Valid Minimal Claim
**Purpose:** Validates a minimal claim with only required fields  
**Fixture:** `fixtures/valid-minimal.yaml`  
**Expected:** Pass (exit code 0)  
**Validates:** Required fields (image, nats.stream, nats.consumer) are sufficient

### Test 2: Valid Full Claim
**Purpose:** Validates a full-featured claim with all optional fields  
**Fixture:** `fixtures/valid-full.yaml`  
**Expected:** Pass (exit code 0)  
**Validates:** All optional fields (secrets, init container, image pull secrets) work correctly

### Test 3: Invalid Size Value
**Purpose:** Validates that size field only accepts 'small', 'medium', or 'large'  
**Fixture:** `fixtures/invalid-size.yaml`  
**Expected:** Fail (exit code 1)  
**Validates:** Enum validation for size field

### Test 4: Missing Required Field
**Purpose:** Validates that required field nats.stream must be present  
**Fixture:** `fixtures/missing-stream.yaml`  
**Expected:** Fail (exit code 1)  
**Validates:** Required field validation

## Adding New Tests

To add a new test case:

1. Create a fixture file in `fixtures/` directory
2. Add a test case in `schema-validation.test.sh` using the `run_test` function:

```bash
run_test \
    "Test Name" \
    "fixture-file.yaml" \
    "pass|fail" \
    "Description of what this test validates"
```

## CI Integration

This test suite is designed to be integrated into CI/CD pipelines. The script:
- Returns exit code 0 on success (all tests pass)
- Returns exit code 1 on failure (any test fails)
- Provides clear output for debugging failures

Example CI integration:
```yaml
- name: Validate EventDrivenService Claims
  run: |
    ./scripts/publish-schema.sh
    ./platform/04-apis/tests/schema-validation.test.sh
```

## Test Output

The test suite provides:
- ✓ Green checkmarks for passing tests
- ✗ Red X marks for failing tests
- Detailed error messages for validation failures
- Summary statistics (tests run, passed, failed)

Example output:
```
==================================================
EventDrivenService Schema Validation Test Suite
==================================================

Checking prerequisites...
✓ Prerequisites check passed

----------------------------------------
Test 1: Valid Minimal Claim
Description: Validates a minimal claim with only required fields
Fixture: valid-minimal.yaml
Expected: pass

✓ PASSED

...

==================================================
Test Suite Summary
==================================================

Tests run:    4
Tests passed: 4
Tests failed: 0

✓ All tests passed!
```

## Troubleshooting

### Schema Not Found Error
If you see "Schema file not found", run the schema publication script:
```bash
./scripts/publish-schema.sh
```

### Python jsonschema Module Missing
If you see "jsonschema module not found", install it:
```bash
python3 -m pip install jsonschema
```

### yq Not Installed
Install yq:
- macOS: `brew install yq`
- Linux: See https://github.com/mikefarah/yq

## Related Documentation

- [EventDrivenService API Documentation](../README.md)
- [Schema Publication Script](../../../scripts/publish-schema.sh)
- [Claim Validation Script](../../../scripts/validate-claim.sh)
- [Requirements Document](../../../.kiro/specs/agent-executor/enhanced-platform/requirements.md)
