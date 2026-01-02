#!/bin/bash
# Local CI simulation for create-cluster workflow
# Usage: ./create-cluster.sh <environment> [--skip-rescue-mode]
# Example: ./create-cluster.sh dev

set -e

ENVIRONMENT="${1:-dev}"
SKIP_RESCUE_MODE=false
if [ "$2" = "--skip-rescue-mode" ]; then
    SKIP_RESCUE_MODE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Set CI environment variable to match workflow
export CI=true

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Local CI: Create Cluster Workflow                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "Environment: $ENVIRONMENT"
echo ""

# Setup environment (matching workflow)
echo "==> Step 0: Setup environment..."
if ! command -v python3 &> /dev/null; then
    echo "⚠ Python3 not found, please install it"
    exit 1
fi

# Install pyyaml if not available
python3 -c "import yaml" 2>/dev/null || pip3 install pyyaml

echo "✓ Environment setup complete"
echo ""

# Step 1: Validate environment overlay exists
echo "==> Step 1: Validating environment overlay..."
OVERLAY_DIR="$REPO_ROOT/bootstrap/argocd/overlays/main/$ENVIRONMENT"

if [ -d "$OVERLAY_DIR" ]; then
    echo "✓ Environment overlay found: $OVERLAY_DIR"
else
    echo "✗ Environment overlay not found: $OVERLAY_DIR"
    echo "  Available overlays: $(ls -1 "$REPO_ROOT/bootstrap/argocd/overlays/main/" | tr '\n' ' ')"
    exit 1
fi
echo ""

# Step 2: Enable Rescue Mode
if [ "$SKIP_RESCUE_MODE" = false ]; then
    echo "==> Step 2: Enable Rescue Mode..."
    "$REPO_ROOT/scripts/bootstrap/00-enable-rescue-mode.sh" "$ENVIRONMENT" -y
    
    echo "==> Step 3: Wait for rescue mode boot (90s)..."
    sleep 90
else
    echo "==> Step 2-3: Skipping rescue mode (--skip-rescue-mode)"
fi
echo ""

# Step 4: Bootstrap Cluster
echo "==> Step 4: Running bootstrap..."
"$REPO_ROOT/scripts/bootstrap/01-master-bootstrap.sh" "$ENVIRONMENT"
