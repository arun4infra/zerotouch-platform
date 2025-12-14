#!/bin/bash
# Verify storage provisioner for Kind clusters
# Note: Kind v1.34+ doesn't install local-path-provisioner by default
# We rely on ArgoCD to deploy it via 01-local-path-provisioner.yaml

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
    echo -e "${BLUE}Context: $CONTEXT${NC}"
    
    # Check if Kind's built-in provisioner exists (in kube-system namespace)
    KIND_PROVISIONER_EXISTS=false
    echo -e "${BLUE}Checking for Kind's built-in provisioner in kube-system namespace...${NC}"
    if kubectl get deployment -n kube-system local-path-provisioner >/dev/null 2>&1; then
        KIND_PROVISIONER_EXISTS=true
        REPLICAS=$(kubectl get deployment -n kube-system local-path-provisioner -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} Kind's built-in local-path-provisioner found in kube-system (replicas: $REPLICAS)"
        
        # Disable our ArgoCD Application to avoid conflicts
        LOCAL_PATH_APP="$REPO_ROOT/bootstrap/components/01-local-path-provisioner.yaml"
        if [ -f "$LOCAL_PATH_APP" ]; then
            mv "$LOCAL_PATH_APP" "$LOCAL_PATH_APP.disabled"
            echo -e "  ${BLUE}ℹ${NC} Disabled ArgoCD Application to avoid conflict with Kind's provisioner"
        fi
    else
        echo -e "  ${BLUE}ℹ${NC} Kind's built-in provisioner not found (Kind v1.34+ doesn't include it)"
        
        # Re-enable our ArgoCD Application if it was disabled
        LOCAL_PATH_APP_DISABLED="$REPO_ROOT/bootstrap/components/01-local-path-provisioner.yaml.disabled"
        if [ -f "$LOCAL_PATH_APP_DISABLED" ]; then
            mv "$LOCAL_PATH_APP_DISABLED" "${LOCAL_PATH_APP_DISABLED%.disabled}"
            echo -e "  ${GREEN}✓${NC} Re-enabled ArgoCD Application for local-path-provisioner"
        else
            echo -e "  ${BLUE}ℹ${NC} ArgoCD Application is enabled: $REPO_ROOT/bootstrap/components/01-local-path-provisioner.yaml"
        fi
        
        # Check if our ArgoCD-deployed provisioner exists
        echo -e "${BLUE}Checking for ArgoCD-deployed provisioner in local-path-storage namespace...${NC}"
        if kubectl get namespace local-path-storage >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} local-path-storage namespace exists"
            
            if kubectl get pods -n local-path-storage -l app.kubernetes.io/name=local-path-provisioner >/dev/null 2>&1; then
                POD_COUNT=$(kubectl get pods -n local-path-storage -l app.kubernetes.io/name=local-path-provisioner --no-headers 2>/dev/null | wc -l)
                POD_STATUS=$(kubectl get pods -n local-path-storage -l app.kubernetes.io/name=local-path-provisioner -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
                POD_NAME=$(kubectl get pods -n local-path-storage -l app.kubernetes.io/name=local-path-provisioner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "unknown")
                
                if [ "$POD_STATUS" = "Running" ]; then
                    echo -e "  ${GREEN}✓${NC} ArgoCD-deployed provisioner is running (pod: $POD_NAME, count: $POD_COUNT)"
                else
                    echo -e "  ${YELLOW}⚠${NC} ArgoCD-deployed provisioner status: $POD_STATUS (pod: $POD_NAME)"
                    # Show pod events for debugging
                    echo -e "${BLUE}Recent pod events:${NC}"
                    kubectl get events -n local-path-storage --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' | tail -5 || true
                fi
            else
                echo -e "  ${YELLOW}⚠${NC} No provisioner pods found in local-path-storage namespace"
                echo -e "  ${BLUE}ℹ${NC} Checking if ArgoCD Application exists..."
                if kubectl get application -n argocd local-path-provisioner >/dev/null 2>&1; then
                    APP_SYNC=$(kubectl get application -n argocd local-path-provisioner -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
                    APP_HEALTH=$(kubectl get application -n argocd local-path-provisioner -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
                    echo -e "  ${BLUE}ℹ${NC} ArgoCD Application status: Sync=$APP_SYNC, Health=$APP_HEALTH"
                else
                    echo -e "  ${YELLOW}⚠${NC} ArgoCD Application 'local-path-provisioner' not found yet"
                fi
            fi
        else
            echo -e "  ${BLUE}ℹ${NC} local-path-storage namespace doesn't exist yet"
            echo -e "  ${BLUE}ℹ${NC} ArgoCD will create it and deploy local-path-provisioner"
        fi
    fi
    
    # Check storage class
    echo -e "${BLUE}Checking storage class configuration...${NC}"
    if kubectl get storageclass local-path >/dev/null 2>&1; then
        PROVISIONER=$(kubectl get storageclass local-path -o jsonpath='{.provisioner}' 2>/dev/null || echo "unknown")
        IS_DEFAULT=$(kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null || echo "false")
        echo -e "  ${GREEN}✓${NC} local-path storage class exists (provisioner: $PROVISIONER, default: $IS_DEFAULT)"
        
        # Make it default if not already
        if [ "$IS_DEFAULT" != "true" ]; then
            echo -e "  ${BLUE}ℹ${NC} Setting local-path as default storage class..."
            kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
            echo -e "  ${GREEN}✓${NC} local-path set as default storage class"
        fi
        
        # Show all storage classes for context
        echo -e "${BLUE}All storage classes:${NC}"
        kubectl get storageclass -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,DEFAULT:.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class
    else
        echo -e "  ${YELLOW}⚠${NC} local-path storage class not found yet"
        if [ "$KIND_PROVISIONER_EXISTS" = true ]; then
            echo -e "  ${RED}✗${NC} Kind's provisioner exists but storage class is missing - this is unexpected"
            echo -e "${BLUE}Checking all storage classes:${NC}"
            kubectl get storageclass || echo "No storage classes found"
        else
            echo -e "  ${BLUE}ℹ${NC} Will be created by ArgoCD deployment"
            echo -e "${BLUE}Current storage classes:${NC}"
            kubectl get storageclass || echo "No storage classes found yet"
        fi
    fi
    
    echo -e "${GREEN}✓ Storage provisioner verification complete${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi
