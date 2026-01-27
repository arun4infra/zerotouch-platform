#!/bin/bash
set -euo pipefail

# ==============================================================================
# Environment Detection Script
# ==============================================================================
# Purpose: Detect if we're in PR or main branch environment
# Usage: ./detect-environment.sh
# Returns: "pr" or "main"
#
# IMPORTANT: This detection is for INFORMATIONAL purposes only in CI testing.
# - in-cluster-test.sh ALWAYS uses 'pr' overlays for testing (Kind cluster)
# - Release deployments use deploy-direct.sh with dev/staging/production overlays
# - Branch detection helps with logging/debugging but doesn't affect overlay selection
# ==============================================================================

detect_environment() {
    local detected_env=""
    
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        # In GitHub Actions - use event context
        if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
            detected_env="pr"
            echo "Detected GitHub Actions PR event" >&2
        elif [[ "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
            detected_env="pr"  # CI testing always uses pr overlays
            echo "Detected GitHub Actions main branch (using pr for CI testing)" >&2
        else
            detected_env="pr"  # Default to PR for other branches in CI
            echo "Detected GitHub Actions other branch (defaulting to pr)" >&2
        fi
    else
        # Local execution - always return PR for testing
        detected_env="pr"
        echo "Detected local execution (defaulting to pr)" >&2
    fi
    
    echo "$detected_env"
}

# Main execution
ENVIRONMENT=$(detect_environment)
echo "Detected environment: $ENVIRONMENT" >&2
echo "" >&2
echo "NOTE: This detection is INFORMATIONAL only for CI testing context." >&2
echo "- CI tests (in-cluster-test.sh) ALWAYS use 'pr' overlays in Kind cluster" >&2
echo "- Release deployments use deploy-direct.sh with dev/staging/production overlays" >&2
echo "- Branch detection helps with logging but doesn't affect overlay selection" >&2
echo "$ENVIRONMENT"