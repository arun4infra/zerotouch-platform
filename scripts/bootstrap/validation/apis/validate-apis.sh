#!/bin/bash
# Validate all Platform APIs
# This script runs all API validation scripts in order
#
# Usage: ./validate-apis.sh
#
# Validates EventDrivenService and WebService Platform APIs

# Don't use set -e as it causes early exit before showing output
# We handle errors manually with exit codes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source diagnostics helper (optional)
source "$SCRIPT_DIR/../../helpers/diagnostics.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Validating Platform APIs                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track validation results
FAILED=0
TOTAL=0

# Run all numbered validation scripts (15-*, 16-*, 17-*, 18-*, 19-*)
for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
    if [ -f "$script" ] && [ "$script" != "$0" ]; then
        script_name=$(basename "$script")
        # Extract descriptive name from filename automatically
        # Pattern: NN-verify-something-description.sh -> Something Description
        api_name=$(echo "$script_name" | sed 's/[0-9][0-9]-verify-\(.*\)\.sh/\1/' | sed 's/-/ /g' | sed 's/\b\w/\U&/g')
        
        echo -e "${BLUE}Validating: ${api_name}${NC}"
        echo "  - Script: $script_name"
        ((TOTAL++))
        
        chmod +x "$script"
        echo "  - Starting validation..."
        echo ""
        
        # Flush stdout to ensure output is visible
        sync
        
        # Run script and capture exit code
        # Use explicit redirection to ensure output is visible
        if "$script" 2>&1; then
            validation_exit_code=0
        else
            validation_exit_code=$?
        fi
        
        # Flush again after script completes
        sync
        echo ""
        
        if [ $validation_exit_code -eq 0 ]; then
            echo -e "  ✅ ${GREEN}${api_name} validation passed${NC}"
        else
            echo -e "  ❌ ${RED}${api_name} validation failed (exit code: $validation_exit_code)${NC}"
            echo -e "  ${RED}Error details shown above${NC}"
            echo ""
            
            # Add diagnostic information for failed validations
            echo -e "  ${YELLOW}🔍 Running diagnostics for ${api_name}...${NC}"
            
            # Check ArgoCD applications status
            if command -v kubectl >/dev/null 2>&1; then
                echo -e "  ${BLUE}ArgoCD Applications Status:${NC}"
                kubectl get applications -n argocd 2>/dev/null | head -10 | while read -r line; do
                    echo -e "    $line"
                done || echo -e "    ${YELLOW}Could not get ArgoCD applications${NC}"
                echo ""
                
                # Show specific diagnostics based on the validation type
                case "${api_name,,}" in
                    *"eventdrivenservice"*)
                        echo -e "  ${BLUE}EventDrivenService XRD Status:${NC}"
                        kubectl get crd xeventdrivenservices.platform.bizmatters.io 2>/dev/null | while read -r line; do
                            echo -e "    $line"
                        done || echo -e "    ${RED}EventDrivenService XRD not found${NC}"
                        
                        echo -e "  ${BLUE}EventDrivenService Composition Status:${NC}"
                        kubectl get composition event-driven-service 2>/dev/null | while read -r line; do
                            echo -e "    $line"
                        done || echo -e "    ${RED}EventDrivenService Composition not found${NC}"
                        ;;
                    *"webservice"*)
                        echo -e "  ${BLUE}WebService XRD Status:${NC}"
                        kubectl get crd xwebservices.platform.bizmatters.io 2>/dev/null | while read -r line; do
                            echo -e "    $line"
                        done || echo -e "    ${RED}WebService XRD not found${NC}"
                        
                        echo -e "  ${BLUE}WebService Composition Status:${NC}"
                        kubectl get composition webservice 2>/dev/null | while read -r line; do
                            echo -e "    $line"
                        done || echo -e "    ${RED}WebService Composition not found${NC}"
                        ;;
                esac
                
                # Show recent events that might be related
                echo -e "  ${BLUE}Recent Warning Events:${NC}"
                kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -5 | while read -r line; do
                    echo -e "    $line"
                done || echo -e "    ${YELLOW}No recent events found${NC}"
                echo ""
                
                # Show APIs application status if available
                if kubectl get application apis -n argocd >/dev/null 2>&1; then
                    echo -e "  ${BLUE}APIs Application Diagnostics:${NC}"
                    diagnose_argocd_app "apis" "argocd" 2>/dev/null || {
                        echo -e "    ${YELLOW}Could not run detailed diagnostics${NC}"
                        kubectl describe application apis -n argocd 2>/dev/null | tail -10 | while read -r line; do
                            echo -e "    $line"
                        done || echo -e "    ${YELLOW}Could not describe APIs application${NC}"
                    }
                fi
            else
                echo -e "    ${YELLOW}kubectl not available for diagnostics${NC}"
            fi
            
            ((FAILED++))
        fi
        echo ""
    fi
done

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Platform API Validation Summary                           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo -e "✅ ${GREEN}All $TOTAL Platform APIs validated successfully${NC}"
    exit 0
else
    echo -e "❌ ${RED}$FAILED out of $TOTAL Platform API validations failed${NC}"
    echo ""
    echo -e "${YELLOW}To debug individual failures, run:${NC}"
    for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
        if [ -f "$script" ] && [ "$script" != "$0" ]; then
            echo -e "  $script"
        fi
    done
    echo ""
    echo -e "${YELLOW}For more detailed diagnostics:${NC}"
    echo -e "  kubectl get applications -n argocd"
    echo -e "  kubectl describe application apis -n argocd"
    echo -e "  kubectl get crd | grep platform.bizmatters.io"
    echo -e "  kubectl get composition"
    echo -e "  kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20"
    exit 1
fi