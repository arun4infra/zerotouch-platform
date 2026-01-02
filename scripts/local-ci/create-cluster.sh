#!/bin/bash
# Local CI simulation for create-cluster workflow
# Usage: ./create-cluster.sh <environment> [--skip-rescue-mode]
# Example: ./create-cluster.sh dev
# cd zerotouch-platform && set -a && source .env && set +a && ./scripts/local-ci/create-cluster.sh dev

set -e

ENVIRONMENT="${1:-dev}"
SKIP_RESCUE_MODE=false
if [ "$2" = "--skip-rescue-mode" ]; then
    SKIP_RESCUE_MODE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/create-cluster-${ENVIRONMENT}-${TIMESTAMP}.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to run command with logging
run_with_log() {
    log "Running: $*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -ne 0 ]; then
        log "Command failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Set CI environment variable to match workflow
export CI=true

log "╔══════════════════════════════════════════════════════════════╗"
log "║   Local CI: Create Cluster Workflow                         ║"
log "╚══════════════════════════════════════════════════════════════╝"
log "Environment: $ENVIRONMENT"
log "Log file: $LOG_FILE"
log ""

# Setup environment (matching workflow)
log "==> Step 0: Setup environment..."
if ! command -v python3 &> /dev/null; then
    log "⚠ Python3 not found, please install it"
    exit 1
fi

# Install pyyaml if not available
python3 -c "import yaml" 2>/dev/null || pip3 install pyyaml

log "✓ Environment setup complete"
log ""

# Step 1: Validate environment overlay exists
log "==> Step 1: Validating environment overlay..."
OVERLAY_DIR="$REPO_ROOT/bootstrap/argocd/overlays/main/$ENVIRONMENT"

if [ -d "$OVERLAY_DIR" ]; then
    log "✓ Environment overlay found: $OVERLAY_DIR"
else
    log "✗ Environment overlay not found: $OVERLAY_DIR"
    log "  Available overlays: $(ls -1 "$REPO_ROOT/bootstrap/argocd/overlays/main/" | tr '\n' ' ')"
    exit 1
fi
log ""

# Step 2: Enable Rescue Mode
if [ "$SKIP_RESCUE_MODE" = false ]; then
    log "==> Step 2: Enable Rescue Mode..."
    run_with_log "$REPO_ROOT/scripts/bootstrap/00-enable-rescue-mode.sh" "$ENVIRONMENT" -y
    
    log "==> Step 3: Wait for rescue mode boot (90s)..."
    sleep 90
else
    log "==> Step 2-3: Skipping rescue mode (--skip-rescue-mode)"
fi
log ""

# Step 4: Bootstrap Cluster
log "==> Step 4: Running bootstrap..."
run_with_log "$REPO_ROOT/scripts/bootstrap/01-master-bootstrap.sh" "$ENVIRONMENT"
