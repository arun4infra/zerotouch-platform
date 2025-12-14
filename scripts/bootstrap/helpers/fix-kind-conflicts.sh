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

# Fix 0: Verify NATS Application has correct storage class
# The NATS Application should have been pre-created with correct values in 01-master-bootstrap.sh
echo -e "${BLUE}Verifying NATS application storage class...${NC}"

if kubectl get application nats -n argocd &>/dev/null; then
    # Check current storage class in the Application spec
    CURRENT_SC=$(kubectl get application nats -n argocd -o jsonpath='{.spec.source.helm.valuesObject.config.jetstream.fileStore.pvc.storageClassName}' 2>/dev/null || echo "")
    echo -e "${BLUE}  Current NATS storageClassName in ArgoCD: ${CURRENT_SC:-not set}${NC}"
    
    if [ "$CURRENT_SC" = "local-path" ]; then
        echo -e "${YELLOW}  ⚠ NATS Application has wrong storage class, fixing...${NC}"
        
        # Delete any existing NATS resources with wrong storage class
        if kubectl get pvc nats-js-nats-0 -n nats &>/dev/null; then
            NATS_PVC_SC=$(kubectl get pvc nats-js-nats-0 -n nats -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
            if [ "$NATS_PVC_SC" = "local-path" ]; then
                echo -e "${BLUE}  Deleting NATS namespace to clean up wrong PVC...${NC}"
                kubectl delete namespace nats --wait=false 2>/dev/null || true
                for i in {1..60}; do
                    if ! kubectl get namespace nats &>/dev/null; then
                        echo -e "${GREEN}  ✓ NATS namespace deleted${NC}"
                        break
                    fi
                    sleep 1
                done
            fi
        fi
        
        # Patch the NATS Application directly
        echo -e "${BLUE}  Patching NATS Application...${NC}"
        kubectl patch application nats -n argocd --type=json -p='[
          {"op": "replace", "path": "/spec/source/helm/valuesObject/config/jetstream/fileStore/pvc/storageClassName", "value": "standard"}
        ]' 2>/dev/null && {
            echo -e "${GREEN}  ✓ NATS Application patched${NC}"
        } || {
            echo -e "${YELLOW}  Patch failed - Application may need manual intervention${NC}"
        }
        
        # Force sync
        kubectl patch application nats -n argocd --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
        
    elif [ "$CURRENT_SC" = "standard" ]; then
        echo -e "${GREEN}  ✓ NATS Application has correct storage class: standard${NC}"
    else
        echo -e "${YELLOW}  ⚠ NATS Application has unexpected storage class: ${CURRENT_SC:-empty}${NC}"
    fi
else
    echo -e "${BLUE}  NATS application doesn't exist yet${NC}"
fi

# Fix 1: Verify Kind's storage provisioner is working
echo -e "${BLUE}Checking Kind storage provisioner...${NC}"
if kubectl get storageclass standard &>/dev/null; then
    echo -e "${GREEN}  ✓ 'standard' StorageClass exists${NC}"
else
    echo -e "${YELLOW}  ⚠ 'standard' StorageClass not found - checking alternatives${NC}"
    kubectl get storageclass 2>/dev/null || true
fi

# Fix 2: Verify NATS PVC will use correct storage class
echo -e "${BLUE}Checking NATS PVC status...${NC}"
if kubectl get pvc nats-js-nats-0 -n nats &>/dev/null; then
    NATS_PVC_SC=$(kubectl get pvc nats-js-nats-0 -n nats -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    NATS_PVC_STATUS=$(kubectl get pvc nats-js-nats-0 -n nats -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    echo -e "${BLUE}  NATS PVC: storageClass=${NATS_PVC_SC}, status=${NATS_PVC_STATUS}${NC}"
    
    if [ "$NATS_PVC_SC" = "local-path" ]; then
        echo -e "${YELLOW}  ⚠ NATS PVC has wrong storage class - this should have been fixed above${NC}"
    else
        echo -e "${GREEN}  ✓ NATS PVC has correct storage class${NC}"
    fi
else
    echo -e "${BLUE}  NATS PVC not yet created (will be created with correct storage class)${NC}"
fi

# Fix 3: Check for other common Kind conflicts
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