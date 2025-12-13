#!/bin/bash
# Cluster Validation Script
# Validates all ArgoCD applications and critical namespaces are healthy
#
# Usage: ./validate-cluster.sh [--ignore-file path/to/ignore-list.txt]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
IGNORE_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --ignore-file)
            IGNORE_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load ignore list
IGNORE_APPS=()
if [[ -n "$IGNORE_FILE" && -f "$IGNORE_FILE" ]]; then
    echo "Loading ignore list from: $IGNORE_FILE"
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        # Extract app name (before any comment)
        app=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -n "$app" ]] && IGNORE_APPS+=("$app")
    done < "$IGNORE_FILE"
    
    if [[ ${#IGNORE_APPS[@]} -gt 0 ]]; then
        echo "Ignoring OutOfSync status for: ${IGNORE_APPS[*]}"
    fi
    echo ""
fi

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

echo "$APPS" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"' | while IFS='|' read -r name sync health; do
    # Check if app is in ignore list
    IS_IGNORED=false
    for ignore_app in "${IGNORE_APPS[@]}"; do
        if [[ "$name" == "$ignore_app" ]]; then
            IS_IGNORED=true
            break
        fi
    done
    
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
        echo -e "  ✅ ${GREEN}$name${NC}: Synced & Healthy"
    elif [[ "$sync" == "Synced" && "$health" == "Progressing" ]]; then
        echo -e "  ⚠️  ${YELLOW}$name${NC}: Synced & Progressing (pods still starting)"
        # Progressing means pods are not fully ready yet - this should be a warning but not a failure
        # The wait-for-pods script should handle waiting for pods to be ready
    elif [[ "$sync" == "OutOfSync" && "$health" == "Healthy" && "$IS_IGNORED" == "true" ]]; then
        echo -e "  ⚠️  ${YELLOW}$name${NC}: OutOfSync but Healthy (ignored)"
    elif [[ "$sync" == "OutOfSync" && "$health" == "Healthy" ]]; then
        echo -e "  ⚠️  ${YELLOW}$name${NC}: OutOfSync but Healthy"
    else
        echo -e "  ❌ ${RED}$name${NC}: $sync / $health"
        ((FAILED++)) || true
    fi
done

echo ""
echo "Summary: $TOTAL_APPS total applications"
echo ""

# 2. Check Critical Namespaces
echo "🏢 Critical Namespaces:"
echo "------------------------------------------"

ALL_NAMESPACES=("argocd" "external-secrets" "crossplane-system" "keda" "kagent" "intelligence-platform")

for ns in "${ALL_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        TOTAL_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        READY_PODS=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
        
        if [[ "$TOTAL_PODS" -eq 0 ]]; then
            echo -e "  ⚠️  ${YELLOW}$ns${NC}: No pods (may be expected)"
        elif [[ "$READY_PODS" -eq "$TOTAL_PODS" ]]; then
            echo -e "  ✅ ${GREEN}$ns${NC}: $READY_PODS/$TOTAL_PODS pods ready"
        else
            NOT_READY=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | .metadata.name' | head -3)
            echo -e "  ❌ ${RED}$ns${NC}: $READY_PODS/$TOTAL_PODS pods ready"
            if [[ -n "$NOT_READY" ]]; then
                echo -e "     ${YELLOW}Not ready:${NC} $(echo "$NOT_READY" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
            fi
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
    CRITICAL_OUTOF_SYNC=""
    IGNORED_OUTOF_SYNC=""
    
    while read -r app; do
        if [[ -n "$app" ]]; then
            # Check if app is in ignore list
            IS_IGNORED=false
            for ignore_app in "${IGNORE_APPS[@]}"; do
                if [[ "$app" == "$ignore_app" ]]; then
                    IS_IGNORED=true
                    break
                fi
            done
            
            if [[ "$IS_IGNORED" == "true" ]]; then
                IGNORED_OUTOF_SYNC="$IGNORED_OUTOF_SYNC\n     - $app (ignored)"
            else
                echo -e "  ❌ ${RED}OutOfSync applications detected:${NC}"
                echo -e "     - $app"
                CRITICAL_OUTOF_SYNC="yes"
                ((FAILED++)) || true
            fi
        fi
    done <<< "$OUTOF_SYNC"
    
    if [[ -n "$IGNORED_OUTOF_SYNC" ]]; then
        echo -e "  ⚠️  ${YELLOW}OutOfSync (ignored):${NC}"
        echo -e "$IGNORED_OUTOF_SYNC"
    fi
    
    if [[ -z "$CRITICAL_OUTOF_SYNC" ]]; then
        echo -e "  ✅ ${GREEN}No critical configuration drift detected${NC}"
    fi
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