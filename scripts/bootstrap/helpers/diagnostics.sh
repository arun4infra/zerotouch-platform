#!/bin/bash
# Shared Diagnostics Library for Bootstrap Scripts
# Usage: source helpers/diagnostics.sh
#
# Provides comprehensive diagnostic functions for ArgoCD apps and Kubernetes resources.

# Colors (define if not already set)
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[1;33m'}
BLUE=${BLUE:-'\033[0;34m'}
CYAN=${CYAN:-'\033[0;36m'}
NC=${NC:-'\033[0m'}

# ============================================================================
# KUBECTL HELPERS
# ============================================================================

# Retry kubectl commands with exponential backoff
kubectl_retry() {
    local max_attempts=${KUBECTL_MAX_ATTEMPTS:-5}
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl "$@" 2>/dev/null; then
            return 0
        fi
        sleep $((attempt * 2))
        attempt=$((attempt + 1))
    done
    return 1
}

# ============================================================================
# ARGOCD APPLICATION DIAGNOSTICS
# ============================================================================

# Get detailed diagnostics for an ArgoCD application
# Usage: diagnose_argocd_app <app_name> [namespace]
diagnose_argocd_app() {
    local app_name="$1"
    local namespace="${2:-argocd}"
    
    local APP_JSON=$(kubectl get application "$app_name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$APP_JSON" ] || [ "$APP_JSON" = "null" ]; then
        echo -e "       ${RED}Could not fetch application details${NC}"
        return 1
    fi
    
    local sync_status=$(echo "$APP_JSON" | jq -r '.status.sync.status // "Unknown"')
    local health_status=$(echo "$APP_JSON" | jq -r '.status.health.status // "Unknown"')
    
    # 1. Show sync/health status
    echo -e "       ${CYAN}Status: $sync_status / $health_status${NC}"
    
    # 2. Show app-level health message if present
    local health_msg=$(echo "$APP_JSON" | jq -r '.status.health.message // empty')
    if [ -n "$health_msg" ]; then
        echo -e "       ${YELLOW}Health Message: $health_msg${NC}"
    fi
    
    # 3. Show conditions (sync errors, warnings, etc.)
    local conditions=$(echo "$APP_JSON" | jq -r '.status.conditions[]? | "         - [\(.type)] \(.message // "no message")"' 2>/dev/null)
    if [ -n "$conditions" ]; then
        echo -e "       ${YELLOW}Conditions:${NC}"
        echo "$conditions" | head -5
    fi
    
    # 4. Show operation state (sync operations)
    local op_phase=$(echo "$APP_JSON" | jq -r '.status.operationState.phase // "none"')
    local op_msg=$(echo "$APP_JSON" | jq -r '.status.operationState.message // empty')
    local op_started=$(echo "$APP_JSON" | jq -r '.status.operationState.startedAt // empty')
    
    if [ "$op_phase" != "none" ] && [ "$op_phase" != "Succeeded" ]; then
        echo -e "       ${YELLOW}Operation State:${NC}"
        echo -e "         Phase: $op_phase"
        [ -n "$op_started" ] && echo -e "         Started: $op_started"
        [ -n "$op_msg" ] && echo -e "         Message: ${op_msg:0:200}"
        
        # Show sync result details if failed
        if [ "$op_phase" = "Failed" ] || [ "$op_phase" = "Error" ]; then
            local sync_results=$(echo "$APP_JSON" | jq -r '.status.operationState.syncResult.resources[]? | select(.status != "Synced") | "         - \(.kind)/\(.name): \(.status) - \(.message // "no message")"' 2>/dev/null | head -5)
            if [ -n "$sync_results" ]; then
                echo -e "       ${RED}Failed Resources:${NC}"
                echo "$sync_results"
            fi
        fi
    fi
    
    # 5. Show resource breakdown by health status
    _show_resource_breakdown "$APP_JSON" "$sync_status" "$health_status"
    
    # 6. Show recent events for the app's namespace
    local app_namespace=$(echo "$APP_JSON" | jq -r '.spec.destination.namespace // "default"')
    _show_namespace_events "$app_namespace" "$app_name"
}

# Internal: Show resource breakdown
_show_resource_breakdown() {
    local APP_JSON="$1"
    local sync_status="$2"
    local health_status="$3"
    
    # Count resources by status
    local total_resources=$(echo "$APP_JSON" | jq -r '.status.resources | length // 0')
    
    if [ "$total_resources" -eq 0 ]; then
        echo -e "       ${YELLOW}No resources found in application${NC}"
        return
    fi
    
    # Show OutOfSync resources
    if [[ "$sync_status" == *"OutOfSync"* ]]; then
        local outofsync=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.status == "OutOfSync") | "         - \(.kind)/\(.name): \(.message // "needs sync")"' 2>/dev/null | head -5)
        if [ -n "$outofsync" ]; then
            echo -e "       ${RED}OutOfSync Resources:${NC}"
            echo "$outofsync"
        fi
    fi
    
    # Show Degraded resources
    if [[ "$health_status" == *"Degraded"* ]]; then
        local degraded=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Degraded") | "         - \(.kind)/\(.name): \(.health.message // "degraded")"' 2>/dev/null | head -5)
        if [ -n "$degraded" ]; then
            echo -e "       ${RED}Degraded Resources:${NC}"
            echo "$degraded"
        fi
    fi
    
    # Show Progressing resources
    if [[ "$health_status" == *"Progressing"* ]]; then
        local progressing=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Progressing") | "         - \(.kind)/\(.name): \(.health.message // "in progress")"' 2>/dev/null | head -5)
        if [ -n "$progressing" ]; then
            echo -e "       ${BLUE}Progressing Resources:${NC}"
            echo "$progressing"
        else
            # No individual resources marked progressing - show full breakdown
            echo -e "       ${BLUE}Resource Health Breakdown:${NC}"
            echo "$APP_JSON" | jq -r '
                .status.resources[]? | 
                select(.health.status != "Healthy") |
                "         - \(.kind)/\(.name): \(.health.status // "Unknown") - \(.health.message // "no message")"
            ' 2>/dev/null | head -8
            
            # If still nothing, show summary counts
            if [ -z "$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status != "Healthy")')" ]; then
                echo -e "         ${CYAN}All $total_resources resources report Healthy but app is Progressing${NC}"
                echo -e "         ${CYAN}This usually means a controller is still reconciling${NC}"
            fi
        fi
    fi
    
    # Show Missing resources
    local missing=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Missing") | "         - \(.kind)/\(.name)"' 2>/dev/null | head -3)
    if [ -n "$missing" ]; then
        echo -e "       ${RED}Missing Resources:${NC}"
        echo "$missing"
    fi
    
    # Show Unknown health resources
    local unknown=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Unknown") | "         - \(.kind)/\(.name): \(.health.message // "unknown state")"' 2>/dev/null | head -3)
    if [ -n "$unknown" ]; then
        echo -e "       ${YELLOW}Unknown Health Resources:${NC}"
        echo "$unknown"
    fi
}

# Internal: Show recent events for a namespace
_show_namespace_events() {
    local namespace="$1"
    local app_name="$2"
    
    # Get warning events from the namespace
    local events=$(kubectl get events -n "$namespace" --field-selector type=Warning --sort-by='.lastTimestamp' -o json 2>/dev/null | \
        jq -r '.items[-5:][] | "         - [\(.involvedObject.kind)/\(.involvedObject.name)] \(.reason): \(.message | .[0:100])"' 2>/dev/null)
    
    if [ -n "$events" ]; then
        echo -e "       ${YELLOW}Recent Warning Events ($namespace):${NC}"
        echo "$events"
    fi
}

# ============================================================================
# KUBERNETES RESOURCE DIAGNOSTICS
# ============================================================================

# Diagnose a StatefulSet
# Usage: diagnose_statefulset <name> <namespace>
diagnose_statefulset() {
    local name="$1"
    local namespace="$2"
    
    local sts_json=$(kubectl get statefulset "$name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$sts_json" ]; then
        echo -e "       ${RED}StatefulSet not found${NC}"
        return 1
    fi
    
    local ready=$(echo "$sts_json" | jq -r '.status.readyReplicas // 0')
    local replicas=$(echo "$sts_json" | jq -r '.spec.replicas // 0')
    local current=$(echo "$sts_json" | jq -r '.status.currentReplicas // 0')
    local updated=$(echo "$sts_json" | jq -r '.status.updatedReplicas // 0')
    
    echo -e "       ${CYAN}Replicas: $ready/$replicas ready (current: $current, updated: $updated)${NC}"
    
    if [ "$ready" -ne "$replicas" ]; then
        # Show pod status
        echo -e "       ${YELLOW}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$name" -o wide 2>/dev/null | head -5 | while read -r line; do
            echo -e "         $line"
        done
        
        # Show pending/failed pods details
        local problem_pods=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$name" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase != "Running") | "\(.metadata.name): \(.status.phase) - \(.status.conditions[]? | select(.status != "True") | .message // "waiting")"' 2>/dev/null | head -3)
        if [ -n "$problem_pods" ]; then
            echo -e "       ${RED}Problem Pods:${NC}"
            echo "$problem_pods" | while read -r line; do
                echo -e "         - $line"
            done
        fi
        
        # Check PVCs
        _diagnose_pvcs "$namespace" "app.kubernetes.io/name=$name"
    fi
}

# Diagnose a Deployment
# Usage: diagnose_deployment <name> <namespace>
diagnose_deployment() {
    local name="$1"
    local namespace="$2"
    
    local deploy_json=$(kubectl get deployment "$name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$deploy_json" ]; then
        echo -e "       ${RED}Deployment not found${NC}"
        return 1
    fi
    
    local ready=$(echo "$deploy_json" | jq -r '.status.readyReplicas // 0')
    local replicas=$(echo "$deploy_json" | jq -r '.spec.replicas // 0')
    local available=$(echo "$deploy_json" | jq -r '.status.availableReplicas // 0')
    local unavailable=$(echo "$deploy_json" | jq -r '.status.unavailableReplicas // 0')
    
    echo -e "       ${CYAN}Replicas: $ready/$replicas ready (available: $available, unavailable: $unavailable)${NC}"
    
    # Show conditions
    local conditions=$(echo "$deploy_json" | jq -r '.status.conditions[]? | select(.status != "True") | "         - \(.type): \(.message // "no message")"' 2>/dev/null)
    if [ -n "$conditions" ]; then
        echo -e "       ${YELLOW}Conditions:${NC}"
        echo "$conditions"
    fi
    
    if [ "$ready" -ne "$replicas" ]; then
        # Show pod status
        echo -e "       ${YELLOW}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$name" -o wide 2>/dev/null | head -5 | while read -r line; do
            echo -e "         $line"
        done
    fi
}

# Internal: Diagnose PVCs
_diagnose_pvcs() {
    local namespace="$1"
    local selector="$2"
    
    local pvcs=$(kubectl get pvc -n "$namespace" ${selector:+-l "$selector"} -o json 2>/dev/null)
    local pending_pvcs=$(echo "$pvcs" | jq -r '.items[] | select(.status.phase != "Bound") | "\(.metadata.name): \(.status.phase)"' 2>/dev/null)
    
    if [ -n "$pending_pvcs" ]; then
        echo -e "       ${RED}Pending PVCs:${NC}"
        echo "$pending_pvcs" | while read -r line; do
            echo -e "         - $line"
        done
        
        # Check for storage class issues
        local sc_name=$(echo "$pvcs" | jq -r '.items[0].spec.storageClassName // "default"' 2>/dev/null)
        if ! kubectl get storageclass "$sc_name" >/dev/null 2>&1; then
            echo -e "         ${RED}StorageClass '$sc_name' not found!${NC}"
        fi
        
        # Show PVC events
        echo -e "       ${YELLOW}PVC Events:${NC}"
        kubectl get events -n "$namespace" --field-selector reason=ProvisioningFailed --sort-by='.lastTimestamp' 2>/dev/null | tail -3 | while read -r line; do
            echo -e "         $line"
        done
    fi
}

# ============================================================================
# SERVICE-SPECIFIC DIAGNOSTICS
# ============================================================================

# Diagnose PostgreSQL (CNPG) cluster
# Usage: diagnose_postgres <cluster_name> <namespace>
diagnose_postgres() {
    local name="$1"
    local namespace="$2"
    
    local cluster_json=$(kubectl get clusters.postgresql.cnpg.io "$name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$cluster_json" ]; then
        echo -e "       ${RED}PostgreSQL cluster not found${NC}"
        return 1
    fi
    
    local phase=$(echo "$cluster_json" | jq -r '.status.phase // "Unknown"')
    local ready=$(echo "$cluster_json" | jq -r '.status.readyInstances // 0')
    local total=$(echo "$cluster_json" | jq -r '.status.instances // 0')
    
    echo -e "       ${CYAN}Phase: $phase ($ready/$total instances ready)${NC}"
    
    # Show conditions
    local conditions=$(echo "$cluster_json" | jq -r '.status.conditions[]? | select(.status != "True") | "         - \(.type): \(.message // "no message")"' 2>/dev/null)
    if [ -n "$conditions" ]; then
        echo -e "       ${YELLOW}Conditions:${NC}"
        echo "$conditions"
    fi
    
    if [ "$phase" != "Cluster in healthy state" ]; then
        # Show pod status
        echo -e "       ${YELLOW}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "cnpg.io/cluster=$name" -o wide 2>/dev/null | while read -r line; do
            echo -e "         $line"
        done
        
        # Check PVCs
        _diagnose_pvcs "$namespace" "cnpg.io/cluster=$name"
    fi
}

# Diagnose NATS cluster
# Usage: diagnose_nats [namespace]
diagnose_nats() {
    local namespace="${1:-nats}"
    
    diagnose_statefulset "nats" "$namespace"
    
    # Additional NATS-specific checks
    local nats_box=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=nats-box -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$nats_box" ]; then
        echo -e "       ${CYAN}NATS Box available for debugging: kubectl exec -n $namespace $nats_box -- nats server check${NC}"
    fi
}

# Diagnose Dragonfly cache
# Usage: diagnose_dragonfly <name> <namespace>
diagnose_dragonfly() {
    local name="$1"
    local namespace="$2"
    
    diagnose_statefulset "$name" "$namespace"
}

# ============================================================================
# SUMMARY DIAGNOSTICS
# ============================================================================

# Print a diagnostic summary for multiple unhealthy apps
# Usage: print_diagnostic_summary <app_list_json>
print_diagnostic_summary() {
    local apps_json="$1"
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Diagnostic Summary                                         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Count by status
    local total=$(echo "$apps_json" | jq -r '.items | length')
    local healthy=$(echo "$apps_json" | jq -r '[.items[] | select(.status.sync.status == "Synced" and .status.health.status == "Healthy")] | length')
    local progressing=$(echo "$apps_json" | jq -r '[.items[] | select(.status.health.status == "Progressing")] | length')
    local degraded=$(echo "$apps_json" | jq -r '[.items[] | select(.status.health.status == "Degraded")] | length')
    local outofsync=$(echo "$apps_json" | jq -r '[.items[] | select(.status.sync.status == "OutOfSync")] | length')
    
    echo -e "   ${GREEN}Healthy:${NC}     $healthy/$total"
    echo -e "   ${BLUE}Progressing:${NC} $progressing"
    echo -e "   ${RED}Degraded:${NC}    $degraded"
    echo -e "   ${RED}OutOfSync:${NC}   $outofsync"
    echo ""
    
    # Common issues detection
    echo -e "${YELLOW}Common Issues Detected:${NC}"
    
    # Check for PVC issues
    local pending_pvcs=$(kubectl get pvc --all-namespaces --field-selector status.phase=Pending -o name 2>/dev/null | wc -l)
    if [ "$pending_pvcs" -gt 0 ]; then
        echo -e "   ${RED}⚠ $pending_pvcs PVCs pending - check storage provisioner${NC}"
    fi
    
    # Check for image pull issues
    local image_pull_errors=$(kubectl get events --all-namespaces --field-selector reason=Failed -o json 2>/dev/null | jq -r '[.items[] | select(.message | contains("ImagePull") or contains("ErrImagePull"))] | length')
    if [ "$image_pull_errors" -gt 0 ]; then
        echo -e "   ${RED}⚠ Image pull errors detected - check registry access${NC}"
    fi
    
    # Check for resource quota issues
    local quota_errors=$(kubectl get events --all-namespaces --field-selector reason=FailedCreate -o json 2>/dev/null | jq -r '[.items[] | select(.message | contains("quota") or contains("exceeded"))] | length')
    if [ "$quota_errors" -gt 0 ]; then
        echo -e "   ${RED}⚠ Resource quota exceeded - check namespace quotas${NC}"
    fi
    
    echo ""
}

# ============================================================================
# DEBUG COMMANDS HELPER
# ============================================================================

# Print helpful debug commands
print_debug_commands() {
    echo -e "${YELLOW}Debug Commands:${NC}"
    echo "  # ArgoCD Applications"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl describe application <app-name> -n argocd"
    echo "  argocd app get <app-name> --show-operation"
    echo ""
    echo "  # Pods & Events"
    echo "  kubectl get pods -A | grep -v Running"
    echo "  kubectl get events -A --sort-by='.lastTimestamp' | tail -20"
    echo ""
    echo "  # Storage"
    echo "  kubectl get pvc -A"
    echo "  kubectl get storageclass"
    echo ""
}
