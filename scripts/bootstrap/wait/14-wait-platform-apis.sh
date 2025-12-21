#!/bin/bash
# Wait for Platform API XRDs to be ready
# Usage: ./14-wait-platform-apis.sh [--timeout seconds]
#
# This script waits for:
# 1. EventDrivenService XRD to be installed and ready
# 2. WebService XRD to be installed and ready
# 3. Both XRDs to have valid API versions

set -e

# Get script directory for sourcing helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
TIMEOUT=300
CHECK_INTERVAL=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source shared diagnostics library
if [ -f "$SCRIPT_DIR/../helpers/diagnostics.sh" ]; then
    source "$SCRIPT_DIR/../helpers/diagnostics.sh"
fi

# Detailed XRD diagnostics function
_diagnose_xrd_failure() {
    local xrd_name="$1"
    local claim_crd="$2"
    local display_name="$3"
    
    echo -e "     ${RED}❌ $display_name: NOT READY${NC}"
    
    # Check if XRD exists
    if ! kubectl get crd "$xrd_name" &>/dev/null; then
        echo -e "       ${RED}XRD not found: $xrd_name${NC}"
        
        # Check ArgoCD application status
        echo -e "       ${YELLOW}Checking ArgoCD application 'apis':${NC}"
        if kubectl get application apis -n argocd &>/dev/null; then
            local app_json=$(kubectl get application apis -n argocd -o json 2>/dev/null)
            local sync_status=$(echo "$app_json" | jq -r '.status.sync.status // "Unknown"')
            local health_status=$(echo "$app_json" | jq -r '.status.health.status // "Unknown"')
            
            echo -e "         Status: $sync_status / $health_status"
            
            # Show sync/health details if not healthy
            if [[ "$sync_status" != "Synced" || "$health_status" != "Healthy" ]]; then
                # Use diagnostics library if available
                if type diagnose_argocd_app &>/dev/null; then
                    diagnose_argocd_app "apis" "argocd"
                else
                    # Fallback inline diagnostics
                    local conditions=$(echo "$app_json" | jq -r '.status.conditions[]? | "           - \(.type): \(.message // "no message")"' 2>/dev/null)
                    [ -n "$conditions" ] && echo -e "         ${YELLOW}Conditions:${NC}" && echo "$conditions"
                    
                    local op_phase=$(echo "$app_json" | jq -r '.status.operationState.phase // "none"')
                    if [ "$op_phase" != "none" ] && [ "$op_phase" != "Succeeded" ]; then
                        local op_msg=$(echo "$app_json" | jq -r '.status.operationState.message // "none"' | head -c 100)
                        echo -e "         ${RED}Operation: $op_phase - $op_msg${NC}"
                    fi
                fi
            fi
        else
            echo -e "         ${RED}ArgoCD application 'apis' not found${NC}"
        fi
        
        # Check if the XRD file exists in the repository
        local service_name=$(echo "$display_name" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
        echo -e "       ${YELLOW}Expected XRD location:${NC}"
        echo -e "         platform/04-apis/$service_name/definitions/"
        
        if [ -d "platform/04-apis/$service_name/definitions" ]; then
            echo -e "         ${GREEN}✓ XRD definition directory exists${NC}"
            if [ -f "platform/04-apis/$service_name/definitions/$xrd_name" ]; then
                echo -e "         ${GREEN}✓ XRD definition file exists${NC}"
            else
                echo -e "         ${YELLOW}⚠️  XRD definition file not found: $xrd_name${NC}"
            fi
        else
            echo -e "         ${RED}✗ XRD definition directory missing${NC}"
        fi
        
    else
        # XRD exists but has issues
        echo -e "       ${YELLOW}XRD exists but not ready: $xrd_name${NC}"
        
        # Check API version
        local api_version=$(kubectl get crd "$xrd_name" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "")
        if [ -z "$api_version" ]; then
            echo -e "         ${RED}API version not available${NC}"
        elif [ "$api_version" != "v1alpha1" ]; then
            echo -e "         ${RED}Unexpected API version: $api_version (expected: v1alpha1)${NC}"
        else
            echo -e "         ${GREEN}API version: $api_version${NC}"
        fi
        
        # Check if XRD is established
        local established=$(kubectl get crd "$xrd_name" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "")
        if [ "$established" != "True" ]; then
            echo -e "         ${RED}XRD not established${NC}"
            
            # Show XRD conditions
            local xrd_conditions=$(kubectl get crd "$xrd_name" -o json 2>/dev/null | jq -r '.status.conditions[]? | "           - \(.type): \(.status) - \(.message // "no message")"' 2>/dev/null)
            [ -n "$xrd_conditions" ] && echo -e "         ${YELLOW}XRD Conditions:${NC}" && echo "$xrd_conditions"
        else
            echo -e "         ${GREEN}XRD established: True${NC}"
        fi
        
        # Show XRD details
        echo -e "       ${YELLOW}XRD Details:${NC}"
        kubectl get crd "$xrd_name" -o json 2>/dev/null | jq -r '"         Created: \(.metadata.creationTimestamp)\n         Generation: \(.metadata.generation)\n         Resource Version: \(.metadata.resourceVersion)"' 2>/dev/null || echo -e "         ${YELLOW}Could not get XRD details${NC}"
    fi
    
    # Check claim CRD
    if ! kubectl get crd "$claim_crd" &>/dev/null; then
        echo -e "       ${RED}Claim CRD not found: $claim_crd${NC}"
    else
        echo -e "       ${GREEN}Claim CRD exists: $claim_crd${NC}"
    fi
    
    # Show recent events related to CRDs
    echo -e "       ${YELLOW}Recent CRD Events:${NC}"
    local crd_events=$(kubectl get events --all-namespaces --field-selector involvedObject.kind=CustomResourceDefinition --sort-by='.lastTimestamp' -o json 2>/dev/null | \
        jq -r --arg xrd "$xrd_name" --arg claim "$claim_crd" '.items[] | select(.involvedObject.name == $xrd or .involvedObject.name == $claim) | "         [\(.lastTimestamp)] \(.reason): \(.message)"' 2>/dev/null | tail -3)
    if [ -n "$crd_events" ]; then
        echo "$crd_events"
    else
        echo -e "         ${YELLOW}No recent CRD events found${NC}"
    fi
    
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--timeout seconds]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for Platform API XRDs to be Ready                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Timeout: ${TIMEOUT}s"
echo "Check interval: ${CHECK_INTERVAL}s"
echo ""

# XRDs to wait for
XRDS=(
    "xeventdrivenservices.platform.bizmatters.io"
    "xwebservices.platform.bizmatters.io"
)

# Claim CRDs to wait for
CLAIM_CRDS=(
    "eventdrivenservices.platform.bizmatters.io"
    "webservices.platform.bizmatters.io"
)

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    echo -e "${BLUE}=== Checking Platform API XRDs (${ELAPSED}s / ${TIMEOUT}s) ===${NC}"
    
    ALL_READY=true
    
    # Check each XRD
    for i in "${!XRDS[@]}"; do
        XRD="${XRDS[$i]}"
        CLAIM_CRD="${CLAIM_CRDS[$i]}"
        XRD_NAME=$(echo "$XRD" | cut -d'.' -f1)
        
        echo -e "${BLUE}Checking $XRD_NAME...${NC}"
        
        # Check if XRD exists
        if ! kubectl get crd "$XRD" &>/dev/null; then
            echo -e "  ${YELLOW}⚠️  XRD not found${NC}"
            
            # Detailed diagnostics for missing XRD
            echo -e "    ${BLUE}Diagnostics:${NC}"
            
            # Check ArgoCD application status
            APP_STATUS=$(kubectl get application apis -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
            echo -e "      ArgoCD app 'apis': $APP_STATUS"
            
            # Check if application exists but has issues
            if kubectl get application apis -n argocd &>/dev/null; then
                # Get sync conditions
                SYNC_CONDITIONS=$(kubectl get application apis -n argocd -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type == "ComparisonError" or .type == "SyncError") | "        - \(.type): \(.message)"' 2>/dev/null)
                [ -n "$SYNC_CONDITIONS" ] && echo -e "      ${YELLOW}Sync Issues:${NC}" && echo "$SYNC_CONDITIONS"
                
                # Check operation state
                OP_PHASE=$(kubectl get application apis -n argocd -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")
                if [ "$OP_PHASE" = "Failed" ] || [ "$OP_PHASE" = "Error" ]; then
                    OP_MSG=$(kubectl get application apis -n argocd -o jsonpath='{.status.operationState.message}' 2>/dev/null | head -c 150)
                    echo -e "      ${RED}Operation: $OP_PHASE - $OP_MSG${NC}"
                fi
                
                # Check for OutOfSync resources related to this XRD
                OUTOFSYNC=$(kubectl get application apis -n argocd -o json 2>/dev/null | jq -r --arg xrd "$XRD_NAME" '.status.resources[]? | select(.status == "OutOfSync" and (.name | contains($xrd))) | "        \(.kind)/\(.name)"' 2>/dev/null)
                [ -n "$OUTOFSYNC" ] && echo -e "      ${RED}OutOfSync XRD resources:${NC}" && echo "$OUTOFSYNC"
            else
                echo -e "      ${RED}ArgoCD application 'apis' not found${NC}"
            fi
            
        # Check if CRD directory exists in the repo
        local service_name=$(echo "$XRD_NAME" | sed 's/^x//')  # Remove 'x' prefix
        if [ -d "platform/04-apis/$service_name/definitions" ]; then
            echo -e "      ${GREEN}✓ XRD definition files exist locally${NC}"
        else
            echo -e "      ${RED}✗ XRD definition directory missing: platform/04-apis/$service_name/definitions${NC}"
        fi
            
            ALL_READY=false
            continue
        fi
        
        # Check if claim CRD exists
        if ! kubectl get crd "$CLAIM_CRD" &>/dev/null; then
            echo -e "  ${YELLOW}⚠️  Claim CRD not found${NC}"
            echo -e "    ${BLUE}Expected claim CRD: $CLAIM_CRD${NC}"
            ALL_READY=false
            continue
        fi
        
        # Check if XRD has valid API version
        API_VERSION=$(kubectl get crd "$XRD" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "")
        if [ -z "$API_VERSION" ]; then
            echo -e "  ${YELLOW}⚠️  API version not available yet${NC}"
            
            # Check XRD conditions
            XRD_CONDITIONS=$(kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '.status.conditions[]? | "      - \(.type): \(.status) - \(.message // "no message")"' 2>/dev/null)
            [ -n "$XRD_CONDITIONS" ] && echo -e "    ${BLUE}XRD Conditions:${NC}" && echo "$XRD_CONDITIONS"
            
            ALL_READY=false
            continue
        fi
        
        if [ "$API_VERSION" != "v1alpha1" ]; then
            echo -e "  ${YELLOW}⚠️  Unexpected API version: $API_VERSION (expected: v1alpha1)${NC}"
            ALL_READY=false
            continue
        fi
        
        # Check if XRD is established
        ESTABLISHED=$(kubectl get crd "$XRD" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "")
        if [ "$ESTABLISHED" != "True" ]; then
            echo -e "  ${YELLOW}⚠️  XRD not established yet${NC}"
            
            # Show establishment conditions
            ESTABLISH_CONDITIONS=$(kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type == "Established") | "      Status: \(.status), Reason: \(.reason // "unknown"), Message: \(.message // "no message")"' 2>/dev/null)
            [ -n "$ESTABLISH_CONDITIONS" ] && echo -e "    ${BLUE}Establishment:${NC}" && echo "$ESTABLISH_CONDITIONS"
            
            ALL_READY=false
            continue
        fi
        
        # Additional health checks for established XRDs
        ACCEPTED=$(kubectl get crd "$XRD" -o jsonpath='{.status.conditions[?(@.type=="NamesAccepted")].status}' 2>/dev/null || echo "")
        if [ "$ACCEPTED" != "True" ]; then
            echo -e "  ${YELLOW}⚠️  XRD names not accepted${NC}"
            NAMES_CONDITIONS=$(kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type == "NamesAccepted") | "      \(.reason): \(.message)"' 2>/dev/null)
            [ -n "$NAMES_CONDITIONS" ] && echo -e "    ${BLUE}Names Issue:${NC}" && echo "$NAMES_CONDITIONS"
            ALL_READY=false
            continue
        fi
        
        echo -e "  ${GREEN}✓ $XRD_NAME ready (API version: $API_VERSION)${NC}"
    done
    
    echo ""
    
    if [ "$ALL_READY" = true ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║   ✓ All Platform API XRDs are Ready                         ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Platform API XRDs ready:"
        for XRD in "${XRDS[@]}"; do
            XRD_NAME=$(echo "$XRD" | cut -d'.' -f1)
            API_VERSION=$(kubectl get crd "$XRD" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
            echo "  ✓ $XRD_NAME ($API_VERSION)"
        done
        echo ""
        exit 0
    fi
    
    echo -e "${YELLOW}Not all XRDs are ready yet. Waiting ${CHECK_INTERVAL}s...${NC}"
    echo ""
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

# Timeout reached
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   ✗ Timeout waiting for Platform API XRDs                   ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}Timeout reached after ${TIMEOUT}s${NC}"
echo ""

echo -e "${YELLOW}Final XRD Status:${NC}"
for XRD in "${XRDS[@]}"; do
    XRD_NAME=$(echo "$XRD" | cut -d'.' -f1)
    if kubectl get crd "$XRD" &>/dev/null; then
        API_VERSION=$(kubectl get crd "$XRD" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "unknown")
        ESTABLISHED=$(kubectl get crd "$XRD" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "unknown")
        ACCEPTED=$(kubectl get crd "$XRD" -o jsonpath='{.status.conditions[?(@.type=="NamesAccepted")].status}' 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓${NC} $XRD_NAME: API=$API_VERSION, Established=$ESTABLISHED, NamesAccepted=$ACCEPTED"
        
        # Show any error conditions
        ERROR_CONDITIONS=$(kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.status == "False") | "    - \(.type): \(.reason) - \(.message)"' 2>/dev/null)
        [ -n "$ERROR_CONDITIONS" ] && echo -e "    ${RED}Issues:${NC}" && echo "$ERROR_CONDITIONS"
    else
        echo -e "  ${RED}✗${NC} $XRD_NAME: NOT FOUND"
    fi
done
echo ""

echo -e "${YELLOW}ArgoCD Application Status:${NC}"
if kubectl get application apis -n argocd &>/dev/null; then
    APP_JSON=$(kubectl get application apis -n argocd -o json 2>/dev/null)
    SYNC_STATUS=$(echo "$APP_JSON" | jq -r '.status.sync.status // "Unknown"')
    HEALTH_STATUS=$(echo "$APP_JSON" | jq -r '.status.health.status // "Unknown"')
    echo -e "  Application 'apis': $SYNC_STATUS / $HEALTH_STATUS"
    
    # Show sync/health details
    if [ "$SYNC_STATUS" != "Synced" ] || [ "$HEALTH_STATUS" != "Healthy" ]; then
        # Conditions
        CONDITIONS=$(echo "$APP_JSON" | jq -r '.status.conditions[]? | "    - \(.type): \(.message // "no message")"' 2>/dev/null | head -3)
        [ -n "$CONDITIONS" ] && echo -e "  ${YELLOW}Conditions:${NC}" && echo "$CONDITIONS"
        
        # Operation state
        OP_PHASE=$(echo "$APP_JSON" | jq -r '.status.operationState.phase // "none"' 2>/dev/null)
        if [ "$OP_PHASE" = "Failed" ] || [ "$OP_PHASE" = "Error" ]; then
            OP_MSG=$(echo "$APP_JSON" | jq -r '.status.operationState.message // "none"' 2>/dev/null | head -c 200)
            echo -e "  ${RED}Operation: $OP_PHASE - $OP_MSG${NC}"
        fi
        
        # OutOfSync resources
        if [[ "$SYNC_STATUS" == *"OutOfSync"* ]]; then
            OUTOFSYNC=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.status == "OutOfSync") | "    \(.kind)/\(.name)"' 2>/dev/null | head -5)
            [ -n "$OUTOFSYNC" ] && echo -e "  ${RED}OutOfSync Resources:${NC}" && echo "$OUTOFSYNC"
        fi
        
        # Degraded resources
        if [[ "$HEALTH_STATUS" == *"Degraded"* ]]; then
            DEGRADED=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Degraded") | "    \(.kind)/\(.name): \(.health.message // "no message")"' 2>/dev/null | head -3)
            [ -n "$DEGRADED" ] && echo -e "  ${RED}Degraded Resources:${NC}" && echo "$DEGRADED"
        fi
    fi
else
    echo -e "  ${RED}✗ ArgoCD application 'apis' not found${NC}"
fi
echo ""

echo -e "${YELLOW}Troubleshooting Commands:${NC}"
echo "  # Check ArgoCD application"
echo "  kubectl get application apis -n argocd"
echo "  kubectl describe application apis -n argocd"
echo ""
echo "  # Check XRD details"
for XRD in "${XRDS[@]}"; do
    echo "  kubectl describe crd $XRD"
done
echo ""
echo "  # Check ArgoCD logs"
echo "  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50"
echo ""
echo "  # Force application sync"
echo "  kubectl patch application apis -n argocd --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{\"revision\":\"HEAD\"}}}'"
echo ""
exit 1
