# Requirements Document: Twin Docs Workflow

## Introduction

This document defines requirements for the automated Twin Docs workflow where the Librarian Agent ensures every platform composition has a corresponding specification document that is validated, accurate, and aligned with business intent.

**Scope:** PR-triggered workflow, Gatekeeper validation, Twin Doc creation/update, Qdrant sync

---

## Glossary

- **Twin Doc**: Specification file in `artifacts/specs/` that mirrors a platform composition 1:1
- **Gatekeeper**: Agent validation logic that compares Spec (business intent) vs Code (technical reality)
- **Spec URL**: GitHub URL in PR description pointing to issue/doc describing business intent
- **Upsert**: Create or update operation with validation
- **No-Fluff Policy**: Documentation rule requiring tables/lists only, no prose paragraphs

---

## Requirements

### Requirement 1: PR Specification Enforcement

**User Story:** As a platform maintainer, I want every PR to reference a specification (external or inline), so that code changes are traceable to business requirements without excessive friction.

**Reference Pattern:** ✅ PR template with flexible specification options

#### Acceptance Criteria

1. WHEN a PR is created, THE PR description SHALL contain EITHER a GitHub URL OR an inline specification
2. WHEN validating GitHub URL, THE URL SHALL be from `github.com` domain only
3. WHEN validating inline spec, THE spec SHALL contain "Business Requirements" and "Acceptance Criteria" sections
4. WHEN neither option provided, THE CI SHALL fail immediately with blocking comment
5. WHEN URL is non-GitHub, THE CI SHALL fail with "must be github.com" error
6. WHEN valid specification provided (URL or inline), THE CI SHALL proceed to agent invocation
7. WHEN inline spec used, THE agent SHALL use PR description content as the specification source

---

### Requirement 2: Universal Contract Validation (Triangulation)

**User Story:** As a platform architect, I want the agent to validate that the "Public Interface" of any changed file matches the Business Spec, regardless of language (YAML/Python/Rego/etc), so that implementation doesn't drift from requirements.

**Reference Pattern:** ✅ Universal Mental Model (Triangulation)

#### Acceptance Criteria

1. WHEN analyzing a file, THE agent SHALL identify the "Contract Boundary" (Interface) and ignore implementation details
2. WHEN analyzing Infrastructure (YAML), THE agent SHALL identify Schemas/Parameters (Contract) vs Patches/Transforms (Implementation)
3. WHEN analyzing Code (Python/Go), THE agent SHALL identify Function Signatures/API Models (Contract) vs Logic/Loops (Implementation)
4. WHEN analyzing Policy (OPA/Kyverno), THE agent SHALL identify Rule Definitions (Contract) vs Rego Logic (Implementation)
5. WHEN analyzing Operations Docs, THE agent SHALL identify Trigger/Resolution Steps (Contract) vs Anecdotes (Implementation)
6. THE agent SHALL compare the extracted Contract against the Spec URL requirements
7. IF a mismatch is detected (e.g., Code allows what Spec forbids), THE agent SHALL block the PR with detailed comment
8. WHEN aligned, THE agent SHALL proceed to Twin Doc creation

---

### Requirement 3: Twin Doc Creation Logic

**User Story:** As a developer, I want the agent to automatically create Twin Docs for new resources, so that documentation is never missing.

**Reference Pattern:** ✅ Template-based document generation with Contract Boundary extraction

#### Acceptance Criteria

1. WHEN resource is new, THE agent SHALL check if Twin Doc exists
2. WHEN Twin Doc missing, THE agent SHALL fetch template from `artifacts/templates/spec-template.md`
3. WHEN creating, THE agent SHALL identify the Contract Boundary in the changed file
4. WHEN creating, THE agent SHALL fill frontmatter with resource metadata extracted from the Contract
5. WHEN creating, THE agent SHALL generate Configuration Parameters table from Contract Boundary data
6. WHEN created, THE agent SHALL call `upsert_twin_doc` (atomic: validate + write + commit)

---

### Requirement 4: Twin Doc Update Logic

**User Story:** As a developer, I want the agent to update only changed parameters in existing Twin Docs, so that manual documentation sections are preserved.

**Reference Pattern:** ✅ Surgical updates (table rows only)

#### Acceptance Criteria

1. WHEN resource modified, THE agent SHALL fetch existing Twin Doc
2. WHEN updating, THE agent SHALL parse Configuration Parameters table
3. WHEN updating, THE agent SHALL identify the Contract Boundary in the changed file
4. WHEN updating, THE agent SHALL compare existing table with extracted Contract data to identify changes
5. WHEN updating, THE agent SHALL modify ONLY changed parameter rows
6. WHEN updating, THE agent SHALL preserve all other sections (Overview, Purpose, etc.)
7. WHEN updated, THE agent SHALL call `upsert_twin_doc` (atomic: validate + write + commit)

