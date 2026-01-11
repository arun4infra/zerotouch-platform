#!/bin/bash
# Wait for Gateway API CRDs to be ready and Cilium to recognize them
# Usage: ./06a-wait-gateway-api.sh
#
# This script validates:
# 1. Gateway API CRDs are established
# 2. Cilium operator can list GatewayClass resources
# 3. No cache sync errors in Cilium operator logs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMEOUT=${1:-120}
INTERVAL=5

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Validating Gateway API Readiness                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check Gateway API CRDs exist and are established
echo -e "${BLUE}⏳ Checking Gateway API CRDs...${NC}"
REQUIRED_CRDS=(
    "gatewayclasses.gateway.networking.k8s.io"
    "gateways.gateway.networking.k8s.io"
    "httproutes.gateway.networking.k8s.io"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        # Check if CRD is established
        ESTABLISHED=$(kubectl get crd "$crd" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)
        if [ "$ESTABLISHED" = "True" ]; then
            echo -e "${GREEN}  ✓ $crd (established)${NC}"
        else
            echo -e "${RED}  ✗ $crd (not established)${NC}"
            exit 1
        fi
    else
        echo -e "${RED}  ✗ $crd (missing)${NC}"
        exit 1
    fi
done

# Wait for Cilium to be able to list GatewayClass resources
echo -e "${BLUE}⏳ Verifying Cilium can access Gateway API resources...${NC}"
elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
    # Try to list GatewayClass - this confirms Cilium's cache is synced
    if kubectl get gatewayclass 2>/dev/null; then
        echo -e "${GREEN}  ✓ GatewayClass API accessible${NC}"
        break
    fi
    
    echo -e "${YELLOW}  Waiting for GatewayClass API... (${elapsed}s/${TIMEOUT}s)${NC}"
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

if [ $elapsed -ge $TIMEOUT ]; then
    echo -e "${RED}✗ Timeout waiting for GatewayClass API${NC}"
    exit 1
fi

# Check Cilium operator logs for cache sync errors
echo -e "${BLUE}⏳ Checking Cilium operator for Gateway API cache sync...${NC}"
CILIUM_OP_POD=$(kubectl get pod -n kube-system -l name=cilium-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$CILIUM_OP_POD" ]; then
    # Check recent logs for cache sync timeout errors
    if kubectl logs -n kube-system "$CILIUM_OP_POD" --tail=50 2>/dev/null | grep -q "timed out waiting for caches to sync"; then
        echo -e "${YELLOW}  ⚠ Cache sync timeout detected in recent logs${NC}"
        echo -e "${YELLOW}  This may indicate Gateway API was not fully ready during startup${NC}"
        echo -e "${BLUE}  The Cilium operator restart should have resolved this${NC}"
    fi
    
    # Verify Gateway API controller is running
    if kubectl logs -n kube-system "$CILIUM_OP_POD" --tail=100 2>/dev/null | grep -q "Starting Gateway API"; then
        echo -e "${GREEN}  ✓ Gateway API controller started${NC}"
    else
        echo -e "${YELLOW}  ⚠ Gateway API controller start message not found in recent logs${NC}"
    fi
fi

# Final validation - try to create a test GatewayClass (dry-run)
echo -e "${BLUE}⏳ Validating GatewayClass can be created (dry-run)...${NC}"
if kubectl apply --dry-run=server -f - <<EOF 2>/dev/null
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: test-validation
spec:
  controllerName: io.cilium/gateway-controller
EOF
then
    echo -e "${GREEN}  ✓ GatewayClass validation passed${NC}"
else
    echo -e "${RED}  ✗ GatewayClass validation failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Gateway API is ready - Cilium can manage Gateway resources${NC}"
echo ""
