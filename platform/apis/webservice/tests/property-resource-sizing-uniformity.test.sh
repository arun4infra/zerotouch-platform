#!/usr/bin/env bash

# property-resource-sizing-uniformity.test.sh
# Property-Based Test for Resource Sizing Uniformity Across XRDs
# 
# **Feature: platform-service-communication, Property 4: Resource Sizing Uniformity**
# **Validates: Requirements 5.1**
#
# Property: For any service size specification, both EventDrivenService and WebService 
# should allocate identical CPU and memory resources for the same size value

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# Test configuration
ITERATIONS=100
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=================================================================="
echo "Property-Based Test: Resource Sizing Uniformity"
echo "=================================================================="
echo ""
echo "Property: For any service size specification, both EventDrivenService"
echo "          and WebService should allocate identical CPU and memory"
echo "          resources for the same size value"
echo ""
echo "Iterations: ${ITERATIONS}"
echo "Temp directory: ${TEMP_DIR}"
echo ""

# Expected resource mappings
get_expected_cpu_request() {
    case "$1" in
        micro) echo "100m" ;;
        small) echo "250m" ;;
        medium) echo "500m" ;;
        large) echo "1000m" ;;
        *) echo "unknown" ;;
    esac
}

get_expected_cpu_limit() {
    case "$1" in
        micro) echo "500m" ;;
        small) echo "1000m" ;;
        medium) echo "2000m" ;;
        large) echo "4000m" ;;
        *) echo "unknown" ;;
    esac
}

get_expected_memory_request() {
    case "$1" in
        micro) echo "256Mi" ;;
        small) echo "512Mi" ;;
        medium) echo "1Gi" ;;
        large) echo "2Gi" ;;
        *) echo "unknown" ;;
    esac
}

get_expected_memory_limit() {
    case "$1" in
        micro) echo "1Gi" ;;
        small) echo "2Gi" ;;
        medium) echo "4Gi" ;;
        large) echo "8Gi" ;;
        *) echo "unknown" ;;
    esac
}

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

# Generate random size values
generate_size() {
    local sizes=("micro" "small" "medium" "large")
    echo "${sizes[$((RANDOM % ${#sizes[@]}))]}"
}

# Generate random NATS configuration
generate_nats_url() {
    local urls=("nats://nats.nats.svc:4222" "nats://nats-cluster.messaging.svc:4222" "nats://jetstream.default.svc:4222")
    echo "${urls[$((RANDOM % ${#urls[@]}))]}"
}

generate_nats_stream() {
    local streams=("AGENT_EXECUTION" "WORKFLOW_EVENTS" "TASK_PROCESSING" "MESSAGE_QUEUE")
    echo "${streams[$((RANDOM % ${#streams[@]}))]}"
}

generate_nats_consumer() {
    local consumers=("worker-group" "processor-pool" "handler-cluster" "executor-farm")
    echo "${consumers[$((RANDOM % ${#consumers[@]}))]}"
}

# Create EventDrivenService test claim
create_eventdriven_claim() {
    local service_name="$1"
    local size="$2"
    local nats_url="$3"
    local nats_stream="$4"
    local nats_consumer="$5"
    local output_file="$6"
    
    cat > "${output_file}" << EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: ${service_name}
  namespace: test-property
spec:
  image: nginx:alpine
  size: ${size}
  nats:
    url: "${nats_url}"
    stream: "${nats_stream}"
    consumer: "${nats_consumer}"
EOF
}

# Create WebService test claim
create_webservice_claim() {
    local service_name="$1"
    local size="$2"
    local port="$3"
    local output_file="$4"
    
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
EOF
}

# Extract resource values from composition
extract_resource_from_composition() {
    local composition_file="$1"
    local resource_type="$2"
    local size="$3"
    
    grep -A 10 "fromFieldPath: spec.size" "$composition_file" | \
    grep -A 10 "$resource_type" | \
    grep -A 5 "type: map" | \
    grep "$size:" | \
    sed 's/.*: "\(.*\)"/\1/' | \
    tr -d ' '
}

