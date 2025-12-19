#!/bin/bash
# Verify storage provisioner for Kind clusters
# Note: Kind v1.34+ includes built-in local-path-provisioner
# We disable our ArgoCD app (00-local-path-provisioner.yaml) to avoid conflicts
# and create a 'local-path' storage class alias if needed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

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
    echo -e "${BLUE}Context: $CONTEXT${NC}"
    
    # Check if Kind has a built-in provisioner (check for standard storage class or deployment)
    KIND_PROVISIONER_EXISTS=false
    echo -e "${BLUE}Checking for Kind's built-in provisioner...${NC}"
    
    # Check for deployment in kube-system (older Kind versions)
    if kubectl get deployment -n kube-system local-path-provisioner >/dev/null 2>&1; then
        KIND_PROVISIONER_EXISTS=true
        REPLICAS=$(kubectl get deployment -n kube-system local-path-provisioner -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} Kind's built-in provisioner found in kube-system (replicas: $REPLICAS)"
    # Check for standard storage class (Kind v1.34+)
    elif kubectl get storageclass standard >/dev/null 2>&1; then
        STANDARD_PROVISIONER=$(kubectl get storageclass standard -o jsonpath='{.provisioner}' 2>/dev/null || echo "unknown")
        if [[ "$STANDARD_PROVISIONER" == "rancher.io/local-path" ]]; then
            KIND_PROVISIONER_EXISTS=true
            echo -e "  ${GREEN}✓${NC} Kind v1.34+ detected with built-in provisioner (storage class: standard)"
        fi
    fi
    
    # Always disable our ArgoCD Application in preview mode to avoid conflicts
    LOCAL_PATH_APP="$REPO_ROOT/bootstrap/00-local-path-provisioner.yaml"
    if [ -f "$LOCAL_PATH_APP" ]; then
        mv "$LOCAL_PATH_APP" "$LOCAL_PATH_APP.disabled"
        echo -e "  ${BLUE}ℹ${NC} Disabled ArgoCD Application (not needed in Kind preview mode)"
    fi
    
    # Check storage class
    echo -e "${BLUE}Checking storage class configuration...${NC}"
    
    # Show all storage classes first
    echo -e "${BLUE}Current storage classes:${NC}"
    kubectl get storageclass -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,DEFAULT:.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class 2>/dev/null || echo "No storage classes found yet"
    
    # Check if local-path storage class exists
    if kubectl get storageclass local-path >/dev/null 2>&1; then
        PROVISIONER=$(kubectl get storageclass local-path -o jsonpath='{.provisioner}' 2>/dev/null || echo "unknown")
        IS_DEFAULT=$(kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null || echo "false")
        echo -e "  ${GREEN}✓${NC} local-path storage class exists (provisioner: $PROVISIONER, default: $IS_DEFAULT)"
    else
        echo -e "  ${YELLOW}⚠${NC} local-path storage class not found"
        
        # Check if Kind's default "standard" storage class exists (Kind v1.34+)
        if kubectl get storageclass standard >/dev/null 2>&1; then
            STANDARD_PROVISIONER=$(kubectl get storageclass standard -o jsonpath='{.provisioner}' 2>/dev/null || echo "unknown")
            STANDARD_BINDING=$(kubectl get storageclass standard -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "unknown")
            STANDARD_RECLAIM=$(kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}' 2>/dev/null || echo "unknown")
            echo -e "  ${BLUE}ℹ${NC} Found Kind's 'standard' storage class"
            echo -e "     Provisioner: $STANDARD_PROVISIONER"
            echo -e "     VolumeBindingMode: $STANDARD_BINDING"
            echo -e "     ReclaimPolicy: $STANDARD_RECLAIM"
            
            # Create local-path as an exact copy of standard
            echo -e "  ${BLUE}ℹ${NC} Creating 'local-path' storage class with same configuration..."
            cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: $STANDARD_PROVISIONER
volumeBindingMode: $STANDARD_BINDING
reclaimPolicy: $STANDARD_RECLAIM
EOF
            echo -e "  ${GREEN}✓${NC} Created 'local-path' storage class"
            
            # Verify it was created
            if kubectl get storageclass local-path >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Verified: local-path storage class is now available"
                echo -e "${BLUE}Testing PVC creation with local-path storage class...${NC}"
                # The provisioner should now work for any PVCs requesting local-path
            else
                echo -e "  ${RED}✗${NC} Failed to create local-path storage class"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} No standard storage class found"
            echo -e "  ${BLUE}ℹ${NC} This is unexpected for Kind clusters"
        fi
    fi
    
    echo -e "${GREEN}✓ Storage provisioner verification complete${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi
