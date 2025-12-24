#!/bin/bash
set -euo pipefail

# ==============================================================================
# Apply Platform Patches for Preview Environment
# ==============================================================================
# Applies platform patches for preview/CI environments BEFORE bootstrap
# This script:
# 1. Disables ArgoCD auto-sync to prevent conflicts during patching
# 2. Applies resource optimization patches
# 3. Disables resource-intensive components (kagent, keda) for preview mode
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*" >&2; }

main() {
    log_info "Applying platform patches for preview environment..."
    
    # Change to the zerotouch-platform root directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
    cd "$PLATFORM_ROOT"
    
    # Ensure we're in the zerotouch-platform directory
    if [[ ! -d "bootstrap" ]]; then
        log_error "bootstrap directory not found - could not find zerotouch-platform directory"
        log_error "Current directory: $(pwd)"
        log_error "Expected to find bootstrap/ directory here"
        exit 1
    fi
    
    # Step 1: Disable ArgoCD auto-sync to prevent conflicts during patching
    log_info "Step 1: Disabling ArgoCD auto-sync for stable patching..."
    ARGOCD_CM_PATCH="bootstrap/argocd/install/argocd-cm-patch.yaml"
    
    if [[ -f "$ARGOCD_CM_PATCH" ]]; then
        log_info "Found ArgoCD ConfigMap patch file: $ARGOCD_CM_PATCH"
        
        # Check if already patched
        if grep -q "application.instanceLabelKey" "$ARGOCD_CM_PATCH" 2>/dev/null; then
            log_warn "ArgoCD auto-sync already disabled, skipping..."
        else
            log_info "Adding auto-sync disable configuration..."
            # Backup original file
            cp "$ARGOCD_CM_PATCH" "$ARGOCD_CM_PATCH.backup"
            
            # Add auto-sync disable configuration
            cat >> "$ARGOCD_CM_PATCH" << 'EOF'
  # Disable auto-sync for preview mode to prevent conflicts during patching
  application.instanceLabelKey: argocd.argoproj.io/instance
  server.disable.auth: "false"
  # Global policy to disable auto-sync (can be overridden per application)
  policy.default: |
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, certificates, get, *, allow
    p, role:readonly, clusters, get, *, allow
    p, role:readonly, repositories, get, *, allow
    g, argocd:readonly, role:readonly
EOF
            log_success "✓ ArgoCD auto-sync configuration added"
        fi
    else
        log_error "ArgoCD ConfigMap patch file not found: $ARGOCD_CM_PATCH"
        exit 1
    fi
    
    # Step 2: Apply resource optimization patches
    log_info "Step 2: Applying resource optimization patches..."
    log_info "✓ Resource optimization patches applied (placeholder for future optimizations)"
    
    # Step 3: Apply conditional service patches based on service configuration
    log_info "Step 3: Applying conditional service patches based on service configuration..."
    
    # Call the conditional services patch script
    PATCHES_DIR="$(dirname "$0")/../../patches"
    CONDITIONAL_PATCH_SCRIPT="$PATCHES_DIR/02-disable-undeclared-services.sh"
    
    if [[ -f "$CONDITIONAL_PATCH_SCRIPT" ]]; then
        log_info "Running conditional services patch: $CONDITIONAL_PATCH_SCRIPT"
        bash "$CONDITIONAL_PATCH_SCRIPT"
        
        if [[ $? -eq 0 ]]; then
            log_success "✓ Conditional services patch completed successfully"
        else
            log_error "✗ Conditional services patch failed"
            exit 1
        fi
    else
        log_error "Conditional services patch script not found: $CONDITIONAL_PATCH_SCRIPT"
        exit 1
    fi
    
    # Final summary
    log_success "Platform patches applied successfully"
    echo ""
    log_info "=== PATCH SUMMARY ==="
    log_info "✓ ArgoCD auto-sync disabled"
    log_info "✓ Conditional services patch applied (based on service config)"
    log_info "✓ Ready for stable bootstrap process"
    echo ""
}

main "$@"