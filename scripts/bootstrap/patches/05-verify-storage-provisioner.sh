#!/bin/bash
# Verify and fix Kind's local-path-provisioner
# Kind should have this built-in, but sometimes it needs to be verified/restarted

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if this is preview mode
IS_PREVIEW_MODE=false
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    CONTEXT=$(kubectl config current-context)
    if [[ "$CONTEXT" == "kind-"* ]]; then
        IS_PREVIEW_MODE=true
    fi
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}Verifying local-path-provisioner for Kind cluster...${NC}"
    
    # Check if provisioner pod exists
    if kubectl get pods -n kube-system -l app=local-path-provisioner >/dev/null 2>&1; then
        POD_STATUS=$(kubectl get pods -n kube-system -l app=local-path-provisioner -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
        
        if [ "$POD_STATUS" = "Running" ]; then
            echo -e "  ${GREEN}✓${NC} local-path-provisioner pod is running"
        else
            echo -e "  ${YELLOW}⚠${NC} local-path-provisioner pod status: $POD_STATUS"
            echo -e "  ${BLUE}ℹ${NC} Attempting to restart provisioner..."
            kubectl delete pod -n kube-system -l app=local-path-provisioner --ignore-not-found=true
            sleep 5
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} local-path-provisioner pod not found"
    fi
    
    # Check storage class
    if kubectl get storageclass local-path >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} local-path storage class exists"
        
        # Make it default if not already
        IS_DEFAULT=$(kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null || echo "false")
        if [ "$IS_DEFAULT" != "true" ]; then
            echo -e "  ${BLUE}ℹ${NC} Setting local-path as default storage class..."
            kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
            echo -e "  ${GREEN}✓${NC} local-path set as default storage class"
        fi
    else
        echo -e "  ${RED}✗${NC} local-path storage class not found"
        echo -e "  ${YELLOW}⚠${NC} This is unexpected for Kind clusters"
    fi
    
    echo -e "${GREEN}✓ Storage provisioner verification complete${NC}"
fi