---

### Requirement 5: Validation with Iteration

**User Story:** As a platform maintainer, I want the agent to automatically fix validation errors, so that PRs are not blocked by formatting issues.

**Reference Pattern:** ✅ Self-correcting agent loop

#### Acceptance Criteria

1. WHEN agent generates doc, THE agent SHALL call `upsert_twin_doc` tool (atomic operation)
2. WHEN validation fails, THE tool SHALL return specific error message WITHOUT committing
3. WHEN error received, THE agent SHALL analyze error and fix issue
4. WHEN fixed, THE agent SHALL retry `upsert_twin_doc` (max 3 attempts)
5. WHEN max attempts exceeded, THE agent SHALL fail CI with all errors
6. WHEN validation passes, THE tool SHALL write AND commit in one atomic operation

---

### Requirement 6: Validation Scripts

**User Story:** As a documentation maintainer, I want strict validation rules enforced, so that all Twin Docs follow consistent standards.

**Reference Pattern:** ✅ Python validation scripts

#### Acceptance Criteria

1. WHEN validating schema, THE script SHALL check frontmatter fields match category requirements
2. WHEN validating prose, THE script SHALL detect paragraphs in forbidden sections
3. WHEN validating filenames, THE script SHALL enforce kebab-case, max 3 words, no timestamps
4. WHEN validation passes, THE script SHALL return success status
5. WHEN validation fails, THE script SHALL return specific error with line number

---

### Requirement 7: Commit to PR Branch

**User Story:** As a developer, I want the agent to commit Twin Docs to my PR branch, so that I can review changes before merge.

**Reference Pattern:** ✅ GitHub API commit to PR branch (via upsert_twin_doc)

**CRITICAL SECURITY REQUIREMENT:** Agent MUST use GitHub App Token or PAT (not default GITHUB_TOKEN)

#### Acceptance Criteria

1. WHEN Twin Doc ready, THE agent SHALL call `upsert_twin_doc` tool (atomic operation)
2. WHEN validation passes, THE tool SHALL commit to SAME PR branch automatically using GitHub App Token or PAT
3. WHEN committing, THE commit message SHALL follow convention: "docs: update Twin Doc for {resource}"
4. WHEN committed using App Token/PAT, THE CI SHALL re-run validation (re-trigger workflows)
5. WHEN CI passes, THE PR SHALL be ready for human review
6. WHEN validation fails, THE tool SHALL NOT commit (prevents validation bypass)
7. WHEN using default GITHUB_TOKEN, THE system SHALL fail with error (prevents workflow re-trigger failure)

---

### Requirement 8: Qdrant Sync on Merge

**User Story:** As a platform operator, I want Twin Docs automatically indexed to Qdrant after merge, so that they are searchable.

**Reference Pattern:** ✅ GitHub Actions workflow on merge to main

#### Acceptance Criteria

1. WHEN PR merges to main, THE workflow SHALL trigger `sync-docs-to-qdrant.yaml`
2. WHEN syncing, THE workflow SHALL call `sync_to_qdrant` MCP tool
3. WHEN indexing, THE tool SHALL chunk Twin Doc (512 tokens, 50% overlap)
4. WHEN indexing, THE tool SHALL generate embeddings and store in Qdrant
5. WHEN indexed, THE Twin Doc SHALL be searchable via `qdrant-find`

---

### Requirement 9: Agent System Prompt

**User Story:** As a platform architect, I want the agent to have clear Gatekeeper instructions, so that it validates consistently.

**Reference Pattern:** ✅ Kagent Agent CRD with systemMessage

#### Acceptance Criteria

1. WHEN agent configured, THE system prompt SHALL define "Guardian of Consistency" identity
2. WHEN agent runs, THE prompt SHALL embed Gatekeeper validation logic
3. WHEN agent runs, THE prompt SHALL embed iteration logic for validation errors
4. WHEN agent runs, THE prompt SHALL embed tool mapping (prompt names → MCP tools)
5. WHEN agent runs, THE prompt SHALL enforce "never trust vector search alone" rule

---

### Requirement 10: Tool Mapping

**User Story:** As a developer, I want clear mapping between prompt tool names and actual MCP tools, so that implementation is consistent.

**Reference Pattern:** ✅ Explicit tool mapping table

#### Acceptance Criteria

