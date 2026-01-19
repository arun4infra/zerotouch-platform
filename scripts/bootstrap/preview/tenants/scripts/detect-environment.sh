#!/bin/bash
set -euo pipefail

# ==============================================================================
# Environment Detection Script
# ==============================================================================
# Purpose: Detect if we're in PR or main branch environment
# Usage: ./detect-environment.sh
# Returns: "pr" or "main"
# ==============================================================================

detect_environment() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        # In GitHub Actions - use event context
        if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
            echo "pr"
        elif [[ "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
            echo "main"
        else
            echo "pr"  # Default to PR for other branches in CI
        fi
    else
        # Local execution - always return PR for testing
        echo "pr"
    fi
}

# Main execution
ENVIRONMENT=$(detect_environment)
echo "Detected environment: $ENVIRONMENT"
echo "$ENVIRONMENT"