# Branch Merge Workflow for ArgoCD Target Revision Updates

## Overview

This document outlines the workflow for merging feature branches that contain ArgoCD `targetRevision` references when the branch structure or naming changes significantly.

## Background

ArgoCD applications use `targetRevision` to specify which Git branch/tag to sync from. When feature branches introduce new directory structures or significant changes, the ArgoCD manifests often reference the feature branch name directly. This creates a circular dependency during merge:

- **Problem**: Feature branch references itself in `targetRevision`
- **Issue**: After merge, ArgoCD tries to sync from a non-existent branch
- **Result**: CI failures and sync errors

## Save time

You should only proceed with cluster creation when you are sure that the branch structure is correct and the target revision is updated correctly. As each cluster bootstrap takes around 30 minutes, it is better to save time and avoid unnecessary cluster creation. Make the branch and environment changes first and then proceed with cluster creation.

## When This Workflow Is Needed

Use this workflow when:
- Feature branch introduces new ArgoCD application structures
- Branch contains `targetRevision` references to itself
- CI/CD depends on ArgoCD sync success
- Branch protection prevents direct deletion after merge

## ⚠️ Critical: New ArgoCD Apps/Services Addition

**ALWAYS reference this document when adding new apps or services to ArgoCD.** Failure to follow this workflow will result in CI failures with these symptoms:

### Common CI Failure Symptoms
- **"XRD not found" errors** even though files exist locally
- **CI getting stuck in middle and fail due to unhealthy or outofsync services**
- **CI getting Timeout waiting for XRDs/resources to become ready**
- **ArgoCD shows "Synced/Healthy" but resources don't appear in cluster**
- **CI passes locally but fails in GitHub Actions**

### When there are CI Failure reported, Immediately before Creating Any Plan - Ask These Questions:

**Status Assessment Questions:**
1. **What phase are you in?**
   - [ ] Pre-merge (feature branch still exists, CI failing)
   - [ ] Post-merge (feature branch deleted, main branch CI failing)
   - [ ] Cleanup phase (need to fix target revisions)

2. **Current branch status:**
   - [ ] Feature branch still exists and accessible?
   - [ ] Feature branch already merged to main?
   - [ ] Feature branch deleted (auto-delete was enabled)?

3. **Target revision status:**
   - [ ] Feature branch has self-referencing `targetRevision`?
   - [ ] Target revisions already updated to `main`?
   - [ ] Unsure about current target revision values?

4. **CI failure context:**
   - [ ] CI failing on feature branch?
   - [ ] CI failing on main branch after merge?
   - [ ] Local testing needed before proceeding?

**Based on answers above, follow the appropriate phase:**
- **Pre-merge issues** → Start with Phase 1
- **Post-merge issues** → Skip to Phase 2 or local debugging
- **Unknown status** → Investigate current state first

**Remember: If you're adding anything new to the platform that ArgoCD manages, this workflow is mandatory to prevent CI failures.**

## Workflow Steps

### Phase 1: Prepare Feature Branch for Merge
1. **Update Target Revisions**: Change all `targetRevision` references from target branch (usually `main`) to feature branch name. Use scripts/bootstrap/update-target-revision.sh script to update the target revision on files that has references to `targetRevision`.
2. **Disable Auto-Delete**: Turn off "Automatically delete head branches" in GitHub repository settings
3. **Test CI**: Ensure CI passes with updated target revisions
4. **Merge**: Merge feature branch to target branch

### Phase 2: Clean Up Target Branch
1. **Sync Local**: Pull latest changes from target branch
2. **Create Cleanup Branch**: Create new branch from updated target branch (usually `main`)
3. **Verify References**: Ensure all `targetRevision` values point to target branch (usually `main`). Use scripts/bootstrap/update-target-revision.sh script to update the target revision on files that has references to `targetRevision`.
4. **Enable Auto-Delete**: Re-enable "Automatically delete head branches" setting
5. **Merge Cleanup**: Merge cleanup branch to target branch

### Phase 3: Final Cleanup
1. **Manual Deletion**: Delete original feature branch manually
2. **Verify CI**: Confirm CI passes on target branch
3. **Document**: Update any relevant documentation

## Key Principles

- **Never merge with self-referencing target revisions**
- **Always test CI before final merge**
- **Use temporary branches for target revision updates**
- **Maintain branch protection settings appropriately**

## Tools

- Use existing update scripts (e.g., `update-target-revision.sh`) when available
- Leverage repository automation settings strategically
- Test in CI environment before production merge

## Common Pitfalls

- Forgetting to update target revisions before merge
- Leaving auto-delete enabled during complex merges
- Not testing CI with updated references
- Assuming ArgoCD will handle branch renames automatically

## Success Criteria

- CI passes on target branch after merge
- All ArgoCD applications sync successfully
- No orphaned branch references remain
- Repository settings restored to normal state

---

*This workflow ensures clean merges while maintaining ArgoCD functionality and CI stability.*