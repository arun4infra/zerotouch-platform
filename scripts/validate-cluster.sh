#!/bin/bash
# Cluster Validation Script
# Validates all ArgoCD applications and critical namespaces are healthy

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "🔍 Cluster Validation Report"
echo "=========================================="
echo ""

# Track overall status
FAILED=0

# 1. Check ArgoCD Applications
echo "📦 ArgoCD Applications Status:"
echo "------------------------------------------"

APPS=$(kubectl get applications -n argocd -o json)
TOTAL_APPS=$(echo "$APPS" | jq -r '.items | length')
SYNCED_HEALTHY=0
ISSUES=0

echo "$APPS" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"' | while IFS='|' read -r name sync health; do
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
        echo -e "  ✅ ${GREEN}$name${NC}: Synced & Healthy"
        ((SYNCED_HEALTHY++)) || true
    elif [[ "$sync" == "Synced" && "$health" == "Progressing" ]]; then
        echo -e "  ⚠️  ${YELLOW}$name${NC}: Synced & Progressing (deploying)"
    elif [[ "$sync" == "OutOfSync" && "$health" == "Healthy" ]]; then
        echo -e "  ⚠️  ${YELLOW}$name${NC}: OutOfSync but Healthy"
    elif [[ "$sync" == "Unknown" && "$health" == "Healthy" ]]; then
        echo -e "  ⚠️  ${YELLOW}$name${NC}: Unknown sync but Healthy"
    else
        echo -e "  ❌ ${RED}$name${NC}: $sync / $health"
        ((ISSUES++)) || true
        ((FAILED++)) || true
    fi
done

echo ""
echo "Summary: $TOTAL_APPS total applications"
echo ""

# 2. Check Critical Namespaces
echo "🏢 Critical Namespaces:"
echo "------------------------------------------"

CRITICAL_NAMESPACES=("argocd" "kagent" "intelligence" "external-secrets" "crossplane-system" "keda")

for ns in "${CRITICAL_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        POD_STATUS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        RUNNING=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [[ "$POD_STATUS" -eq "$RUNNING" && "$POD_STATUS" -gt 0 ]]; then
            echo -e "  ✅ ${GREEN}$ns${NC}: $RUNNING/$POD_STATUS pods running"
        elif [[ "$POD_STATUS" -eq 0 ]]; then
            echo -e "  ⚠️  ${YELLOW}$ns${NC}: No pods (may be expected)"
        else
            echo -e "  ❌ ${RED}$ns${NC}: $RUNNING/$POD_STATUS pods running"
            ((FAILED++)) || true
        fi
    else
        echo -e "  ❌ ${RED}$ns${NC}: Namespace not found"
        ((FAILED++)) || true
    fi
done

echo ""

# 3. Check External Secrets
echo "🔐 External Secrets Status:"
echo "------------------------------------------"

EXTERNAL_SECRETS=$(kubectl get externalsecrets -A -o json 2>/dev/null)
if [[ -n "$EXTERNAL_SECRETS" ]]; then
    echo "$EXTERNAL_SECRETS" | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.status.conditions[0].status // "Unknown")|\(.status.conditions[0].reason // "Unknown")"' | while IFS='|' read -r ns name status reason; do
        if [[ "$status" == "True" ]]; then
            echo -e "  ✅ ${GREEN}$ns/$name${NC}: Synced"
        else
            echo -e "  ❌ ${RED}$ns/$name${NC}: $reason"
            ((FAILED++)) || true
        fi
    done
else
    echo "  ⚠️  No ExternalSecrets found"
fi

echo ""

# 4. Check ClusterSecretStore
echo "🗄️  ClusterSecretStore Status:"
echo "------------------------------------------"

STORES=$(kubectl get clustersecretstore -o json 2>/dev/null)
if [[ -n "$STORES" ]]; then
    echo "$STORES" | jq -r '.items[] | "\(.metadata.name)|\(.status.conditions[0].status // "Unknown")|\(.status.conditions[0].reason // "Unknown")"' | while IFS='|' read -r name status reason; do
        if [[ "$status" == "True" ]]; then
            echo -e "  ✅ ${GREEN}$name${NC}: Ready"
        else
            echo -e "  ❌ ${RED}$name${NC}: $reason"
            ((FAILED++)) || true
        fi
    done
else
    echo "  ⚠️  No ClusterSecretStores found"
fi

echo ""

# 5. Check for OutOfSync applications
echo "🔄 Checking for Configuration Drift:"
echo "------------------------------------------"

OUTOF_SYNC=$(echo "$APPS" | jq -r '.items[] | select(.status.sync.status == "OutOfSync") | .metadata.name')
if [[ -n "$OUTOF_SYNC" ]]; then
    echo -e "  ❌ ${RED}OutOfSync applications detected:${NC}"
    echo "$OUTOF_SYNC" | while read -r app; do
        echo -e "     - $app"
        ((FAILED++)) || true
    done
else
    echo -e "  ✅ ${GREEN}No configuration drift detected${NC}"
fi

echo ""

# 6. Final Summary
echo "=========================================="
if [[ $FAILED -eq 0 ]]; then
    echo -e "✅ ${GREEN}VALIDATION PASSED${NC}"
    echo "All applications Synced & Healthy"
    exit 0
else
    echo -e "❌ ${RED}VALIDATION FAILED${NC}"
    echo "$FAILED issue(s) detected"
    echo ""
    echo "Run './scripts/validate-cluster.sh' to see details"
    exit 1
fi
