#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI Deploy Script
# ==============================================================================
# Purpose: GitOps service deployment automation
# 
# IMPORTANT: Preview vs Production Namespace Handling
# - Production: Namespaces created by tenant-infrastructure (ArgoCD app)  
# - Preview: Namespaces created by this CI script (mocks landing zones)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT should point to where the service code is checked out
# In CI workflows, service code is checked out to 'service-code' subdirectory
# The deploy script is called from service-code directory, so PROJECT_ROOT is current dir
PROJECT_ROOT="$(pwd)"

# Set PLATFORM_ROOT if not already set
if [[ -z "${PLATFORM_ROOT:-}" ]]; then
    # PLATFORM_ROOT should point to zerotouch-platform directory
    # When called from service directory, it's at ./zerotouch-platform
    PLATFORM_ROOT="$(cd "${PROJECT_ROOT}/zerotouch-platform" && pwd)"
fi

# Load service configuration from ci/config.yaml
load_service_config() {
    local config_file="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Service config not found: $config_file"
        echo "🔍 Debug: Current directory: $(pwd)"
        echo "🔍 Debug: Looking for config at: $config_file"
        exit 1
    fi
    
    if command -v yq &> /dev/null; then
        SERVICE_NAME=$(yq eval '.service.name' "$config_file")
        NAMESPACE=$(yq eval '.service.namespace' "$config_file")
        WAIT_TIMEOUT=$(yq eval '.deployment.wait_timeout // 300' "$config_file")
    else
        echo "❌ yq is required but not installed"
        exit 1
    fi
    
    if [[ -z "$SERVICE_NAME" || -z "$NAMESPACE" ]]; then
        echo "❌ service.name and service.namespace are required in ci/config.yaml"
        exit 1
    fi
}

# Load configuration
load_service_config

# Default values (can be overridden by environment or config)
ENVIRONMENT="${1:-ci}"
IMAGE_TAG="${2:-latest}"
# WAIT_TIMEOUT now loaded from config in load_service_config()

echo "🚀 Deploying ${SERVICE_NAME} to ${ENVIRONMENT} environment..."

cd "${PROJECT_ROOT}"

# Validate environment
case "${ENVIRONMENT}" in
    pr|dev|staging|production)
        echo "✅ Valid environment: ${ENVIRONMENT}"
        ;;
    *)
        echo "❌ Invalid environment: ${ENVIRONMENT}. Must be pr, dev, staging, or production"
        exit 1
        ;;
esac

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo "🔍 Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

# Mock Landing Zone (Preview Mode Only)
# In Production, tenant-infrastructure creates namespaces
# In Preview, CI must simulate this behavior
echo "📁 Setting up landing zone for preview mode..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Mock landing zone '${NAMESPACE}' created"

# Apply platform claims and manifests
echo "📋 Applying platform claims..."
CLAIMS_DIR="${PROJECT_ROOT}/platform/${SERVICE_NAME}/base/claims/"

if [[ ! -d "$CLAIMS_DIR" ]]; then
    echo "ℹ️  No platform claims directory found, skipping..."
elif [ -z "$(find "$CLAIMS_DIR" -maxdepth 1 \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null)" ]; then
    echo "ℹ️  No platform claims files found (directory is empty), skipping..."
else
    echo "✅ Found platform claims, applying..."
    kubectl apply -f "$CLAIMS_DIR" -n "${NAMESPACE}" --recursive
    echo "✅ Platform claims applied"
fi

# Apply external secrets with PR overlay patches
EXTERNAL_SECRETS_BASE="${PROJECT_ROOT}/platform/${SERVICE_NAME}/base/external-secrets"
EXTERNAL_SECRETS_OVERLAY="${PROJECT_ROOT}/platform/${SERVICE_NAME}/overlays/pr"

