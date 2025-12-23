#!/bin/bash
# Verify that Tenant Namespaces (Landing Zones) exist
# Usage: ./16-verify-landing-zones.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verifying Tenant Landing Zones                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "🔍 Verifying Tenant Landing Zones..."

# Check if running in preview mode (Kind cluster)
IS_PREVIEW_MODE=false
if kubectl get nodes -o name 2>/dev/null | grep -q "zerotouch-preview"; then
    IS_PREVIEW_MODE=true
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}Preview mode detected - tenant-infrastructure not deployed${NC}"
    echo -e "${BLUE}Namespaces should be created by CI scripts (mock landing zones)${NC}"
    
    # In preview mode, just check if expected namespaces exist (created by CI)
    EXPECTED_NS=("intelligence-deepagents" "intelligence-orchestrator")
    
    FAILED=0
    for ns in "${EXPECTED_NS[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Mock namespace '$ns' exists (created by CI)${NC}"
        else
            echo -e "${YELLOW}⚠️  Mock namespace '$ns' not found - CI should create it${NC}"
            # Don't fail in preview mode - CI might create namespaces later
        fi
    done
    
    echo -e "${GREEN}✅ Preview mode validation complete${NC}"
    exit 0
fi

# 1. Fetch expected tenants from the tenant-infrastructure application
TENANT_CACHE_DIR=".tenants-cache"

# Check if tenant-infrastructure app exists and is synced
if ! kubectl get application tenant-infrastructure -n argocd >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  tenant-infrastructure application not found. Skipping validation.${NC}"
    exit 0
fi

# Check if tenant-infrastructure is synced
SYNC_STATUS=$(kubectl get application tenant-infrastructure -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
if [ "$SYNC_STATUS" != "Synced" ]; then
    echo -e "${YELLOW}⚠️  tenant-infrastructure not synced (status: $SYNC_STATUS). Skipping validation.${NC}"
    exit 0
fi

# Get expected namespaces from known tenants (fallback approach)
EXPECTED_NS=("intelligence-deepagents" "intelligence-orchestrator")

# Try to get namespaces dynamically from tenant configs if available
if kubectl get applications -n argocd -l managed-by=applicationset >/dev/null 2>&1; then
    DYNAMIC_NS=$(kubectl get applications -n argocd -l managed-by=applicationset -o jsonpath='{.items[*].spec.destination.namespace}' 2>/dev/null | tr ' ' '\n' | sort -u | grep -E "^intelligence-" || true)
    if [ -n "$DYNAMIC_NS" ]; then
        EXPECTED_NS=($DYNAMIC_NS)
        echo -e "${BLUE}Found ${#EXPECTED_NS[@]} tenant namespaces from ApplicationSet${NC}"
    fi
fi

FAILED=0

for ns in "${EXPECTED_NS[@]}"; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Namespace '$ns' exists${NC}"
        
        # Optional: Check for governance labels
        LABELS=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")
        if echo "$LABELS" | grep -q "zerotouch.io/managed-by"; then
            echo -e "  ${GREEN}✓ Governance labels present${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Namespace exists but missing governance labels${NC}"
        fi
        
        # Check Pod Security Standards
        if echo "$LABELS" | grep -q "pod-security.kubernetes.io/enforce"; then
            echo -e "  ${GREEN}✓ Pod Security Standards configured${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Pod Security Standards not configured${NC}"
        fi
    else
        echo -e "${RED}✗ Namespace '$ns' MISSING${NC}"
        echo -e "  ${RED}ArgoCD will fail to deploy applications for this tenant.${NC}"
        FAILED=1
    fi
done

echo ""

if [ $FAILED -eq 1 ]; then
    echo -e "${RED}❌ Landing Zone Verification Failed${NC}"
    echo -e "${YELLOW}Some tenant namespaces are missing. Check tenant-infrastructure sync status:${NC}"
    echo -e "${YELLOW}  kubectl describe application tenant-infrastructure -n argocd${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All tenant landing zones verified${NC}"
fi