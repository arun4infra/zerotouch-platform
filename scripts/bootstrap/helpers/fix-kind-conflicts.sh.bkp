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

# Fix 0: Preemptively delete NATS application to force recreation with patched values
echo -e "${BLUE}Checking if NATS application needs recreation...${NC}"
if kubectl get application nats -n argocd &>/dev/null; then
    echo -e "${YELLOW}  ⚠ NATS application exists - checking if it needs recreation${NC}"
    
    # Check if NATS namespace has resources
    if kubectl get namespace nats &>/dev/null; then
        # Check PVC storage class
        if kubectl get pvc nats-js-nats-0 -n nats &>/dev/null; then
            NATS_SC=$(kubectl get pvc nats-js-nats-0 -n nats -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
            if [ "$NATS_SC" = "local-path" ]; then
                echo -e "${YELLOW}  ⚠ NATS PVC has wrong storage class: $NATS_SC${NC}"
                echo -e "${BLUE}  Deleting NATS application and namespace for clean recreation...${NC}"
                
                # Delete application first (stops ArgoCD from recreating resources)
                kubectl delete application nats -n argocd --wait=false 2>/dev/null || true
                
                # Delete namespace (cascades to all resources)
                kubectl delete namespace nats --wait=false 2>/dev/null || true
                
                # Wait for deletion
                echo -e "${BLUE}  Waiting for cleanup (max 60s)...${NC}"
                for i in {1..60}; do
                    if ! kubectl get namespace nats &>/dev/null; then
                        echo -e "${GREEN}  ✓ NATS namespace deleted${NC}"
                        break
                    fi
                    sleep 1
                done
                
                # Force platform-bootstrap to recreate NATS with patched values
                echo -e "${BLUE}  Triggering platform-bootstrap refresh...${NC}"
                kubectl patch application platform-bootstrap -n argocd --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
                
                # Wait for NATS app to be recreated
                echo -e "${BLUE}  Waiting for NATS application recreation...${NC}"
                for i in {1..30}; do
                    if kubectl get application nats -n argocd &>/dev/null; then
                        echo -e "${GREEN}  ✓ NATS application recreated${NC}"
                        break
                    fi
                    sleep 2
                done
                
                echo -e "${GREEN}  ✓ NATS will be recreated with correct storage class${NC}"
            else
                echo -e "${GREEN}  ✓ NATS PVC has correct storage class: ${NATS_SC}${NC}"
            fi
        else
            echo -e "${BLUE}  NATS PVC not yet created${NC}"
        fi
    else
        echo -e "${BLUE}  NATS namespace doesn't exist yet${NC}"
    fi
else
    echo -e "${BLUE}  NATS application doesn't exist yet${NC}"
fi

# Fix 1: local-path-provisioner - SKIP deletion
# Kind comes with its own local-path-provisioner that works fine.
# We no longer deploy our own via ArgoCD in preview mode, so no conflict.
# The storage class 'standard' in Kind uses Kind's built-in provisioner.
echo -e "${BLUE}Checking local-path-provisioner...${NC}"
if kubectl get deployment local-path-provisioner -n local-path-storage &>/dev/null; then
    echo -e "${GREEN}  ✓ Kind's built-in local-path-provisioner is running${NC}"
    echo -e "${BLUE}  Using Kind's provisioner (not deploying our own in preview mode)${NC}"
else
    echo -e "${YELLOW}  ⚠ local-path-provisioner not found - storage may not work${NC}"
fi

# Fix 2: Clean up PVCs with wrong storage class
# If a PVC was created with 'local-path' but we need 'standard', delete it
# so it can be recreated with the correct storage class
echo -e "${BLUE}Checking for PVCs with wrong storage class...${NC}"

# Check NATS PVC specifically
if kubectl get pvc nats-js-nats-0 -n nats &>/dev/null; then
    NATS_SC=$(kubectl get pvc nats-js-nats-0 -n nats -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    if [ "$NATS_SC" = "local-path" ]; then
        echo -e "${YELLOW}  ⚠ Found NATS PVC with wrong storage class: $NATS_SC${NC}"
        echo -e "${BLUE}  Deleting PVC so it can be recreated with 'standard' storage class...${NC}"
        
        # Delete the StatefulSet first to release the PVC
        kubectl delete statefulset nats -n nats --ignore-not-found=true --wait=false 2>/dev/null || true
        
        # Delete the PVC
        kubectl delete pvc nats-js-nats-0 -n nats --ignore-not-found=true 2>/dev/null || true
        
        # Wait for PVC to be deleted (max 30 seconds)
        echo -e "${BLUE}  Waiting for PVC to be deleted...${NC}"
        for i in {1..30}; do
            if ! kubectl get pvc nats-js-nats-0 -n nats &>/dev/null; then
                echo -e "${GREEN}  ✓ PVC deleted${NC}"
                break
            fi
            sleep 1
        done
        
        # Force ArgoCD to re-sync the NATS application
        if kubectl get application nats -n argocd &>/dev/null; then
            echo -e "${BLUE}  Triggering ArgoCD re-sync for NATS...${NC}"
            kubectl patch application nats -n argocd --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
            
            # Also trigger a sync operation
            kubectl patch application nats -n argocd --type=merge -p '{"operation":{"initiatedBy":{"username":"fix-kind-conflicts"},"sync":{"revision":"HEAD"}}}' 2>/dev/null || true
        fi
        
        echo -e "${GREEN}  ✓ NATS PVC cleanup complete - will be recreated with correct storage class${NC}"
    else
        echo -e "${GREEN}  ✓ NATS PVC has correct storage class: ${NATS_SC:-standard}${NC}"
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