if [[ -d "$EXTERNAL_SECRETS_BASE" ]]; then
    echo "📋 Applying external secrets..."
    
    # Use Kustomize overlay if it exists, otherwise use base
    if [[ -f "$EXTERNAL_SECRETS_OVERLAY/kustomization.yaml" ]]; then
        echo "   Using PR overlay kustomization..."
        kubectl apply -k "$EXTERNAL_SECRETS_OVERLAY" -n "${NAMESPACE}"
    else
        echo "   Using base manifests (no overlay found)..."
        kubectl apply -f "$EXTERNAL_SECRETS_BASE" -n "${NAMESPACE}" --recursive
    fi
    
    echo "✅ External secrets applied"
    
    # Force immediate sync of secrets
    echo "🔄 Forcing immediate secret sync..."
    kubectl annotate externalsecret \
        -n "${NAMESPACE}" \
        -l zerotouch.io/managed=true \
        force-sync="$(date +%s)" \
        --overwrite
    
    echo "⏳ Waiting for secrets to become Ready..."
    kubectl wait \
        --for=condition=Ready \
        externalsecret \
        -n "${NAMESPACE}" \
        -l zerotouch.io/managed=true \
        --timeout=60s
    
    echo "✅ Secrets synced"
else
    echo "ℹ️  No ExternalSecrets found, skipping"
fi

# Apply overlay claims if they exist (for PR environment)
OVERLAY_CLAIMS_DIR="${PROJECT_ROOT}/platform/${SERVICE_NAME}/overlays/pr"
if [[ -d "$OVERLAY_CLAIMS_DIR" ]]; then
    echo "📋 Applying PR overlay claims..."
    # Skip certain files that shouldn't be applied directly
    for claim_file in "$OVERLAY_CLAIMS_DIR"/*.yaml; do
        if [[ -f "$claim_file" ]]; then
            filename=$(basename "$claim_file")
            if [[ "$filename" != "config.yaml" && "$filename" != kustomization* && "$filename" != *-job.yaml ]]; then
                echo "Applying: $filename"
                kubectl apply -f "$claim_file" -n "${NAMESPACE}"
            fi
        fi
    done
    echo "✅ PR overlay claims applied"
fi

# Check if service has internal database dependencies
has_internal_database_dependency() {
    local config_file="${PROJECT_ROOT}/ci/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Check if service has postgres in internal dependencies
    if command -v yq &> /dev/null; then
        local internal_deps=$(yq eval '.dependencies.internal[]?' "$config_file" 2>/dev/null | grep -E "postgres|database" || echo "")
        if [[ -n "$internal_deps" ]]; then
            return 0  # Has internal database dependency
        fi
    fi
    
    return 1  # No internal database dependency
}

# Wait for infrastructure dependencies using dedicated script (only if needed)
if has_internal_database_dependency; then
    echo "📋 Service has internal database dependencies, waiting for infrastructure..."
    INFRA_WAIT_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/wait-for-database-and-secrets.sh"
    if [[ -f "$INFRA_WAIT_SCRIPT" ]]; then
        chmod +x "$INFRA_WAIT_SCRIPT"
        # Ensure we exit if the wait script fails
        if ! "$INFRA_WAIT_SCRIPT" "${SERVICE_NAME}" "${NAMESPACE}"; then
            echo "❌ ERROR: Infrastructure dependencies failed to become ready"
            exit 1
        fi
    else
        echo "❌ Database and secrets wait script not found: $INFRA_WAIT_SCRIPT"
        exit 1
    fi
else
    echo "📋 Service has no internal database dependencies, skipping infrastructure wait"
fi

# Use platform's generalized wait script for Platform Services (EventDrivenService or WebService)
WAIT_SCRIPT="${PLATFORM_ROOT}/scripts/bootstrap/wait/wait-for-platform-service.sh"
if [[ -f "$WAIT_SCRIPT" ]]; then
    chmod +x "$WAIT_SCRIPT"
    "$WAIT_SCRIPT" "${SERVICE_NAME}" "${NAMESPACE}" "${WAIT_TIMEOUT}"
else
    echo "❌ Platform service wait script not found: $WAIT_SCRIPT"
    exit 1
fi

# Always update image tag with what CI provides
echo "🏷️  Image tag already updated by patch-service-images.sh: ${IMAGE_TAG}..."
echo "✅ Platform claims already patched with correct image tags"

echo "✅ Platform service deployment completed (verified by wait script)"

echo "🎉 Deployment completed successfully!"