#!/bin/bash
# Fix Common Kind Cluster Deployment Conflicts
# Usage: ./fix-kind-conflicts.sh
#
# This script fixes common issues in Kind clusters where existing deployments
# conflict with ArgoCD's desired state due to immutable fields.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Fixing Kind Cluster Deployment Conflicts                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Fix 1: local-path-provisioner immutable selector issue
echo -e "${BLUE}Checking local-path-provisioner deployment...${NC}"
if kubectl get deployment local-path-provisioner -n local-path-storage &>/dev/null; then
    echo -e "${YELLOW}  Found existing local-path-provisioner deployment${NC}"
    echo -e "${BLUE}  Deleting to allow ArgoCD to recreate with correct labels...${NC}"
    
    # Delete the deployment (but not the namespace or other resources)
    kubectl delete deployment local-path-provisioner -n local-path-storage --ignore-not-found=true
    
    # Wait a moment for deletion to complete
    sleep 5
    
    echo -e "${GREEN}  ✓ Deployment deleted${NC}"
else
    echo -e "${GREEN}  ✓ No conflicting deployment found${NC}"
fi

# Fix 2: Check for other common Kind conflicts
echo -e "${BLUE}Checking for other Kind deployment conflicts...${NC}"

# List of common Kind deployments that might conflict
COMMON_CONFLICTS=(
    "coredns:kube-system"
    "kindnet:kube-system"
)

for conflict in "${COMMON_CONFLICTS[@]}"; do
    IFS=':' read -r deployment namespace <<< "$conflict"
    
    if kubectl get deployment "$deployment" -n "$namespace" &>/dev/null; then
        # Check if it has ArgoCD annotations (managed by ArgoCD)
        ARGOCD_MANAGED=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/instance}' 2>/dev/null || echo "")
        
        if [ -n "$ARGOCD_MANAGED" ]; then
            echo -e "${YELLOW}  Found ArgoCD-managed deployment: $deployment in $namespace${NC}"
            echo -e "${BLUE}  This may need manual intervention if conflicts occur${NC}"
        fi
    fi
done

echo -e "${GREEN}✓ Kind conflict fixes complete${NC}"
echo ""