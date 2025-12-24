#!/bin/bash
set -euo pipefail

# ==============================================================================
# Conditional Optional Services Patch
# ==============================================================================
# Purpose: Disable optional platform services not declared in service config
# Usage: ./02-conditional-optional-services.sh
# ==============================================================================

# Install required dependencies
install_dependencies() {
    if ! command -v yq &> /dev/null; then
        echo "Installing yq..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if command -v brew &> /dev/null; then
                brew install yq
            else
                echo "Error: Homebrew not found. Please install yq manually."
                exit 1
            fi
        else
            # Linux
            YQ_VERSION="v4.35.2"
            YQ_BINARY="yq_linux_amd64"
            curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /tmp/yq
            chmod +x /tmp/yq
            sudo mv /tmp/yq /usr/local/bin/yq
        fi
        echo "yq installed successfully"
    fi
}

# Install dependencies first
install_dependencies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CONDITIONAL-SERVICES]${NC} $*"; }
log_success() { echo -e "${GREEN}[CONDITIONAL-SERVICES]${NC} $*"; }
log_error() { echo -e "${RED}[CONDITIONAL-SERVICES]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[CONDITIONAL-SERVICES]${NC} $*"; }

# Find service config file
find_service_config() {
    # Look for ci/config.yaml in current directory or parent directories
    local current_dir="$(pwd)"
    local config_file=""
    
    # Check current directory first
    if [[ -f "${current_dir}/ci/config.yaml" ]]; then
        config_file="${current_dir}/ci/config.yaml"
    # Check parent directory (common when running from platform checkout)
    elif [[ -f "${current_dir}/../ci/config.yaml" ]]; then
        config_file="${current_dir}/../ci/config.yaml"
    # Check if we're in a service subdirectory
    elif [[ -f "${current_dir}/../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../ci/config.yaml"
    fi
    
    echo "$config_file"
}

# Get platform dependencies from service config
get_service_platform_dependencies() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        echo ""
        return
    fi
    
    if command -v yq &> /dev/null; then
        yq eval '.dependencies.platform[]' "$config_file" 2>/dev/null | tr '\n' ' ' || echo ""
    else
        log_error "yq is required but not installed"
        exit 1
    fi
}

# Dynamically discover all available services from ArgoCD base applications
discover_all_services() {
    local all_services=()
    
    # Read the base kustomization to get all ArgoCD applications
    local kustomization_file="${PLATFORM_ROOT}/bootstrap/argocd/base/kustomization.yaml"
    
    if [[ -f "$kustomization_file" ]]; then
        # Extract resource file names from kustomization
        local resource_files
        resource_files=$(yq eval '.resources[]' "$kustomization_file" 2>/dev/null)
        
        for resource_file in $resource_files; do
            if [[ "$resource_file" == *.yaml ]]; then
                local app_file="${PLATFORM_ROOT}/bootstrap/argocd/base/$resource_file"
                if [[ -f "$app_file" ]]; then
                    # Extract application name from the YAML file
                    local app_name
                    app_name=$(yq eval '.metadata.name' "$app_file" 2>/dev/null)
                    
                    if [[ -n "$app_name" ]]; then
                        all_services+=("$app_name")
                    fi
                fi
            fi
        done
    fi
    
    echo "${all_services[@]:-}"
}

# Foundation services (always enabled) - these are never disabled
# Foundation services (always enabled) - these are never disabled
# Foundation services are sync-wave 0-3: core platform infrastructure that ALL services need
get_foundation_services() {
    local foundation_services=()
    local kustomization_file="${PLATFORM_ROOT}/bootstrap/argocd/base/kustomization.yaml"
    
    if [[ -f "$kustomization_file" ]]; then
        # Get all resource files from kustomization
        local resource_files
        resource_files=$(yq eval '.resources[]' "$kustomization_file" 2>/dev/null || grep -A 20 "resources:" "$kustomization_file" | grep -E "^\s*-\s*" | sed 's/^\s*-\s*//')
        
        for resource_file in $resource_files; do
            if [[ "$resource_file" == *.yaml ]]; then
                local app_file="${PLATFORM_ROOT}/bootstrap/argocd/base/$resource_file"
                if [[ -f "$app_file" ]]; then
                    local app_name
                    local sync_wave
                    
                    # Extract application name and sync-wave
                    app_name=$(yq eval '.metadata.name' "$app_file" 2>/dev/null)
                    sync_wave=$(yq eval '.metadata.annotations."argocd.argoproj.io/sync-wave"' "$app_file" 2>/dev/null)
                    
                    if [[ -n "$app_name" && -n "$sync_wave" ]]; then
                        # Foundation services: sync-wave 0-3 (core platform infrastructure)
                        # Wave 0: external-secrets
                        # Wave 1: crossplane-operator, kagent-crds  
                        # Wave 2: cnpg
                        # Wave 3: foundation-config
                        if [[ "$sync_wave" -le 3 ]]; then
                            foundation_services+=("$app_name")
                        fi
                    fi
                fi
            fi
        done
    fi
    
    echo "${foundation_services[@]:-}"
}

# Get optional services by excluding foundation services from all services
get_optional_services() {
    local all_services
    local foundation_services
    local optional_services=()
    
    all_services=($(discover_all_services))
    foundation_services=($(get_foundation_services))
    
    for service in "${all_services[@]:-}"; do
        local is_foundation=false
        for foundation in "${foundation_services[@]:-}"; do
            if [[ "$service" == "$foundation" ]]; then
                is_foundation=true
                break
            fi
        done
        
        if [[ "$is_foundation" == false ]]; then
            optional_services+=("$service")
        fi
    done
    
    echo "${optional_services[@]:-}"
}

echo "================================================================================"
echo "Conditional Optional Services Patch"
echo "================================================================================"

# Discover all services dynamically
ALL_SERVICES=($(discover_all_services))
FOUNDATION_SERVICES=($(get_foundation_services))
OPTIONAL_SERVICES=($(get_optional_services))

log_info "Discovered services from ArgoCD base applications:"
log_info "  Foundation services: ${FOUNDATION_SERVICES[*]:-}"
log_info "  Optional services: ${OPTIONAL_SERVICES[*]:-}"

# Find service configuration
SERVICE_CONFIG=$(find_service_config)

if [[ -n "$SERVICE_CONFIG" ]]; then
    log_info "Found service config: $SERVICE_CONFIG"
    
    # Get platform dependencies from service config
    PLATFORM_DEPS=$(get_service_platform_dependencies "$SERVICE_CONFIG")
    log_info "Service platform dependencies: ${PLATFORM_DEPS:-none}"
    
    # Check each optional service
    for service in "${OPTIONAL_SERVICES[@]:-}"; do
        if echo "$PLATFORM_DEPS" | grep -q "$service"; then
            log_success "✓ $service - ENABLED (declared in service config)"
        else
            log_warn "✗ $service - DISABLING (not declared in service config)"
            disable_service "$service"
        fi
    done
    
    # Show foundation services (always enabled)
    log_info "Foundation services (always enabled):"
    for service in "${FOUNDATION_SERVICES[@]:-}"; do
        log_success "✓ $service - ENABLED (foundation service)"
    done
    
else
    log_warn "No service config found - keeping all optional services enabled"
    log_warn "Searched for ci/config.yaml in current and parent directories"
fi

echo "================================================================================"

# Generic function to disable any service by commenting out its kustomization entry
disable_service() {
    local service="$1"
    
    log_info "Disabling service: $service"
    
    # Find the corresponding YAML file for this service
    local service_file=""
    for yaml_file in "${PLATFORM_ROOT}/bootstrap/argocd/base"/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            local app_name
            app_name=$(yq eval '.metadata.name' "$yaml_file" 2>/dev/null || grep -E "^\s*name:" "$yaml_file" | head -1 | sed 's/.*name:\s*//' | tr -d '"')
            
            if [[ "$app_name" == "$service" ]]; then
                service_file="$yaml_file"
                break
            fi
        fi
    done
    
    if [[ -n "$service_file" ]]; then
        # Comment out the service in the kustomization file
        local kustomization_file="${PLATFORM_ROOT}/bootstrap/argocd/base/kustomization.yaml"
        local resource_name=$(basename "$service_file")
        
        if [[ -f "$kustomization_file" ]]; then
            # Create backup
            cp "$kustomization_file" "${kustomization_file}.bak"
            
            # Comment out the resource line
            sed -i "s|^- ${resource_name}|# DISABLED by conditional patch: ${resource_name}|" "$kustomization_file"
            
            log_success "Disabled $service by commenting out $resource_name in kustomization.yaml"
        else
            log_error "Kustomization file not found: $kustomization_file"
        fi
    else
        log_warn "Could not find YAML file for service: $service"
    fi
}

log_success "Conditional optional services patch completed"