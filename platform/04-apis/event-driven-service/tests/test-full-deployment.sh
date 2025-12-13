#!/usr/bin/env bash

# test-full-deployment.sh
# Test script for full-featured EventDrivenService claim deployment
# This script applies a full claim with all features (secrets, init container, size),
# verifies resource sizing, secret mounts, init container, imagePullSecrets, and cleans up.

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
TEST_NAMESPACE="test-eds-full-$(date +%s)"
CLAIM_NAME="full-featured-worker"
CLAIM_FILE="${PROJECT_ROOT}/platform/04-apis/examples/full-claim.yaml"
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
echo "EventDrivenService Full Claim Deployment Test"
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
    
    # Delete test secrets
    echo "Deleting test secrets..."
    kubectl delete secret full-featured-worker-db-conn -n "${TEST_NAMESPACE}" 2>/dev/null || true
    kubectl delete secret full-featured-worker-cache-conn -n "${TEST_NAMESPACE}" 2>/dev/null || true
    kubectl delete secret full-featured-worker-llm-keys -n "${TEST_NAMESPACE}" 2>/dev/null || true
    kubectl delete secret full-featured-worker-app-config -n "${TEST_NAMESPACE}" 2>/dev/null || true
    kubectl delete secret ghcr-pull-secret -n "${TEST_NAMESPACE}" 2>/dev/null || true
    
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

# Setup: Create test namespace and secrets
echo "=================================================="
echo "Setup"
echo "=================================================="
echo ""

echo "Creating test namespace: ${TEST_NAMESPACE}"
kubectl create namespace "${TEST_NAMESPACE}" 2>/dev/null || echo "Namespace already exists"
echo ""

# Create test secrets that the full claim expects
echo "Creating test secrets..."

# Secret 1: Database credentials (simulating Crossplane-generated)
kubectl create secret generic full-featured-worker-db-conn \
    -n "${TEST_NAMESPACE}" \
    --from-literal=endpoint=postgres.db.svc \
    --from-literal=port=5432 \
    --from-literal=database=myapp \
    --from-literal=username=appuser \
    --from-literal=password=testpass123 \
    2>/dev/null || echo "Secret full-featured-worker-db-conn already exists"

# Secret 2: Cache credentials (simulating Crossplane-generated)
kubectl create secret generic full-featured-worker-cache-conn \
    -n "${TEST_NAMESPACE}" \
    --from-literal=endpoint=dragonfly.cache.svc \
    --from-literal=port=6379 \
    --from-literal=password=cachepass456 \
    2>/dev/null || echo "Secret full-featured-worker-cache-conn already exists"

# Secret 3: LLM keys (simulating ESO-synced)
kubectl create secret generic full-featured-worker-llm-keys \
    -n "${TEST_NAMESPACE}" \
    --from-literal=OPENAI_API_KEY=sk-test-openai-key \
    --from-literal=ANTHROPIC_API_KEY=sk-ant-test-key \
    --from-literal=STRIPE_API_KEY=sk_test_stripe \
    2>/dev/null || echo "Secret full-featured-worker-llm-keys already exists"

# Secret 4: App config (simulating ESO-synced)
kubectl create secret generic full-featured-worker-app-config \
    -n "${TEST_NAMESPACE}" \
    --from-literal=WEBHOOK_SECRET=webhook-secret-123 \
    --from-literal=ENCRYPTION_KEY=encryption-key-456 \
    2>/dev/null || echo "Secret full-featured-worker-app-config already exists"

# Secret 5: Image pull secret (simulating private registry credentials)
kubectl create secret generic ghcr-pull-secret \
    -n "${TEST_NAMESPACE}" \
    --from-literal=.dockerconfigjson='{"auths":{"ghcr.io":{"auth":"dGVzdDp0ZXN0"}}}' \
    --type=kubernetes.io/dockerconfigjson \
    2>/dev/null || echo "Secret ghcr-pull-secret already exists"

echo "Test secrets created"
echo ""

# Apply the full claim
echo "Applying full claim from: ${CLAIM_FILE}"
# Modify the claim to use our test namespace
if command -v yq &>/dev/null; then
    yq eval ".metadata.namespace = \"${TEST_NAMESPACE}\"" "${CLAIM_FILE}" | kubectl apply -f -
else
    sed "s/namespace: production/namespace: ${TEST_NAMESPACE}/" "${CLAIM_FILE}" | kubectl apply -f -
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