# Validate resource sizing uniformity
validate_resource_sizing_uniformity() {
    local size="$1"
    local eds_claim="$2"
    local ws_claim="$3"
    
    # Validate both claims with kubectl
    if ! kubectl apply --dry-run=client -f "${eds_claim}" &>/dev/null; then
        echo "VALIDATION_ERROR: EventDrivenService claim failed kubectl validation"
        return 1
    fi
    
    if ! kubectl apply --dry-run=client -f "${ws_claim}" &>/dev/null; then
        echo "VALIDATION_ERROR: WebService claim failed kubectl validation"
        return 1
    fi
    
    # Get composition files
    local eds_composition="${PROJECT_ROOT}/platform/apis/event-driven-service/compositions/event-driven-service-composition.yaml"
    local ws_composition="${PROJECT_ROOT}/platform/apis/webservice/compositions/webservice-composition.yaml"
    
    if [[ ! -f "$eds_composition" ]]; then
        echo "COMPOSITION_ERROR: EventDrivenService composition not found"
        return 1
    fi
    
    if [[ ! -f "$ws_composition" ]]; then
        echo "COMPOSITION_ERROR: WebService composition not found"
        return 1
    fi
    
    # Extract resource values from compositions
    local eds_cpu_req=$(extract_resource_from_composition "$eds_composition" "requests.cpu" "$size")
    local ws_cpu_req=$(extract_resource_from_composition "$ws_composition" "requests.cpu" "$size")
    local expected_cpu_req=$(get_expected_cpu_request "$size")
    
    local eds_cpu_limit=$(extract_resource_from_composition "$eds_composition" "limits.cpu" "$size")
    local ws_cpu_limit=$(extract_resource_from_composition "$ws_composition" "limits.cpu" "$size")
    local expected_cpu_limit=$(get_expected_cpu_limit "$size")
    
    local eds_mem_req=$(extract_resource_from_composition "$eds_composition" "requests.memory" "$size")
    local ws_mem_req=$(extract_resource_from_composition "$ws_composition" "requests.memory" "$size")
    local expected_mem_req=$(get_expected_memory_request "$size")
    
    local eds_mem_limit=$(extract_resource_from_composition "$eds_composition" "limits.memory" "$size")
    local ws_mem_limit=$(extract_resource_from_composition "$ws_composition" "limits.memory" "$size")
    local expected_mem_limit=$(get_expected_memory_limit "$size")
    
    # Validate CPU requests
    if [[ "$eds_cpu_req" != "$expected_cpu_req" ]]; then
        echo "CPU_REQUEST_MISMATCH: EventDrivenService $size CPU request: expected $expected_cpu_req, got $eds_cpu_req"
        return 1
    fi
    
    if [[ "$ws_cpu_req" != "$expected_cpu_req" ]]; then
        echo "CPU_REQUEST_MISMATCH: WebService $size CPU request: expected $expected_cpu_req, got $ws_cpu_req"
        return 1
    fi
    
    if [[ "$eds_cpu_req" != "$ws_cpu_req" ]]; then
        echo "CPU_REQUEST_INCONSISTENCY: $size CPU request differs: EventDrivenService=$eds_cpu_req, WebService=$ws_cpu_req"
        return 1
    fi
    
    # Validate CPU limits
    if [[ "$eds_cpu_limit" != "$expected_cpu_limit" ]]; then
        echo "CPU_LIMIT_MISMATCH: EventDrivenService $size CPU limit: expected $expected_cpu_limit, got $eds_cpu_limit"
        return 1
    fi
    
    if [[ "$ws_cpu_limit" != "$expected_cpu_limit" ]]; then
        echo "CPU_LIMIT_MISMATCH: WebService $size CPU limit: expected $expected_cpu_limit, got $ws_cpu_limit"
        return 1
    fi
    
    if [[ "$eds_cpu_limit" != "$ws_cpu_limit" ]]; then
        echo "CPU_LIMIT_INCONSISTENCY: $size CPU limit differs: EventDrivenService=$eds_cpu_limit, WebService=$ws_cpu_limit"
        return 1
    fi
    
    # Validate Memory requests
    if [[ "$eds_mem_req" != "$expected_mem_req" ]]; then
        echo "MEMORY_REQUEST_MISMATCH: EventDrivenService $size memory request: expected $expected_mem_req, got $eds_mem_req"
        return 1
    fi
    
    if [[ "$ws_mem_req" != "$expected_mem_req" ]]; then
        echo "MEMORY_REQUEST_MISMATCH: WebService $size memory request: expected $expected_mem_req, got $ws_mem_req"
        return 1
    fi
    
    if [[ "$eds_mem_req" != "$ws_mem_req" ]]; then
        echo "MEMORY_REQUEST_INCONSISTENCY: $size memory request differs: EventDrivenService=$eds_mem_req, WebService=$ws_mem_req"
        return 1
    fi
    
    # Validate Memory limits
    if [[ "$eds_mem_limit" != "$expected_mem_limit" ]]; then
        echo "MEMORY_LIMIT_MISMATCH: EventDrivenService $size memory limit: expected $expected_mem_limit, got $eds_mem_limit"
        return 1
    fi
    
    if [[ "$ws_mem_limit" != "$expected_mem_limit" ]]; then
        echo "MEMORY_LIMIT_MISMATCH: WebService $size memory limit: expected $expected_mem_limit, got $ws_mem_limit"
        return 1
    fi
    
    if [[ "$eds_mem_limit" != "$ws_mem_limit" ]]; then
        echo "MEMORY_LIMIT_INCONSISTENCY: $size memory limit differs: EventDrivenService=$eds_mem_limit, WebService=$ws_mem_limit"
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

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Run property-based test iterations
echo "Running property-based test iterations..."
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
    ((TESTS_RUN++))
    
    # Generate random test inputs
    SERVICE_NAME=$(generate_service_name)
    SIZE=$(generate_size)
    PORT=$(generate_port)
    NATS_URL=$(generate_nats_url)
    NATS_STREAM=$(generate_nats_stream)
    NATS_CONSUMER=$(generate_nats_consumer)
    
    # Create test claim files
    EDS_CLAIM_FILE="${TEMP_DIR}/eds-claim-${i}.yaml"
    WS_CLAIM_FILE="${TEMP_DIR}/ws-claim-${i}.yaml"
    
    create_eventdriven_claim "${SERVICE_NAME}-eds" "${SIZE}" "${NATS_URL}" "${NATS_STREAM}" "${NATS_CONSUMER}" "${EDS_CLAIM_FILE}"
    create_webservice_claim "${SERVICE_NAME}-ws" "${SIZE}" "${PORT}" "${WS_CLAIM_FILE}"
    
    # Validate the property
    if validate_resource_sizing_uniformity "${SIZE}" "${EDS_CLAIM_FILE}" "${WS_CLAIM_FILE}"; then
        ((TESTS_PASSED++))
        if [[ $((i % 10)) -eq 0 ]]; then
            echo -e "${GREEN}✓${NC} Iteration ${i}/${ITERATIONS} - Size: ${SIZE}"
        fi
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} Iteration ${i}/${ITERATIONS} FAILED"
        echo "  Service: ${SERVICE_NAME}"
        echo "  Size: ${SIZE}"
        echo "  EDS Claim: ${EDS_CLAIM_FILE}"
        echo "  WS Claim: ${WS_CLAIM_FILE}"
        echo ""
        
        # Show the claim content for debugging
        echo "EventDrivenService claim:"
        cat "${EDS_CLAIM_FILE}"
        echo ""
        echo "WebService claim:"
        cat "${WS_CLAIM_FILE}"
        echo ""
    fi
