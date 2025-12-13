#!/usr/bin/env bash

# test-minimal-deployment.sh
# Test script for minimal EventDrivenService claim deployment
# This script applies a minimal claim, verifies all resources are created,
# validates their configurations, and cleans up test resources.

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
TEST_NAMESPACE="test-eds-$(date +%s)"
CLAIM_NAME="simple-worker"
CLAIM_FILE="${PROJECT_ROOT}/platform/04-apis/examples/minimal-claim.yaml"
TIMEOUT_SECONDS=300
POLL_INTERVAL=5

# Expected resources
EXPECTED_DEPLOYMENT="${CLAIM_NAME}"
EXPECTED_SERVICE="${CLAIM_NAME}"
EXPECTED_SERVICEACCOUNT="${CLAIM_NAME}"
EXPECTED_SCALEDOBJECT="${CLAIM_NAME}-scaler"

# Test counters
CHECKS_RUN=0
CHECKS_PASSED=0
CHECKS_FAILED=0

# Failed checks array
declare -a FAILED_CHECKS

# Cleanup flag
CLEANUP_PERFORMED=false

echo "=================================================="
echo "EventDrivenService Minimal Claim Deployment Test"
echo "=================================================="
echo ""

# Cleanup function
cleanup() {
    if [[ "${CLEANUP_PERFORMED}" == "true" ]]; then
        return
    fi
    
    echo ""
    echo "=================================================="
    echo "Cleanup"
    echo "=================================================="
    echo ""
    
    # Delete the claim (this should cascade delete all composed resources)
    echo "Deleting EventDrivenService claim..."
    if kubectl get eventdrivenservice "${CLAIM_NAME}" -n "${TEST_NAMESPACE}" &>/dev/null; then
        kubectl delete eventdrivenservice "${CLAIM_NAME}" -n "${TEST_NAMESPACE}" --timeout=60s 2>/dev/null || true
        echo "Claim deleted"
    else
        echo "Claim not found (may have been already deleted)"
    fi
    
    # Wait for resources to be cleaned up
    echo "Waiting for resources to be cleaned up..."
    sleep 5
    
    # Delete the test namespace
    echo "Deleting test namespace..."
    if kubectl get namespace "${TEST_NAMESPACE}" &>/dev/null; then
        kubectl delete namespace "${TEST_NAMESPACE}" --timeout=60s 2>/dev/null || true
        echo "Namespace deleted"
    else
        echo "Namespace not found (may have been already deleted)"
    fi
    
    CLEANUP_PERFORMED=true
    echo ""
    echo -e "${GREEN}✓ Cleanup completed${NC}"
    echo ""
}

# Register cleanup on exit
trap cleanup EXIT

# Helper function to run a check
run_check() {
    local check_name="$1"
    local description="$2"
    
    ((CHECKS_RUN++))
    
    echo "----------------------------------------"
    echo -e "${BLUE}Check ${CHECKS_RUN}:${NC} ${check_name}"
    echo "Description: ${description}"
    echo ""
}

# Helper function to report check result
report_result() {
    local success="$1"
    local message="$2"
    
    if [[ "${success}" == "true" ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "Reason: ${message}"
        ((CHECKS_FAILED++))
        FAILED_CHECKS+=("Check ${CHECKS_RUN}")
    fi
    
    echo ""
}

# Helper function to wait for resource
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="$4"
    
    local elapsed=0
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if kubectl get "${resource_type}" "${resource_name}" -n "${namespace}" &>/dev/null; then
            return 0
        fi
        
        sleep "${POLL_INTERVAL}"
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    return 1
}

# Prerequisites check
echo "Checking prerequisites..."
echo ""

if [[ ! -f "${CLAIM_FILE}" ]]; then
    echo -e "${RED}ERROR: Claim file not found: ${CLAIM_FILE}${NC}"
    exit 1
fi

if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}ERROR: kubectl not found in PATH${NC}"
    exit 1
fi

