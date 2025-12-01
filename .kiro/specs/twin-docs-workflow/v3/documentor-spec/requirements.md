# Requirements Document: Documentor Agent

## Introduction

This document defines requirements for the Documentor Agent, which automatically creates and updates MDX Twin Docs for platform compositions.

**Scope:** MDX documentation generation, Qdrant integration, docs.json management, distillation workflow

**Execution Time:** < 3 minutes per PR

**Location:** `.github/actions/documentor/`

---

## Glossary

- **Twin Doc**: Specification file in `artifacts/specs/` (MDX format) that mirrors a platform composition 1:1
- **Documentor Agent**: Documentation generator agent that creates/updates Twin Docs (~1-3 min execution)
- **Upsert**: Create or update operation with validation (atomic: validate + write + commit)
- **MDX**: Markdown with JSX components for structured, machine-readable documentation
- **Navigation Manifest**: `docs.json` file that defines documentation structure and prevents orphaned files
- **Contract Boundary**: Public interface of a file (schemas, parameters, API signatures) vs implementation details

---

## Requirements

### Requirement 1: MDX Twin Doc Creation

**User Story:** As a developer, I want the Documentor Agent to automatically create Twin Docs in MDX format with structured components, so that documentation is machine-readable and never missing.

**Reference Pattern:** ✅ Template-based MDX generation with Contract Boundary extraction

#### Acceptance Criteria

1. WHEN resource is new, THE Documentor Agent SHALL check if Twin Doc exists
2. WHEN Twin Doc missing, THE agent SHALL fetch template from `artifacts/templates/spec-template.mdx`
3. WHEN creating, THE agent SHALL identify the Contract Boundary in the changed file
4. WHEN creating, THE agent SHALL fill frontmatter with resource metadata extracted from the Contract
5. WHEN creating, THE agent SHALL generate `<ParamField>` components (not Markdown tables) from Contract Boundary data
6. WHEN creating, THE agent SHALL update `docs.json` navigation manifest with new file entry
7. WHEN created, THE agent SHALL call `upsert_twin_doc` (atomic: validate MDX + write + commit)
8. THE generated MDX SHALL use structured components: `<ParamField>`, `<CodeGroup>`, `<Warning>`, `<Note>`, `<Tip>`

---

### Requirement 2: MDX Twin Doc Update

**User Story:** As a developer, I want the Documentor Agent to update only changed parameters in existing Twin Docs, so that manual documentation sections are preserved.

**Reference Pattern:** ✅ Surgical updates (component-level, not table rows)

#### Acceptance Criteria

1. WHEN resource modified, THE Documentor Agent SHALL fetch existing Twin Doc
2. WHEN updating, THE agent SHALL parse existing `<ParamField>` components
3. WHEN updating, THE agent SHALL identify the Contract Boundary in the changed file
4. WHEN updating, THE agent SHALL compare existing components with extracted Contract data to identify changes
5. WHEN updating, THE agent SHALL modify ONLY changed `<ParamField>` components
6. WHEN updating, THE agent SHALL preserve all other sections (Overview, Purpose, etc.)
7. WHEN updating, THE agent SHALL update `docs.json` if file path or navigation group changed
8. WHEN updated, THE agent SHALL call `upsert_twin_doc` (atomic: validate MDX + write + commit)

---

### Requirement 3: MDX Component Validation

**User Story:** As a documentation maintainer, I want strict MDX validation rules enforced, so that all Twin Docs follow consistent standards and render correctly.

**Reference Pattern:** ✅ MDX syntax validation with component-specific rules

#### Acceptance Criteria

1. WHEN validating MDX, THE validation SHALL check for unclosed tags
2. WHEN validating `<ParamField>`, THE validation SHALL require `path` and `type` attributes
3. WHEN validating `<Step>`, THE validation SHALL require `title` attribute
4. WHEN validating components, THE validation SHALL only allow approved components: `ParamField`, `Steps`, `Step`, `CodeGroup`, `Warning`, `Note`, `Tip`, `Frame`
5. WHEN validation fails, THE validation SHALL return specific error with component name and missing attribute
6. WHEN validation passes, THE validation SHALL return success status
7. THE validation SHALL check frontmatter fields match category requirements
8. THE validation SHALL enforce filename rules: kebab-case, max 3 words, no timestamps

