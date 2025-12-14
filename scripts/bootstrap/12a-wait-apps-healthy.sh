#!/bin/bash
# Wait for All Applications to be Synced & Healthy
# Usage: ./12a-wait-apps-healthy.sh [--timeout <seconds>]
#
# This script waits for all ArgoCD applications to reach Synced & Healthy status.
# Only Synced & Healthy is considered success - Progressing is NOT accepted.

set -e

# Get script directory for sourcing helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source shared diagnostics library
if [ -f "$SCRIPT_DIR/helpers/diagnostics.sh" ]; then
    source "$SCRIPT_DIR/helpers/diagnostics.sh"
fi

# Fallback inline diagnostics if library not available
_inline_diagnose_app() {
    local app_name="$1"
    local status="$2"
    
    APP_JSON=$(kubectl get application "$app_name" -n argocd -o json 2>/dev/null)
    APP_NAMESPACE=$(echo "$APP_JSON" | jq -r '.spec.destination.namespace // "default"' 2>/dev/null)
    
    # Conditions
    CONDITIONS=$(echo "$APP_JSON" | jq -r '.status.conditions[]? | "         - \(.type): \(.message // "no message")"' 2>/dev/null | head -2)
    [ -n "$CONDITIONS" ] && echo -e "       ${YELLOW}Conditions:${NC}" && echo "$CONDITIONS"
    
    # Operation state
    OP_PHASE=$(echo "$APP_JSON" | jq -r '.status.operationState.phase // "none"' 2>/dev/null)
    if [ "$OP_PHASE" = "Failed" ] || [ "$OP_PHASE" = "Error" ]; then
        OP_MSG=$(echo "$APP_JSON" | jq -r '.status.operationState.message // "none"' 2>/dev/null | head -c 200)
        echo -e "       ${RED}Operation: $OP_PHASE - $OP_MSG${NC}"
    fi
    
    # OutOfSync resources
    if [[ "$status" == *"OutOfSync"* ]]; then
        OUTOFSYNC=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.status == "OutOfSync") | "         \(.kind)/\(.name)"' 2>/dev/null | head -3)
        [ -n "$OUTOFSYNC" ] && echo -e "       ${RED}OutOfSync:${NC}" && echo "$OUTOFSYNC"
    fi
    
    # Degraded resources
    if [[ "$status" == *"Degraded"* ]]; then
        DEGRADED=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Degraded") | "         \(.kind)/\(.name): \(.health.message // "no message")"' 2>/dev/null | head -3)
        [ -n "$DEGRADED" ] && echo -e "       ${RED}Degraded:${NC}" && echo "$DEGRADED"
    fi
    
    # Progressing - enhanced diagnostics
    if [[ "$status" == *"Progressing"* ]]; then
        # ArgoCD progressing resources
        PROGRESSING=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Progressing") | "         \(.kind)/\(.name): \(.health.message // "waiting")"' 2>/dev/null | head -3)
        [ -n "$PROGRESSING" ] && echo -e "       ${BLUE}Progressing:${NC}" && echo "$PROGRESSING"
        
        # Waiting pods
        WAITING_PODS=$(kubectl get pods -n "$APP_NAMESPACE" -o json 2>/dev/null | \
            jq -r '.items[]? | select(.status.phase != "Running" or (.status.containerStatuses[]?.ready == false)) | 
            "         \(.metadata.name): \(.status.phase) - \(.status.containerStatuses[]? | select(.ready == false) | .state | to_entries[0] | "\(.key): \(.value.reason // .value.message // "waiting")")"' 2>/dev/null | head -3)
        [ -n "$WAITING_PODS" ] && echo -e "       ${BLUE}Waiting pods:${NC}" && echo "$WAITING_PODS"
        
        # Pending PVCs
        PENDING_PVCS=$(kubectl get pvc -n "$APP_NAMESPACE" -o json 2>/dev/null | \
            jq -r '.items[]? | select(.status.phase != "Bound") | "         \(.metadata.name): \(.status.phase)"' 2>/dev/null | head -2)
        [ -n "$PENDING_PVCS" ] && echo -e "       ${BLUE}Pending PVCs:${NC}" && echo "$PENDING_PVCS"
        
        # Recent warnings
        EVENTS=$(kubectl get events -n "$APP_NAMESPACE" --field-selector type=Warning --sort-by='.lastTimestamp' -o json 2>/dev/null | \
            jq -r '.items[-3:][]? | "         \(.involvedObject.kind)/\(.involvedObject.name): \(.reason) - \(.message | .[0:80])"' 2>/dev/null)
        [ -n "$EVENTS" ] && echo -e "       ${YELLOW}Recent warnings:${NC}" && echo "$EVENTS"
        
        # Fallback summary
        if [ -z "$PROGRESSING" ] && [ -z "$WAITING_PODS" ] && [ -z "$PENDING_PVCS" ]; then
            HEALTH_MSG=$(echo "$APP_JSON" | jq -r '.status.health.message // empty' 2>/dev/null)
            [ -n "$HEALTH_MSG" ] && echo -e "       ${BLUE}Health: $HEALTH_MSG${NC}"
            echo -e "       ${BLUE}Resources:${NC}"
            echo "$APP_JSON" | jq -r '[.status.resources[]? | .health.status // "Unknown"] | group_by(.) | map("\(.[0]): \(length)") | "         " + join(", ")' 2>/dev/null
        fi
    fi
}

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
    "intelligence"              # AI/documentation layer - resource intensive, not needed for core functionality
    "local-path-provisioner"    # Kind has its own built-in provisioner, ours conflicts with immutable fields
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
    
    # Show not ready apps with comprehensive diagnostics
    if [ ${#NOT_READY_APPS[@]} -gt 0 ]; then
        echo -e "   ${YELLOW}Not ready applications:${NC}"
        for app_status in "${NOT_READY_APPS[@]:0:3}"; do
            app_name=$(echo "$app_status" | cut -d':' -f1)
            status=$(echo "$app_status" | cut -d':' -f2)
            
            echo -e "     ${RED}❌ $app_name: $status${NC}"
            
            # Use shared diagnostics library
            if type diagnose_argocd_app &>/dev/null; then
                diagnose_argocd_app "$app_name"
            else
                # Fallback inline diagnostics if library not loaded
                _inline_diagnose_app "$app_name" "$status"
            fi
            echo ""
        done
        
        if [ ${#NOT_READY_APPS[@]} -gt 3 ]; then
            echo -e "     ${YELLOW}... and $((${#NOT_READY_APPS[@]} - 3)) more apps not ready${NC}"
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
        
        # Use shared diagnostics library for detailed output
        if type diagnose_argocd_app &>/dev/null; then
            diagnose_argocd_app "$name"
        else
            _inline_diagnose_app "$name" "$sync/$health"
        fi
        echo ""
    fi
done < <(echo "$APPS_JSON" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"')

# Print diagnostic summary if library available
if type print_diagnostic_summary &>/dev/null; then
    echo ""
    print_diagnostic_summary "$APPS_JSON"
fi

# Print debug commands
if type print_debug_commands &>/dev/null; then
    print_debug_commands
else
    echo ""
    echo -e "${YELLOW}Debug commands:${NC}"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl describe application <app-name> -n argocd"
    echo "  kubectl get pods -A | grep -v Running"
    echo "  kubectl get events -A --sort-by='.lastTimestamp' | tail -20"
    echo ""
fi

exit 1