# Check if EventDrivenService CRD exists
if ! kubectl get crd eventdrivenservices.platform.bizmatters.io &>/dev/null; then
    echo -e "${RED}ERROR: EventDrivenService CRD not installed${NC}"
    echo "Please apply the XRD first: kubectl apply -f platform/04-apis/definitions/xeventdrivenservices.yaml"
    exit 1
fi

# Check if Composition exists
if ! kubectl get composition event-driven-service &>/dev/null; then
    echo -e "${RED}ERROR: event-driven-service Composition not found${NC}"
    echo "Please apply the Composition first: kubectl apply -f platform/04-apis/compositions/event-driven-service-composition.yaml"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Setup: Create test namespace
echo "=================================================="
echo "Setup"
echo "=================================================="
echo ""

echo "Creating test namespace: ${TEST_NAMESPACE}"
kubectl create namespace "${TEST_NAMESPACE}" 2>/dev/null || echo "Namespace already exists"
echo ""

# Apply the minimal claim
echo "Applying minimal claim from: ${CLAIM_FILE}"
# Modify the claim to use our test namespace by using yq or sed
# We need to override the namespace in the claim
if command -v yq &>/dev/null; then
    # Use yq to modify namespace
    yq eval ".metadata.namespace = \"${TEST_NAMESPACE}\"" "${CLAIM_FILE}" | kubectl apply -f -
else
    # Fallback: use sed to modify namespace
    sed "s/namespace: workers/namespace: ${TEST_NAMESPACE}/" "${CLAIM_FILE}" | kubectl apply -f -
fi
echo ""

echo "Waiting for resources to be created (timeout: ${TIMEOUT_SECONDS}s)..."
echo ""

# Check 1: Wait for Deployment to be created
run_check \
    "Deployment Created" \
    "Verifies that the Deployment resource is created by Crossplane"

if wait_for_resource "deployment" "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}" "${TIMEOUT_SECONDS}"; then
    echo "Deployment '${EXPECTED_DEPLOYMENT}' found"
    report_result "true" ""
else
    report_result "false" "Deployment '${EXPECTED_DEPLOYMENT}' not created within ${TIMEOUT_SECONDS}s"
fi

# Check 2: Wait for Service to be created
run_check \
    "Service Created" \
    "Verifies that the Service resource is created by Crossplane"

if wait_for_resource "service" "${EXPECTED_SERVICE}" "${TEST_NAMESPACE}" "${TIMEOUT_SECONDS}"; then
    echo "Service '${EXPECTED_SERVICE}' found"
    report_result "true" ""
else
    report_result "false" "Service '${EXPECTED_SERVICE}' not created within ${TIMEOUT_SECONDS}s"
fi

# Check 3: Wait for ServiceAccount to be created
run_check \
    "ServiceAccount Created" \
    "Verifies that the ServiceAccount resource is created by Crossplane"

if wait_for_resource "serviceaccount" "${EXPECTED_SERVICEACCOUNT}" "${TEST_NAMESPACE}" "${TIMEOUT_SECONDS}"; then
    echo "ServiceAccount '${EXPECTED_SERVICEACCOUNT}' found"
    report_result "true" ""
else
    report_result "false" "ServiceAccount '${EXPECTED_SERVICEACCOUNT}' not created within ${TIMEOUT_SECONDS}s"
fi

# Check 4: Wait for ScaledObject to be created
run_check \
    "ScaledObject Created" \
    "Verifies that the KEDA ScaledObject resource is created by Crossplane"

if wait_for_resource "scaledobject" "${EXPECTED_SCALEDOBJECT}" "${TEST_NAMESPACE}" "${TIMEOUT_SECONDS}"; then
    echo "ScaledObject '${EXPECTED_SCALEDOBJECT}' found"
    report_result "true" ""
else
    report_result "false" "ScaledObject '${EXPECTED_SCALEDOBJECT}' not created within ${TIMEOUT_SECONDS}s"
fi

