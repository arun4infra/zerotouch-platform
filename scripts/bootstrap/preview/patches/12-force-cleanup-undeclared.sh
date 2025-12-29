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
        # Patch to remove finalizers
        kubectl get namespace "$service" -o json | jq '.spec = {"finalizers":[]}' > "/tmp/${service}.json" 2>/dev/null || true
        kubectl replace --raw "/api/v1/namespaces/${service}/finalize" -f "/tmp/${service}.json" 2>/dev/null || true
        kubectl delete namespace "$service" --force --grace-period=0 || true
        log_success "✓ Deleted namespace: $service"
        
        # Clean up temp file
        rm -f "/tmp/${service}.json"
    fi
}

main() {
    log_info "Running cleanup for undeclared services..."
    
    install_dependencies
    
    local config_file=$(find_service_config)
    if [[ -z "$config_file" ]]; then
        log_warn "No ci/config.yaml found, skipping cleanup"
        exit 0
    fi
    
    log_info "Using config file: $config_file"
    
    # List of all optional services (from 02 script logic)
    # Excludes foundation services (eso, crossplane, cnpg, foundation-config)
    local optional_services=("agents.kagent.dev" "kagent" "keda" "nats" "apis" "databases" "intelligence")
    
    # Get allowed services from config
    local allowed_deps=$(yq eval '.dependencies.platform[]' "$config_file" 2>/dev/null | tr '\n' ' ' || echo "")
    log_info "Allowed platform dependencies: ${allowed_deps:-none}"
    
    for service in "${optional_services[@]}"; do
        if echo "$allowed_deps" | grep -q "$service"; then
            log_info "Keeping declared service: $service"
        else
            log_warn "Found undeclared service candidate: $service"
            # Check if it's actually running
            if kubectl get application "$service" -n argocd &>/dev/null || kubectl get namespace "$service" &>/dev/null; then
                log_warn "Service $service is RUNNING but NOT DECLARED. Force cleaning..."
                force_delete_service "$service"
            else
                log_info "Service $service is correctly not running."
            fi
        fi
    done
    
    log_success "Cleanup check complete"
}

main "$@"