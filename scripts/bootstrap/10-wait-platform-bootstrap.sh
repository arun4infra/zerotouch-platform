#!/bin/bash
# Wait for Platform Bootstrap Application
# Usage: ./11-wait-platform-bootstrap.sh
#
# This script waits for the platform-bootstrap ArgoCD application
# to sync and become healthy

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for Platform Bootstrap                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}⏳ Waiting for platform-bootstrap to sync (timeout: 5 minutes)...${NC}"
TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if platform-bootstrap application exists
    if kubectl_retry get application platform-bootstrap -n argocd >/dev/null 2>&1; then
        SYNC_STATUS=$(kubectl_retry get application platform-bootstrap -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH_STATUS=$(kubectl_retry get application platform-bootstrap -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        echo -e "${BLUE}platform-bootstrap found: $SYNC_STATUS / $HEALTH_STATUS${NC}"
        
        if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
            echo -e "${GREEN}✓ platform-bootstrap synced successfully${NC}"
            echo ""
            exit 0
        fi
        
        if [ "$SYNC_STATUS" = "OutOfSync" ] || [ "$HEALTH_STATUS" = "Degraded" ]; then
            echo -e "${YELLOW}⚠️  Status: $SYNC_STATUS / $HEALTH_STATUS - waiting...${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  platform-bootstrap application not found yet${NC}"
        
        # Show all applications for debugging
        echo -e "${BLUE}Current applications:${NC}"
        kubectl_retry get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || echo "Failed to get applications"
        
        # Check platform-root status specifically
        if kubectl_retry get application platform-root -n argocd >/dev/null 2>&1; then
            ROOT_SYNC=$(kubectl_retry get application platform-root -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            ROOT_HEALTH=$(kubectl_retry get application platform-root -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
            echo -e "${BLUE}platform-root status: $ROOT_SYNC / $ROOT_HEALTH${NC}"
            
            # Show platform-root sync details if it has issues
            if [ "$ROOT_SYNC" != "Synced" ]; then
                echo -e "${YELLOW}platform-root sync details:${NC}"
                kubectl_retry describe application platform-root -n argocd | grep -A 10 -B 5 "Sync\|Error\|Message" || echo "Failed to get details"
            fi
        fi
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo -e "${RED}✗ Timeout waiting for platform-bootstrap to sync${NC}"
echo -e "${YELLOW}Check status: kubectl describe application platform-bootstrap -n argocd${NC}"
echo ""
exit 1