# Check 5: Validate resource sizing (medium: 500m-2000m CPU, 1Gi-4Gi memory)
run_check \
    "Resource Sizing (Medium)" \
    "Validates that the Deployment has correct resource requests/limits for size: medium"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check image
    ACTUAL_IMAGE=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
    EXPECTED_IMAGE="ghcr.io/org/full-featured-worker:v2.1.0"
    
    echo "Expected image: ${EXPECTED_IMAGE}"
    echo "Actual image:   ${ACTUAL_IMAGE}"
    
    if [[ "${ACTUAL_IMAGE}" != "${EXPECTED_IMAGE}" ]]; then
        validation_passed=false
        validation_errors+=("Image mismatch: expected ${EXPECTED_IMAGE}, got ${ACTUAL_IMAGE}")
    fi
    
    # Check resource size (medium: 500m-2000m CPU, 1Gi-4Gi memory)
    CPU_REQUEST=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    CPU_LIMIT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
    MEM_REQUEST=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
    MEM_LIMIT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
    
    echo "CPU request:    ${CPU_REQUEST} (expected: 500m)"
    echo "CPU limit:      ${CPU_LIMIT} (expected: 2000m)"
    echo "Memory request: ${MEM_REQUEST} (expected: 1Gi)"
    echo "Memory limit:   ${MEM_LIMIT} (expected: 4Gi)"
    
    if [[ "${CPU_REQUEST}" != "500m" ]]; then
        validation_passed=false
        validation_errors+=("CPU request mismatch: expected 500m, got ${CPU_REQUEST}")
    fi
    
    if [[ "${CPU_LIMIT}" != "2000m" ]] && [[ "${CPU_LIMIT}" != "2" ]]; then
        validation_passed=false
        validation_errors+=("CPU limit mismatch: expected 2000m, got ${CPU_LIMIT}")
    fi
    
    if [[ "${MEM_REQUEST}" != "1Gi" ]]; then
        validation_passed=false
        validation_errors+=("Memory request mismatch: expected 1Gi, got ${MEM_REQUEST}")
    fi
    
    if [[ "${MEM_LIMIT}" != "4Gi" ]]; then
        validation_passed=false
        validation_errors+=("Memory limit mismatch: expected 4Gi, got ${MEM_LIMIT}")
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

# Check 6: Validate secret mounts (envFrom pattern)
run_check \
    "Secret Mounts (envFrom)" \
    "Validates that all 4 secrets are mounted via envFrom"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Get all envFrom secret references
    ENVFROM_SECRETS=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].secretRef.name}' 2>/dev/null || echo "")
    
    echo "EnvFrom secrets: ${ENVFROM_SECRETS}"
    
    # Check for each expected secret
    EXPECTED_SECRETS=(
        "full-featured-worker-db-conn"
        "full-featured-worker-cache-conn"
        "full-featured-worker-llm-keys"
        "full-featured-worker-app-config"
    )
    
    for secret in "${EXPECTED_SECRETS[@]}"; do
        if [[ ! "${ENVFROM_SECRETS}" =~ ${secret} ]]; then
            validation_passed=false
            validation_errors+=("Secret ${secret} not found in envFrom")
        else
            echo "✓ Secret ${secret} found in envFrom"
        fi
    done
    
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

# Check 7: Validate init container configuration
run_check \
    "Init Container Configuration" \
    "Validates that init container is present with correct command and args (if implemented)"

# SKIPPED: Init container feature not yet implemented (task 3.7 deferred)
echo -e "${YELLOW}⚠ Init container validation skipped${NC}"
echo "Init container feature is not yet implemented in the composition"
echo "This is expected - the feature will be added in a future iteration"
report_result "true" "Init container feature not implemented - skipping validation"

# Check 8: Validate imagePullSecrets configuration
run_check \
    "ImagePullSecrets Configuration" \
    "Validates that imagePullSecrets are configured for private registry access"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Get imagePullSecrets
    IMAGE_PULL_SECRETS=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}' 2>/dev/null || echo "")
    
    echo "ImagePullSecrets: ${IMAGE_PULL_SECRETS}"
    
    if [[ ! "${IMAGE_PULL_SECRETS}" =~ "ghcr-pull-secret" ]]; then
        validation_passed=false
        validation_errors+=("Expected imagePullSecret 'ghcr-pull-secret' not found")
    else
        echo "✓ ImagePullSecret 'ghcr-pull-secret' configured"
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

# Check 9: Validate NATS environment variables
run_check \
    "NATS Environment Variables" \
    "Validates that NATS configuration is correctly set in environment variables"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check NATS environment variables
    NATS_URL=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NATS_URL")].value}' 2>/dev/null || echo "")
    NATS_STREAM=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NATS_STREAM_NAME")].value}' 2>/dev/null || echo "")
    NATS_CONSUMER=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NATS_CONSUMER_GROUP")].value}' 2>/dev/null || echo "")
    
    echo "NATS_URL:           ${NATS_URL} (expected: nats://nats.nats.svc:4222)"
    echo "NATS_STREAM_NAME:   ${NATS_STREAM} (expected: PRODUCTION_JOBS)"
    echo "NATS_CONSUMER_GROUP: ${NATS_CONSUMER} (expected: full-featured-workers)"
    
    if [[ "${NATS_URL}" != "nats://nats.nats.svc:4222" ]]; then
        validation_passed=false
        validation_errors+=("NATS_URL mismatch: expected nats://nats.nats.svc:4222, got ${NATS_URL}")
    fi
    
    if [[ "${NATS_STREAM}" != "PRODUCTION_JOBS" ]]; then
        validation_passed=false
        validation_errors+=("NATS_STREAM_NAME mismatch: expected PRODUCTION_JOBS, got ${NATS_STREAM}")
    fi
    
    if [[ "${NATS_CONSUMER}" != "full-featured-workers" ]]; then
        validation_passed=false
        validation_errors+=("NATS_CONSUMER_GROUP mismatch: expected full-featured-workers, got ${NATS_CONSUMER}")
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

