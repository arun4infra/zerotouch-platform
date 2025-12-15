#!/bin/bash
# Update tenant configuration and push to private repository
#
# Usage:
#   ./helpers/update-tenant-config.sh <FILE_PATH> <COMMIT_MESSAGE>

set -e

FILE_PATH="$1"
COMMIT_MESSAGE="${2:-Update tenant configuration}"

if [[ -z "$FILE_PATH" ]]; then
    echo "Error: File path required" >&2
    echo "Usage: $0 <file-path> [commit-message]" >&2
    exit 1
fi

if [[ ! -f "$FILE_PATH" ]]; then
    echo "Error: File not found: $FILE_PATH" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CACHE_DIR="$REPO_ROOT/.tenants-cache"

# Verify file is in cache directory
if [[ ! "$FILE_PATH" =~ ^"$CACHE_DIR" ]]; then
    echo "Error: File must be in tenant cache directory" >&2
    exit 1
fi

if [[ ! -d "$CACHE_DIR/.git" ]]; then
    echo "Error: Tenant cache not initialized" >&2
    exit 1
fi

cd "$CACHE_DIR"

# Check if there are changes
if git diff --quiet "$FILE_PATH"; then
    echo "No changes to commit" >&2
    return 0
fi

echo "Committing changes to tenant repository..." >&2

# Configure git if needed
git config user.email "bootstrap@zerotouch.dev" 2>/dev/null || true
git config user.name "ZeroTouch Bootstrap" 2>/dev/null || true

# Commit and push
git add "$FILE_PATH"
git commit -m "$COMMIT_MESSAGE" --quiet
git push origin main --quiet 2>/dev/null || {
    echo "Error: Failed to push to tenant repository" >&2
    exit 1
}

echo "✓ Changes pushed to tenant repository" >&2