1. WHEN agent calls `qdrant-find`, THE call SHALL search for similar documentation patterns
2. WHEN agent calls `fetch_from_git`, THE call SHALL fetch file content from GitHub
3. WHEN agent calls `upsert_twin_doc`, THE call SHALL map to `upsert_twin_doc` MCP tool (atomic: validate + write + commit)
4. WHEN mapping, THE agent SHALL NOT have direct access to `commit_to_pr` (prevents validation bypass)
5. THE agent SHALL NOT require custom parsing tools (parse_composition removed - uses LLM reasoning instead)

---

### Requirement 11: Error Handling

**User Story:** As a developer, I want clear error messages when validation fails, so that I know how to fix issues.

**Reference Pattern:** ✅ Structured error responses

#### Acceptance Criteria

1. WHEN Spec URL missing, THE CI SHALL fail with "❌ Missing GitHub Spec URL" comment
2. WHEN URL non-GitHub, THE CI SHALL fail with "❌ Spec URL must be from github.com" comment
3. WHEN Spec vs Code mismatch, THE agent SHALL fail with detailed comparison table
4. WHEN validation fails, THE agent SHALL fail with specific error and line number
5. WHEN max retries exceeded, THE agent SHALL fail with all attempted fixes listed

---

### Requirement 12: PR Template

**User Story:** As a developer, I want a PR template that guides me to add Spec URL, so that I don't forget.

**Reference Pattern:** ✅ GitHub PR template

#### Acceptance Criteria

1. WHEN creating PR, THE template SHALL display "Spec URL" field
2. WHEN template shown, THE field SHALL have placeholder: "https://github.com/org/repo/issues/123"
3. WHEN template shown, THE field SHALL have help text explaining requirement
4. WHEN PR created, THE CI SHALL validate this field
5. WHEN field empty, THE CI SHALL fail before agent runs

---

### Requirement 13: Historical Precedent Search

**User Story:** As the agent, I want to search for similar past documentation, so that I maintain consistency with historical patterns.

**Reference Pattern:** ✅ Qdrant semantic search

#### Acceptance Criteria

1. WHEN agent runs, THE agent SHALL call `qdrant-find` with resource type query
2. WHEN searching, THE query SHALL be: "similar to {resource_type}"
3. WHEN results returned, THE agent SHALL review top 3 results
4. WHEN reviewing, THE agent SHALL extract naming patterns and structure
5. WHEN creating new doc, THE agent SHALL follow historical patterns

---

### Requirement 14: Test Composition

**User Story:** As a developer, I want a test composition to validate the workflow, so that I can test without affecting production.

**Reference Pattern:** ✅ Simple test resource

#### Acceptance Criteria

1. WHEN testing, THE test composition SHALL be `platform/03-intelligence/test-webservice.yaml`
2. WHEN testing, THE composition SHALL have 2-3 simple parameters
3. WHEN testing, THE composition SHALL follow standard Crossplane structure
4. WHEN testing, THE expected Twin Doc SHALL be `artifacts/specs/test-webservice.md`
5. WHEN testing, THE workflow SHALL complete end-to-end successfully

---

### Requirement 15: Metrics and Observability

**User Story:** As a platform operator, I want metrics on agent performance, so that I can monitor workflow health.

**Reference Pattern:** ✅ Prometheus metrics

#### Acceptance Criteria

1. WHEN agent runs, THE agent SHALL emit execution time metric
2. WHEN validation fails, THE agent SHALL emit validation_error counter
3. WHEN Gatekeeper blocks, THE agent SHALL emit gatekeeper_block counter
4. WHEN Twin Doc created, THE agent SHALL emit twin_doc_created counter
5. WHEN metrics collected, THE metrics SHALL be visible in Grafana

---

### Requirement 16: Distillation from docs/ to artifacts/

**User Story:** As a developer, I want to write free-form troubleshooting notes in docs/, and have the agent extract operational knowledge into structured runbooks in artifacts/.

**Reference Pattern:** ⚠️ CUSTOM - Agent reads docs/, creates artifacts/, preserves original

#### Acceptance Criteria

1. WHEN PR modifies docs/**/*.md, THE CI SHALL invoke agent in distillation mode
2. WHEN agent reads docs/ file, THE agent SHALL identify operational knowledge (runbooks, procedures)
3. WHEN operational knowledge found, THE agent SHALL create structured artifact using template
4. WHEN creating artifact, THE agent SHALL preserve original docs/ file unchanged
5. WHEN distilling, THE agent SHALL commit only artifacts/ changes to PR

---

### Requirement 17: Duplicate Detection for Distillation

**User Story:** As a platform operator, I want the agent to detect duplicate runbooks and merge information, so that we don't have fragmented knowledge.

**Reference Pattern:** ✅ Qdrant similarity search

#### Acceptance Criteria