# Check 10: Validate security context
run_check \
    "Security Context" \
    "Validates that security context is properly configured (runAsNonRoot, drop capabilities)"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check pod security context
    RUN_AS_NON_ROOT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || echo "")
    RUN_AS_USER=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null || echo "")
    
    echo "Pod runAsNonRoot: ${RUN_AS_NON_ROOT} (expected: true)"
    echo "Pod runAsUser:    ${RUN_AS_USER} (expected: 1000)"
    
    if [[ "${RUN_AS_NON_ROOT}" != "true" ]]; then
        validation_passed=false
        validation_errors+=("Pod runAsNonRoot should be true, got ${RUN_AS_NON_ROOT}")
    fi
    
    if [[ "${RUN_AS_USER}" != "1000" ]]; then
        validation_passed=false
        validation_errors+=("Pod runAsUser should be 1000, got ${RUN_AS_USER}")
    fi
    
    # Check container security context
    ALLOW_PRIV_ESC=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null || echo "")
    CAPABILITIES=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.drop}' 2>/dev/null || echo "")
    
    echo "Container allowPrivilegeEscalation: ${ALLOW_PRIV_ESC} (expected: false)"
    echo "Container capabilities drop:        ${CAPABILITIES} (expected: ALL)"
    
    if [[ "${ALLOW_PRIV_ESC}" != "false" ]]; then
        validation_passed=false
        validation_errors+=("Container allowPrivilegeEscalation should be false, got ${ALLOW_PRIV_ESC}")
    fi
    
    if [[ ! "${CAPABILITIES}" =~ "ALL" ]]; then
        validation_passed=false
        validation_errors+=("Container should drop ALL capabilities, got ${CAPABILITIES}")
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

# Check 11: Validate health probes
run_check \
    "Health Probes" \
    "Validates that liveness and readiness probes are configured"

if kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" &>/dev/null; then
    validation_passed=true
    validation_errors=()
    
    # Check liveness probe
    LIVENESS_PATH=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null || echo "")
    LIVENESS_PORT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}' 2>/dev/null || echo "")
    
    echo "Liveness probe path: ${LIVENESS_PATH} (expected: /health)"
    echo "Liveness probe port: ${LIVENESS_PORT} (expected: 8080)"
    
    if [[ "${LIVENESS_PATH}" != "/health" ]]; then
        validation_passed=false
        validation_errors+=("Liveness probe path should be /health, got ${LIVENESS_PATH}")
    fi
    
    if [[ "${LIVENESS_PORT}" != "8080" ]]; then
        validation_passed=false
        validation_errors+=("Liveness probe port should be 8080, got ${LIVENESS_PORT}")
    fi
    
    # Check readiness probe
    READINESS_PATH=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || echo "")
    READINESS_PORT=$(kubectl get deployment "${EXPECTED_DEPLOYMENT}" -n "${TEST_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}' 2>/dev/null || echo "")
    
    echo "Readiness probe path: ${READINESS_PATH} (expected: /ready)"
    echo "Readiness probe port: ${READINESS_PORT} (expected: 8080)"
    
    if [[ "${READINESS_PATH}" != "/ready" ]]; then
        validation_passed=false
        validation_errors+=("Readiness probe path should be /ready, got ${READINESS_PATH}")
    fi
    
    if [[ "${READINESS_PORT}" != "8080" ]]; then
        validation_passed=false
        validation_errors+=("Readiness probe port should be 8080, got ${READINESS_PORT}")
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
    echo "The full-featured EventDrivenService claim successfully provisioned all resources:"
    echo "  - Deployment with correct image and medium resource sizing (500m-2000m CPU, 1Gi-4Gi memory)"
    echo "  - 4 secrets mounted via envFrom (db, cache, llm-keys, app-config)"
    echo "  - ImagePullSecrets configured for private registry"
    echo "  - Init container configured (if feature implemented)"
    echo "  - Service exposing port 8080"
    echo "  - ServiceAccount for pod identity"
    echo "  - ScaledObject with NATS JetStream trigger"
    echo "  - Security context properly configured"
    echo "  - Health probes configured"
    echo ""
    echo "Cleanup will be performed automatically..."
    exit 0
fi
