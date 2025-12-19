#!/bin/bash
# Disable Cilium for Kind clusters (use Kind's default CNI instead)
# Kind clusters work better with kindnet than Cilium for port-forward stability

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

FORCE_UPDATE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_UPDATE=true
fi

# Check if this is Kind cluster
IS_KIND_CLUSTER=false

if [ "$FORCE_UPDATE" = true ]; then
    IS_KIND_CLUSTER=true
elif command -v kubectl > /dev/null 2>&1 && kubectl cluster-info > /dev/null 2>&1; then
    # Check if running on Kind cluster (no control-plane taints on nodes)
    if ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' 2>/dev/null | grep -q "control-plane"; then
        IS_KIND_CLUSTER=true
    fi
fi

if [ "$IS_KIND_CLUSTER" = true ]; then
    echo -e "${BLUE}Disabling Cilium for Kind cluster (using kindnet instead)...${NC}"
    
    CILIUM_APP="$PLATFORM_ROOT/platform/01-foundation/cilium.yaml"
    
    if [ -f "$CILIUM_APP" ]; then
        # Rename the file to prevent ArgoCD from finding it
        mv "$CILIUM_APP" "$CILIUM_APP.disabled"
        
        # Also delete the ArgoCD application if it exists
        if kubectl get application cilium -n argocd >/dev/null 2>&1; then
            echo -e "${BLUE}Deleting existing Cilium ArgoCD application...${NC}"
            kubectl delete application cilium -n argocd --ignore-not-found=true
        fi
        
        echo -e "${GREEN}✓${NC} Cilium application disabled for Kind cluster"
        echo -e "${YELLOW}ℹ${NC} Kind will use its default CNI (kindnet) instead"
        echo -e "${YELLOW}ℹ${NC} This should resolve port-forward stability issues"
        
        # Also remove any existing Cilium installation
        if kubectl get namespace kube-system >/dev/null 2>&1; then
            echo -e "${BLUE}Removing existing Cilium installation...${NC}"
            
            # Remove all Cilium DaemonSets
            kubectl delete daemonset cilium cilium-envoy -n kube-system --ignore-not-found=true
            
            # Remove all Cilium Deployments
            kubectl delete deployment cilium-operator -n kube-system --ignore-not-found=true
            
            # Remove Cilium ConfigMaps
            kubectl delete configmap cilium-config -n kube-system --ignore-not-found=true
            
            # Remove Cilium Services
            kubectl delete service cilium-agent cilium-operator-metrics -n kube-system --ignore-not-found=true
            
            # Remove Cilium ServiceAccounts
            kubectl delete serviceaccount cilium cilium-operator -n kube-system --ignore-not-found=true
            
            # Remove Cilium ClusterRoles and ClusterRoleBindings
            kubectl delete clusterrole cilium cilium-operator --ignore-not-found=true
            kubectl delete clusterrolebinding cilium cilium-operator --ignore-not-found=true
            
            # Force delete any remaining Cilium pods
            kubectl delete pods -n kube-system -l k8s-app=cilium --force --grace-period=0 --ignore-not-found=true
            kubectl delete pods -n kube-system -l io.cilium/app=operator --force --grace-period=0 --ignore-not-found=true
            
            echo -e "${GREEN}✓${NC} Existing Cilium components removed"
        fi
    else
        echo -e "${YELLOW}⊘${NC} Cilium application not found: $CILIUM_APP"
    fi
    
    echo -e "${GREEN}✓ Cilium disabled for Kind cluster${NC}"
else
    echo -e "${YELLOW}Not a Kind cluster - keeping Cilium enabled${NC}"
fi

exit 0