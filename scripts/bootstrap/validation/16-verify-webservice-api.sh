#!/bin/bash
# Verify WebService Platform API
# Usage: ./16-verify-webservice-api.sh
#
# This script verifies:
# 1. platform-apis Application exists and is synced
# 2. WebService XRD (CRD) is installed
# 3. webservice Composition exists
# 4. Test claims can be validated
# 5. Database XRD integration works

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl retry function with shorter timeouts for validation
kubectl_retry() {
    local max_attempts=3
    local timeout=5
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying...${NC}" >&2
            sleep 1
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verifying WebService Platform API                         ║${NC}"
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

# 2. Verify WebService XRD (CRD) is installed
echo -e "${BLUE}Verifying WebService XRD...${NC}"

if kubectl_retry get crd xwebservices.platform.bizmatters.io &>/dev/null; then
    echo -e "${GREEN}✓ XRD 'xwebservices.platform.bizmatters.io' is installed${NC}"
    
    # Verify claim CRD also exists
    if kubectl_retry get crd webservices.platform.bizmatters.io &>/dev/null; then
        echo -e "${GREEN}✓ Claim CRD 'webservices.platform.bizmatters.io' is installed${NC}"
    else
        echo -e "${RED}✗ Claim CRD 'webservices.platform.bizmatters.io' not found${NC}"
        ((ERRORS++))
    fi
    
    # Verify XRD has correct API version
    API_VERSION=$(kubectl_retry get crd xwebservices.platform.bizmatters.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ "$API_VERSION" = "v1alpha1" ]; then
        echo -e "${GREEN}✓ XRD API version: v1alpha1${NC}"
    else
        echo -e "${YELLOW}⚠️  XRD API version: $API_VERSION (expected: v1alpha1)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ XRD 'xwebservices.platform.bizmatters.io' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/webservice/definitions/xwebservices.yaml is applied${NC}"
    ((ERRORS++))
fi

echo ""

# 3. Verify webservice Composition exists
echo -e "${BLUE}Verifying webservice Composition...${NC}"

if kubectl_retry get composition webservice &>/dev/null; then
    echo -e "${GREEN}✓ Composition 'webservice' exists${NC}"
    
    # Verify Composition references correct XRD
    COMPOSITE_TYPE=$(kubectl_retry get composition webservice -o jsonpath='{.spec.compositeTypeRef.kind}' 2>/dev/null)
    if [ "$COMPOSITE_TYPE" = "XWebService" ]; then
        echo -e "${GREEN}✓ Composition references correct XRD: XWebService${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition references: $COMPOSITE_TYPE (expected: XWebService)${NC}"
        ((WARNINGS++))
    fi
    
    # Count resource templates in Composition
    RESOURCE_COUNT=$(kubectl_retry get composition webservice -o json 2>/dev/null | jq '.spec.resources | length' 2>/dev/null)
    if [ "$RESOURCE_COUNT" = "5" ]; then
        echo -e "${GREEN}✓ Composition has 5 resource templates (ServiceAccount, PostgresInstance, Deployment, Service, HTTPRoute)${NC}"
    else
        echo -e "${YELLOW}⚠️  Composition has $RESOURCE_COUNT resource templates (expected: 5)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ Composition 'webservice' not found${NC}"
    echo -e "${BLUE}ℹ  Check if platform/04-apis/webservice/compositions/webservice-composition.yaml is applied${NC}"
    ((ERRORS++))
fi

echo ""

# 4. Verify Database XRD integration (optional - may not be installed yet)
echo -e "${BLUE}Verifying Database XRD integration...${NC}"

if kubectl_retry get crd xpostgresinstances.database.bizmatters.io &>/dev/null; then
    echo -e "${GREEN}✓ PostgresInstance XRD is available${NC}"
    
    # Verify claim CRD also exists
    if kubectl_retry get crd postgresinstances.database.bizmatters.io &>/dev/null; then
        echo -e "${GREEN}✓ PostgresInstance claim CRD is available${NC}"
    else
        echo -e "${YELLOW}⚠️  PostgresInstance claim CRD not found${NC}"
        echo -e "${BLUE}ℹ  This is optional - database features will be limited${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  PostgresInstance XRD not found${NC}"
    echo -e "${BLUE}ℹ  This is optional - WebService can work without database provisioning${NC}"
    echo -e "${BLUE}ℹ  To enable database features, install the database XRDs first${NC}"
    ((WARNINGS++))
fi

echo ""

# 5. Test claim validation using test fixtures
echo -e "${BLUE}Testing WebService claim validation...${NC}"

WEBSERVICE_DIR="platform/04-apis/webservice"

# Create temporary namespace for testing (if it doesn't exist)
kubectl create namespace test --dry-run=client -o yaml | kubectl apply -f - &>/dev/null || true

# Test valid minimal claim
if kubectl apply --dry-run=server -f "$WEBSERVICE_DIR/tests/fixtures/valid-minimal.yaml" &>/dev/null; then
    echo -e "${GREEN}✓ Minimal WebService claim validates successfully${NC}"
else
    echo -e "${RED}✗ Minimal WebService claim validation failed${NC}"
    ((ERRORS++))
fi

# Test valid full claim
if kubectl apply --dry-run=server -f "$WEBSERVICE_DIR/tests/fixtures/valid-full.yaml" &>/dev/null; then
    echo -e "${GREEN}✓ Full WebService claim validates successfully${NC}"
else
    echo -e "${RED}✗ Full WebService claim validation failed${NC}"
    ((ERRORS++))
fi

# Test invalid claim (missing image) - should fail
if kubectl apply --dry-run=server -f "$WEBSERVICE_DIR/tests/fixtures/invalid-missing-image.yaml" &>/dev/null; then
    echo -e "${RED}✗ Invalid WebService claim was accepted (should have been rejected)${NC}"
    ((ERRORS++))
else
    echo -e "${GREEN}✓ Invalid WebService claim correctly rejected${NC}"
fi

# Clean up temporary namespace
kubectl delete namespace test --ignore-not-found=true &>/dev/null || true

echo ""

# 6. Check Gateway API support
echo -e "${BLUE}Verifying Gateway API support...${NC}"

if kubectl_retry get crd httproutes.gateway.networking.k8s.io &>/dev/null; then
    echo -e "${GREEN}✓ HTTPRoute CRD is available${NC}"
    
    # Check for cilium-gateway (common gateway name)
    if kubectl_retry get gateway cilium-gateway -n default &>/dev/null; then
        echo -e "${GREEN}✓ Gateway 'cilium-gateway' exists in default namespace${NC}"
    else
        echo -e "${YELLOW}⚠️  Gateway 'cilium-gateway' not found in default namespace${NC}"
        echo -e "${BLUE}ℹ  WebService external ingress requires a Gateway to be configured${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  HTTPRoute CRD not found${NC}"
    echo -e "${BLUE}ℹ  WebService external ingress requires Gateway API to be installed${NC}"
    ((WARNINGS++))
fi

echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verification Summary                                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! WebService API is ready.${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Next steps:${NC}"
    echo "  - Validate example claims: ./platform/04-apis/webservice/scripts/validate-claim.sh platform/04-apis/webservice/examples/minimal-claim.yaml"
    echo "  - Test deployment: kubectl apply -f platform/04-apis/webservice/examples/minimal-claim.yaml"
    echo "  - Run test suite: ./platform/04-apis/webservice/scripts/validate-claim.sh --test"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  WebService API has $WARNINGS warning(s) but no errors${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Review warnings above and monitor the deployment${NC}"
    echo -e "${BLUE}ℹ  WebService will work for internal services, external ingress may need Gateway configuration${NC}"
    exit 0
else
    echo -e "${RED}✗ WebService API has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo -e "${BLUE}ℹ  Troubleshooting steps:${NC}"
    echo "  1. Check ArgoCD Application: kubectl describe application apis -n argocd"
    echo "  2. Check XRD status: kubectl get xrd xwebservices.platform.bizmatters.io"
    echo "  3. Check Composition: kubectl describe composition webservice"
    echo "  4. Verify database XRDs: kubectl get xrd xpostgresinstances.database.bizmatters.io"
    echo "  5. Review platform/04-apis/webservice/README.md for setup instructions"
    exit 1
fi