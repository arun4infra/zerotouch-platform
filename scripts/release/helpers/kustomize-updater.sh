#!/bin/bash
# kustomize-updater.sh - Handles Kustomize manifest updates

# Update tenant overlay with new artifact using kustomize
update_tenant_overlay() {
    log_step_start "Updating tenant overlay with new artifact"
    
    local overlay_dir="${TENANTS_REPO_DIR}/tenants/${TENANT}/overlays/${ENVIRONMENT}"
    local kustomization_file="${overlay_dir}/kustomization.yaml"
    
    log_info "Updating overlay for environment: $ENVIRONMENT"
    log_info "Artifact: $ARTIFACT"
    log_info "Overlay directory: $overlay_dir"
    log_info "Kustomization file: $kustomization_file"
    
    # Ensure overlay directory exists
    if [[ ! -d "$overlay_dir" ]]; then
        log_error "Tenant overlay directory not found: $overlay_dir"
        return 1
    fi
    
    # Check if kustomization.yaml exists
    if [[ ! -f "$kustomization_file" ]]; then
        log_error "Kustomization file not found: $kustomization_file"
        return 1
    fi
    
    # Extract image name and tag from artifact
    local image_name
    local image_tag
    if [[ "$ARTIFACT" =~ ^(.+):(.+)$ ]]; then
        image_name="${BASH_REMATCH[1]}"
        image_tag="${BASH_REMATCH[2]}"
    else
        log_error "Invalid artifact format: $ARTIFACT"
        return 1
    fi
    
    log_info "Parsed artifact - Image: $image_name, Tag: $image_tag"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update kustomization.yaml with:"
        log_info "[DRY RUN]   Image: $image_name"
        log_info "[DRY RUN]   New Tag: $image_tag"
        log_step_end "Updating tenant overlay with new artifact" "SUCCESS"
        return 0
    fi
    
    # Change to overlay directory for kustomize operations
    cd "$overlay_dir"
    
    # Method 1: Try using kustomize edit set image (preferred)
    if command -v kustomize &> /dev/null; then
        log_info "Using kustomize to update image tag"
        
        # Create backup
        cp "$kustomization_file" "${kustomization_file}.backup"
        
        # Use kustomize edit set image to update the tag
        if log_command "kustomize edit set image ${TENANT}=${ARTIFACT}"; then
            log_info "Successfully updated image using kustomize"
        else
            log_warn "kustomize edit failed, falling back to yq/sed"
            # Restore backup and try alternative method
            cp "${kustomization_file}.backup" "$kustomization_file"
        fi
    fi
    
    # Method 2: Try using yq (if kustomize failed or not available)
    if ! command -v kustomize &> /dev/null || ! grep -q "$image_tag" "$kustomization_file"; then
        if command -v yq &> /dev/null; then
            log_info "Using yq to update image tag"
            
            # Create backup if not already created
            [[ ! -f "${kustomization_file}.backup" ]] && cp "$kustomization_file" "${kustomization_file}.backup"
            
            # Show current content for debugging
            log_debug "Current kustomization content before yq update:"
            log_debug "$(cat "$kustomization_file")"
            
            # Update the newTag field for the tenant image
            if yq eval "(.images[] | select(.name == \"${TENANT}\") | .newTag) = \"${image_tag}\"" -i "$kustomization_file"; then
                log_info "Successfully updated image using yq"
                
                # Show updated content for debugging
                log_debug "Updated kustomization content after yq update:"
                log_debug "$(cat "$kustomization_file")"
            else
                log_warn "yq update failed, falling back to sed"
                # Restore backup and try sed
                cp "${kustomization_file}.backup" "$kustomization_file"
            fi
        fi
    fi
    
    # Method 3: Fallback to sed (if both kustomize and yq failed)
    if ! grep -q "$image_tag" "$kustomization_file"; then
        log_info "Using sed to update image tag"
        
        # Create backup if not already created
        [[ ! -f "${kustomization_file}.backup" ]] && cp "$kustomization_file" "${kustomization_file}.backup"
        
        # Use sed to update the newTag field
        sed -i.tmp "/name: ${TENANT}/,/newTag:/ s/newTag: .*/newTag: ${image_tag}/" "$kustomization_file"
        rm -f "${kustomization_file}.tmp"
        
        log_info "Updated image tag using sed"
    fi
    
    # Verify the update was successful
    if grep -q "$image_tag" "$kustomization_file"; then
        log_success "Image tag successfully updated in kustomization.yaml"
        log_info "New tag: $image_tag"
    else
        log_error "Failed to update image tag in kustomization.yaml"
        return 1
    fi
    
    log_step_end "Updating tenant overlay with new artifact" "SUCCESS"
    return 0
}