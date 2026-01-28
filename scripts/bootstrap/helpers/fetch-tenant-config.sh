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
# Find repository root by looking for .git directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"
CACHE_DIR="$REPO_ROOT/.tenants-cache"
ENV_FILE="$CACHE_DIR/environments/$ENV/talos-values.yaml"

# Get tenant repo credentials from environment variables
GITHUB_USERNAME="${BOT_GITHUB_USERNAME:-${GITHUB_REPOSITORY_OWNER:-arun4infra}}"
if [[ -n "$GITHUB_USERNAME" && -n "$BOT_GITHUB_TOKEN" && -n "$TENANTS_REPO_NAME" ]]; then
    TENANT_USERNAME="$GITHUB_USERNAME"
    TENANT_PASSWORD="$BOT_GITHUB_TOKEN"
    TENANT_REPO_URL="https://github.com/${GITHUB_USERNAME}/${TENANTS_REPO_NAME}.git"
    echo "✓ Using tenant repo credentials from environment variables" >&2
else
    echo "Error: Tenant repository credentials not available" >&2
    echo "Set environment variables: BOT_GITHUB_TOKEN, TENANTS_REPO_NAME" >&2
    echo "Optional: BOT_GITHUB_USERNAME (defaults to GITHUB_REPOSITORY_OWNER)" >&2
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
        echo "Check credentials: BOT_GITHUB_TOKEN, TENANTS_REPO_NAME" >&2
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
