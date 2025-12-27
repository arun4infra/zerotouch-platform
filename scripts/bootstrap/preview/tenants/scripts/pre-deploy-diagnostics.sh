#!/bin/bash
set -euo pipefail

# ==============================================================================
# Pre-Deploy Diagnostics Script
# ==============================================================================
# Purpose: Run pre-deployment diagnostics based on service config
# Usage: ./pre-deploy-diagnostics.sh
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PRE-DEPLOY]${NC} $*"; }
log_success() { echo -e "${GREEN}[PRE-DEPLOY]${NC} $*"; }
log_error() { echo -e "${RED}[PRE-DEPLOY]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PRE-DEPLOY]${NC} $*"; }

# Helper function to check if a config flag is enabled
config_enabled() {
    local config_path="$1"
    if command -v yq &> /dev/null; then
        local value=$(yq eval ".$config_path // false" ci/config.yaml 2>/dev/null)
        [[ "$value" == "true" ]]
    else
        # Fallback: assume enabled if not specified
        return 0
    fi
}

# Load service configuration from ci/config.yaml
load_service_config() {
    # Look for ci/config.yaml in current directory (service directory)
    local config_file="ci/config.yaml"
    
    # If not found in current directory, try one level up (in case we're in platform dir)
    if [[ ! -f "$config_file" ]]; then
        config_file="../ci/config.yaml"
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_error "ci/config.yaml not found - cannot run diagnostics"
        log_error "Looked in: ./ci/config.yaml and ../ci/config.yaml"
        log_error "Current directory: $(pwd)"
        exit 1
    fi
    
    log_info "Using config file: $config_file"
    
    if command -v yq &> /dev/null; then
        SERVICE_NAME=$(yq eval '.service.name' "$config_file")
        NAMESPACE=$(yq eval '.service.namespace' "$config_file")
    else
        log_error "yq is required but not installed"
        exit 1
    fi
    
    log_info "Service config loaded: ${SERVICE_NAME} in ${NAMESPACE}"
}

