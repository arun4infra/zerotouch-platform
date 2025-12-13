#!/usr/bin/env bash

# verify-composition.sh
# Verification script for EventDrivenService Composition structure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Expected values
COMPOSITION_NAME="event-driven-service"
XRD_API_VERSION="platform.bizmatters.io/v1alpha1"
XRD_KIND="XEventDrivenService"
EXPECTED_RESOURCES=("serviceaccount" "deployment" "service" "scaledobject")

# Check counters
CHECKS_RUN=0
CHECKS_PASSED=0
CHECKS_FAILED=0

# Failed checks array
declare -a FAILED_CHECKS

echo "=================================================="
echo "EventDrivenService Composition Verification"
echo "=================================================="
echo ""

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

# Check 1: Composition exists in cluster
run_check \
    "Composition Exists" \
    "Verifies that the event-driven-service Composition is installed in the cluster"

set +e
COMPOSITION_EXISTS=$(kubectl get composition "${COMPOSITION_NAME}" --ignore-not-found -o name 2>/dev/null)
set -e

if [[ -n "${COMPOSITION_EXISTS}" ]]; then
    echo "Found: ${COMPOSITION_EXISTS}"
    report_result "true" ""
else
    report_result "false" "Composition '${COMPOSITION_NAME}' not found in cluster"
    echo "Hint: Apply the composition with: kubectl apply -f platform/04-apis/compositions/event-driven-service-composition.yaml"
    echo ""
    echo "Exiting early - remaining checks require the Composition to exist"
    exit 1
fi

# Check 2: Composition references correct XRD
run_check \
    "XRD Reference" \
    "Verifies that the Composition references the correct XRD (${XRD_API_VERSION} ${XRD_KIND})"

ACTUAL_API_VERSION=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.compositeTypeRef.apiVersion}' 2>/dev/null || echo "")
ACTUAL_KIND=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.compositeTypeRef.kind}' 2>/dev/null || echo "")

echo "Expected API Version: ${XRD_API_VERSION}"
echo "Actual API Version:   ${ACTUAL_API_VERSION}"
echo "Expected Kind:        ${XRD_KIND}"
echo "Actual Kind:          ${ACTUAL_KIND}"
echo ""

if [[ "${ACTUAL_API_VERSION}" == "${XRD_API_VERSION}" ]] && [[ "${ACTUAL_KIND}" == "${XRD_KIND}" ]]; then
    report_result "true" ""
else
    report_result "false" "XRD reference mismatch. Expected ${XRD_API_VERSION}/${XRD_KIND}, got ${ACTUAL_API_VERSION}/${ACTUAL_KIND}"
fi

# Check 3: List all resource templates
run_check \
    "Resource Templates" \
    "Lists all resource templates defined in the Composition and verifies expected resources are present"

# Get all resource names from the composition
set +e
ACTUAL_RESOURCES=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.resources[*].name}' 2>/dev/null || echo "")
set -e

if [[ -z "${ACTUAL_RESOURCES}" ]]; then
    echo "No resources found in Composition"
    report_result "false" "Composition has no resource templates defined"
else
    echo "Resource templates found:"
    for resource in ${ACTUAL_RESOURCES}; do
        echo "  - ${resource}"
    done
    echo ""
    
    # Check if all expected resources are present
    all_present=true
    missing_resources=()
    
    for expected in "${EXPECTED_RESOURCES[@]}"; do
        if [[ ! " ${ACTUAL_RESOURCES} " =~ " ${expected} " ]]; then
            all_present=false
            missing_resources+=("${expected}")
        fi
    done
    
    if [[ "${all_present}" == "true" ]]; then
        echo "All expected resources are present (${#EXPECTED_RESOURCES[@]}/${#EXPECTED_RESOURCES[@]})"
        report_result "true" ""
    else
        echo "Missing resources:"
        for missing in "${missing_resources[@]}"; do
            echo "  - ${missing}"
        done
        report_result "false" "Not all expected resources are present. Missing: ${missing_resources[*]}"
    fi
fi

# Check 4: Verify resource template details
run_check \
    "Resource Template Details" \
    "Verifies that each resource template has the correct base configuration"

details_valid=true
details_errors=()

# Check ServiceAccount
SA_KIND=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.resources[?(@.name=="serviceaccount")].base.spec.forProvider.manifest.kind}' 2>/dev/null || echo "")
if [[ "${SA_KIND}" != "ServiceAccount" ]]; then
    details_valid=false
    details_errors+=("ServiceAccount resource has incorrect kind: ${SA_KIND}")
else
    echo "✓ ServiceAccount resource configured correctly"
fi

# Check Deployment
DEPLOY_KIND=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.resources[?(@.name=="deployment")].base.spec.forProvider.manifest.kind}' 2>/dev/null || echo "")
if [[ "${DEPLOY_KIND}" != "Deployment" ]]; then
    details_valid=false
    details_errors+=("Deployment resource has incorrect kind: ${DEPLOY_KIND}")
else
    echo "✓ Deployment resource configured correctly"
fi

# Check Service
SVC_KIND=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.resources[?(@.name=="service")].base.spec.forProvider.manifest.kind}' 2>/dev/null || echo "")
if [[ "${SVC_KIND}" != "Service" ]]; then
    details_valid=false
    details_errors+=("Service resource has incorrect kind: ${SVC_KIND}")
else
    echo "✓ Service resource configured correctly"
fi

# Check ScaledObject
SO_KIND=$(kubectl get composition "${COMPOSITION_NAME}" -o jsonpath='{.spec.resources[?(@.name=="scaledobject")].base.spec.forProvider.manifest.kind}' 2>/dev/null || echo "")
if [[ "${SO_KIND}" != "ScaledObject" ]]; then
    details_valid=false
    details_errors+=("ScaledObject resource has incorrect kind: ${SO_KIND}")
else
    echo "✓ ScaledObject resource configured correctly"
fi

echo ""

if [[ "${details_valid}" == "true" ]]; then
    report_result "true" ""
else
    error_msg=$(IFS="; "; echo "${details_errors[*]}")
    report_result "false" "${error_msg}"
fi

# Summary
echo "=================================================="
echo "Verification Summary"
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
    exit 1
else
    echo -e "${GREEN}✓ All verification checks passed!${NC}"
    echo ""
    echo "The EventDrivenService Composition is correctly configured with:"
    echo "  - Correct XRD reference (${XRD_API_VERSION}/${XRD_KIND})"
    echo "  - All 4 expected resource templates (ServiceAccount, Deployment, Service, ScaledObject)"
    echo "  - Proper resource template configurations"
    echo ""
    exit 0
fi