done

# Summary
echo ""
echo "=================================================================="
echo "Property Test Summary"
echo "=================================================================="
echo ""
echo "Property: Resource Sizing Uniformity"
echo "Iterations run:    ${TESTS_RUN}"
echo -e "Iterations passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Iterations failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}✗ Property test FAILED${NC}"
    echo ""
    echo "The property 'Resource Sizing Uniformity' does not hold."
    echo "Some generated service claims with size specifications"
    echo "failed validation or had inconsistent resource allocations"
    echo "between EventDrivenService and WebService XRDs."
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ Property test PASSED${NC}"
    echo ""
    echo "The property 'Resource Sizing Uniformity' holds for all"
    echo "${ITERATIONS} randomly generated test cases."
    echo ""
    echo "This validates that for any service size specification,"
    echo "both EventDrivenService and WebService allocate identical"
    echo "CPU and memory resources for the same size value."
    echo ""
    echo "Validated size presets:"
    echo "- micro:  100m-500m CPU,   256Mi-1Gi memory"
    echo "- small:  250m-1000m CPU,  512Mi-2Gi memory"
    echo "- medium: 500m-2000m CPU,  1Gi-4Gi memory"
    echo "- large:  1000m-4000m CPU, 2Gi-8Gi memory"
    echo ""
    echo "This ensures consistent resource allocation across all platform XRDs."
    echo ""
    exit 0
fi