# Check platform dependencies from config
check_platform_dependencies() {
    log_info "Checking platform dependencies from config..."
    
    local config_file="ci/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        config_file="../ci/config.yaml"
    fi
    
    # Get platform dependencies from config
    local platform_deps=$(yq eval '.dependencies.platform[]?' "$config_file" 2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$platform_deps" ]]; then
        log_info "No platform dependencies specified in config"
        return 0
    fi
    
    log_info "Platform dependencies from config: $platform_deps"
    
    for dep in $platform_deps; do
        log_info "Checking platform dependency: $dep"
        
        local found=false
        local found_namespace=""
        local found_type=""
        local found_name=""
        
        # First try to find exact match by name
        local deployment_result=$(kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.metadata.name=="'$dep'")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
        local statefulset_result=$(kubectl get statefulsets --all-namespaces -o jsonpath='{range .items[?(@.metadata.name=="'$dep'")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
        
        if [[ -n "$deployment_result" ]]; then
            found_namespace=$(echo "$deployment_result" | awk '{print $1}')
            found_type="deployment"
            found_name="$dep"
            found=true
        elif [[ -n "$statefulset_result" ]]; then
            found_namespace=$(echo "$statefulset_result" | awk '{print $1}')
            found_type="statefulset"
            found_name="$dep"
            found=true
        else
            # Try common variations
            for variation in "${dep}-operator" "${dep}-controller" "${dep}-server" "${dep}-admission-webhooks"; do
                local var_deployment_result=$(kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.metadata.name=="'$variation'")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
                if [[ -n "$var_deployment_result" ]]; then
                    found_namespace=$(echo "$var_deployment_result" | awk '{print $1}')
                    found_type="deployment"
                    found_name="$variation"
                    found=true
                    break
                fi
            done
        fi
        
        if [[ "$found" == "true" ]]; then
            # Verify the namespace exists
            if kubectl get namespace "$found_namespace" &>/dev/null; then
                log_success "✓ Platform dependency '$dep' found as $found_type '$found_name' in namespace '$found_namespace'"
            else
                log_error "✗ Platform dependency '$dep' found but namespace '$found_namespace' does not exist"
                exit 1
            fi
        else
            log_error "✗ Platform dependency '$dep' not found in cluster"
            log_error "Service declared '$dep' as a platform dependency in ci/config.yaml"
            log_error "This dependency must be deployed and running for the service to function correctly"
            exit 1
        fi
    done
}

# Check external dependencies from config
check_external_dependencies() {
    log_info "Checking external dependencies from config..."
    
    local config_file="ci/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        config_file="../ci/config.yaml"
    fi
    
    # Get external dependencies from config
    local external_deps=$(yq eval '.dependencies.external[]?' "$config_file" 2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$external_deps" ]]; then
        log_info "No external dependencies specified in config"
        return 0
    fi
    
    log_info "External dependencies from config: $external_deps"
    
    for dep in $external_deps; do
        log_info "Checking external dependency: $dep"
        
        # Try to find the service in common namespaces
        local found=false
        local common_namespaces=("intelligence-deepagents" "intelligence-orchestrator" "intelligence" "default")
        
        for ns in "${common_namespaces[@]}"; do
            if kubectl get deployment "$dep" -n "$ns" &>/dev/null; then
                log_success "✓ External dependency '$dep' found in namespace '$ns'"
                found=true
                break
            fi
        done
        
        if [[ "$found" == "false" ]]; then
            # Try to find it in any namespace
            if kubectl get deployment "$dep" --all-namespaces &>/dev/null; then
                local found_ns=$(kubectl get deployment "$dep" --all-namespaces -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
                log_success "✓ External dependency '$dep' found in namespace '$found_ns'"
            else
                log_error "✗ External dependency '$dep' not found in any namespace"
                exit 1
            fi
        fi
    done
}

# Check platform APIs based on dependencies
check_platform_apis() {
    log_info "Checking required platform APIs based on dependencies..."
    
    local config_file="ci/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        config_file="../ci/config.yaml"
    fi
    
    # Get all available XRDs in the cluster
    local available_xrds=$(kubectl get xrd -o name 2>/dev/null | sed 's|customresourcedefinition.apiextensions.k8s.io/||' || echo "")
    
    if [[ -z "$available_xrds" ]]; then
        log_warn "⚠ No XRDs found in cluster - Crossplane may not be installed"
        return 0
    fi
    
    log_info "Found $(echo "$available_xrds" | wc -w) XRDs in cluster"
    
    # Get internal dependencies to check for relevant XRDs
    local internal_deps=$(yq eval '.dependencies.internal[]?' "$config_file" 2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$internal_deps" ]]; then
        log_info "No internal dependencies specified - checking for any platform XRDs"
        local xrd_count=$(echo "$available_xrds" | wc -w)
        if [[ $xrd_count -gt 0 ]]; then
            log_success "✓ Found $xrd_count platform XRDs available"
        else
            log_warn "⚠ No platform XRDs found"
        fi
        return 0
    fi
    
    log_info "Internal dependencies from config: $internal_deps"
    
    # For each internal dependency, try to find a matching XRD
    for dep in $internal_deps; do
        log_info "Looking for XRDs related to internal dependency: $dep"
        
        # Look for XRDs that might be related to this dependency
        local matching_xrds=$(echo "$available_xrds" | grep -i "$dep" || echo "")
        
        if [[ -n "$matching_xrds" ]]; then
            log_success "✓ Found XRDs related to '$dep': $(echo $matching_xrds | tr '\n' ' ')"
        else
            log_info "No specific XRDs found for '$dep' - may be handled by generic platform resources"
        fi
    done
    
    # General platform readiness check
    local total_xrds=$(echo "$available_xrds" | wc -w)
    if [[ $total_xrds -gt 0 ]]; then
        log_success "✓ Platform APIs ready - $total_xrds XRDs available for resource provisioning"
    else
        log_error "✗ No platform XRDs available - infrastructure provisioning may not work"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Running pre-deploy diagnostics based on ci/config.yaml"
    
    # Load service configuration
    load_service_config
    
    echo "================================================================================"
    echo "Platform Pre-Deploy Diagnostics"
    echo "================================================================================"
    echo "  Service:    ${SERVICE_NAME}"
    echo "  Namespace:  ${NAMESPACE}"
    echo "================================================================================"
    
    # Check dependencies if enabled in config
    if config_enabled "diagnostics.pre_deploy.check_dependencies"; then
        log_info "Checking dependencies (enabled in config)..."
        check_platform_dependencies
        check_external_dependencies
    else
        log_info "Dependencies check disabled in config"
    fi
    
    # Check platform APIs if enabled in config
    if config_enabled "diagnostics.pre_deploy.check_platform_apis"; then
        log_info "Checking platform APIs (enabled in config)..."
        check_platform_apis
    else
        log_info "Platform API checks disabled in config"
    fi
    
    log_success "✅ Pre-deploy diagnostics completed successfully"
    log_info "Platform infrastructure is ready for ${SERVICE_NAME} deployment"
}

main "$@"