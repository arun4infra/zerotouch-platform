#!/bin/bash
# Wait for Platform Service (EventDrivenService or WebService) to be processed and deployment to be created
# Usage: ./wait-for-platform-service.sh <service-name> <namespace> [timeout]

set -euo pipefail

SERVICE_NAME="${1:?Service name required}"
NAMESPACE="${2:?Namespace required}"
TIMEOUT="${3:-300}"

ELAPSED=0
INTERVAL=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Waiting for Platform Service $SERVICE_NAME to be processed...${NC}"

# Detect service type by checking what platform claims exist
SERVICE_TYPE=""
EDS_EXISTS=false
WS_EXISTS=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if EventDrivenService exists
    if kubectl get eventdrivenservice "$SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        EDS_EXISTS=true
        SERVICE_TYPE="EventDrivenService"
    fi
    
    # Check if WebService exists
    if kubectl get webservice "$SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        WS_EXISTS=true
        SERVICE_TYPE="WebService"
    fi
    
    # If neither exists yet, wait
    if [ "$EDS_EXISTS" = false ] && [ "$WS_EXISTS" = false ]; then
        echo -e "  ${YELLOW}Platform service $SERVICE_NAME not found yet... (${ELAPSED}s elapsed)${NC}"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi
    
    echo -e "  ${BLUE}Found $SERVICE_TYPE: $SERVICE_NAME${NC}"
    
    # Check if Deployment exists (created by Crossplane composition)
    if ! kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Waiting for Deployment to be created by platform... (${ELAPSED}s elapsed)${NC}"
        
        # Show service status for debugging
        if [ "$EDS_EXISTS" = true ]; then
            EDS_STATUS=$(kubectl get eventdrivenservice "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
            echo -e "    ${BLUE}EventDrivenService status: $EDS_STATUS${NC}"
        fi
        
        if [ "$WS_EXISTS" = true ]; then
            WS_STATUS=$(kubectl get webservice "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
            echo -e "    ${BLUE}WebService status: $WS_STATUS${NC}"
        fi
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi
    
    # Check Deployment status
    READY_REPLICAS=$(kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    TOTAL_REPLICAS=$(kubectl get deployment "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    echo -e "  ${BLUE}Deployment: $SERVICE_NAME | Ready: $READY_REPLICAS/$TOTAL_REPLICAS (${ELAPSED}s elapsed)${NC}"
    
    # Check for pod failures
    POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" = "Failed" ] || [ "$POD_STATUS" = "CrashLoopBackOff" ]; then
        echo -e "  ${RED}✗ Pod is in failed state: $POD_STATUS${NC}"
        kubectl describe pods -n "$NAMESPACE" -l app="$SERVICE_NAME"
        exit 1
    fi
    
    if [ "$READY_REPLICAS" = "$TOTAL_REPLICAS" ] && [ "$READY_REPLICAS" != "0" ]; then
        echo -e "  ${GREEN}✓ $SERVICE_TYPE $SERVICE_NAME is ready${NC}"
        exit 0
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo -e "${RED}✗ Timeout waiting for Platform Service after ${TIMEOUT}s${NC}"
echo ""
echo -e "${YELLOW}=== Debugging Information ===${NC}"

if [ "$EDS_EXISTS" = true ]; then
    echo "EventDrivenService details:"
    kubectl describe eventdrivenservice "$SERVICE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Not found"
    echo ""
fi

if [ "$WS_EXISTS" = true ]; then
    echo "WebService details:"
    kubectl describe webservice "$SERVICE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Not found"
    echo ""
fi

echo "Deployment details:"
kubectl describe deployment "$SERVICE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Not found"
echo ""
echo "Pods:"
kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME" 2>/dev/null || echo "No pods found"
echo ""
echo "Recent events in namespace:"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20
exit 1