# Check 5: Validate Deployment configuration
run_check \
    "Deployment Configuration" \
    "Validates that the Deployment has correct image and resource configuration"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check image
    ACTUAL_IMAGE=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
    EXPECTED_IMAGE="ghcr.io/org/simple-worker:v1.0.0"
    
    echo "Expected image: ${EXPECTED_IMAGE}"
    echo "Actual image:   ${ACTUAL_IMAGE}"
    
    if [[ "${ACTUAL_IMAGE}" != "${EXPECTED_IMAGE}" ]]; then
        validation_passed=false
        validation_errors+=("Image mismatch: expected ${EXPECTED_IMAGE}, got ${ACTUAL_IMAGE}")
    fi
    
    # Check resource size (small: 250m-1000m CPU, 512Mi-2Gi memory)
    CPU_REQUEST=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    CPU_LIMIT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
    MEM_REQUEST=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
    MEM_LIMIT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
    
    echo "CPU request:    ${CPU_REQUEST} (expected: 250m)"
    echo "CPU limit:      ${CPU_LIMIT} (expected: 1000m)"
    echo "Memory request: ${MEM_REQUEST} (expected: 512Mi)"
    echo "Memory limit:   ${MEM_LIMIT} (expected: 2Gi)"
    
    if [[ "${CPU_REQUEST}" != "250m" ]]; then
        validation_passed=false
        validation_errors+=("CPU request mismatch: expected 250m, got ${CPU_REQUEST}")
    fi
    
    if [[ "${CPU_LIMIT}" != "1000m" ]] && [[ "${CPU_LIMIT}" != "1" ]]; then
        validation_passed=false
        validation_errors+=("CPU limit mismatch: expected 1000m, got ${CPU_LIMIT}")
    fi
    
    if [[ "${MEM_REQUEST}" != "512Mi" ]]; then
        validation_passed=false
        validation_errors+=("Memory request mismatch: expected 512Mi, got ${MEM_REQUEST}")
    fi
    
    if [[ "${MEM_LIMIT}" != "2Gi" ]]; then
        validation_passed=false
        validation_errors+=("Memory limit mismatch: expected 2Gi, got ${MEM_LIMIT}")
    fi
    
    # Check NATS environment variables
    NATS_URL=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NATS_URL")].value}' 2>/dev/null || echo "")
    NATS_STREAM=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NATS_STREAM_NAME")].value}' 2>/dev/null || echo "")
    NATS_CONSUMER=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NATS_CONSUMER_GROUP")].value}' 2>/dev/null || echo "")
    
    echo "NATS_URL:           ${NATS_URL} (expected: nats://nats.nats.svc:4222)"
    echo "NATS_STREAM_NAME:   ${NATS_STREAM} (expected: SIMPLE_JOBS)"
    echo "NATS_CONSUMER_GROUP: ${NATS_CONSUMER} (expected: simple-workers)"
    
    if [[ "${NATS_URL}" != "nats://nats.nats.svc:4222" ]]; then
        validation_passed=false
        validation_errors+=("NATS_URL mismatch: expected nats://nats.nats.svc:4222, got ${NATS_URL}")
    fi
    
    if [[ "${NATS_STREAM}" != "SIMPLE_JOBS" ]]; then
        validation_passed=false
        validation_errors+=("NATS_STREAM_NAME mismatch: expected SIMPLE_JOBS, got ${NATS_STREAM}")
    fi
    
    if [[ "${NATS_CONSUMER}" != "simple-workers" ]]; then
        validation_passed=false
        validation_errors+=("NATS_CONSUMER_GROUP mismatch: expected simple-workers, got ${NATS_CONSUMER}")
    fi
    
    echo ""
    
    if [[ "${validation_passed}" == "true" ]]; then
        report_result "true" ""
    else
        error_msg=$(IFS="; "; echo "${validation_errors[*]}")
        report_result "false" "${error_msg}"
    fi
else
    report_result "false" "Deployment not found"
fi

# Check 6: Validate Service configuration
run_check \
    "Service Configuration" \
    "Validates that the Service exposes port 8080 and has correct selector"

if kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check service type
    SERVICE_TYPE=$(kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
    echo "Service type: ${SERVICE_TYPE} (expected: ClusterIP)"
    
    if [[ "${SERVICE_TYPE}" != "ClusterIP" ]]; then
        validation_passed=false
        validation_errors+=("Service type mismatch: expected ClusterIP, got ${SERVICE_TYPE}")
    fi
    
    # Check port
    SERVICE_PORT=$(kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")
    TARGET_PORT=$(kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")
    
    echo "Service port:   ${SERVICE_PORT} (expected: 8080)"
    echo "Target port:    ${TARGET_PORT} (expected: 8080)"
    
    if [[ "${SERVICE_PORT}" != "8080" ]]; then
        validation_passed=false
        validation_errors+=("Service port mismatch: expected 8080, got ${SERVICE_PORT}")
    fi
    
    # Target port can be numeric (8080) or named (http)
    if [[ "${TARGET_PORT}" != "8080" ]] && [[ "${TARGET_PORT}" != "http" ]]; then
        validation_passed=false
        validation_errors+=("Target port mismatch: expected 8080 or http, got ${TARGET_PORT}")
    fi
    
    # Check selector (using Kubernetes recommended label)
    SELECTOR_APP=$(kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.selector.app\.kubernetes\.io/name}' 2>/dev/null || echo "")
    echo "Selector app.kubernetes.io/name:   ${SELECTOR_APP} (expected: ${CLAIM_NAME})"
    
    if [[ "${SELECTOR_APP}" != "${CLAIM_NAME}" ]]; then
        validation_passed=false
        validation_errors+=("Selector mismatch: expected app.kubernetes.io/name=${CLAIM_NAME}, got app.kubernetes.io/name=${SELECTOR_APP}")
    fi
    
    echo ""
    
    if [[ "${validation_passed}" == "true" ]]; then
        report_result "true" ""
    else
        error_msg=$(IFS="; "; echo "${validation_errors[*]}")
        report_result "false" "${error_msg}"
    fi
else
    report_result "false" "Service not found"
fi

# Check 7: Validate ScaledObject configuration
run_check \
    "ScaledObject Configuration" \
    "Validates that the ScaledObject has correct NATS trigger configuration"

if kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check scale target
    SCALE_TARGET=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null || echo "")
    echo "Scale target: ${SCALE_TARGET} (expected: ${EXPECTED_DEPLOYMENT})"
    
    if [[ "${SCALE_TARGET}" != "${EXPECTED_DEPLOYMENT}" ]]; then
        validation_passed=false
        validation_errors+=("Scale target mismatch: expected ${EXPECTED_DEPLOYMENT}, got ${SCALE_TARGET}")
    fi
    
    # Check replica counts
    MIN_REPLICAS=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.minReplicaCount}' 2>/dev/null || echo "")
    MAX_REPLICAS=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.maxReplicaCount}' 2>/dev/null || echo "")
    
    echo "Min replicas: ${MIN_REPLICAS} (expected: 1)"
    echo "Max replicas: ${MAX_REPLICAS} (expected: 10)"
    
    if [[ "${MIN_REPLICAS}" != "1" ]]; then
        validation_passed=false
        validation_errors+=("Min replicas mismatch: expected 1, got ${MIN_REPLICAS}")
    fi
    
    if [[ "${MAX_REPLICAS}" != "10" ]]; then
        validation_passed=false
        validation_errors+=("Max replicas mismatch: expected 10, got ${MAX_REPLICAS}")
    fi
    
    # Check NATS trigger configuration
    TRIGGER_TYPE=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.triggers[0].type}' 2>/dev/null || echo "")
    NATS_ENDPOINT=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.natsServerMonitoringEndpoint}' 2>/dev/null || echo "")
    NATS_STREAM=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.stream}' 2>/dev/null || echo "")
    NATS_CONSUMER=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.consumer}' 2>/dev/null || echo "")
    
    echo "Trigger type:   ${TRIGGER_TYPE} (expected: nats-jetstream)"
    echo "NATS endpoint:  ${NATS_ENDPOINT} (expected: nats-headless.nats.svc.cluster.local:8222)"
    echo "Stream:         ${NATS_STREAM} (expected: SIMPLE_JOBS)"
    echo "Consumer:       ${NATS_CONSUMER} (expected: simple-workers)"
    
    if [[ "${TRIGGER_TYPE}" != "nats-jetstream" ]]; then
        validation_passed=false
        validation_errors+=("Trigger type mismatch: expected nats-jetstream, got ${TRIGGER_TYPE}")
    fi
    
    if [[ "${NATS_ENDPOINT}" != "nats-headless.nats.svc.cluster.local:8222" ]]; then
        validation_passed=false
        validation_errors+=("NATS endpoint mismatch: expected nats-headless.nats.svc.cluster.local:8222, got ${NATS_ENDPOINT}")
    fi
    
    if [[ "${NATS_STREAM}" != "SIMPLE_JOBS" ]]; then
        validation_passed=false
        validation_errors+=("Stream mismatch: expected SIMPLE_JOBS, got ${NATS_STREAM}")
    fi
    
    if [[ "${NATS_CONSUMER}" != "simple-workers" ]]; then
        validation_passed=false
        validation_errors+=("Consumer mismatch: expected simple-workers, got ${NATS_CONSUMER}")
    fi
    
    echo ""
    
    if [[ "${validation_passed}" == "true" ]]; then
        report_result "true" ""
    else
        error_msg=$(IFS="; "; echo "${validation_errors[*]}")
        report_result "false" "${error_msg}"
    fi