---

### Requirement 4: Navigation Manifest Management

**User Story:** As a platform operator, I want all Twin Docs explicitly listed in a navigation manifest, so that documentation is organized and discoverable with no orphaned files.

**Reference Pattern:** ✅ `docs.json` as single source of truth for navigation

#### Acceptance Criteria

1. WHEN Documentor Agent creates Twin Doc, THE agent SHALL update `artifacts/docs.json` with new file entry
2. WHEN updating `docs.json`, THE agent SHALL read current manifest from main branch
3. WHEN updating `docs.json`, THE agent SHALL find appropriate navigation group (Infrastructure, APIs, Runbooks)
4. WHEN updating `docs.json`, THE agent SHALL append new page path (without `.mdx` extension)
5. WHEN updating `docs.json`, THE agent SHALL format JSON with one entry per line (for git auto-merge)
6. WHEN merge conflict detected on `docs.json`, THE agent SHALL rebase and retry (max 3 attempts)
7. WHEN `docs.json` update fails, THE entire Twin Doc creation SHALL fail (atomic guarantee)
8. THE `docs.json` SHALL use simplified structure: only `groups` and `pages` (no tabs, dropdowns, products)

---

### Requirement 5: Validation with Iteration

**User Story:** As a platform maintainer, I want the Documentor Agent to automatically fix validation errors, so that PRs are not blocked by formatting issues.

**Reference Pattern:** ✅ Self-correcting agent loop with MDX validation

#### Acceptance Criteria

1. WHEN Documentor Agent generates doc, THE agent SHALL call `upsert_twin_doc` tool (atomic operation)
2. WHEN MDX validation fails, THE tool SHALL return specific error message WITHOUT committing
3. WHEN error received, THE agent SHALL analyze error and fix issue
4. WHEN fixed, THE agent SHALL retry `upsert_twin_doc` (max 3 attempts)
5. WHEN max attempts exceeded, THE agent SHALL fail CI with all errors (but PR remains valid)
6. WHEN validation passes, THE tool SHALL write AND commit in one atomic operation
7. THE validation SHALL include both MDX syntax validation and frontmatter validation

---

### Requirement 6: Commit to PR Branch

**User Story:** As a developer, I want the Documentor Agent to commit Twin Docs to my PR branch, so that I can review changes before merge.

**Reference Pattern:** ✅ GitHub API commit to PR branch (via GitHub MCP tools)

**CRITICAL SECURITY REQUIREMENT:** Agents MUST use GitHub App Token or PAT (not default GITHUB_TOKEN)

#### Acceptance Criteria

1. WHEN Twin Doc ready, THE Documentor Agent SHALL use GitHub MCP tools to commit
2. WHEN validation passes, THE agent SHALL commit to SAME PR branch automatically using BOT_GITHUB_TOKEN
3. WHEN committing, THE commit message SHALL follow convention: "docs: update Twin Doc for {resource}"
4. WHEN committed using App Token/PAT, THE CI SHALL re-run validation (re-trigger workflows)
5. WHEN CI passes, THE PR SHALL be ready for human review
6. WHEN validation fails, THE agent SHALL NOT commit (prevents validation bypass)
7. THE Documentor Agent SHALL also commit `docs.json` updates in same PR

---

### Requirement 7: Historical Precedent Search

**User Story:** As the Documentor Agent, I want to search for similar past documentation, so that I maintain consistency with historical patterns.

**Reference Pattern:** ✅ Qdrant semantic search with MDX-aware retrieval

#### Acceptance Criteria

1. WHEN Documentor Agent runs, THE agent SHALL call `qdrant_find` with resource type query
2. WHEN searching, THE query SHALL be: "similar to {resource_type}"
3. WHEN results returned, THE agent SHALL review top 3 results
4. WHEN reviewing, THE agent SHALL extract naming patterns, component structure, and frontmatter conventions
5. WHEN creating new doc, THE agent SHALL follow historical patterns
6. THE search SHALL leverage MDX component metadata for precise matching

---

### Requirement 8: MDX-Aware Qdrant Sync

**User Story:** As a platform operator, I want Twin Docs automatically indexed to Qdrant with semantic chunking, so that agents can retrieve precise information.

**Reference Pattern:** ✅ GitHub Actions workflow on merge to main with MDX-aware chunking

