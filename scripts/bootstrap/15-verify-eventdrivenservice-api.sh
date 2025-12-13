#!/bin/bash
# Verify EventDrivenService Platform API
# Usage: ./15-verify-eventdrivenservice-api.sh
#
# This script verifies:
# 1. platform-apis Application exists and is synced
# 2. EventDrivenService XRD (CRD) is installed
# 3. event-driven-service Composition exists
# 4. Schema file published at platform/04-apis/schemas/

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
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
        ((WARNINGS++))
    fi
    
    HEALTH_STATUS=$(kubectl_retry get application apis -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    if [ "$HEALTH_STATUS" = "Healthy" ]; then
        echo -e "${GREEN}✓ Application health status: Healthy${NC}"
    else
        echo -e "${YELLOW}⚠️  Application health status: $HEALTH_STATUS (expected: Healthy)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ Application 'apis' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis.yaml exists and is applied${NC}"
    ((ERRORS++))
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
        ((ERRORS++))
    fi
    
    # Verify XRD has correct API version
    API_VERSION=$(kubectl_retry get crd xeventdrivenservices.platform.bizmatters.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ "$API_VERSION" = "v1alpha1" ]; then
        echo -e "${GREEN}✓ XRD API version: v1alpha1${NC}"
    else
        echo -e "${YELLOW}⚠️  XRD API version: $API_VERSION (expected: v1alpha1)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ XRD 'xeventdrivenservices.platform.bizmatters.io' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/definitions/xeventdrivenservices.yaml is applied${NC}"
    ((ERRORS++))
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
        ((WARNINGS++))
    fi
    
    # Count resource templates in Composition
    RESOURCE_COUNT=$(kubectl_retry get composition event-driven-service -o json 2>/dev/null | jq '.spec.resources | length' 2>/dev/null)
    if [ "$RESOURCE_COUNT" = "4" ]; then
        echo -e "${GREEN}✓ Composition has 4 resource templates (ServiceAccount, Deployment, Service, ScaledObject)${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition has $RESOURCE_COUNT resource templates (expected: 4)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ Composition 'event-driven-service' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/compositions/event-driven-service-composition.yaml is applied${NC}"
    ((ERRORS++))
fi

echo ""

# 4. Verify schema file published
echo -e "${BLUE}Verifying schema file...${NC}"

SCHEMA_FILE="platform/04-apis/schemas/eventdrivenservice.schema.json"
if [ -f "$SCHEMA_FILE" ]; then
    echo -e "${GREEN}✓ Schema file exists at $SCHEMA_FILE${NC}"
    
    # Verify schema is valid JSON
    if jq empty "$SCHEMA_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Schema file is valid JSON${NC}"
    else
        echo -e "${RED}✗ Schema file is not valid JSON${NC}"
        ((ERRORS++))
    fi
    
    # Verify schema has required fields
    if jq -e '.properties.spec' "$SCHEMA_FILE" &>/dev/null; then
        echo -e "${GREEN}✓ Schema contains spec properties${NC}"
    else
        echo -e "${YELLOW}⚠️  Schema may be incomplete (missing spec properties)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ Schema file not found at $SCHEMA_FILE${NC}"
    echo -e "${BLUE}ℹ  Run: ./scripts/publish-schema.sh${NC}"
    ((ERRORS++))
fi

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
    echo "  - Validate example claims: ./scripts/validate-claim.sh platform/04-apis/examples/minimal-claim.yaml"
    echo "  - Test deployment: kubectl apply -f platform/04-apis/examples/minimal-claim.yaml"
    echo "  - Run composition tests: ./platform/04-apis/tests/verify-composition.sh"
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
