#!/bin/bash
# Wait for Tenant Repository Credentials to Sync
# Usage: ./10b-wait-tenant-auth.sh [--timeout seconds]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Kubectl retry function
kubectl_retry() {
    local max_attempts=5
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl "$@" 2>/dev/null; then
            return 0
        fi
        sleep $((attempt * 2))
        attempt=$((attempt + 1))
    done
    return 1
}

TIMEOUT=180
ELAPSED=0
SECRET_NAME="repo-zerotouch-tenants"
NAMESPACE="argocd"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for Tenant Repository Authentication              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Secret: ${SECRET_NAME}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}Timeout: ${TIMEOUT}s${NC}"
echo ""

echo -e "${BLUE}⏳ Waiting for tenant credentials to sync from AWS SSM...${NC}"

while [ $ELAPSED -lt $TIMEOUT ]; do
    # 1. Check if the Kubernetes Secret exists
    if kubectl_retry get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        # 2. Check if it has the required ArgoCD label
        LABEL=$(kubectl_retry get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}' 2>/dev/null || echo "")
        
        if [ "$LABEL" == "repository" ]; then
            echo -e "${GREEN}✓ Secret '$SECRET_NAME' is ready and labeled for ArgoCD${NC}"
            
            # 3. Trigger a Hard Refresh on the dependent apps to clear "Auth Required" errors
            echo -e "${BLUE}Clearing ArgoCD cache for tenant apps...${NC}"
            kubectl_retry annotate app tenant-infrastructure -n argocd argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true
            kubectl_retry annotate appset tenant-applications -n argocd argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true
            
            echo ""
            exit 0
        fi
    fi

    # Detailed diagnostics every 20 seconds
    if [ $((ELAPSED % 20)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo -e "${YELLOW}⏳ Still waiting... (${ELAPSED}s / ${TIMEOUT}s)${NC}"
        
        # Check ExternalSecret status
        if kubectl_retry get externalsecret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
            ES_STATUS=$(kubectl_retry get externalsecret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
            ES_MESSAGE=$(kubectl_retry get externalsecret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "No message")
            echo -e "   ${CYAN}ExternalSecret status: ${ES_STATUS}${NC}"
            if [ "$ES_STATUS" != "SecretSynced" ]; then
                echo -e "   ${YELLOW}Message: ${ES_MESSAGE}${NC}"
            fi
        else
            echo -e "   ${YELLOW}ExternalSecret not found yet${NC}"
        fi
        
        # Check if secret exists (without label)
        if kubectl_retry get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
            echo -e "   ${YELLOW}Secret exists but missing ArgoCD label - checking...${NC}"
            LABELS=$(kubectl_retry get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")
            echo -e "   Labels: $LABELS"
        else
            echo -e "   ${YELLOW}Kubernetes secret not created yet${NC}"
        fi
        
        # Check ArgoCD Application wrapper status
        if kubectl_retry get application argocd-repo-registry-secret -n "$NAMESPACE" >/dev/null 2>&1; then
            APP_SYNC=$(kubectl_retry get application argocd-repo-registry-secret -n "$NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            APP_HEALTH=$(kubectl_retry get application argocd-repo-registry-secret -n "$NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
            echo -e "   ${CYAN}ArgoCD App (wrapper): $APP_SYNC / $APP_HEALTH${NC}"
        fi
        
        echo ""
    fi

    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

# Timeout reached - show comprehensive diagnostics
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: Tenant credentials not ready after ${TIMEOUT}s       ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}=== DIAGNOSTICS ===${NC}"
echo ""

# 1. ExternalSecret Status
echo -e "${BLUE}1. ExternalSecret Status:${NC}"
if kubectl_retry get externalsecret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl_retry get externalsecret "$SECRET_NAME" -n "$NAMESPACE" -o yaml
else
    echo -e "${RED}✗ ExternalSecret '$SECRET_NAME' not found in namespace '$NAMESPACE'${NC}"
fi
echo ""

# 2. ArgoCD Application wrapper status
echo -e "${BLUE}2. ArgoCD Application Wrapper Status:${NC}"
if kubectl_retry get application argocd-repo-registry-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl_retry describe application argocd-repo-registry-secret -n "$NAMESPACE"
else
    echo -e "${RED}✗ Application 'argocd-repo-registry-secret' not found${NC}"
fi
echo ""

# 3. Kubernetes Secret Status
echo -e "${BLUE}3. Kubernetes Secret Status:${NC}"
if kubectl_retry get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Secret exists but may be missing ArgoCD label${NC}"
    kubectl_retry get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml
else
    echo -e "${RED}✗ Secret '$SECRET_NAME' not found in namespace '$NAMESPACE'${NC}"
fi
echo ""

# 4. ClusterSecretStore Status
echo -e "${BLUE}4. ClusterSecretStore Status:${NC}"
if kubectl_retry get clustersecretstore aws-parameter-store >/dev/null 2>&1; then
    kubectl_retry describe clustersecretstore aws-parameter-store
else
    echo -e "${RED}✗ ClusterSecretStore 'aws-parameter-store' not found${NC}"
fi
echo ""

# 5. External Secrets Operator Status
echo -e "${BLUE}5. External Secrets Operator Pods:${NC}"
if kubectl_retry get namespace external-secrets >/dev/null 2>&1; then
    kubectl_retry get pods -n external-secrets -o wide
    echo ""
    echo -e "${BLUE}ESO Logs (last 30 lines):${NC}"
    kubectl_retry logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=30 2>/dev/null || echo "No logs available"
else
    echo -e "${RED}✗ external-secrets namespace not found${NC}"
fi
echo ""

# 6. Recent Events
echo -e "${BLUE}6. Recent Events in ArgoCD Namespace:${NC}"
kubectl_retry get events -n "$NAMESPACE" --sort-by='.lastTimestamp' --field-selector type=Warning 2>/dev/null | tail -10 || echo "No warning events found"
echo ""

# 7. Manual debug commands
echo -e "${YELLOW}=== TROUBLESHOOTING STEPS ===${NC}"
echo ""
echo "1. Verify AWS SSM Parameters exist:"
echo "   aws ssm get-parameters-by-path --path /zerotouch/prod/argocd/repos/zerotouch-tenants/ --region ap-south-1"
echo ""
echo "2. Check ExternalSecret details:"
echo "   kubectl get externalsecret $SECRET_NAME -n $NAMESPACE -o yaml"
echo "   kubectl describe externalsecret $SECRET_NAME -n $NAMESPACE"
echo ""
echo "3. Check ClusterSecretStore:"
echo "   kubectl describe clustersecretstore aws-parameter-store"
echo ""
echo "4. Check ESO logs:"
echo "   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100"
echo ""
echo "5. Verify ESO webhook is healthy:"
echo "   kubectl get pods -n external-secrets"
echo "   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets-webhook"
echo ""
echo "6. Check ArgoCD application wrapper:"
echo "   kubectl describe application argocd-repo-registry-secret -n argocd"
echo ""

exit 1
