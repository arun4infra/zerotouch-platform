#!/bin/bash
# Wait for Platform Service Dependencies
# Usage: ./13-wait-service-dependencies.sh [--timeout <seconds>]
#
# This script waits for core platform services to be ready before applications deploy.

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
if [ -f "$SCRIPT_DIR/../helpers/diagnostics.sh" ]; then
    source "$SCRIPT_DIR/../helpers/diagnostics.sh"
fi

# Configuration
TIMEOUT=300  # 5 minutes default
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
            echo "Usage: $0 [--timeout <seconds>] [--preview-mode]"
            exit 1
            ;;
    esac
done

# Kubectl retry function (fallback if not in shared library)
if ! type kubectl_retry &>/dev/null; then
    kubectl_retry() {
        local max_attempts=5
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if kubectl "$@" 2>/dev/null; then
                return 0
            fi
            sleep 2
            attempt=$((attempt + 1))
        done
        return 1
    }
fi

# Check PostgreSQL clusters
check_postgres() {
    local clusters_json=$(kubectl_retry get clusters.postgresql.cnpg.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
    local total=$(echo "$clusters_json" | jq -r '.items | length')
    
    if [ "$total" -eq 0 ]; then
        # Check if PostgreSQL XRD exists (should be deployed)
        if kubectl_retry get xrd xpostgresinstances.database.bizmatters.io >/dev/null 2>&1; then
            if [ "$PREVIEW_MODE" = true ]; then
                echo -e "   ${GREEN}PostgreSQL: XRD ready (instances created on-demand)${NC}"
                return 0  # In preview mode, XRD existence is sufficient
            else
                echo -e "   ${RED}PostgreSQL: XRD exists but no clusters deployed!${NC}"
                echo -e "     ${YELLOW}Check: kubectl get postgresinstances --all-namespaces${NC}"
                return 1  # In production, we expect instances to exist
            fi
        else
            echo -e "   ${YELLOW}PostgreSQL: XRD not found (not deployed in this platform)${NC}"
            return 0  # XRD doesn't exist - PostgreSQL not part of this deployment
        fi
    fi
    
    local healthy=0
    local unhealthy_details=()
    
    while IFS='|' read -r namespace name phase ready_instances total_instances; do
        if [ -z "$namespace" ]; then continue; fi
        
        if [ "$phase" = "Cluster in healthy state" ] && [ "$ready_instances" = "$total_instances" ]; then
            healthy=$((healthy + 1))
        else
            unhealthy_details+=("$namespace/$name: $phase ($ready_instances/$total_instances)")
        fi
    done < <(echo "$clusters_json" | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.status.phase // "Unknown")|\(.status.readyInstances // 0)|\(.status.instances // 0)"')
    
    echo -e "   PostgreSQL: $healthy/$total ready"
    
    if [ ${#unhealthy_details[@]} -gt 0 ]; then
        echo -e "     ${RED}Unhealthy clusters:${NC}"
        for detail in "${unhealthy_details[@]:0:3}"; do
            echo -e "       ${RED}✗ $detail${NC}"
        done
        
        # Use shared diagnostic functions
        show_pvc_details "" "cnpg.io/cluster"
        show_postgres_details "$(echo "${unhealthy_details[0]}" | cut -d'/' -f1)" "$(echo "${unhealthy_details[0]}" | cut -d'/' -f2 | cut -d':' -f1)"
        show_storage_classes
        show_recent_events "--all-namespaces" "postgresql|cnpg|pvc|volume|provision|schedule" 10
    fi
    
    [ "$healthy" -eq "$total" ]
}

# Check Dragonfly caches
check_dragonfly() {
    local sts_json=$(kubectl_retry get statefulsets --all-namespaces -l app=dragonfly -o json 2>/dev/null || echo '{"items":[]}')
    local total=$(echo "$sts_json" | jq -r '.items | length')
    
    if [ "$total" -eq 0 ]; then
        # Check if Dragonfly XRD exists (should be deployed)
        if kubectl_retry get xrd xdragonflyinstances.database.bizmatters.io >/dev/null 2>&1; then
            if [ "$PREVIEW_MODE" = true ]; then
                echo -e "   ${GREEN}Dragonfly: XRD ready (instances created on-demand)${NC}"
                return 0  # In preview mode, XRD existence is sufficient
            else
                echo -e "   ${RED}Dragonfly: XRD exists but no caches deployed!${NC}"
                echo -e "     ${YELLOW}Check: kubectl get dragonflyinstances --all-namespaces${NC}"
                return 1  # In production, we expect instances to exist
            fi
        else
            echo -e "   ${YELLOW}Dragonfly: XRD not found (not deployed in this platform)${NC}"
            return 0  # XRD doesn't exist - Dragonfly not part of this deployment
        fi
    fi
    
    local ready=0
    local unhealthy_details=()
    
    while IFS='|' read -r namespace name ready_replicas replicas; do
        if [ -z "$namespace" ]; then continue; fi
        
        if [ "$ready_replicas" = "$replicas" ]; then
            ready=$((ready + 1))
        else
            unhealthy_details+=("$namespace/$name: $ready_replicas/$replicas")
            
            # Check for pending pods
            local pending_pods=$(kubectl_retry get pods -n "$namespace" -l app=dragonfly --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
            if [ "$pending_pods" -gt 0 ]; then
                unhealthy_details+=("  └─ $pending_pods pods pending (likely PVC issues)")
            fi
        fi
    done < <(echo "$sts_json" | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.status.readyReplicas // 0)|\(.spec.replicas // 0)"')
    
    echo -e "   Dragonfly: $ready/$total ready"
    
    if [ ${#unhealthy_details[@]} -gt 0 ]; then
        echo -e "     ${RED}Unhealthy caches:${NC}"
        for detail in "${unhealthy_details[@]:0:5}"; do
            echo -e "       ${RED}✗ $detail${NC}"
        done
        
        # Use shared diagnostic functions
        show_pvc_details "" "app=dragonfly"
        show_pod_details "" "app=dragonfly"
        show_recent_events "--all-namespaces" "dragonfly|pvc|volume|provision|schedule" 10
    fi
    
    [ "$ready" -eq "$total" ]
}

# Check NATS messaging
check_nats() {
    if ! kubectl_retry get statefulset nats -n nats >/dev/null 2>&1; then
        return 0  # No NATS to check
    fi
    
    local ready=$(kubectl_retry get statefulset nats -n nats -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local total=$(kubectl_retry get statefulset nats -n nats -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    echo -e "   NATS: $ready/$total ready"
    
    if [ "$ready" -ne "$total" ]; then
        echo -e "     ${RED}NATS not ready:${NC}"
        echo -e "       ${RED}✗ nats/nats: $ready/$total replicas${NC}"
        
        # Use shared diagnostic function
        show_nats_details "nats"
    fi
    
    [ "$ready" -eq "$total" ]
}

# Check External Secrets
check_external_secrets() {
    if ! kubectl_retry get clustersecretstore aws-parameter-store >/dev/null 2>&1; then
        return 0  # No ESO to check
    fi
    
    local store_ready=$(kubectl_retry get clustersecretstore aws-parameter-store -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
    local es_json=$(kubectl_retry get externalsecrets --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
    
    local synced=0
    local total=0
    local failed_secrets=()
    
    while IFS='|' read -r namespace name reason; do
        if [ -z "$namespace" ]; then continue; fi
        
        # Skip tenant repository secrets (expected to fail in preview mode)
        if [[ "$name" == repo-* ]]; then
            continue
        fi
        
        # Skip aws-parameter-store in preview mode (optional secret)
        if [ "$PREVIEW_MODE" = true ] && [[ "$name" == "aws-parameter-store" ]]; then
            continue
        fi
        
        total=$((total + 1))
        
        if [ "$reason" = "SecretSynced" ]; then
            synced=$((synced + 1))
        else
            failed_secrets+=("$namespace/$name: $reason")
        fi
    done < <(echo "$es_json" | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.status.conditions[0].reason // "Unknown")"')
    
    echo -e "   External Secrets: Store=$store_ready, Secrets=$synced/$total"
    
    if [ ${#failed_secrets[@]} -gt 0 ]; then
        echo -e "     ${RED}Failed secrets:${NC}"
        for secret in "${failed_secrets[@]:0:5}"; do
            echo -e "       ${RED}✗ $secret${NC}"
            
            # Get detailed error message for this secret
            local namespace=$(echo "$secret" | cut -d'/' -f1)
            local name=$(echo "$secret" | cut -d':' -f1 | cut -d'/' -f2)
            local error_msg=$(kubectl_retry get externalsecret "$name" -n "$namespace" -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "Unknown error")
            echo -e "         ${YELLOW}Error: $error_msg${NC}"
            
            # Check if this is a tenant repo secret (expected to fail in preview)
            if [[ "$name" == repo-* ]] && [ "$PREVIEW_MODE" = true ]; then
                echo -e "         ${BLUE}Note: Tenant repo secrets expected to fail in preview mode${NC}"
            fi
        done
    fi
    
    [ "$store_ready" = "True" ] && [ "$synced" -eq "$total" ]
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for Platform Service Dependencies                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Timeout: $((TIMEOUT/60)) minutes${NC}"
if [ "$PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}Mode: Preview (some services may be optional)${NC}"
fi
echo ""

# Show cluster resource status upfront
show_cluster_status

ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    echo -e "${YELLOW}⏳ Checking services ($((ELAPSED/60))m $((ELAPSED%60))s elapsed)...${NC}"
    
    all_ready=true
    
    if ! check_postgres; then all_ready=false; fi
    if ! check_dragonfly; then all_ready=false; fi
    if ! check_nats; then all_ready=false; fi
    if ! check_external_secrets; then all_ready=false; fi
    
    if [ "$all_ready" = true ]; then
        echo ""
        echo -e "${GREEN}✓ All platform services are ready!${NC}"
        exit 0
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: Services not ready after $((TIMEOUT/60)) minutes              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}Final service status:${NC}"
echo ""

# Show final detailed status for all services
echo -e "${BLUE}=== PostgreSQL Status ===${NC}"
check_postgres || true
echo ""

echo -e "${BLUE}=== Dragonfly Status ===${NC}"
check_dragonfly || true
echo ""

echo -e "${BLUE}=== NATS Status ===${NC}"
check_nats || true
echo ""

echo -e "${BLUE}=== External Secrets Status ===${NC}"
check_external_secrets || true
echo ""

echo -e "${YELLOW}=== DETAILED DIAGNOSTICS ===${NC}"
echo ""

# Use shared comprehensive timeout diagnostics
show_timeout_diagnostics

echo -e "${YELLOW}Manual debug commands:${NC}"
echo "  kubectl get clusters.postgresql.cnpg.io --all-namespaces -o wide"
echo "  kubectl get statefulsets --all-namespaces -l app=dragonfly -o wide"
echo "  kubectl get statefulset nats -n nats -o wide"
echo "  kubectl get externalsecrets --all-namespaces -o wide"
echo "  kubectl describe clustersecretstore aws-parameter-store"
echo ""

exit 1