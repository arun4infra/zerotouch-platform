#!/usr/bin/env bash

# verify-keda-config.sh
# Verification script for KEDA ScaledObject configuration
# This script checks that ScaledObject trigger configuration is correct,
# verifies nats-headless endpoint is used, and validates stream/consumer names.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCALEDOBJECT_NAME=""
NAMESPACE=""
EXPECTED_STREAM=""
EXPECTED_CONSUMER=""

# Test counters
CHECKS_RUN=0
CHECKS_PASSED=0
CHECKS_FAILED=0

# Failed checks array
declare -a FAILED_CHECKS

echo "=================================================="
echo "KEDA ScaledObject Configuration Verification"
echo "=================================================="
echo ""

# Usage function
usage() {
    echo "Usage: $0 -n <scaledobject-name> -s <namespace> [-t <stream>] [-c <consumer>]"
    echo ""
    echo "Options:"
    echo "  -n    ScaledObject name (required)"
    echo "  -s    Namespace (required)"
    echo "  -t    Expected NATS stream name (optional)"
    echo "  -c    Expected NATS consumer name (optional)"
    echo ""
    echo "Example:"
    echo "  $0 -n simple-worker-scaler -s workers -t SIMPLE_JOBS -c simple-workers"
    echo ""
    exit 1
}

# Parse command line arguments
while getopts "n:s:t:c:h" opt; do
    case ${opt} in
        n)
            SCALEDOBJECT_NAME="${OPTARG}"
            ;;
        s)
            NAMESPACE="${OPTARG}"
            ;;
        t)
            EXPECTED_STREAM="${OPTARG}"
            ;;
        c)
            EXPECTED_CONSUMER="${OPTARG}"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -${OPTARG}" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "${SCALEDOBJECT_NAME}" ]] || [[ -z "${NAMESPACE}" ]]; then
    echo -e "${RED}ERROR: ScaledObject name and namespace are required${NC}"
    echo ""
    usage
fi

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

# Prerequisites check
echo "Checking prerequisites..."
echo ""

if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}ERROR: kubectl not found in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Check 1: Verify ScaledObject exists
run_check \
    "ScaledObject Exists" \
    "Verifies that the ScaledObject resource exists in the specified namespace"

if kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ScaledObject '${SCALEDOBJECT_NAME}' found in namespace '${NAMESPACE}'"
    report_result "true" ""
else
    echo "ScaledObject '${SCALEDOBJECT_NAME}' not found in namespace '${NAMESPACE}'"
    report_result "false" "ScaledObject not found"
    
    # Exit early if ScaledObject doesn't exist
    echo "=================================================="
    echo "Test Summary"
    echo "=================================================="
    echo ""
    echo "Checks run:    ${CHECKS_RUN}"
    echo -e "Checks passed: ${GREEN}${CHECKS_PASSED}${NC}"
    echo -e "Checks failed: ${RED}${CHECKS_FAILED}${NC}"
    echo ""
    exit 1
fi

# Check 2: Verify trigger type is nats-jetstream
run_check \
    "Trigger Type" \
    "Verifies that the trigger type is 'nats-jetstream'"

TRIGGER_TYPE=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].type}' 2>/dev/null || echo "")

echo "Trigger type: ${TRIGGER_TYPE}"
echo "Expected:     nats-jetstream"

if [[ "${TRIGGER_TYPE}" == "nats-jetstream" ]]; then
    report_result "true" ""
else
    report_result "false" "Expected trigger type 'nats-jetstream', got '${TRIGGER_TYPE}'"
fi

# Check 3: Verify nats-headless endpoint is used (not nats)
run_check \
    "NATS Monitoring Endpoint" \
    "Verifies that nats-headless endpoint is used for monitoring (not nats service)"

NATS_ENDPOINT=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.natsServerMonitoringEndpoint}' 2>/dev/null || echo "")

echo "NATS endpoint: ${NATS_ENDPOINT}"
echo "Expected:      nats-headless.nats.svc.cluster.local:8222"

if [[ "${NATS_ENDPOINT}" == "nats-headless.nats.svc.cluster.local:8222" ]]; then
    report_result "true" ""
else
    if [[ "${NATS_ENDPOINT}" =~ ^nats\.nats\.svc ]]; then
        report_result "false" "Using 'nats' service instead of 'nats-headless' - this will cause KEDA errors. Expected 'nats-headless.nats.svc.cluster.local:8222', got '${NATS_ENDPOINT}'"
    else
        report_result "false" "Expected 'nats-headless.nats.svc.cluster.local:8222', got '${NATS_ENDPOINT}'"
    fi
fi

# Check 4: Verify account is set to $SYS
run_check \
    "NATS Account" \
    "Verifies that the NATS account is set to '\$SYS' for monitoring"

NATS_ACCOUNT=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.account}' 2>/dev/null || echo "")

echo "NATS account: ${NATS_ACCOUNT}"
echo "Expected:     \$SYS"

if [[ "${NATS_ACCOUNT}" == "\$SYS" ]]; then
    report_result "true" ""
else
    report_result "false" "Expected account '\$SYS', got '${NATS_ACCOUNT}'"
fi

# Check 5: Verify stream name (if provided)
if [[ -n "${EXPECTED_STREAM}" ]]; then
    run_check \
        "NATS Stream Name" \
        "Verifies that the stream name matches the expected value"
    
    ACTUAL_STREAM=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.stream}' 2>/dev/null || echo "")
    
    echo "Stream name: ${ACTUAL_STREAM}"
    echo "Expected:    ${EXPECTED_STREAM}"
    
    if [[ "${ACTUAL_STREAM}" == "${EXPECTED_STREAM}" ]]; then
        report_result "true" ""
    else
        report_result "false" "Expected stream '${EXPECTED_STREAM}', got '${ACTUAL_STREAM}'"
    fi
