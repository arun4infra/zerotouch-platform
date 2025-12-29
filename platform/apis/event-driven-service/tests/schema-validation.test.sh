#!/usr/bin/env bash

# schema-validation.test.sh
# Test suite for EventDrivenService schema validation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Paths
VALIDATE_SCRIPT="${PROJECT_ROOT}/scripts/validate-claim.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test results array
declare -a FAILED_TESTS

echo "=================================================="
echo "EventDrivenService Schema Validation Test Suite"
echo "=================================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if [[ ! -f "${VALIDATE_SCRIPT}" ]]; then
    echo -e "${RED}ERROR: Validation script not found: ${VALIDATE_SCRIPT}${NC}"
    exit 1
fi

if [[ ! -x "${VALIDATE_SCRIPT}" ]]; then
    echo -e "${RED}ERROR: Validation script is not executable: ${VALIDATE_SCRIPT}${NC}"
    exit 1
fi

if [[ ! -d "${FIXTURES_DIR}" ]]; then
    echo -e "${RED}ERROR: Fixtures directory not found: ${FIXTURES_DIR}${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Helper function to run a test
run_test() {
    local test_name="$1"
    local fixture_file="$2"
    local expected_result="$3"  # "pass" or "fail"
    local description="$4"
    
    ((TESTS_RUN++))
    
    echo "----------------------------------------"
    echo -e "${BLUE}Test ${TESTS_RUN}:${NC} ${test_name}"
    echo "Description: ${description}"
    echo "Fixture: ${fixture_file}"
    echo "Expected: ${expected_result}"
    echo ""
    
    # Run validation script and capture exit code
    set +e
    OUTPUT=$("${VALIDATE_SCRIPT}" "${FIXTURES_DIR}/${fixture_file}" 2>&1)
    EXIT_CODE=$?
    set -e
    
    # Determine if test passed
    local test_passed=false
    
    if [[ "${expected_result}" == "pass" ]]; then
        # Expecting validation to succeed (exit code 0)
        if [[ ${EXIT_CODE} -eq 0 ]]; then
            test_passed=true
        fi
    elif [[ "${expected_result}" == "fail" ]]; then
        # Expecting validation to fail (exit code 1)
        if [[ ${EXIT_CODE} -eq 1 ]]; then
            test_passed=true
        fi
    fi
    
    # Report result
    if [[ "${test_passed}" == true ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo ""
        echo "Expected validation to ${expected_result}, but got exit code: ${EXIT_CODE}"
        echo ""
        echo "Output:"
        echo "${OUTPUT}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${test_name}")
    fi
    
    echo ""
}

# Test 1: Valid minimal claim
run_test \
    "Valid Minimal Claim" \
    "valid-minimal.yaml" \
    "pass" \
    "Validates a minimal claim with only required fields (image, nats.stream, nats.consumer)"

# Test 2: Valid full claim
run_test \
    "Valid Full Claim" \
    "valid-full.yaml" \
    "pass" \
    "Validates a full-featured claim with all optional fields (secrets, init container, image pull secrets)"

# Test 3: Invalid size value
run_test \
    "Invalid Size Value" \
    "invalid-size.yaml" \
    "fail" \
    "Validates that size field only accepts 'small', 'medium', or 'large'"

# Test 4: Missing required field (nats.stream)
run_test \
    "Missing Required Field" \
    "missing-stream.yaml" \
    "fail" \
    "Validates that required field nats.stream must be present"

# Summary
echo "=================================================="
echo "Test Suite Summary"
echo "=================================================="
echo ""
echo "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - ${test}"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    exit 0
fi
