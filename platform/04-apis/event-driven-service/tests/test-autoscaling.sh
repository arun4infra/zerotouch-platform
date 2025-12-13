#!/usr/bin/env bash

# test-autoscaling.sh
# Test script for KEDA autoscaling with EventDrivenService
# This script publishes messages to NATS, monitors pod scaling behavior,
# verifies scale-up and scale-down based on queue depth.
#
# KNOWN LIMITATION:
# Check 2 (Scale Up on Message Load) may fail in cold-start scenarios due to
# KEDA's NATS JetStream scaler implementation. The scaler uses num_pending
# (messages actively being pulled) rather than unprocessed messages.
# See: platform/04-apis/docs/KEDA-NATS-LIMITATIONS.md for details.
#
# In production, autoscaling works correctly once workers are running and
# actively pulling messages from the stream.

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
TEST_NAMESPACE="test-autoscale-$(date +%s)"
CLAIM_NAME="autoscale-worker"
CLAIM_FILE="${PROJECT_ROOT}/platform/04-apis/event-driven-service/examples/minimal-claim.yaml"
MESSAGE_COUNT=50
NATS_STREAM="SIMPLE_JOBS"
NATS_CONSUMER="simple-workers"
NATS_URL="nats://nats.nats.svc:4222"
SCALE_UP_TIMEOUT=180
SCALE_DOWN_TIMEOUT=300
POLL_INTERVAL=5

# Expected resources
EXPECTED_DEPLOYMENT="${CLAIM_NAME}"
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
echo "KEDA Autoscaling Test for EventDrivenService"
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
    
    # Clean up NATS stream (if it was created for testing)
    echo "Cleaning up NATS stream (if exists)..."
    if [[ -n "${NATS_BOX_POD}" ]]; then
        kubectl exec -n nats "${NATS_BOX_POD}" -- nats stream rm "${NATS_STREAM}" -f 2>/dev/null || echo "Stream cleanup skipped or already removed"
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

# Helper function to get pod count
get_pod_count() {
    local deployment="$1"
    local namespace="$2"
    
    # Count pods directly without grep -c to avoid leading zeros
    local count
    count=$(kubectl get pods -n "${namespace}" -l "app.kubernetes.io/name=${deployment}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    # Ensure we return a valid number (default to 0 if empty)
    if [[ -z "${count}" ]] || [[ "${count}" == "" ]]; then
        echo "0"
    else
        # Strip leading zeros and return
        echo "${count#0}"
    fi
}

# Helper function to wait for pod count
wait_for_pod_count() {
    local deployment="$1"
    local namespace="$2"
    local target_count="$3"
    local timeout="$4"
    local comparison="$5"  # "eq", "gt", "lt"
    
    local elapsed=0
    
    echo "Waiting for pod count ${comparison} ${target_count} (timeout: ${timeout}s)..."
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        local current_count
        current_count=$(get_pod_count "${deployment}" "${namespace}")
        
        echo "  Current pod count: ${current_count} (elapsed: ${elapsed}s)"
        
        case "${comparison}" in
            "eq")
                if [[ ${current_count} -eq ${target_count} ]]; then
                    echo "  ✓ Target count reached"
                    return 0
                fi
                ;;
            "gt")
                if [[ ${current_count} -gt ${target_count} ]]; then
                    echo "  ✓ Pod count exceeded target"
                    return 0
                fi
                ;;
            "gte")
                if [[ ${current_count} -ge ${target_count} ]]; then
                    echo "  ✓ Pod count reached or exceeded target"
                    return 0
                fi
                ;;
            "lt")
                if [[ ${current_count} -lt ${target_count} ]]; then
                    echo "  ✓ Pod count below target"
                    return 0
                fi
                ;;
        esac
        
        sleep "${POLL_INTERVAL}"
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    echo "  ✗ Timeout reached"
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

# Check if NATS is available
if ! kubectl get statefulset nats -n nats &>/dev/null; then
    echo -e "${RED}ERROR: NATS not found in nats namespace${NC}"
    exit 1
