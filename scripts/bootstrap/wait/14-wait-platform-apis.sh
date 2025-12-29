#!/bin/bash
# Wait for Platform API XRDs to be ready
# Usage: ./14-wait-platform-apis.sh [--timeout seconds]
#
# This script waits for:
# 1. EventDrivenService XRD to be installed and ready
# 2. WebService XRD to be installed and ready
# 3. Both XRDs to have valid API versions

set -e

# Default values
TIMEOUT=300
CHECK_INTERVAL=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
            
            # Detailed diagnostics for CI debugging
            echo -e "    ${BLUE}Diagnostics:${NC}"
            
            # Check ArgoCD application status
            if kubectl get application apis -n argocd &>/dev/null; then
                APP_STATUS=$(kubectl get application apis -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo "UNKNOWN")
                echo -e "      ArgoCD app 'apis': $APP_STATUS"
                
                # Show sync details if not synced
                if [[ "$APP_STATUS" != "Synced/Healthy" ]]; then
                    echo -e "      ${YELLOW}ArgoCD Details:${NC}"
                    kubectl get application apis -n argocd -o json 2>/dev/null | jq -r '
                        "        Sync Status: \(.status.sync.status // "Unknown")",
                        "        Health Status: \(.status.health.status // "Unknown")",
                        "        Last Sync: \(.status.operationState.finishedAt // "Never")",
                        "        Sync Revision: \(.status.sync.revision // "Unknown")[0:8]"
                    ' 2>/dev/null || echo -e "        Could not get ArgoCD details"
                    
                    # Show conditions if any
                    CONDITIONS=$(kubectl get application apis -n argocd -o json 2>/dev/null | jq -r '.status.conditions[]? | "        - \(.type): \(.message)"' 2>/dev/null)
                    [ -n "$CONDITIONS" ] && echo -e "      ${YELLOW}Conditions:${NC}" && echo "$CONDITIONS"
                fi
                
                # Show OutOfSync resources
                OUTOFSYNC=$(kubectl get application apis -n argocd -o json 2>/dev/null | jq -r --arg xrd "$XRD_NAME" '.status.resources[]? | select(.status == "OutOfSync" and (.name | contains($xrd))) | "        \(.kind)/\(.name)"' 2>/dev/null)
                [ -n "$OUTOFSYNC" ] && echo -e "      ${RED}OutOfSync XRD resources:${NC}" && echo "$OUTOFSYNC"
                
            else
                echo -e "      ${RED}ArgoCD application 'apis' not found${NC}"
            fi
            
            # Check if XRD definition files exist locally
            if [ "$XRD_NAME" = "xwebservices" ]; then
                LOCAL_PATH="platform/apis/webservice/definitions"
            elif [ "$XRD_NAME" = "xeventdrivenservices" ]; then
                LOCAL_PATH="platform/apis/event-driven-service/definitions"
            else
                LOCAL_PATH="platform/apis/unknown/definitions"
            fi
            
            echo -e "      ${BLUE}Local files:${NC}"
            if [ -d "$LOCAL_PATH" ]; then
                echo -e "        ✓ Directory exists: $LOCAL_PATH"
                if [ -f "$LOCAL_PATH/$XRD_NAME.yaml" ]; then
                    echo -e "        ✓ XRD file exists: $LOCAL_PATH/$XRD_NAME.yaml"
                else
                    echo -e "        ✗ XRD file missing: $LOCAL_PATH/$XRD_NAME.yaml"
                    echo -e "        Available files:"
                    ls -la "$LOCAL_PATH/" 2>/dev/null | sed 's/^/          /' || echo -e "          Could not list files"
                fi
            else
                echo -e "        ✗ Directory missing: $LOCAL_PATH"
            fi
            
            ALL_READY=false
            continue
        fi
        
        # Check if claim CRD exists
        if ! kubectl get crd "$CLAIM_CRD" &>/dev/null; then
            echo -e "  ${YELLOW}⚠️  Claim CRD not found${NC}"
            ALL_READY=false
            continue
        fi
        
        # Check if XRD has valid API version
        API_VERSION=$(kubectl get crd "$XRD" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "")
        if [ -z "$API_VERSION" ]; then
            echo -e "  ${YELLOW}⚠️  API version not available yet${NC}"
            echo -e "    ${BLUE}XRD Status:${NC}"
            kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '
                "      Created: \(.metadata.creationTimestamp)",
                "      Generation: \(.metadata.generation)",
                "      Versions: \(.spec.versions | length) defined"
            ' 2>/dev/null || echo -e "      Could not get XRD details"
            ALL_READY=false
            continue
        fi
        
        if [ "$API_VERSION" != "v1alpha1" ]; then
            echo -e "  ${YELLOW}⚠️  Unexpected API version: $API_VERSION (expected: v1alpha1)${NC}"
            echo -e "    ${BLUE}Available versions:${NC}"
            kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '.spec.versions[]? | "      - \(.name) (served: \(.served), storage: \(.storage))"' 2>/dev/null || echo -e "      Could not get version details"
            ALL_READY=false
            continue
        fi
        
        # Check if XRD is established
        ESTABLISHED=$(kubectl get crd "$XRD" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "")
        if [ "$ESTABLISHED" != "True" ]; then
            echo -e "  ${YELLOW}⚠️  XRD not established yet${NC}"
            echo -e "    ${BLUE}XRD Conditions:${NC}"
            kubectl get crd "$XRD" -o json 2>/dev/null | jq -r '.status.conditions[]? | "      - \(.type): \(.status) (\(.reason // "no reason")) - \(.message // "no message")"' 2>/dev/null || echo -e "      Could not get XRD conditions"
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
echo "XRD Status:"
for XRD in "${XRDS[@]}"; do
    XRD_NAME=$(echo "$XRD" | cut -d'.' -f1)
    if kubectl get crd "$XRD" &>/dev/null; then
        API_VERSION=$(kubectl get crd "$XRD" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "unknown")
        ESTABLISHED=$(kubectl get crd "$XRD" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "unknown")
        echo "  $XRD_NAME: API=$API_VERSION, Established=$ESTABLISHED"
    else
        echo "  $XRD_NAME: NOT FOUND"
    fi
done
echo ""
echo "Troubleshooting:"
echo "  1. Check ArgoCD Application: kubectl get application apis -n argocd"
echo "  2. Check Application sync status: kubectl describe application apis -n argocd"
echo "  3. Check XRD details: kubectl describe crd xeventdrivenservices.platform.bizmatters.io"
echo "  4. Check XRD details: kubectl describe crd xwebservices.platform.bizmatters.io"
echo ""
exit 1