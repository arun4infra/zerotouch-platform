#!/bin/bash
# image-updater.sh - Helper for updating Crossplane CRD image fields

# Update Crossplane CRD image field
update_crossplane_image() {
    local crd_file="$1"
    
    if [[ ! -f "$crd_file" ]]; then
        log_error "Crossplane deployment file not found: $crd_file"
        return 1
    fi
    
    log_info "Current Crossplane CRD file:"
    cat "$crd_file"
    
    # Update image field using yq (if available) or sed fallback
    if command -v yq &> /dev/null; then
        log_info "Updating Crossplane image using yq"
        yq eval ".spec.image = \"${IMAGE_TAG}\"" -i "$crd_file"
    else
        log_info "Updating Crossplane image using sed (yq not available)"
        sed -i.bak "s|^\([[:space:]]*\)image: .*|\1image: ${IMAGE_TAG}|" "$crd_file"
        rm -f "${crd_file}.bak"
    fi
    
    log_info "Updated Crossplane CRD file:"
    cat "$crd_file"
    
    log_success "Crossplane CRD image updated successfully"
    return 0
}