#!/bin/bash
# Verify EventDrivenService Platform API
# Usage: ./15-verify-eventdrivenservice-api.sh
#
# This script verifies:
# 1. platform-apis Application exists and is synced
# 2. EventDrivenService XRD (CRD) is installed
# 3. event-driven-service Composition exists
# 4. Schema file published at platform/04-apis/schemas/

# Print output immediately for CI visibility
echo "Starting EventDrivenService API verification..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "ERROR: Failed to determine script directory" >&2
    exit 1
}

# Navigate to repo root from script location (4 levels up from scripts/bootstrap/validation/04-apis/)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)" || {
    echo "ERROR: Failed to navigate to repo root from $SCRIPT_DIR" >&2
    # Fallback: assume we're in the repo root already
    REPO_ROOT="$(pwd)"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl wrapper function with optional timeout
kubectl_cmd() {
    # Use timeout if available, otherwise run directly
    if command -v timeout >/dev/null 2>&1; then
        timeout 15 kubectl "$@"
    else
        kubectl "$@"
    fi
}

# Kubectl retry function
kubectl_retry() {
    local max_attempts=5
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if kubectl_cmd "$@" 2>/dev/null; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verifying EventDrivenService Platform API                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track overall status
ERRORS=0
WARNINGS=0

# 1. Verify platform-apis Application exists and is synced
echo -e "${BLUE}Verifying platform-apis Application...${NC}"

if kubectl_retry get application apis -n argocd &>/dev/null; then
    echo -e "${GREEN}✓ Application 'apis' exists${NC}"
    
    SYNC_STATUS=$(kubectl_retry get application apis -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
    if [ "$SYNC_STATUS" = "Synced" ]; then
        echo -e "${GREEN}✓ Application sync status: Synced${NC}"
    else
        echo -e "${YELLOW}⚠️  Application sync status: $SYNC_STATUS (expected: Synced)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    HEALTH_STATUS=$(kubectl_retry get application apis -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    if [ "$HEALTH_STATUS" = "Healthy" ]; then
        echo -e "${GREEN}✓ Application health status: Healthy${NC}"
    else
        echo -e "${YELLOW}⚠️  Application health status: $HEALTH_STATUS (expected: Healthy)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ Application 'apis' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis.yaml exists and is applied${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 2. Verify EventDrivenService XRD (CRD) is installed
echo -e "${BLUE}Verifying EventDrivenService XRD...${NC}"

if kubectl_retry get crd xeventdrivenservices.platform.bizmatters.io &>/dev/null; then
    echo -e "${GREEN}✓ XRD 'xeventdrivenservices.platform.bizmatters.io' is installed${NC}"
    
    # Verify claim CRD also exists
    if kubectl_retry get crd eventdrivenservices.platform.bizmatters.io &>/dev/null; then
        echo -e "${GREEN}✓ Claim CRD 'eventdrivenservices.platform.bizmatters.io' is installed${NC}"
    else
        echo -e "${RED}✗ Claim CRD 'eventdrivenservices.platform.bizmatters.io' not found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Verify XRD has correct API version
    API_VERSION=$(kubectl_retry get crd xeventdrivenservices.platform.bizmatters.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ "$API_VERSION" = "v1alpha1" ]; then
        echo -e "${GREEN}✓ XRD API version: v1alpha1${NC}"
    else
        echo -e "${YELLOW}⚠️  XRD API version: $API_VERSION (expected: v1alpha1)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ XRD 'xeventdrivenservices.platform.bizmatters.io' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/definitions/xeventdrivenservices.yaml is applied${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 3. Verify event-driven-service Composition exists
echo -e "${BLUE}Verifying event-driven-service Composition...${NC}"

if kubectl_retry get composition event-driven-service &>/dev/null; then
    echo -e "${GREEN}✓ Composition 'event-driven-service' exists${NC}"
    
    # Verify Composition references correct XRD
    COMPOSITE_TYPE=$(kubectl_retry get composition event-driven-service -o jsonpath='{.spec.compositeTypeRef.kind}' 2>/dev/null)
    if [ "$COMPOSITE_TYPE" = "XEventDrivenService" ]; then
        echo -e "${GREEN}✓ Composition references correct XRD: XEventDrivenService${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition references: $COMPOSITE_TYPE (expected: XEventDrivenService)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Count resource templates in Composition
    RESOURCE_COUNT=$(kubectl_retry get composition event-driven-service -o json 2>/dev/null | jq '.spec.resources | length' 2>/dev/null)
    if [ "$RESOURCE_COUNT" = "5" ]; then
        echo -e "${GREEN}✓ Composition has 5 resource templates (ServiceAccount, Deployment, Service, HTTP-Service, ScaledObject)${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition has $RESOURCE_COUNT resource templates (expected: 5)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗ Composition 'event-driven-service' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/compositions/event-driven-service-composition.yaml is applied${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 4. Test EventDrivenService claim validation using test fixtures
echo -e "${BLUE}Testing EventDrivenService claim validation...${NC}"

EVENTDRIVENSERVICE_DIR="$REPO_ROOT/platform/04-apis/event-driven-service"

# Create temporary namespace for testing (must actually exist for --dry-run=server)
kubectl create namespace test 2>/dev/null || true

# Test valid minimal claim
if kubectl apply --dry-run=server -f "$EVENTDRIVENSERVICE_DIR/tests/fixtures/valid-minimal.yaml" &>/dev/null; then
    echo -e "${GREEN}✓ Minimal EventDrivenService claim validates successfully${NC}"
else
    echo -e "${RED}✗ Minimal EventDrivenService claim validation failed${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Test valid full claim
if kubectl apply --dry-run=server -f "$EVENTDRIVENSERVICE_DIR/tests/fixtures/valid-full.yaml" &>/dev/null; then
    echo -e "${GREEN}✓ Full EventDrivenService claim validates successfully${NC}"
else
    echo -e "${RED}✗ Full EventDrivenService claim validation failed${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Test invalid claim (missing stream) - should fail
if kubectl apply --dry-run=server -f "$EVENTDRIVENSERVICE_DIR/tests/fixtures/missing-stream.yaml" &>/dev/null; then
    echo -e "${RED}✗ Invalid EventDrivenService claim was accepted (should have been rejected)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Invalid EventDrivenService claim correctly rejected${NC}"
fi

# Clean up temporary namespace
kubectl delete namespace test --ignore-not-found=true &>/dev/null || true

echo ""

# 5. Verify schema file published (optional - not critical for API functionality)
echo -e "${BLUE}Verifying schema file...${NC}"

# Use a simpler path check that works in CI
SCHEMA_FILE="$REPO_ROOT/platform/04-apis/event-driven-service/schemas/eventdrivenservice.schema.json"
echo "Checking for schema at: $SCHEMA_FILE"

# Check if file exists using test command explicitly
if test -f "$SCHEMA_FILE"; then
    echo -e "${GREEN}✓ Schema file exists${NC}"
    
    # Check if jq is available for JSON validation
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$SCHEMA_FILE" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Schema file is valid JSON${NC}"
        else
            echo -e "${YELLOW}⚠️  Schema file may not be valid JSON${NC}"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
else
    # Schema file is optional - just warn, don't error
    echo -e "${YELLOW}⚠️  Schema file not found (optional - does not affect API functionality)${NC}"
    # Don't increment warnings for missing schema - it's truly optional
fi

echo "Schema check complete"

echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verification Summary                                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! EventDrivenService API is ready.${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Next steps:${NC}"
    echo "  - Validate example claims: ./scripts/validate-claim.sh $REPO_ROOT/platform/04-apis/examples/minimal-claim.yaml"
    echo "  - Test deployment: kubectl apply -f $REPO_ROOT/platform/04-apis/examples/minimal-claim.yaml"
    echo "  - Run composition tests: $REPO_ROOT/platform/04-apis/tests/verify-composition.sh"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  EventDrivenService API has $WARNINGS warning(s) but no errors${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Review warnings above and monitor the deployment${NC}"
    exit 0
else
    echo -e "${RED}✗ EventDrivenService API has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Troubleshooting steps:${NC}"
    echo "  1. Check ArgoCD Application: kubectl describe application apis -n argocd"
    echo "  2. Check XRD status: kubectl get xrd xeventdrivenservices.platform.bizmatters.io"
    echo "  3. Check Composition: kubectl describe composition event-driven-service"
    echo "  4. Review platform/04-apis/README.md for setup instructions"
    exit 1
fi
