#!/bin/bash
# pr-manager.sh - Handles Pull Request creation for GitOps deployments

# Create PR for deployment changes (if using Git repository)
create_deployment_pr() {
    log_step_start "Creating deployment PR"
    
    cd "$TENANTS_REPO_DIR"
    
    # Check if this is a Git repository
    if [[ ! -d ".git" ]]; then
        log_info "Not a Git repository, skipping PR creation"
        log_step_end "Creating deployment PR" "SUCCESS"
        return 0
    fi
    
    # Show current status for debugging
    log_debug "Git status before PR creation:"
    git status --porcelain || true
    
    # Check if there are any changes
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes detected, skipping PR creation"
        log_step_end "Creating deployment PR" "SUCCESS"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create PR with changes:"
        git diff --name-only 2>/dev/null || true
        log_step_end "Creating deployment PR" "SUCCESS"
        return 0
    fi
    
    # Configure Git user if not already configured
    if ! git config user.name &>/dev/null; then
        git config user.name "Release Pipeline Bot"
    fi
    if ! git config user.email &>/dev/null; then
        git config user.email "release-pipeline@zerotouch.dev"
    fi
    
    # Create a unique branch name for this deployment
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local branch_name="deploy/${TENANT}/${ENVIRONMENT}/${timestamp}"
    
    log_info "Creating deployment branch: $branch_name"
    
    # Create and checkout new branch
    if ! log_command "git checkout -b $branch_name"; then
        log_error "Failed to create deployment branch"
        return 1
    fi
    
    # Add all changes
    git add .
    
    # Check again after adding
    if git diff --cached --quiet; then
        log_info "No staged changes after git add, skipping PR creation"
        log_step_end "Creating deployment PR" "SUCCESS"
        return 0
    fi
    
    # Create commit message
    local commit_message="Deploy ${TENANT} to ${ENVIRONMENT}

Artifact: ${ARTIFACT}
Environment: ${ENVIRONMENT}
Deployed by: Release Pipeline
Timestamp: $(get_timestamp)
"
    
    # Commit changes
    if ! log_command "git commit -m \"$commit_message\""; then
        log_error "Failed to commit changes"
        return 1
    fi
    
    # Push branch to remote (if repository has remote)
    if [[ "$TENANTS_REPO_TYPE" == "remote" ]] || [[ "$TENANTS_REPO_TYPE" == "local_with_remote" ]]; then
        log_info "Pushing deployment branch to remote repository"
        
        # Check if we have a remote
        if ! git remote get-url origin &>/dev/null; then
            log_error "No remote origin configured"
            return 1
        fi
        
        if ! log_command "git push origin $branch_name"; then
            log_error "Failed to push deployment branch to remote repository"
            return 1
        fi
        
        log_info "Deployment branch pushed to remote repository"
        
        # Create PR using GitHub CLI if available
        if command -v gh &> /dev/null; then
            log_info "Creating pull request using GitHub CLI"
            
            local pr_title="Deploy ${TENANT} to ${ENVIRONMENT}"
            local pr_body="**Automated Deployment**

- **Tenant:** ${TENANT}
- **Environment:** ${ENVIRONMENT}
- **Artifact:** ${ARTIFACT}
- **Timestamp:** $(get_timestamp)

This PR was automatically created by the release pipeline to deploy the specified artifact to the ${ENVIRONMENT} environment.

**Changes:**
- Updated image tag in \`tenants/${TENANT}/overlays/${ENVIRONMENT}/kustomization.yaml\`

**Review Notes:**
- Verify the artifact tag is correct
- Ensure the target environment is appropriate
- Check that all required approvals are in place"
            
            # Create the PR
            if log_command "gh pr create --title \"$pr_title\" --body \"$pr_body\" --base main --head $branch_name"; then
                log_success "Pull request created successfully"
                
                # Get PR URL for reference
                local pr_url
                pr_url=$(gh pr view $branch_name --json url --jq '.url' 2>/dev/null || echo "unknown")
                log_info "PR URL: $pr_url"
                export DEPLOYMENT_PR_URL="$pr_url"
            else
                log_warn "Failed to create PR using GitHub CLI, but branch was pushed successfully"
                log_info "You can manually create a PR from branch: $branch_name"
            fi
        else
            log_warn "GitHub CLI (gh) not available, branch pushed but PR not created"
            log_info "You can manually create a PR from branch: $branch_name"
            log_info "Or install GitHub CLI: https://cli.github.com/"
        fi
    else
        log_info "Changes committed to local branch (no remote configured)"
    fi
    
    # Get commit SHA for tracking
    local commit_sha
    commit_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    log_deployment_info "$TENANT" "$ENVIRONMENT" "$ARTIFACT"
    log_info "GitOps commit SHA: $commit_sha"
    log_info "Deployment branch: $branch_name"
    
    export DEPLOYMENT_COMMIT_SHA="$commit_sha"
    export DEPLOYMENT_BRANCH="$branch_name"
    
    log_step_end "Creating deployment PR" "SUCCESS"
    return 0
}