#### Acceptance Criteria

1. WHEN PR merges to main, THE workflow SHALL trigger `sync-docs-to-qdrant.yaml`
2. WHEN syncing, THE workflow SHALL call `qdrant_store` MCP tool
3. WHEN indexing, THE tool SHALL chunk by MDX components (not arbitrary token counts)
4. WHEN indexing, THE tool SHALL create separate chunks for: frontmatter, each `<ParamField>`, each `<Step>`, regular sections
5. WHEN indexing, THE tool SHALL store component metadata in Qdrant payload (type, path, title, index)
6. WHEN indexing, THE tool SHALL generate embeddings and store in Qdrant
7. WHEN indexed, THE Twin Doc SHALL be searchable via `qdrant_find` with precise component-level retrieval
8. THE chunking SHALL preserve semantic boundaries (no splitting mid-component)

---

### Requirement 9: Distillation from docs/ to artifacts/

**User Story:** As a developer, I want to write free-form troubleshooting notes in docs/, and have the Documentor Agent extract operational knowledge into structured runbooks in artifacts/.

**Reference Pattern:** ⚠️ CUSTOM - Agent reads docs/, creates artifacts/, preserves original

#### Acceptance Criteria

1. WHEN PR modifies docs/**/*.md, THE CI SHALL invoke Documentor Agent in distillation mode
2. WHEN agent reads docs/ file, THE agent SHALL identify operational knowledge (runbooks, procedures)
3. WHEN operational knowledge found, THE agent SHALL create structured artifact using `runbook-template.mdx`
4. WHEN creating artifact, THE agent SHALL use `<Steps>` components for diagnosis and resolution
5. WHEN creating artifact, THE agent SHALL preserve original docs/ file unchanged
6. WHEN distilling, THE agent SHALL commit only artifacts/ changes to PR
7. THE distilled runbook SHALL be in MDX format with structured components

---

### Requirement 10: Duplicate Detection for Distillation

**User Story:** As a platform operator, I want the Documentor Agent to detect duplicate runbooks and merge information, so that we don't have fragmented knowledge.

**Reference Pattern:** ✅ Qdrant similarity search with MDX component matching

#### Acceptance Criteria

1. WHEN distilling content, THE Documentor Agent SHALL call `qdrant_find` to search for similar artifacts
2. WHEN similarity score > 0.85, THE agent SHALL update existing artifact (not create new)
3. WHEN updating, THE agent SHALL merge new information into existing `<Steps>` components
4. WHEN no match found, THE agent SHALL create new artifact
5. WHEN merging, THE agent SHALL preserve existing structure and add new details
6. THE duplicate detection SHALL leverage MDX component metadata for precise matching

---

### Requirement 11: Runbook Template Compliance

**User Story:** As an on-call engineer, I want all runbooks to follow the same MDX structure, so that I can quickly find diagnosis and resolution steps.

**Reference Pattern:** ✅ Template-based MDX generation with `<Steps>` components

#### Acceptance Criteria

1. WHEN creating runbook, THE Documentor Agent SHALL use `artifacts/templates/runbook-template.mdx`
2. WHEN filling template, THE agent SHALL include sections: Symptoms, Diagnosis, Resolution, Prevention
3. WHEN filling Diagnosis section, THE agent SHALL use `<Steps>` component with `<Step>` children
4. WHEN filling Resolution section, THE agent SHALL use `<Steps>` component with `<Step>` children
5. WHEN validating runbook, THE validation SHALL enforce category: runbook in frontmatter
6. WHEN validating runbook, THE validation SHALL enforce MDX component structure
7. WHEN runbook created, THE runbook SHALL pass all MDX validation scripts

---

### Requirement 12: Auto-Generated Header Warning

**User Story:** As a developer, I want clear warnings on auto-generated files, so that I don't accidentally edit them directly and lose my changes.

**Reference Pattern:** ✅ MDX comment header in all artifacts/ files

#### Acceptance Criteria

1. WHEN Documentor Agent creates Twin Doc, THE agent SHALL prepend auto-generated warning using `<Warning>` component
2. WHEN Documentor Agent creates runbook, THE agent SHALL prepend auto-generated warning using `<Warning>` component
3. WHEN warning added, THE component SHALL include: "DO NOT EDIT DIRECTLY" message
4. WHEN warning added, THE component SHALL include: Source location (composition path or docs/ path)
5. WHEN warning added, THE component SHALL include: Last generated timestamp
6. WHEN human edits artifacts/ file directly, THE validation SHALL detect and warn (optional enforcement)

