#!/bin/bash
# Apply Service-Specific Patches
# Usage: ./apply-service-patches.sh [--service-dir <path>]
#
# This script applies service-specific patches to platform claims before deployment.
# Service patches are located in <service-root>/scripts/patches/

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[APPLY-SERVICE-PATCHES]${NC} $*"; }
log_success() { echo -e "${GREEN}[APPLY-SERVICE-PATCHES]${NC} $*"; }
log_error() { echo -e "${RED}[APPLY-SERVICE-PATCHES]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[APPLY-SERVICE-PATCHES]${NC} $*"; }

# Default service directory (relative to platform scripts)
SERVICE_DIR="../.."

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service-dir)
            SERVICE_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--service-dir <path>]"
            echo ""
            echo "Apply service-specific patches to platform claims before deployment."
            echo ""
            echo "Options:"
            echo "  --service-dir <path>  Path to service root directory (default: ../..)"
            echo "  --help               Show this help message"
            echo ""
            echo "Service patches should be located in: <service-dir>/scripts/patches/"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Resolve absolute path to service directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

if [[ "$SERVICE_DIR" == /* ]]; then
    # Absolute path provided - use as-is
    log_info "Using absolute service directory: $SERVICE_DIR"
else
    # Relative path provided - resolve from workspace root
    log_info "Resolving relative service directory: $SERVICE_DIR from workspace: $WORKSPACE_ROOT"
    if ! SERVICE_DIR="$(cd "$WORKSPACE_ROOT/$SERVICE_DIR" && pwd)"; then
        log_error "Failed to resolve service directory: $WORKSPACE_ROOT/$SERVICE_DIR"
        exit 1
    fi
fi
SERVICE_PATCHES_DIR="$SERVICE_DIR/scripts/patches"

log_info "Service directory: $SERVICE_DIR"
log_info "Looking for patches in: $SERVICE_PATCHES_DIR"

# Check if service patches directory exists
if [[ ! -d "$SERVICE_PATCHES_DIR" ]]; then
    log_info "No service patches directory found at $SERVICE_PATCHES_DIR"
    log_info "Skipping service-specific patches"
    exit 0
fi

# Find and apply service patches
PATCHES_FOUND=false
PATCHES_APPLIED=0
PATCHES_FAILED=0

log_info "Applying service-specific patches..."

for patch in "$SERVICE_PATCHES_DIR"/[0-9][0-9]-*.sh; do
    if [[ -f "$patch" ]]; then
        PATCHES_FOUND=true
        patch_name="$(basename "$patch")"
        
        log_info "Applying service patch: $patch_name"
        
        # Make patch executable
        chmod +x "$patch"
        
        # Apply patch with --force flag (for preview mode)
        if "$patch" --force; then
            log_success "✓ Applied: $patch_name"
            PATCHES_APPLIED=$((PATCHES_APPLIED + 1))
        else
            log_warn "⚠ Failed: $patch_name (continuing...)"
            PATCHES_FAILED=$((PATCHES_FAILED + 1))
        fi
    fi
done

# Summary
if [[ "$PATCHES_FOUND" == false ]]; then
    log_info "No service patches found (no files matching [0-9][0-9]-*.sh)"
    exit 0
fi

log_info "Service patches summary:"
log_info "  Applied: $PATCHES_APPLIED"
if [[ $PATCHES_FAILED -gt 0 ]]; then
    log_warn "  Failed: $PATCHES_FAILED"
fi

if [[ $PATCHES_APPLIED -gt 0 ]]; then
    log_success "Service patches applied successfully"
else
    log_warn "No service patches were applied"
fi

exit 0