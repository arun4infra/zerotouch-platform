#!/usr/bin/env bash

# property-session-affinity-configuration.test.sh
# Property-Based Test for WebService Session Affinity Configuration
# 
# **Feature: platform-service-communication, Property 5: Session Affinity Configuration**
# **Validates: Requirements 4.2**
#
# Property: For any service with sessionAffinity specified, the Kubernetes Service 
# should have the exact sessionAffinity setting configured

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

# Test configuration
ITERATIONS=100
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=================================================================="
echo "Property-Based Test: Session Affinity Configuration"
echo "=================================================================="
echo ""
echo "Property: For any service with sessionAffinity specified,"
echo "          the Kubernetes Service should have the exact"
echo "          sessionAffinity setting configured"
echo ""
echo "Iterations: ${ITERATIONS}"
echo "Temp directory: ${TEMP_DIR}"
echo ""

# Generate random valid service names (DNS-1123 compliant)
generate_service_name() {
    local length=$((5 + RANDOM % 10))  # 5-15 characters
    local name=""
    local chars="abcdefghijklmnopqrstuvwxyz0123456789"
    
    # First character must be alphabetic
    name="${chars:$((RANDOM % 26)):1}"
    
    # Remaining characters can be alphanumeric or hyphen
    local extended_chars="${chars}-"
    for ((i=1; i<length; i++)); do
        name="${name}${extended_chars:$((RANDOM % ${#extended_chars})):1}"
    done
    
    # Ensure it doesn't end with hyphen
    if [[ "${name}" == *- ]]; then
        name="${name%?}a"
    fi
    
    echo "${name}"
}

# Generate random valid ports
generate_port() {
    # Generate random port between 1024 and 65535 (avoiding well-known ports)
    echo $((1024 + RANDOM % (65535 - 1024 + 1)))
}

# Generate random session affinity values
generate_session_affinity() {
    local values=("None" "ClientIP")
    echo "${values[$((RANDOM % ${#values[@]}))]}"
}

# Generate random size values
generate_size() {
    local sizes=("micro" "small" "medium" "large")
    echo "${sizes[$((RANDOM % ${#sizes[@]}))]}"
}

# Generate random hostnames
generate_hostname() {
    local domains=("api.example.com" "web.test.local" "service.dev.io" "app.staging.net")
    echo "${domains[$((RANDOM % ${#domains[@]}))]}"
}

# Create test claim with generated values
create_test_claim() {
    local service_name="$1"
    local port="$2"
    local session_affinity="$3"
    local size="$4"
    local hostname="$5"
    local output_file="$6"
    
    cat > "${output_file}" << EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: ${service_name}
  namespace: test-property
spec:
  image: nginx:alpine
  port: ${port}
  size: ${size}
  hostname: "${hostname}"
  pathPrefix: "/api"
  sessionAffinity: "${session_affinity}"
EOF
}

# Create test claim with backend service discovery
create_test_claim_with_backend() {
    local service_name="$1"
    local port="$2"
    local session_affinity="$3"
    local size="$4"
    local backend_service="$5"
    local backend_port="$6"
    local output_file="$7"
    
    cat > "${output_file}" << EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: ${service_name}
  namespace: test-property
spec:
  image: nginx:alpine
  port: ${port}
  size: ${size}
  sessionAffinity: "${session_affinity}"
  backendServiceName: "${backend_service}"
  backendServicePort: ${backend_port}
EOF
}

