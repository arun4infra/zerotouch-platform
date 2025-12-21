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