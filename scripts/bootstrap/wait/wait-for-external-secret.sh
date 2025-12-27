#!/bin/bash
# Wait for ExternalSecret to sync and create Kubernetes secret
# Usage: ./wait-for-external-secret.sh <secret-name> <namespace> [--timeout <seconds>]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TIMEOUT=120  # 2 minutes default
POLL_INTERVAL=2

# Parse arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <secret-name> <namespace> [--timeout <seconds>]"
    echo ""
    echo "Example: $0 ghcr-pull-secret intelligence-deepagents --timeout 120"
    exit 1
fi

SECRET_NAME="$1"
NAMESPACE="$2"
shift 2

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for ExternalSecret to Sync                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Secret: ${SECRET_NAME}${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}Timeout: ${TIMEOUT}s${NC}"
echo ""

ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if the Kubernetes secret exists (created by ExternalSecret)
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ Secret ${SECRET_NAME} is ready in namespace ${NAMESPACE}${NC}"
        exit 0
    fi
    
    # Show progress every 10 seconds
    if [ $((ELAPSED % 10)) -eq 0 ]; then
        echo -e "${YELLOW}⏳ Waiting for secret... (${ELAPSED}s / ${TIMEOUT}s)${NC}"
        
        # Check ExternalSecret status
        if kubectl get externalsecret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
            ES_STATUS=$(kubectl get externalsecret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
            ES_MESSAGE=$(kubectl get externalsecret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "No message")
            echo -e "   ExternalSecret status: ${ES_STATUS}"
            if [ "$ES_STATUS" != "SecretSynced" ]; then
                echo -e "   ${YELLOW}Message: ${ES_MESSAGE}${NC}"
            fi
        else
            echo -e "   ${YELLOW}ExternalSecret ${SECRET_NAME} not found in namespace ${NAMESPACE}${NC}"
        fi
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# Timeout reached - show diagnostics
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: Secret not ready after ${TIMEOUT}s                    ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}=== DIAGNOSTICS ===${NC}"
echo ""

# Check if ExternalSecret exists
echo -e "${BLUE}1. ExternalSecret Status:${NC}"
if kubectl get externalsecret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    kubectl get externalsecret "$SECRET_NAME" -n "$NAMESPACE" -o yaml
else
    echo -e "${RED}✗ ExternalSecret ${SECRET_NAME} not found in namespace ${NAMESPACE}${NC}"
fi
echo ""

# Check ClusterSecretStore
echo -e "${BLUE}2. ClusterSecretStore Status:${NC}"
if kubectl get clustersecretstore aws-parameter-store &>/dev/null; then
    kubectl get clustersecretstore aws-parameter-store -o yaml
else
    echo -e "${RED}✗ ClusterSecretStore aws-parameter-store not found${NC}"
fi
echo ""

# Check ESO pods
echo -e "${BLUE}3. External Secrets Operator Pods:${NC}"
if kubectl get namespace external-secrets &>/dev/null; then
    kubectl get pods -n external-secrets
    echo ""
    echo -e "${BLUE}ESO Logs (last 20 lines):${NC}"
    kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=20 2>/dev/null || echo "No logs available"
else
    echo -e "${RED}✗ external-secrets namespace not found${NC}"
fi
echo ""

# Check if secret exists (shouldn't, but check anyway)
echo -e "${BLUE}4. Kubernetes Secret Status:${NC}"
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}✓ Secret exists (this shouldn't happen if we timed out)${NC}"
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml
else
    echo -e "${RED}✗ Secret ${SECRET_NAME} not found in namespace ${NAMESPACE}${NC}"
fi
echo ""

echo -e "${YELLOW}Manual debug commands:${NC}"
echo "  kubectl get externalsecret ${SECRET_NAME} -n ${NAMESPACE} -o yaml"
echo "  kubectl describe externalsecret ${SECRET_NAME} -n ${NAMESPACE}"
echo "  kubectl get clustersecretstore aws-parameter-store -o yaml"
echo "  kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50"
echo ""

exit 1
