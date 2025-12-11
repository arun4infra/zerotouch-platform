#!/bin/bash
# Wait for All Applications to be Synced & Healthy
# Usage: ./13-wait-apps-healthy.sh [--timeout <seconds>]
#
# This script waits for all ArgoCD applications to reach Synced & Healthy status.
# Only Synced & Healthy is considered success - Progressing is NOT accepted.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TIMEOUT=600  # 10 minutes default
POLL_INTERVAL=15
PREVIEW_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --preview-mode)
            PREVIEW_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Infrastructure apps that can be unhealthy in preview mode
# These are known to have issues in Kind clusters but don't affect core functionality
PREVIEW_OPTIONAL_APPS=(
    "cilium"                    # Kind uses kindnet instead
    "argocd-repo-credentials"   # Tenant repo credentials fail without SSM params
)

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for All Applications to be Healthy                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Timeout: $((TIMEOUT/60)) minutes${NC}"
echo ""

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Get all applications
    APPS_JSON=$(kubectl get applications -n argocd -o json 2>/dev/null)
    TOTAL_APPS=$(echo "$APPS_JSON" | jq -r '.items | length')
    
    if [ "$TOTAL_APPS" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No applications found yet, waiting...${NC}"
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        continue
    fi
    
    # Count healthy apps
    HEALTHY_APPS=0
    NOT_READY_APPS=()
    OPTIONAL_UNHEALTHY=0
    
    while IFS='|' read -r name sync health; do
        if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
            HEALTHY_APPS=$((HEALTHY_APPS + 1))
        else
            # Check if this is an optional app in preview mode
            IS_OPTIONAL=false
            if [ "$PREVIEW_MODE" = true ]; then
                for optional_app in "${PREVIEW_OPTIONAL_APPS[@]}"; do
                    if [ "$name" = "$optional_app" ]; then
                        IS_OPTIONAL=true
                        OPTIONAL_UNHEALTHY=$((OPTIONAL_UNHEALTHY + 1))
                        break
                    fi
                done
            fi
            
            if [ "$IS_OPTIONAL" = false ]; then
                NOT_READY_APPS+=("$name:$sync/$health")
            fi
        fi
    done < <(echo "$APPS_JSON" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"')
    
    # Check if all required apps are healthy
    REQUIRED_APPS=$((TOTAL_APPS - OPTIONAL_UNHEALTHY))
    if [ $HEALTHY_APPS -eq $REQUIRED_APPS ]; then
        echo ""
        if [ "$PREVIEW_MODE" = true ] && [ $OPTIONAL_UNHEALTHY -gt 0 ]; then
            echo -e "${GREEN}✓ All $HEALTHY_APPS required applications are Synced & Healthy${NC}"
            echo -e "${BLUE}ℹ  $OPTIONAL_UNHEALTHY optional infrastructure apps are unhealthy (acceptable in preview mode)${NC}"
        else
            echo -e "${GREEN}✓ All $TOTAL_APPS applications are Synced & Healthy${NC}"
        fi
        echo ""
        exit 0
    fi
    
    # Print progress
    echo -e "${YELLOW}⏳ $HEALTHY_APPS/$TOTAL_APPS healthy ($((ELAPSED/60))m $((ELAPSED%60))s elapsed)${NC}"
    
    # Show not ready apps with error details
    if [ ${#NOT_READY_APPS[@]} -gt 0 ]; then
        echo -e "   ${YELLOW}Not ready applications:${NC}"
        for app_status in "${NOT_READY_APPS[@]:0:5}"; do
            app_name=$(echo "$app_status" | cut -d':' -f1)
            status=$(echo "$app_status" | cut -d':' -f2)
            
            # Get error message if available
            error_msg=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.conditions[?(@.type=="SyncError")].message}' 2>/dev/null)
            health_msg=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.conditions[?(@.type=="HealthError")].message}' 2>/dev/null)
            
            echo -n "     - $app_name: $status"
            
            if [ -n "$error_msg" ]; then
                echo -e " ${RED}(Sync: ${error_msg:0:80})${NC}"
            elif [ -n "$health_msg" ]; then
                echo -e " ${RED}(Health: ${health_msg:0:80})${NC}"
            else
                echo ""
            fi
        done
        
        if [ ${#NOT_READY_APPS[@]} -gt 5 ]; then
            echo -e "     ${YELLOW}... and $((${#NOT_READY_APPS[@]} - 5)) more${NC}"
        fi
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# Timeout - print detailed failure info
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: Applications not healthy after $((TIMEOUT/60)) minutes        ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get final status
APPS_JSON=$(kubectl get applications -n argocd -o json 2>/dev/null)

echo -e "${YELLOW}Application Status:${NC}"
echo ""

while IFS='|' read -r name sync health; do
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
        echo -e "  ✅ $name: $sync / $health"
    else
        echo -e "  ❌ $name: $sync / $health"
        echo ""
        
        # Get detailed status using kubectl and jq
        APP_JSON=$(kubectl get application "$name" -n argocd -o json 2>/dev/null)
        
        # Print ALL conditions
        echo -e "     ${YELLOW}Conditions:${NC}"
        CONDITIONS_OUT=$(echo "$APP_JSON" | jq -r '.status.conditions[]? | "       - \(.type): \(.message // "no message")"' 2>/dev/null)
        if [ -n "$CONDITIONS_OUT" ]; then
            echo "$CONDITIONS_OUT"
        else
            echo "       (no conditions)"
        fi
        
        # Print operation state
        echo -e "     ${YELLOW}Operation State:${NC}"
        OP_PHASE=$(echo "$APP_JSON" | jq -r '.status.operationState.phase // "none"' 2>/dev/null)
        OP_MSG=$(echo "$APP_JSON" | jq -r '.status.operationState.message // "none"' 2>/dev/null)
        echo "       Phase: $OP_PHASE"
        if [ "$OP_MSG" != "none" ]; then
            echo "       Message: $OP_MSG"
        fi
        
        # For OutOfSync, show what's out of sync
        if [[ "$sync" == "OutOfSync" ]]; then
            echo -e "     ${RED}Out of Sync Resources:${NC}"
            OUTOFSYNC=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.status == "OutOfSync") | "       - \(.kind)/\(.name): \(.message // "no message")"' 2>/dev/null | head -5)
            if [ -n "$OUTOFSYNC" ]; then
                echo "$OUTOFSYNC"
            else
                echo "       (no out of sync resources found)"
            fi
        fi
        
        # For Degraded health, show ALL degraded resources with full details
        if [[ "$health" == "Degraded" ]]; then
            echo -e "     ${RED}Degraded Resources:${NC}"
            DEGRADED=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Degraded") | "       - \(.kind)/\(.name) in \(.namespace): \(.health.message // "no message")"' 2>/dev/null)
            if [ -n "$DEGRADED" ]; then
                echo "$DEGRADED"
            else
                echo "       (no degraded resources found)"
            fi
            
            # Also check for progressing resources
            echo -e "     ${YELLOW}Progressing Resources:${NC}"
            PROGRESSING=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Progressing") | "       - \(.kind)/\(.name) in \(.namespace): \(.health.message // "no message")"' 2>/dev/null)
            if [ -n "$PROGRESSING" ]; then
                echo "$PROGRESSING"
            else
                echo "       (no progressing resources)"
            fi
            
            # Get pod status for degraded apps
            echo -e "     ${YELLOW}Pod Status:${NC}"
            PODS=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.kind == "Pod") | "\(.namespace)/\(.name): \(.health.status // "Unknown")"' 2>/dev/null | head -5)
            if [ -n "$PODS" ]; then
                echo "$PODS" | while read -r pod; do
                    echo "       - $pod"
                done
            else
                echo "       (no pods found)"
            fi
        fi
        
        echo ""
    fi
done < <(echo "$APPS_JSON" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"')

echo ""
echo -e "${YELLOW}Debug commands:${NC}"
echo "  kubectl get applications -n argocd"
echo "  kubectl describe application <app-name> -n argocd"
echo ""

exit 1
