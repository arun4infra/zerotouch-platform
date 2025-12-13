#!/bin/bash
set -e

# Preview Environment Setup Script
# Configures platform for Kind/preview environments using Kustomize overlays
# Usage: ./setup-preview.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

log_info "Setting up preview environment configurations..."

# 1. Verify Kustomize overlays exist
log_info "Verifying Kustomize overlay structure..."

if [[ ! -d "$REPO_ROOT/platform/05-databases/overlays/development" ]]; then
    log_warn "Development overlay not found - using industry standard approach"
    
    # Create the overlay structure if it doesn't exist
    mkdir -p "$REPO_ROOT/platform/05-databases/overlays/development"
    mkdir -p "$REPO_ROOT/platform/05-databases/overlays/production"
    
    # Create base kustomization
    cat > "$REPO_ROOT/platform/05-databases/overlays/kustomization.yaml" << 'EOF'
# Base kustomization for database compositions
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../compositions/postgres-composition.yaml
  - ../compositions/dragonfly-composition.yaml
EOF

    # Create development overlay
    cat > "$REPO_ROOT/platform/05-databases/overlays/development/kustomization.yaml" << 'EOF'
# Development/Kind environment patches
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../

patches:
  # PostgreSQL storage class patch for Kind
  - target:
      kind: Composition
      name: postgres-instance
    patch: |-
      - op: replace
        path: /spec/resources/0/base/spec/forProvider/manifest/spec/storage/storageClass
        value: standard

  # Dragonfly storage class patch for Kind  
  - target:
      kind: Composition
      name: dragonfly-instance
    patch: |-
      - op: replace
        path: /spec/resources/2/base/spec/forProvider/manifest/spec/volumeClaimTemplates/0/spec/storageClassName
        value: standard
EOF

    # Create production overlay
    cat > "$REPO_ROOT/platform/05-databases/overlays/production/kustomization.yaml" << 'EOF'
# Production environment - uses base configurations as-is
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../

# No patches needed - production uses local-path as configured in base
EOF

    log_info "✓ Created Kustomize overlay structure"
fi

# 2. Verify preview components exist
log_info "Verifying preview component structure..."

if [[ ! -d "$REPO_ROOT/bootstrap/components/preview" ]]; then
    log_warn "Preview components not found - this should have been created already"
    exit 1
fi

# 3. Detect and configure storage class
log_info "Detecting available storage classes..."

# Get default storage class in Kind
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "standard")

if [[ -z "$DEFAULT_SC" ]]; then
    DEFAULT_SC="standard"
fi

log_info "Using storage class: $DEFAULT_SC"

# 4. Update overlays if non-standard storage class detected
if [[ "$DEFAULT_SC" != "standard" ]]; then
    log_warn "Non-standard storage class detected: $DEFAULT_SC"
    log_info "Updating development overlay to use: $DEFAULT_SC"
    
    # Update the development overlay to use the detected storage class
    sed -i.bak "s/value: standard/value: $DEFAULT_SC/g" \
        "$REPO_ROOT/platform/05-databases/overlays/development/kustomization.yaml"
    
    log_info "✓ Development overlay updated for storage class: $DEFAULT_SC"
fi

# 5. Verify preview bootstrap application exists
if [[ ! -f "$REPO_ROOT/bootstrap/10-platform-bootstrap-preview.yaml" ]]; then
    log_warn "Preview bootstrap application not found - this should have been created already"
    exit 1
fi

log_info "✓ Preview environment setup complete!"
log_info ""
log_info "Preview mode uses:"
log_info "  • Kustomize overlays for environment-specific configurations"
log_info "  • Development overlay with storage class: $DEFAULT_SC"
log_info "  • Preview components without control plane tolerations"
log_info "  • Preview bootstrap application: bootstrap/10-platform-bootstrap-preview.yaml"
log_info ""