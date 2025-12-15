#!/bin/bash
# Fetch tenant configuration from private zerotouch-tenants repository
#
# Usage:
#   source ./helpers/fetch-tenant-config.sh <ENV> [--use-cache]
#   # Sets: TENANT_CONFIG_FILE

set -e

ENV="${1:-dev}"
USE_CACHE=false

if [[ "$2" == "--use-cache" ]]; then
    USE_CACHE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CACHE_DIR="$REPO_ROOT/.tenants-cache"
ENV_FILE="$CACHE_DIR/environments/$ENV/talos-values.yaml"

# Source .env.ssm to get tenant repo credentials
if [[ ! -f "$REPO_ROOT/.env.ssm" ]]; then
    echo "Error: .env.ssm not found at $REPO_ROOT/.env.ssm" >&2
    exit 1
fi

# Parse .env.ssm for tenant repo URL and credentials
TENANT_REPO_URL=$(grep "^/zerotouch/prod/argocd/repos/zerotouch-tenants/url=" "$REPO_ROOT/.env.ssm" | cut -d'=' -f2)
TENANT_USERNAME=$(grep "^/zerotouch/prod/argocd/repos/zerotouch-tenants/username=" "$REPO_ROOT/.env.ssm" | cut -d'=' -f2)
TENANT_PASSWORD=$(grep "^/zerotouch/prod/argocd/repos/zerotouch-tenants/password=" "$REPO_ROOT/.env.ssm" | cut -d'=' -f2)

if [[ -z "$TENANT_REPO_URL" ]]; then
    echo "Error: Tenant repository URL not found in .env.ssm" >&2
    echo "Expected: /zerotouch/prod/argocd/repos/zerotouch-tenants/url=..." >&2
    exit 1
fi

# Convert HTTPS URL to include credentials
TENANT_REPO_AUTH_URL=$(echo "$TENANT_REPO_URL" | sed "s|https://|https://${TENANT_USERNAME}:${TENANT_PASSWORD}@|")

# Use cache if requested and exists
if [[ "$USE_CACHE" == "true" ]] && [[ -f "$ENV_FILE" ]]; then
    echo "✓ Using cached tenant config" >&2
    export TENANT_CONFIG_FILE="$ENV_FILE"
    export TENANT_CACHE_DIR="$CACHE_DIR"
    return 0
fi

# Clone or update cache
if [[ -d "$CACHE_DIR/.git" ]]; then
    echo "Updating tenant config cache..." >&2
    cd "$CACHE_DIR"
    git fetch origin main --quiet 2>/dev/null || {
        echo "Error: Failed to fetch from tenant repository" >&2
        exit 1
    }
    git reset --hard origin/main --quiet
else
    echo "Cloning tenant config repository..." >&2
    rm -rf "$CACHE_DIR"
    
    # Sparse checkout - only environments folder
    git clone --filter=blob:none --no-checkout --depth 1 --branch main \
        "$TENANT_REPO_AUTH_URL" "$CACHE_DIR" --quiet 2>/dev/null || {
        echo "Error: Failed to clone tenant repository" >&2
        echo "Check credentials in .env.ssm" >&2
        exit 1
    }
    
    cd "$CACHE_DIR"
    git sparse-checkout init --cone 2>/dev/null
    git sparse-checkout set environments 2>/dev/null
    git checkout main --quiet 2>/dev/null
    git pull origin main --quiet 2>/dev/null
fi

# Verify environment file exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: Environment config not found: $ENV" >&2
    echo "Path: $ENV_FILE" >&2
    exit 1
fi

echo "✓ Tenant config fetched: $ENV" >&2

export TENANT_CONFIG_FILE="$ENV_FILE"
export TENANT_CACHE_DIR="$CACHE_DIR"
