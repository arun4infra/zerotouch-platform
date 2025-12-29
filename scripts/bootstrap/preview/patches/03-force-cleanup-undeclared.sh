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
        
        # Step 1: Remove finalizers to prevent hangs
        log_info "Cleaning finalizers for $service..."
        if kubectl get namespace "$service" -o json > "/tmp/${service}-ns.json" 2>/dev/null; then
            # Create finalize payload with empty finalizers
            jq '.spec.finalizers = []' "/tmp/${service}-ns.json" > "/tmp/${service}-finalize.json" 2>/dev/null || {
                log_warn "jq not available, using manual finalizer removal"
                kubectl patch namespace "$service" -p '{"spec":{"finalizers":[]}}' --type=merge || true
            }
            
            # Apply finalizer removal via finalize endpoint
            if [[ -f "/tmp/${service}-finalize.json" ]]; then
                kubectl replace --raw "/api/v1/namespaces/${service}/finalize" -f "/tmp/${service}-finalize.json" 2>/dev/null || {
                    log_warn "Finalize endpoint failed, trying patch method"
                    kubectl patch namespace "$service" -p '{"spec":{"finalizers":[]}}' --type=merge || true
                }
            fi
        else
            log_warn "Could not get namespace JSON, trying direct patch"
            kubectl patch namespace "$service" -p '{"spec":{"finalizers":[]}}' --type=merge || true
        fi
        
        # Step 2: Force delete the namespace (should be instant now)
        kubectl delete namespace "$service" --force --grace-period=0 || true
        log_success "✓ Deleted namespace: $service"
        
        # Clean up temp files
        rm -f "/tmp/${service}-ns.json" "/tmp/${service}-finalize.json"
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