else
    report_result "false" "ScaledObject not found"
fi

# Check 8: Validate resource labels
run_check \
    "Resource Labels" \
    "Validates that all resources have correct labels applied"

validation_passed=true
validation_errors=()

# Check Deployment labels (using Kubernetes recommended labels)
if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    DEPLOY_APP_LABEL=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}' 2>/dev/null || echo "")
    
    if [[ "${DEPLOY_APP_LABEL}" != "${CLAIM_NAME}" ]]; then
        validation_passed=false
        validation_errors+=("Deployment missing app.kubernetes.io/name=${CLAIM_NAME} label")
    else
        echo "✓ Deployment has correct app.kubernetes.io/name label"
    fi
fi

# Check Service labels (using Kubernetes recommended labels)
if kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    SERVICE_APP_LABEL=$(kubectl get service "${EXPECTED_SERVICE}" -n "${TEST_NAMESPACE}" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}' 2>/dev/null || echo "")
    
    if [[ "${SERVICE_APP_LABEL}" != "${CLAIM_NAME}" ]]; then
        validation_passed=false
        validation_errors+=("Service missing app.kubernetes.io/name=${CLAIM_NAME} label")
    else
        echo "✓ Service has correct app.kubernetes.io/name label"
    fi
fi

echo ""

if [[ "${validation_passed}" == "true" ]]; then
    report_result "true" ""
else
    error_msg=$(IFS="; "; echo "${validation_errors[*]}")
    report_result "false" "${error_msg}"
fi

# Summary
echo "=================================================="
echo "Test Summary"
echo "=================================================="
echo ""
echo "Checks run:    ${CHECKS_RUN}"
echo -e "Checks passed: ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "Checks failed: ${RED}${CHECKS_FAILED}${NC}"
echo ""

if [[ ${CHECKS_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed checks:${NC}"
    for check in "${FAILED_CHECKS[@]}"; do
        echo "  - ${check}"
    done
    echo ""
    echo "Cleanup will be performed automatically..."
    exit 1
else
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "The minimal EventDrivenService claim successfully provisioned all resources:"
    echo "  - Deployment with correct image and resource sizing"
    echo "  - Service exposing port 8080"
    echo "  - ServiceAccount for pod identity"
    echo "  - ScaledObject with NATS JetStream trigger"
    echo ""
    echo "Cleanup will be performed automatically..."
    exit 0
fi
