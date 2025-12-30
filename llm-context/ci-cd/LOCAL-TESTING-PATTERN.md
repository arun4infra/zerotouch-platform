## Create ./scripts/ci/in-cluster-test.sh

```bash
#!/bin/bash
set -euo pipefail

# ==============================================================================
# Service CI Entry Point for ide-orchestrator
# ==============================================================================
# Purpose: Standardized entry point for platform-based CI testing
# Usage: ./scripts/ci/in-cluster-test.sh
# ==============================================================================

# Get platform branch from service config
if [[ -f "ci/config.yaml" ]]; then
    if command -v yq &> /dev/null; then
        PLATFORM_BRANCH=$(yq eval '.platform.branch // "main"' ci/config.yaml)
    else
        PLATFORM_BRANCH="main"
    fi
else
    PLATFORM_BRANCH="main"
fi

# Always ensure fresh platform checkout
if [[ -d "zerotouch-platform" ]]; then
    echo "Removing existing platform checkout for fresh clone..."
    rm -rf zerotouch-platform
fi

echo "Cloning fresh zerotouch-platform repository (branch: $PLATFORM_BRANCH)..."
git clone -b "$PLATFORM_BRANCH" https://github.com/arun4infra/zerotouch-platform.git zerotouch-platform

# Run platform script
./zerotouch-platform/scripts/bootstrap/preview/tenants/in-cluster-test.sh

```

## Update .env file

```bash
# AWS Credentials (dummy values for local preview mode)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
BOT_GITHUB_USERNAME=
BOT_GITHUB_TOKEN=
TENANTS_REPO_NAME=zerotouch-tenants
ANTHROPIC_API_KEY=12345567
AWS_ROLE_ARN=
```

## Run below command,

```bash
export CLEANUP_CLUSTER=false && export $(grep -v '^#' .env | grep -v '^$' | xargs) && ./scripts/ci/in-cluster-test.sh
```