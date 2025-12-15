#!/bin/bash
# Test script to verify tenant config fetching works

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "Testing tenant configuration fetch..."
echo ""

# Test 1: Check .env.ssm exists
echo "✓ Checking .env.ssm..."
if [[ ! -f "$REPO_ROOT/.env.ssm" ]]; then
    echo "✗ Error: .env.ssm not found"
    exit 1
fi

# Test 2: Check tenant URL is configured
echo "✓ Checking tenant repository URL..."
TENANT_URL=$(grep "^/zerotouch/prod/argocd/repos/zerotouch-tenants/url=" "$REPO_ROOT/.env.ssm" | cut -d'=' -f2)
if [[ -z "$TENANT_URL" ]]; then
    echo "✗ Error: Tenant URL not found in .env.ssm"
    exit 1
fi
echo "  URL: $TENANT_URL"

# Test 3: Try fetching dev environment
echo "✓ Fetching dev environment config..."
source "$SCRIPT_DIR/fetch-tenant-config.sh" dev

if [[ -z "$TENANT_CONFIG_FILE" ]]; then
    echo "✗ Error: TENANT_CONFIG_FILE not set"
    exit 1
fi

if [[ ! -f "$TENANT_CONFIG_FILE" ]]; then
    echo "✗ Error: Config file not found: $TENANT_CONFIG_FILE"
    exit 1
fi

echo "  Config file: $TENANT_CONFIG_FILE"

# Test 4: Verify file content
echo "✓ Verifying config file content..."
if ! grep -q "controlplane:" "$TENANT_CONFIG_FILE"; then
    echo "✗ Error: Invalid config file format"
    exit 1
fi

echo ""
echo "✓ All tests passed!"
echo ""
echo "Cache location: $TENANT_CACHE_DIR"
echo "Config file: $TENANT_CONFIG_FILE"
