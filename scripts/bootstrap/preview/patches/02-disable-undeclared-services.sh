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
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

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
    
    # Debug: show current directory (redirect to stderr)
    log_info "Current directory: $current_dir" >&2
    
    # Check current directory first
    if [[ -f "${current_dir}/ci/config.yaml" ]]; then
        config_file="${current_dir}/ci/config.yaml"
        log_info "Found config in current dir: $config_file" >&2
    # Check parent directory (common when running from platform checkout)
    elif [[ -f "${current_dir}/../ci/config.yaml" ]]; then
        config_file="${current_dir}/../ci/config.yaml"
        log_info "Found config in parent dir: $config_file" >&2
    # Check if we're in a service subdirectory (2 levels up)
    elif [[ -f "${current_dir}/../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../ci/config.yaml"
        log_info "Found config 2 levels up: $config_file" >&2
    # Check if we're deep in platform structure (6 levels up for zerotouch-platform/scripts/bootstrap/preview/tenants/scripts/)
    elif [[ -f "${current_dir}/../../../../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../../../../ci/config.yaml"
        log_info "Found config 6 levels up: $config_file" >&2
    # Check if we're in patches directory (7 levels up for zerotouch-platform/scripts/bootstrap/preview/patches/)
    elif [[ -f "${current_dir}/../../../../../../ci/config.yaml" ]]; then
        config_file="${current_dir}/../../../../../../ci/config.yaml"
        log_info "Found config 7 levels up: $config_file" >&2
    fi
    
    echo "$config_file"
}

# Get platform dependencies from service config
get_service_platform_dependencies() {
    local config_file="$1"
    
    log_info "Debug: Checking config file: $config_file" >&2
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "Debug: Config file not found: $config_file" >&2
        echo ""
        return
    fi
    
    if command -v yq &> /dev/null; then
        local deps=$(yq eval '.dependencies.platform[]' "$config_file" 2>/dev/null | tr '\n' ' ' || echo "")
        log_info "Debug: Raw dependencies: '$deps'" >&2
        echo "$deps"
    else
        log_error "yq is required but not installed"
        exit 1
    fi
}

# Generic function to disable any service by commenting out its kustomization entry
disable_service() {
    local service="$1"
    
    log_info "Disabling service: $service" >&2
    log_info "Debug: PLATFORM_ROOT = $PLATFORM_ROOT" >&2
    
    # Find the corresponding YAML file for this service
    local service_file=""
    log_info "Debug: Looking for YAML file for service: $service" >&2
    log_info "Debug: Glob pattern: ${PLATFORM_ROOT}/bootstrap/argocd/base/*.yaml" >&2
    
    for yaml_file in "${PLATFORM_ROOT}/bootstrap/argocd/base"/*.yaml; do
        log_info "Debug: Processing file: $yaml_file" >&2
        if [[ -f "$yaml_file" ]]; then
            local app_name
            app_name=$(yq eval '.metadata.name' "$yaml_file" 2>/dev/null | head -1 || echo "")
            
            log_info "Debug: Checking $yaml_file -> app_name: $app_name"
            
            if [[ -n "$app_name" && "$app_name" == "$service" ]]; then
                service_file="$yaml_file"
                log_info "Debug: Found matching file: $service_file" >&2
                break
            fi
        else
            log_warn "Debug: File not found: $yaml_file" >&2
        fi
    done
    
    if [[ -n "$service_file" ]]; then
        # Comment out the service in the kustomization file
        local kustomization_file="${PLATFORM_ROOT}/bootstrap/argocd/base/kustomization.yaml"
        local resource_name=$(basename "$service_file")
        
        log_info "Debug: kustomization_file: $kustomization_file" >&2
        log_info "Debug: resource_name: $resource_name" >&2
        
        if [[ -f "$kustomization_file" ]]; then
            # Create backup
            cp "$kustomization_file" "${kustomization_file}.bak"
            log_info "Debug: Created backup file" >&2
            
            # Comment out the resource line (macOS compatible)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|^- ${resource_name}|# DISABLED by conditional patch: ${resource_name}|" "$kustomization_file"
            else
                sed -i "s|^- ${resource_name}|# DISABLED by conditional patch: ${resource_name}|" "$kustomization_file"
            fi
            
            log_info "Debug: Applied sed command" >&2
            log_success "Disabled $service by commenting out $resource_name in kustomization.yaml" >&2
        else
            log_error "Kustomization file not found: $kustomization_file" >&2
        fi
    else
        log_warn "Could not find YAML file for service: $service" >&2
    fi
}

# Dynamically discover all available services from ArgoCD base applications
discover_all_services() {
    local all_services=()
    
    # Read the base kustomization to get all ArgoCD applications
    local kustomization_file="${PLATFORM_ROOT}/bootstrap/argocd/base/kustomization.yaml"
    
    log_info "Debug: Looking for kustomization file: $kustomization_file" >&2
    
    if [[ -f "$kustomization_file" ]]; then
        log_info "Debug: Found kustomization file" >&2
        # Extract resource file names from kustomization
        local resource_files
        resource_files=$(yq eval '.resources[]' "$kustomization_file" 2>/dev/null)
        
        log_info "Debug: Resource files: $resource_files" >&2
        
        for resource_file in $resource_files; do
            if [[ "$resource_file" == *.yaml ]]; then
                local app_file="${PLATFORM_ROOT}/bootstrap/argocd/base/$resource_file"
                log_info "Debug: Checking app file: $app_file" >&2
                if [[ -f "$app_file" ]]; then
                    # Extract application name from the YAML file
                    # Handle multi-document YAML files by taking only the first document
                    local app_name
                    app_name=$(yq eval '.metadata.name' "$app_file" 2>/dev/null | head -1)
                    
                    if [[ -n "$app_name" && "$app_name" != "---" ]]; then
                        log_info "Debug: Found app: $app_name" >&2
                        all_services+=("$app_name")
                    fi
                else
                    log_warn "Debug: App file not found: $app_file" >&2
                fi
            fi
        done
    else
        log_error "Debug: Kustomization file not found: $kustomization_file" >&2
    fi
    
    log_info "Debug: All services found: ${all_services[*]:-}" >&2
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
                    # Handle multi-document YAML files by taking only the first document
                    app_name=$(yq eval '.metadata.name' "$app_file" 2>/dev/null | head -1)
                    sync_wave=$(yq eval '.metadata.annotations."argocd.argoproj.io/sync-wave"' "$app_file" 2>/dev/null | head -1)
                    
                    # Set default sync-wave if not found or null
                    if [[ -z "$sync_wave" || "$sync_wave" == "null" ]]; then
                        sync_wave="999"
                    fi
                    
                    if [[ -n "$app_name" && "$app_name" != "---" ]]; then
                        # Foundation services: sync-wave 0-3 (core platform infrastructure)
                        # Wave 0: external-secrets
                        # Wave 1: crossplane-operator, kagent-crds  
                        # Wave 2: cnpg
                        # Wave 3: foundation-config
                        if [[ "$sync_wave" =~ ^[0-9]+$ && "$sync_wave" -le 3 ]]; then
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

log_success "Conditional optional services patch completed"