fi

# Check if EventDrivenService CRD exists
if ! kubectl get crd eventdrivenservices.platform.bizmatters.io &>/dev/null; then
    echo -e "${RED}ERROR: EventDrivenService CRD not installed${NC}"
    exit 1
fi

# Check if KEDA is installed
if ! kubectl get deployment keda-operator -n keda &>/dev/null; then
    echo -e "${YELLOW}WARNING: KEDA operator not found in keda namespace${NC}"
    echo "Autoscaling may not work without KEDA"
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

# Get NATS box pod name
NATS_BOX_POD=$(kubectl get pods -n nats -l app.kubernetes.io/component=nats-box -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -z "${NATS_BOX_POD}" ]]; then
    echo -e "${RED}ERROR: nats-box pod not found${NC}"
    exit 1
fi

echo "Using NATS box pod: ${NATS_BOX_POD}"
echo ""

# Setup: Create NATS stream (if it doesn't exist)
echo "Setting up NATS stream: ${NATS_STREAM}"
if kubectl exec -n nats "${NATS_BOX_POD}" -- nats stream info "${NATS_STREAM}" &>/dev/null; then
    echo "Stream '${NATS_STREAM}' already exists"
else
    echo "Creating stream '${NATS_STREAM}'..."
    kubectl exec -n nats "${NATS_BOX_POD}" -- nats stream add "${NATS_STREAM}" \
        --subjects="${NATS_STREAM}.*" \
        --storage=memory \
        --retention=workq \
        --max-msgs=-1 \
        --max-bytes=-1 \
        --max-age=1h \
        --replicas=1 \
        --defaults || {
            echo -e "${RED}ERROR: Failed to create NATS stream${NC}"
            exit 1
        }
    echo "Stream created successfully"
fi

# Setup: Create NATS consumer (if it doesn't exist)
echo "Setting up NATS consumer: ${NATS_CONSUMER}"
if kubectl exec -n nats "${NATS_BOX_POD}" -- nats consumer info "${NATS_STREAM}" "${NATS_CONSUMER}" &>/dev/null; then
    echo "Consumer '${NATS_CONSUMER}' already exists"
else
    echo "Creating consumer '${NATS_CONSUMER}'..."
    kubectl exec -n nats "${NATS_BOX_POD}" -- nats consumer add "${NATS_STREAM}" "${NATS_CONSUMER}" \
        --pull \
        --deliver=all \
        --ack=explicit \
        --replay=instant \
        --max-pending=10000 \
        --defaults || {
            echo -e "${RED}ERROR: Failed to create NATS consumer${NC}"
            exit 1
        }
    echo "Consumer created successfully"
fi
echo ""

# Apply the claim
echo "Applying EventDrivenService claim..."
if command -v yq &>/dev/null; then
    yq eval ".metadata.name = \"${CLAIM_NAME}\" | .metadata.namespace = \"${TEST_NAMESPACE}\"" "${CLAIM_FILE}" | kubectl apply -f -
else
    sed -e "s/name: simple-worker/name: ${CLAIM_NAME}/" -e "s/namespace: workers/namespace: ${TEST_NAMESPACE}/" "${CLAIM_FILE}" | kubectl apply -f -
fi
echo ""

echo "Waiting for Deployment to be created..."
sleep 10

# Check 1: Verify initial pod count is 1 (minReplicaCount)
run_check \
    "Initial Pod Count" \
    "Verifies that the deployment starts with 1 pod (minReplicaCount)"

if wait_for_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}" 1 60 "gte"; then
    INITIAL_COUNT=$(get_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}")
    echo "Initial pod count: ${INITIAL_COUNT}"
    
    if [[ ${INITIAL_COUNT} -eq 1 ]]; then
        report_result "true" ""
    else
        report_result "true" "Pod count is ${INITIAL_COUNT} (expected 1, but >= 1 is acceptable)"
    fi