---

### Requirement 13: Manual Documentor Trigger

**User Story:** As a developer, I want to manually trigger documentation generation via PR comment, so that I can regenerate docs without pushing new commits.

**Reference Pattern:** ✅ GitHub issue comment triggers (ChatOps pattern)

#### Acceptance Criteria

1. WHEN developer comments `@librarian regenerate-docs`, THE CI SHALL re-run Documentor Agent only
2. THE workflow SHALL trigger on `issue_comment` event type `created` (in addition to `pull_request` events)

---

### Requirement 14: GitHub and Qdrant MCP Tools

**User Story:** As a Documentor Agent, I want to use MCP tools for all operations, so that I leverage standardized tooling.

**Reference Pattern:** ✅ Official GitHub and Qdrant MCP servers

#### Acceptance Criteria

**GitHub MCP Tools:**
1. WHEN Documentor needs file content, THE agent SHALL call `github_get_file_contents` MCP tool
2. WHEN Documentor creates/updates file, THE agent SHALL call `github_create_or_update_file` or `github_push_files` MCP tool
3. WHEN Documentor posts comment, THE agent SHALL call `github_create_issue_comment` MCP tool

**Qdrant MCP Tools:**
4. WHEN Documentor searches precedent, THE agent SHALL call `qdrant_find` MCP tool
5. WHEN Documentor indexes docs, THE agent SHALL call `qdrant_store` MCP tool

**Local Logic:**
6. THE Documentor SHALL use LLM reasoning for Contract Boundary extraction (no custom parsing tools)
7. THE Documentor SHALL implement MDX validation logic locally (not via MCP tool)

---

### Requirement 15: Qdrant Cloud Configuration

**User Story:** As a platform operator, I want to use Qdrant Cloud instead of self-hosted Qdrant, so that I don't need to expose cluster services.

**Reference Pattern:** ✅ Qdrant Cloud with API key authentication

#### Acceptance Criteria

1. WHEN configuring Qdrant, THE system SHALL use Qdrant Cloud (not self-hosted cluster instance)
2. WHEN configuring Qdrant, THE user SHALL provide `QDRANT_URL` (Qdrant Cloud endpoint)
3. WHEN configuring Qdrant, THE user SHALL provide `QDRANT_API_KEY` (Qdrant Cloud API key)
4. WHEN storing secrets, THE `QDRANT_URL` and `QDRANT_API_KEY` SHALL be stored in GitHub secrets
5. WHEN Documentor Agent runs, THE agent SHALL pass Qdrant credentials to MCP server via environment variables
6. THE Qdrant MCP server SHALL connect to Qdrant Cloud using provided credentials
7. THE Qdrant MCP server SHALL use collection name: `documentation`
8. THE Qdrant MCP server SHALL use embedding model: `sentence-transformers/all-MiniLM-L6-v2`
9. THE system SHALL NOT require exposing self-hosted Qdrant via ingress
10. THE system SHALL NOT require cluster networking for Qdrant access

---

### Requirement 16: Error Handling

**User Story:** As a developer, I want clear error messages when documentation generation fails, so that I know how to fix issues.

**Reference Pattern:** ✅ Structured error responses

#### Acceptance Criteria

1. WHEN MDX validation fails, THE Documentor SHALL fail with specific component error and attribute name
2. WHEN `docs.json` update fails, THE Documentor SHALL fail with merge conflict details
3. WHEN max retries exceeded, THE Documentor SHALL fail with all attempted fixes listed
4. WHEN Documentor fails, THE PR SHALL remain valid (docs can be regenerated)

---

### Requirement 17: System Prompt

**User Story:** As a platform architect, I want the Documentor prompt stored in the repository, so that the "Brain" is version-controlled with the code.

**Reference Pattern:** ✅ Prompt loaded at runtime from repo

#### Acceptance Criteria