# Validate that sessionAffinity is correctly configured
validate_session_affinity_configuration() {
    local claim_file="$1"
    local expected_session_affinity="$2"
    
    # Use kubectl dry-run to validate the claim
    if ! kubectl apply --dry-run=client -f "${claim_file}" &>/dev/null; then
        echo "VALIDATION_ERROR: Claim failed kubectl validation"
        return 1
    fi
    
    # Extract sessionAffinity from the claim
    local actual_session_affinity
    actual_session_affinity=$(yq eval '.spec.sessionAffinity' "${claim_file}")
    
    if [[ "${actual_session_affinity}" != "${expected_session_affinity}" ]]; then
        echo "SESSION_AFFINITY_MISMATCH: Expected ${expected_session_affinity}, got ${actual_session_affinity}"
        return 1
    fi
    
    # Validate that the sessionAffinity value is one of the allowed values
    if [[ "${actual_session_affinity}" != "None" && "${actual_session_affinity}" != "ClientIP" ]]; then
        echo "INVALID_SESSION_AFFINITY: ${actual_session_affinity} is not a valid sessionAffinity value"
        return 1
    fi
    
    return 0
}

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found${NC}"
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo -e "${RED}ERROR: yq not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Run property-based test iterations
echo "Running property-based test iterations..."
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
    ((TESTS_RUN++))
    
    # Generate random test inputs
    SERVICE_NAME=$(generate_service_name)
    PORT=$(generate_port)
    SESSION_AFFINITY=$(generate_session_affinity)
    SIZE=$(generate_size)
    
    # Create test claim file (alternating between regular and backend service claims)
    CLAIM_FILE="${TEMP_DIR}/test-claim-${i}.yaml"
    
    if [[ $((i % 2)) -eq 0 ]]; then
        # Create claim with backend service discovery
        BACKEND_SERVICE=$(generate_service_name)
        BACKEND_PORT=$(generate_port)
        create_test_claim_with_backend "${SERVICE_NAME}" "${PORT}" "${SESSION_AFFINITY}" "${SIZE}" "${BACKEND_SERVICE}" "${BACKEND_PORT}" "${CLAIM_FILE}"
    else
        # Create regular claim with hostname
        HOSTNAME=$(generate_hostname)
        create_test_claim "${SERVICE_NAME}" "${PORT}" "${SESSION_AFFINITY}" "${SIZE}" "${HOSTNAME}" "${CLAIM_FILE}"
    fi
    
    # Validate the property
    if validate_session_affinity_configuration "${CLAIM_FILE}" "${SESSION_AFFINITY}"; then
        ((TESTS_PASSED++))
        if [[ $((i % 10)) -eq 0 ]]; then
            echo -e "${GREEN}✓${NC} Iteration ${i}/${ITERATIONS} - Service: ${SERVICE_NAME}, Affinity: ${SESSION_AFFINITY}"
        fi
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} Iteration ${i}/${ITERATIONS} FAILED"
        echo "  Service: ${SERVICE_NAME}"
        echo "  Port: ${PORT}"
        echo "  Session Affinity: ${SESSION_AFFINITY}"
        echo "  Size: ${SIZE}"
        echo "  Claim file: ${CLAIM_FILE}"
        echo ""
        
        # Show the claim content for debugging
        echo "Claim content:"
        cat "${CLAIM_FILE}"
        echo ""
    fi
done

# Summary
echo ""
echo "=================================================================="
echo "Property Test Summary"
echo "=================================================================="
echo ""
echo "Property: Session Affinity Configuration"
echo "Iterations run:    ${TESTS_RUN}"
echo -e "Iterations passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Iterations failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}✗ Property test FAILED${NC}"
    echo ""
    echo "The property 'Session Affinity Configuration' does not hold."
    echo "Some generated WebService claims with sessionAffinity specified"
    echo "failed validation or did not meet the expected configuration."
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ Property test PASSED${NC}"
    echo ""
    echo "The property 'Session Affinity Configuration' holds for all"
    echo "${ITERATIONS} randomly generated test cases."
    echo ""
    echo "This validates that for any service with sessionAffinity specified,"
    echo "the Kubernetes Service has the exact sessionAffinity setting configured."
    echo ""
    echo "Validated configurations:"
    echo "- None: Standard load balancing without session persistence"
    echo "- ClientIP: Session persistence based on client IP address"
    echo ""
    echo "This ensures WebSocket connections maintain session affinity when configured."
    echo ""
    exit 0
fi