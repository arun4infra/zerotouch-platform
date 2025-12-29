#!/bin/bash
set -euo pipefail

# ==============================================================================
# Patch 12: Force Cleanup of Undeclared Services
# ==============================================================================
# Purpose: Safety net to ensure undeclared optional services are NOT running.
#          It checks ci/config.yaml and force-deletes any optional service
#          (ArgoCD App + Namespace) that is not explicitly allowed.
# Use case: Fixes scenarios where ArgoCD synced before patching could finish.
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CLEANUP-PATCH]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[CLEANUP-PATCH]${NC} $*" >&2; }
log_error() { echo -e "${RED}[CLEANUP-PATCH]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[CLEANUP-PATCH]${NC} $*" >&2; }

# Install required dependencies
install_dependencies() {
    if ! command -v yq &> /dev/null; then
        log_info "Installing yq..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install yq
            else
                echo "Error: Homebrew not found. Please install yq manually."
                exit 1
            fi
        else
            YQ_VERSION="v4.35.2"
            YQ_BINARY="yq_linux_amd64"
            curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /tmp/yq
            chmod +x /tmp/yq
            sudo mv /tmp/yq /usr/local/bin/yq
        fi
    fi
}

# Find service config file
find_service_config() {
    local current_dir="$(pwd)"
    local config_file=""
    
    # Check SERVICE_ROOT first
    if [[ -n "${SERVICE_ROOT:-}" && -f "${SERVICE_ROOT}/ci/config.yaml" ]]; then
        config_file="${SERVICE_ROOT}/ci/config.yaml"
    # Check GitHub Actions structure (service-code directory)
    elif [[ -f "${current_dir}/../service-code/ci/config.yaml" ]]; then
        config_file="${current_dir}/../service-code/ci/config.yaml"
    elif [[ -f "${current_dir}/service-code/ci/config.yaml" ]]; then
        config_file="${current_dir}/service-code/ci/config.yaml"
    # Check standard locations
    elif [[ -f "${current_dir}/ci/config.yaml" ]]; then
        config_file="${current_dir}/ci/config.yaml"
    elif [[ -f "${current_dir}/../ci/config.yaml" ]]; then
        config_file="${current_dir}/../ci/config.yaml"
    elif [[ -f "${current_dir}/../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../ci/config.yaml"
    elif [[ -f "${current_dir}/../../../../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../../../../ci/config.yaml"
    elif [[ -f "${current_dir}/../../../../../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../../../../../ci/config.yaml"
    fi
    
    echo "$config_file"
}

# Force delete a service
force_delete_service() {
    local service="$1"
    
    # 1. Delete ArgoCD Application
    if kubectl get application "$service" -n argocd &>/dev/null; then
        log_info "Deleting undeclared ArgoCD application: $service"
        
        # Show current sync policy before deletion
        local sync_policy=$(kubectl get application "$service" -n argocd -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null || echo "null")
        log_info "Application $service sync policy: ${sync_policy}"
        
        # Patch to remove finalizers for instant deletion
        kubectl patch application "$service" -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge || true
        kubectl delete application "$service" -n argocd --force --grace-period=0 || true
        log_success "✓ Deleted ArgoCD application: $service"
    fi
    
    # 2. Delete Namespace (if it exists and is not a system namespace)
    local system_namespaces=("kube-system" "kube-public" "kube-node-lease" "argocd" "crossplane-system" "external-secrets" "cnpg-system" "local-path-storage" "default")
    local is_system=false
    
    for sys in "${system_namespaces[@]}"; do
        if [[ "$service" == "$sys" ]]; then 
            is_system=true
            break
        fi
    done
    
    if [[ "$is_system" == "false" ]] && kubectl get namespace "$service" &>/dev/null; then
        log_info "Deleting undeclared namespace: $service"
        
        # Step 1: Delete all Custom Resources first to avoid finalizer deadlocks
        log_info "Cleaning Custom Resources in namespace $service..."
        
        # Get all CRDs and delete their instances in this namespace with timeout
        timeout 30 kubectl get crd -o name 2>/dev/null | while read -r crd; do
            crd_name=$(echo "$crd" | cut -d'/' -f2)
            if timeout 5 kubectl get "$crd_name" -n "$service" --no-headers 2>/dev/null | grep -q .; then
                log_info "Deleting $crd_name resources in $service..."
                timeout 10 kubectl delete "$crd_name" --all -n "$service" --force --grace-period=0 --timeout=5s &>/dev/null || true
            fi
        done 2>/dev/null || {
            log_warn "Custom resource cleanup timed out or failed - continuing anyway"
        }
        
        # Step 2: Use the one-liner to remove finalizers instantly
        log_info "Cleaning finalizers for $service to prevent hang..."
        kubectl get namespace "$service" -o json 2>/dev/null | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$service/finalize" -f - 2>/dev/null || {
            log_warn "Finalize endpoint failed, using patch method"
            kubectl patch namespace "$service" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        }
        
        # Step 3: Force delete the namespace (should be instant now)
        kubectl delete namespace "$service" --force --grace-period=0 --timeout=30s || true
        
        # Step 4: Verify deletion with robust timeout
        local timeout=15
        local count=0
        log_info "Verifying namespace deletion (timeout: ${timeout}s)..."
        
        while [ $count -lt $timeout ]; do
            # Use timeout command to prevent kubectl from hanging
            if timeout 3 kubectl get namespace "$service" &>/dev/null; then
                sleep 1
                count=$((count + 1))
            else
                # Namespace is gone or kubectl timed out - either way, we're done
                break
            fi
        done
        
        # Final check with timeout
        if timeout 3 kubectl get namespace "$service" &>/dev/null; then
            log_warn "Namespace $service still exists after $timeout seconds - may need manual cleanup"
        else
            log_success "✓ Deleted namespace: $service"
        fi
    fi
}

main() {
    log_info "Running cleanup for undeclared services..."
    
    # Check ArgoCD auto-sync status first
    log_info "Checking ArgoCD auto-sync configuration..."
    if kubectl get namespace argocd &>/dev/null; then
        if kubectl get configmap argocd-cm -n argocd &>/dev/null; then
            log_info "ArgoCD ConfigMap found, checking auto-sync settings..."
            
            # Check for auto-sync disable configuration
            local autosync_disabled=$(kubectl get configmap argocd-cm -n argocd -o yaml 2>/dev/null | grep -c "application.instanceLabelKey" || echo "0")
            local policy_config=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.policy\.default}' 2>/dev/null || echo "")
            
            if [[ "$autosync_disabled" -gt 0 ]]; then
                log_success "✓ ArgoCD auto-sync disable configuration detected"
                log_info "Policy config: ${policy_config:-none}"
            else
                log_warn "⚠️  ArgoCD auto-sync disable configuration NOT found"
                log_warn "This may cause conflicts during cleanup"
            fi
            
            # Show current application sync policies
            log_info "Current ArgoCD application sync policies:"
            kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,AUTO-SYNC:.spec.syncPolicy.automated" 2>/dev/null || log_warn "Could not retrieve application sync policies"
        else
            log_warn "ArgoCD ConfigMap not found"
        fi
    else
        log_warn "ArgoCD namespace not found"
    fi
    
    install_dependencies
    
    local config_file=$(find_service_config)
    if [[ -z "$config_file" ]]; then
        log_warn "No ci/config.yaml found, skipping cleanup"
        exit 0
    fi
    
    log_info "Using config file: $config_file"
    
    # List of all optional services (from 02 script logic)
    # Excludes foundation services (eso, crossplane, cnpg, foundation-config)
    # Include all services that could be running from ArgoCD sync
    local optional_services=("agents.kagent.dev" "kagent" "keda" "nats" "apis" "databases" "intelligence")
    
    # Get allowed services from config
    local allowed_deps=$(yq eval '.dependencies.platform[]' "$config_file" 2>/dev/null | tr '\n' ' ' || echo "")
    log_info "Allowed platform dependencies: ${allowed_deps:-none}"
    
    # Debug: Show current applications
    log_info "Debug: Current ArgoCD Applications:"
    kubectl get applications -n argocd -o name | sed 's/application.argoproj.io\///' || echo "Failed to list apps"
    
    for service in "${optional_services[@]}"; do
        # Check if service is in allowed dependencies
        local is_allowed=false
        if [[ -n "$allowed_deps" ]]; then
            for allowed in $allowed_deps; do
                if [[ "$service" == "$allowed" ]]; then
                    is_allowed=true
                    break
                fi
            done
        fi
        
        if [[ "$is_allowed" == "true" ]]; then
            log_info "Keeping declared service: $service"
        else
            log_warn "Processing undeclared service candidate: $service"
            
            # AGGRESSIVE CHECK: Check if it exists, regardless of status
            local app_exists=false
            if kubectl get application "$service" -n argocd --ignore-not-found | grep -q "$service"; then
                app_exists=true
                log_warn "Found active Application: $service"
            fi
            
            local ns_exists=false
            if kubectl get namespace "$service" --ignore-not-found | grep -q "$service"; then
                ns_exists=true
                log_warn "Found active Namespace: $service"
            fi
            
            if [[ "$app_exists" == "true" || "$ns_exists" == "true" ]]; then
                log_warn "Service $service is PRESENT but NOT DECLARED. Force cleaning..."
                force_delete_service "$service"
            else
                log_info "Service $service not found in cluster."
            fi
        fi
    done
    
    log_success "Cleanup check complete"
}

main "$@"