1. WHEN Documentor Agent runs, THE system prompt SHALL be loaded from `platform/03-intelligence/agents/documentor/prompt.md` at runtime
2. THE system prompt SHALL NOT be hardcoded inside Docker image
3. THE system prompt SHALL be version-controlled in the repository
4. WHEN prompt file changes, THE agent SHALL use updated prompt on next run (no rebuild required)
5. THE prompt SHALL reference Diataxis framework guide for content type classification
6. THE prompt SHALL reference MDX component guide for syntax
7. THE prompt SHALL embed iteration logic for validation errors
8. THE prompt SHALL NOT include Gatekeeper validation logic

---

### Requirement 18: Metrics

**User Story:** As a platform operator, I want metrics on Documentor performance, so that I can monitor workflow health.

**Reference Pattern:** ✅ Prometheus metrics

#### Acceptance Criteria

1. WHEN Documentor runs, THE agent SHALL emit `documentor_duration_seconds` histogram
2. WHEN Twin Doc created, THE agent SHALL emit `twin_doc_created_total` counter
3. WHEN Twin Doc updated, THE agent SHALL emit `twin_doc_updated_total` counter
4. WHEN MDX validation fails, THE agent SHALL emit `mdx_validation_errors_total` counter
5. WHEN `docs.json` conflict occurs, THE agent SHALL emit `docs_json_conflicts_total` counter
6. THE metrics SHALL be exported in Prometheus format

---

### Requirement 19: Execution Flow

**User Story:** As a Documentor Agent, I want a clear execution flow, so that I generate documentation efficiently.

**Reference Pattern:** ✅ Sequential execution with validation loops

#### Acceptance Criteria

1. WHEN Documentor starts, THE agent SHALL parse inputs (PR number, GitHub token, OpenAI key, Qdrant credentials)
2. WHEN Documentor starts, THE agent SHALL start GitHub MCP server
3. WHEN Documentor starts, THE agent SHALL start Qdrant MCP server
4. WHEN Documentor starts, THE agent SHALL initialize MCP bridge
5. WHEN Documentor starts, THE agent SHALL load system prompt from repo
6. WHEN Documentor starts, THE agent SHALL identify changed compositions
7. WHEN Documentor starts, THE agent SHALL run agent loop (OpenAI + MCP bridge)
8. WHEN doc generated, THE agent SHALL validate MDX (max 3 retries)
9. WHEN validation passes, THE agent SHALL update docs.json
10. WHEN complete, THE agent SHALL commit to PR branch
11. WHEN complete, THE agent SHALL post summary comment

---

## Dependencies

- Core Infrastructure (MCP bridge, contract extractor, MDX validator)
- OpenAI API Key
- GitHub Bot Token (BOT_GITHUB_TOKEN)
- Qdrant Cloud URL and API Key
- GitHub MCP Server (`@modelcontextprotocol/server-github`)
- Qdrant MCP Server (`mcp-server-qdrant`)

---

## Success Criteria

1. ✅ 100% of new compositions get Twin Docs automatically in MDX format
2. ✅ 100% of Twin Docs use structured components (`<ParamField>`, `<Steps>`, `<CodeGroup>`)
3. ✅ 100% of Twin Docs pass MDX validation after agent commits
4. ✅ 100% of Twin Docs listed in `docs.json` (no orphaned files)
5. ✅ 0% merge conflicts on `docs.json` (git auto-merge + rebase)
6. ✅ Documentor execution time < 3 minutes (with caching)
7. ✅ 100% of merged Twin Docs are indexed in Qdrant with MDX-aware chunking
8. ✅ >90% retrieval precision (queries return exact relevant component)
9. ✅ 100% of PRs modifying `docs/` trigger distillation workflow
10. ✅ 100% of operational knowledge extracted to structured runbooks

---

## Non-Functional Requirements

### Performance
- Execution time: < 3 minutes per PR (with caching)
- MDX validation: < 5 seconds per document
- Qdrant sync time: < 2 minutes for full `artifacts/` directory
- `docs.json` conflict resolution: < 10 seconds (rebase + retry)

### Reliability
- Success rate: > 90% (excluding validation errors)
- Qdrant sync success rate: 100%
- `docs.json` auto-merge success rate: > 95%

### Security
- Read-only access to platform/, specs, docs/
- Write access to artifacts/ only
- Qdrant Cloud credentials stored securely

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** Ready for Implementation  
**Depends On:** Core Infrastructure Spec
