#!/bin/bash
set -euo pipefail

# ==============================================================================
# Platform Service Image Patcher
# ==============================================================================
# Purpose: Updates Kubernetes manifests to use the image built in the previous step
# Usage: ./patch-service-images.sh <service-name> <build-mode> <image-tag>
# ==============================================================================

SERVICE_NAME="${1:-}"
BUILD_MODE="${2:-test}"
IMAGE_TAG="${3:-ci-test}"

# Default registry to match build script
REGISTRY="${CONTAINER_REGISTRY:-ghcr.io/arun4infra}"

if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: $0 <service-name> [build-mode] [image-tag]"
    exit 1
fi

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PATCH]${NC} $*"; }
log_success() { echo -e "${GREEN}[PATCH]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PATCH]${NC} $*"; }

main() {
    log_info "Patching deployment manifests..."
    log_info "  Service: ${SERVICE_NAME}"
    log_info "  Mode:    ${BUILD_MODE}"
    log_info "  Tag:     ${IMAGE_TAG}"

    # Validate that image tag contains a tag (has colon)
    if [[ "${IMAGE_TAG}" != *":"* ]]; then
        echo "ERROR: Image tag must contain a tag (e.g., service:sha-abc123 or registry/service:tag)"
        echo "Received: ${IMAGE_TAG}"
        exit 1
    fi

    # Use the exact image tag passed to the script
    local target_image="${IMAGE_TAG}"
    log_info "  Target:  ${target_image}"

    # Find all yaml files in platform/SERVICE_NAME/overlays/BUILD_MODE and replace any image field containing the service name
    local count=0
    local files_found=0

    # Use ENVIRONMENT variable for overlay directory (defaults to pr for CI testing)
    local overlay_env="${ENVIRONMENT:-pr}"
    
    # Check if platform/SERVICE_NAME/overlays/overlay_env directory exists
    local claims_dir="platform/${SERVICE_NAME}/overlays/${overlay_env}"
    if [[ ! -d "$claims_dir" ]]; then
        log_warn "$claims_dir directory not found, skipping image patching"
        return 0
    fi

    # Using find to get files from the correct claims directory, then processing
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files_found=$((files_found + 1))
            # Check if file contains an image definition with the service name (with or without tag)
            # Matches: image: anything-containing-service-name (with or without tag)
            if grep -qE "image:.*${SERVICE_NAME}" "$file"; then
                log_info "Patching file: $file"
                
                # Create backup
                cp "$file" "$file.bak"
                
                # Use sed to replace any image line containing the service name
                # Pattern handles any image reference containing the service name
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s|image: .*${SERVICE_NAME}.*|image: ${target_image}|g" "$file"
                else
                    sed -i "s|image: .*${SERVICE_NAME}.*|image: ${target_image}|g" "$file"
                fi
                
                # Remove backup if sed succeeded
                if [[ $? -eq 0 ]]; then
                    rm -f "$file.bak"
                    count=$((count + 1))
                else
                    # Restore backup if sed failed
                    mv "$file.bak" "$file"
                    log_warn "Failed to patch $file, restored backup"
                fi
            fi
        fi
    done < <(find "$claims_dir" -name "*.yaml" -type f 2>/dev/null || true)

    if [[ $files_found -eq 0 ]]; then
        log_warn "No YAML files found in platform/claims directory"
    elif [[ $count -gt 0 ]]; then
        log_success "Updated $count manifests to use image: ${target_image}"
    else
        log_info "No manifests found requiring updates for service: ${SERVICE_NAME}"
    fi
}

main "$@"