1. WHEN distilling content, THE agent SHALL call `qdrant-find` to search for similar artifacts
2. WHEN similarity score > 0.85, THE agent SHALL update existing artifact (not create new)
3. WHEN updating, THE agent SHALL merge new information into existing sections
4. WHEN no match found, THE agent SHALL create new artifact
5. WHEN merging, THE agent SHALL preserve existing structure and add new details

---

### Requirement 18: Runbook Template Compliance

**User Story:** As an on-call engineer, I want all runbooks to follow the same structure, so that I can quickly find diagnosis and resolution steps.

**Reference Pattern:** ✅ Template-based document generation

#### Acceptance Criteria

1. WHEN creating runbook, THE agent SHALL use `artifacts/templates/runbook-template.md`
2. WHEN filling template, THE agent SHALL include sections: Symptoms, Diagnosis, Resolution, Prevention
3. WHEN validating runbook, THE validation SHALL enforce category: runbook in frontmatter
4. WHEN validating runbook, THE validation SHALL enforce No-Fluff policy (tables/lists only)
5. WHEN runbook created, THE runbook SHALL pass all validation scripts

---

### Requirement 19: Auto-Generated Header Warning

**User Story:** As a developer, I want clear warnings on auto-generated files, so that I don't accidentally edit them directly and lose my changes.

**Reference Pattern:** ✅ HTML comment header in all artifacts/ files

#### Acceptance Criteria

1. WHEN agent creates Twin Doc, THE agent SHALL prepend auto-generated warning comment
2. WHEN agent creates runbook, THE agent SHALL prepend auto-generated warning comment
3. WHEN warning added, THE comment SHALL include: "DO NOT EDIT DIRECTLY" message
4. WHEN warning added, THE comment SHALL include: Source location (composition path or docs/ path)
5. WHEN warning added, THE comment SHALL include: Last generated timestamp
6. WHEN human edits artifacts/ file directly, THE validation SHALL detect and warn (optional enforcement)

---

## Success Criteria

**For Twin Docs Workflow (Phases 1-7):**

1. ✅ 100% of PRs modifying `platform/` have valid GitHub Spec URLs
2. ✅ 100% of Spec vs Code mismatches are detected and blocked
3. ✅ 100% of new compositions get Twin Docs automatically
4. ✅ 100% of Twin Docs pass validation after agent commits
5. ✅ 0% false positives (incorrect mismatch detection)
6. ✅ < 30 seconds agent execution time per PR
7. ✅ 100% of merged Twin Docs are indexed in Qdrant
8. ✅ 100% of indexed Twin Docs are searchable via `qdrant-find`

**For Distillation Workflow (Phase 8):**

1. ✅ 100% of PRs modifying `docs/` trigger distillation workflow
2. ✅ 100% of operational knowledge extracted to structured artifacts
3. ✅ 100% of duplicate runbooks detected (similarity > 0.85)
4. ✅ 100% of original docs/ files preserved unchanged
5. ✅ 100% of distilled artifacts pass validation
6. ✅ 0% duplicate artifacts created when similar content exists

---

## Non-Functional Requirements

### Performance

- Agent execution time: < 30 seconds per PR
- Validation script execution: < 5 seconds per document
- Qdrant sync time: < 2 minutes for full `artifacts/` directory

### Reliability

- Agent success rate: > 95% (excluding intentional blocks)
- Validation accuracy: 100% (no false positives/negatives)
- Qdrant sync success rate: 100%

### Security

- GitHub token: Stored in External Secrets Operator
- Agent permissions: Read-only to platform/, write to artifacts/
- Spec URL validation: Prevent injection attacks via URL parsing

### Maintainability

- Validation scripts: Unit tested with 100% coverage
- Agent prompt: Version controlled in Git
- Tool mapping: Documented in design doc

---

## Dependencies

- Milestone 2 complete (Agent deployed, MCP tools functional)
- GitHub Actions enabled
- Qdrant v1.16.0 running
- Kagent v0.7.4+ installed
- External Secrets Operator configured

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|:-----|:-------|:-----------|
| Agent infinite loop on validation | High | Max 3 retry limit |
| False positive Gatekeeper blocks | High | Extensive testing, clear error messages |
| Qdrant sync fails silently | Medium | Add health checks and alerts |
| GitHub API rate limits | Medium | Implement exponential backoff |
| Large PRs timeout agent | Medium | Set 5-minute timeout, fail gracefully |

---

## Future Enhancements (Post-Milestone 3)

1. **Semantic Mismatch Detection** - Use LLM to detect logical inconsistencies beyond simple parameter checks
2. **Auto-Spec Generation** - Generate GitHub issue template from composition
3. **Diff Visualization** - Show before/after comparison in PR comments
4. **Batch Processing** - Handle multiple compositions in one PR efficiently
5. **Rollback Detection** - Detect when code reverts and update Twin Doc accordingly