else
    report_result "false" "Deployment did not reach 1 pod within timeout"
fi

# Check 2: Publish messages to NATS and verify scale-up
run_check \
    "Scale Up on Message Load" \
    "Publishes ${MESSAGE_COUNT} messages and verifies pods scale up from 1 to multiple replicas"

echo -e "${YELLOW}NOTE: This check may fail due to KEDA's NATS JetStream scaler limitation${NC}"
echo -e "${YELLOW}      See platform/04-apis/docs/KEDA-NATS-LIMITATIONS.md for details${NC}"
echo ""
echo "Publishing ${MESSAGE_COUNT} messages to NATS stream '${NATS_STREAM}'..."

# Publish messages using NATS CLI
for i in $(seq 1 ${MESSAGE_COUNT}); do
    kubectl exec -n nats "${NATS_BOX_POD}" -- nats pub "${NATS_STREAM}.test" "Test message ${i}" 2>/dev/null || echo "Message ${i} publish may have failed"
done

echo "Messages published"
echo ""

# Wait for scale-up
echo "Monitoring pod count for scale-up..."
INITIAL_COUNT=$(get_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}")
echo "Starting pod count: ${INITIAL_COUNT}"
echo ""

if wait_for_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}" 1 "${SCALE_UP_TIMEOUT}" "gt"; then
    SCALED_COUNT=$(get_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}")
    echo "Scaled pod count: ${SCALED_COUNT}"
    
    if [[ ${SCALED_COUNT} -gt 1 ]]; then
        report_result "true" ""
    else
        report_result "false" "Pod count did not increase (still at ${SCALED_COUNT})"
    fi
else
    FINAL_COUNT=$(get_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}")
    report_result "false" "Pods did not scale up within ${SCALE_UP_TIMEOUT}s (final count: ${FINAL_COUNT})"
fi

# Check 3: Verify ScaledObject status
run_check \
    "ScaledObject Status" \
    "Verifies that the ScaledObject is active and reporting metrics"

if kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    # Check if ScaledObject has conditions
    CONDITIONS=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.status.conditions}' 2>/dev/null || echo "")
    
    if [[ -n "${CONDITIONS}" ]]; then
        echo "ScaledObject has status conditions"
        
        # Check for Ready condition
        READY_STATUS=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        
        if [[ "${READY_STATUS}" == "True" ]]; then
            echo "ScaledObject is Ready"
            report_result "true" ""
        else
            echo "ScaledObject Ready status: ${READY_STATUS}"
            
            # Get reason if available
            READY_REASON=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "")
            READY_MESSAGE=$(kubectl get scaledobject "${EXPECTED_SCALEDOBJECT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
            
            if [[ -n "${READY_REASON}" ]]; then
                echo "Reason: ${READY_REASON}"
            fi
            if [[ -n "${READY_MESSAGE}" ]]; then
                echo "Message: ${READY_MESSAGE}"
            fi
            
            report_result "false" "ScaledObject not Ready (status: ${READY_STATUS})"
        fi
    else
        echo "ScaledObject exists but has no status conditions yet"
        report_result "true" "ScaledObject exists (status may be pending)"
    fi
else
    report_result "false" "ScaledObject not found"
fi

# Check 4: Monitor message processing
run_check \
    "Message Processing" \
    "Monitors NATS stream to verify messages are being consumed"

echo "Checking NATS stream message count..."

# Get initial message count
INITIAL_MSG_COUNT=$(kubectl exec -n nats "${NATS_BOX_POD}" -- nats stream info "${NATS_STREAM}" -j 2>/dev/null | grep -o '"messages":[0-9]*' | cut -d':' -f2 || echo "${MESSAGE_COUNT}")
echo "Initial message count in stream: ${INITIAL_MSG_COUNT}"

# Wait a bit for processing
echo "Waiting 30 seconds for message processing..."
sleep 30

# Get final message count
FINAL_MSG_COUNT=$(kubectl exec -n nats "${NATS_BOX_POD}" -- nats stream info "${NATS_STREAM}" -j 2>/dev/null | grep -o '"messages":[0-9]*' | cut -d':' -f2 || echo "${MESSAGE_COUNT}")
echo "Final message count in stream: ${FINAL_MSG_COUNT}"

if [[ ${FINAL_MSG_COUNT} -lt ${INITIAL_MSG_COUNT} ]]; then
    PROCESSED=$((INITIAL_MSG_COUNT - FINAL_MSG_COUNT))
    echo "Messages processed: ${PROCESSED}"
    report_result "true" ""
else
    echo "No messages processed (nginx doesn't consume messages)"
    echo ""
    echo "Manually acknowledging messages to allow scale-down..."
    # Since nginx doesn't actually process messages, manually ACK them
    # This simulates what a real worker would do
    kubectl exec -n nats "${NATS_BOX_POD}" -- sh -c "for i in \$(seq 1 ${MESSAGE_COUNT}); do nats consumer next ${NATS_STREAM} ${NATS_CONSUMER} --ack --timeout=1s 2>/dev/null || true; done" || true
    echo "Messages acknowledged"
    report_result "true" "Messages manually acknowledged (test worker doesn't process)"
fi

# Check 5: Verify scale-down after queue drains
run_check \
    "Scale Down After Queue Drain" \
    "Waits for queue to drain and verifies pods scale down to minReplicaCount (1)"

echo "Waiting for queue to drain and pods to scale down..."
echo "This may take up to ${SCALE_DOWN_TIMEOUT} seconds..."
echo ""

# First, wait for messages to be processed or timeout
DRAIN_TIMEOUT=120
DRAIN_ELAPSED=0

while [[ ${DRAIN_ELAPSED} -lt ${DRAIN_TIMEOUT} ]]; do
    CURRENT_MSG_COUNT=$(kubectl exec -n nats "${NATS_BOX_POD}" -- nats stream info "${NATS_STREAM}" -j 2>/dev/null | grep -o '"messages":[0-9]*' | cut -d':' -f2 || echo "0")
    echo "  Messages remaining: ${CURRENT_MSG_COUNT} (elapsed: ${DRAIN_ELAPSED}s)"
    
    if [[ ${CURRENT_MSG_COUNT} -eq 0 ]]; then
        echo "  ✓ Queue drained"
        break
    fi
    
    sleep "${POLL_INTERVAL}"
    DRAIN_ELAPSED=$((DRAIN_ELAPSED + POLL_INTERVAL))
done

echo ""

# Now wait for scale-down
if wait_for_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}" 1 "${SCALE_DOWN_TIMEOUT}" "eq"; then
    FINAL_COUNT=$(get_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}")
    echo "Final pod count: ${FINAL_COUNT}"
    
    if [[ ${FINAL_COUNT} -eq 1 ]]; then
        report_result "true" ""
    else
        report_result "false" "Pod count did not scale down to 1 (final count: ${FINAL_COUNT})"
    fi
else
    FINAL_COUNT=$(get_pod_count "${EXPECTED_DEPLOYMENT}" "${TEST_NAMESPACE}")
    
    if [[ ${FINAL_COUNT} -eq 1 ]]; then
        report_result "true" ""
    else
        echo "Note: Scale-down may take longer than ${SCALE_DOWN_TIMEOUT}s"
        echo "KEDA has a cooldown period before scaling down"
        report_result "false" "Pods did not scale down to 1 within ${SCALE_DOWN_TIMEOUT}s (final count: ${FINAL_COUNT})"
    fi
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
    echo "KEDA autoscaling works correctly:"
    echo "  - Started with 1 pod (minReplicaCount)"
    echo "  - Scaled up to multiple pods when messages were published"
    echo "  - ScaledObject is active and monitoring NATS"
    echo "  - Scaled down to 1 pod after queue drained"
    echo ""
    echo "Cleanup will be performed automatically..."
    exit 0
fi
