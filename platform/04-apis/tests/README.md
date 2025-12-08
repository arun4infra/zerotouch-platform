# EventDrivenService API Test Suite

This directory contains the test suite for validating EventDrivenService claims against the published JSON schema.

## Test Structure

```
tests/
├── README.md                          # This file
├── schema-validation.test.sh          # Main test suite script
└── fixtures/                          # Test claim fixtures
    ├── valid-minimal.yaml             # Valid minimal claim
    ├── valid-full.yaml                # Valid full-featured claim
    ├── invalid-size.yaml              # Invalid size value test
    └── missing-stream.yaml            # Missing required field test
```

## Running Tests

### Run All Tests

```bash
# From project root
./platform/04-apis/tests/schema-validation.test.sh
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

## Test Cases

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