else
    # Just display the stream name without validation
    ACTUAL_STREAM=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.stream}' 2>/dev/null || echo "")
    echo "Stream name: ${ACTUAL_STREAM} (not validated - no expected value provided)"
    echo ""
fi

# Check 6: Verify consumer name (if provided)
if [[ -n "${EXPECTED_CONSUMER}" ]]; then
    run_check \
        "NATS Consumer Name" \
        "Verifies that the consumer name matches the expected value"
    
    ACTUAL_CONSUMER=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.consumer}' 2>/dev/null || echo "")
    
    echo "Consumer name: ${ACTUAL_CONSUMER}"
    echo "Expected:      ${EXPECTED_CONSUMER}"
    
    if [[ "${ACTUAL_CONSUMER}" == "${EXPECTED_CONSUMER}" ]]; then
        report_result "true" ""
    else
        report_result "false" "Expected consumer '${EXPECTED_CONSUMER}', got '${ACTUAL_CONSUMER}'"
    fi
else
    # Just display the consumer name without validation
    ACTUAL_CONSUMER=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.consumer}' 2>/dev/null || echo "")
    echo "Consumer name: ${ACTUAL_CONSUMER} (not validated - no expected value provided)"
    echo ""
fi

# Check 7: Verify lagThreshold
run_check \
    "Lag Threshold" \
    "Verifies that the lagThreshold is set to 5"

LAG_THRESHOLD=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.lagThreshold}' 2>/dev/null || echo "")

echo "Lag threshold: ${LAG_THRESHOLD}"
echo "Expected:      5"

if [[ "${LAG_THRESHOLD}" == "5" ]]; then
    report_result "true" ""
else
    report_result "false" "Expected lagThreshold '5', got '${LAG_THRESHOLD}'"
fi

# Check 8: Verify minReplicaCount
run_check \
    "Minimum Replica Count" \
    "Verifies that minReplicaCount is set to 1"

MIN_REPLICAS=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.minReplicaCount}' 2>/dev/null || echo "")

echo "Min replicas: ${MIN_REPLICAS}"
echo "Expected:     1"

if [[ "${MIN_REPLICAS}" == "1" ]]; then
    report_result "true" ""
else
    report_result "false" "Expected minReplicaCount '1', got '${MIN_REPLICAS}'"
fi

# Check 9: Verify maxReplicaCount
run_check \
    "Maximum Replica Count" \
    "Verifies that maxReplicaCount is set to 10"

MAX_REPLICAS=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.maxReplicaCount}' 2>/dev/null || echo "")

echo "Max replicas: ${MAX_REPLICAS}"
echo "Expected:     10"

if [[ "${MAX_REPLICAS}" == "10" ]]; then
    report_result "true" ""
else
    report_result "false" "Expected maxReplicaCount '10', got '${MAX_REPLICAS}'"
fi

# Check 10: Verify scaleTargetRef
run_check \
    "Scale Target Reference" \
    "Verifies that scaleTargetRef points to a Deployment"

SCALE_TARGET_KIND=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.scaleTargetRef.kind}' 2>/dev/null || echo "Deployment")
SCALE_TARGET_NAME=$(kubectl get scaledobject "${SCALEDOBJECT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null || echo "")

echo "Scale target kind: ${SCALE_TARGET_KIND}"
echo "Scale target name: ${SCALE_TARGET_NAME}"

validation_passed=true
validation_errors=()

# Verify kind is Deployment (or empty, which defaults to Deployment)
if [[ -n "${SCALE_TARGET_KIND}" ]] && [[ "${SCALE_TARGET_KIND}" != "Deployment" ]]; then
    validation_passed=false
    validation_errors+=("Expected kind 'Deployment', got '${SCALE_TARGET_KIND}'")
fi

# Verify target name is not empty
if [[ -z "${SCALE_TARGET_NAME}" ]]; then
    validation_passed=false
    validation_errors+=("Scale target name is empty")
fi

# Verify the target Deployment exists
if [[ -n "${SCALE_TARGET_NAME}" ]]; then
    if kubectl get deployment "${SCALE_TARGET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        echo "✓ Target Deployment '${SCALE_TARGET_NAME}' exists"
    else
        validation_passed=false
        validation_errors+=("Target Deployment '${SCALE_TARGET_NAME}' not found")
    fi
fi

if [[ "${validation_passed}" == "true" ]]; then
    report_result "true" ""
else
    error_msg=$(IFS="; "; echo "${validation_errors[*]}")
    report_result "false" "${error_msg}"
fi

# Summary
echo "=================================================="
echo "Verification Summary"
echo "=================================================="
echo ""
echo "ScaledObject: ${SCALEDOBJECT_NAME}"
echo "Namespace:    ${NAMESPACE}"
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
    echo -e "${RED}✗ KEDA configuration has issues${NC}"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "KEDA ScaledObject is correctly configured:"
    echo "  - Trigger type: nats-jetstream"
    echo "  - Monitoring endpoint: nats-headless.nats.svc.cluster.local:8222"
    echo "  - Account: \$SYS"
    echo "  - Stream: ${ACTUAL_STREAM}"
    echo "  - Consumer: ${ACTUAL_CONSUMER}"
    echo "  - Lag threshold: 5"
    echo "  - Replica range: 1-10"
    echo "  - Scale target: ${SCALE_TARGET_NAME}"
    echo ""
    exit 0
fi
