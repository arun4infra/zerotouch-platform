# Requirements Document: Twin Docs Workflow v2

## Introduction

This document defines requirements for the automated Twin Docs workflow where two specialized agents (Validator and Documentor) ensure every platform composition has a corresponding specification document that is validated, accurate, and aligned with business intent.

**Scope:** PR-triggered workflow, two-agent architecture (Validator + Documentor), MDX-based documentation, Gatekeeper validation, Twin Doc creation/update, Qdrant sync

**Key Enhancements in v2:**
- **Two-Agent Architecture**: Separate Validator (fast gate) and Documentor (doc generator) for better performance and separation of concerns
- **MDX Format**: Structured components (`<ParamField>`, `<Steps>`, `<CodeGroup>`) instead of Markdown tables for machine-readable documentation
- **Navigation Manifest**: `docs.json` for organized, discoverable documentation
- **Semantic Chunking**: MDX-aware Qdrant indexing for precise retrieval
- **Interpreted Intent Pattern**: Transparent agent interpretation of natural language specs

---

## Glossary

- **Twin Doc**: Specification file in `artifacts/specs/` (MDX format) that mirrors a platform composition 1:1
- **Validator Agent**: Fast gate agent that validates Spec vs Code alignment (~20-30s execution)
- **Documentor Agent**: Documentation generator agent that creates/updates Twin Docs (~1-3 min execution)
- **Gatekeeper**: Validation logic in Validator Agent that compares Spec (business intent) vs Code (technical reality)
- **Spec URL**: GitHub URL in PR description pointing to issue/doc describing business intent
- **Inline Spec**: Specification embedded directly in PR description (for small changes)
- **Upsert**: Create or update operation with validation (atomic: validate + write + commit)
- **MDX**: Markdown with JSX components for structured, machine-readable documentation
- **Contract Boundary**: Public interface of a file (schemas, parameters, API signatures) vs implementation details
- **Interpreted Intent**: Agent's projection of natural language requirements into structured format
- **Navigation Manifest**: `docs.json` file that defines documentation structure and prevents orphaned files

## Structure

### Architecture

PR Event
    ↓
┌─────────────────────────────────────────────┐
│  Validator Agent (Fast Gate)                │
│  - Fetch PR diff (GitHub MCP)               │
│  - Fetch spec (GitHub MCP)                  │
│  - Compare Intent vs Reality                │
│  - Block if mismatch                        │
│  Time: ~20-30s                              │
└─────────────────────────────────────────────┘
    ↓ (only if passed)
┌─────────────────────────────────────────────┐
│  Documentor Agent (Twin Doc Writer)         │
│  - Search precedent (Qdrant MCP)            │
│  - Fetch existing doc (GitHub MCP)          │
│  - Generate/update markdown                 │
│  - Validate + commit (GitHub MCP)           │
│  - Post summary comment                     │
│  Time: ~1-3 min                             │
└─────────────────────────────────────────────┘

### File Structure
.github/
├── actions/
│   ├── validator/
│   │   ├── Dockerfile
│   │   ├── action.yml
│   │   ├── validator.py
│   │   ├── mcp_client.py
│   │   ├── contract_extractor.py
│   │   └── requirements.txt
│   │
│   └── documentor/
│       ├── Dockerfile
│       ├── action.yml
│       ├── documentor.py
│       ├── mcp_client.py
│       ├── template_engine.py
│       ├── markdown_validator.py
│       └── requirements.txt
│
└── workflows/
    └── librarian.yml

### .github/workflows/librarian.yml
```
name: Librarian Pipeline

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  validate:
    name: Validate Spec Alignment
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Run Validator
        uses: ./.github/actions/validator
        with:
          pr_number: ${{ github.event.pull_request.number }}
          github_token: ${{ secrets.GITHUB_TOKEN }}

  document:
    name: Generate Twin Docs
    needs: validate  # Only runs if validation passes
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}  # Checkout PR branch
      
      - name: Run Documentor
        uses: ./.github/actions/documentor
        with:
          pr_number: ${{ github.event.pull_request.number }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          qdrant_url: ${{ secrets.QDRANT_MCP_URL }}
```
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
6. WHEN valid specification provided (URL or inline), THE CI SHALL proceed to Validator Agent invocation
7. WHEN inline spec used, THE Validator Agent SHALL use PR description content as the specification source

---

### Requirement 2: Two-Agent Architecture

**User Story:** As a platform architect, I want separate agents for validation and documentation, so that invalid PRs are blocked quickly without wasting resources on doc generation.

**Reference Pattern:** ✅ Sequential workflow: Validator → Documentor

#### Acceptance Criteria

1. WHEN PR is created, THE CI SHALL invoke Validator Agent first
2. WHEN Validator Agent detects mismatch, THE CI SHALL block PR and NOT invoke Documentor Agent
3. WHEN Validator Agent passes, THE CI SHALL invoke Documentor Agent
4. WHEN Documentor Agent fails, THE PR SHALL remain valid (docs can be regenerated)
5. WHEN Validator Agent fails, THE PR SHALL be blocked (cannot proceed)
6. THE Validator Agent execution time SHALL be < 30 seconds
7. THE Documentor Agent execution time SHALL be < 3 minutes
8. THE agents SHALL run sequentially (Validator → Documentor), not in parallel

---

### Requirement 3: Validator Agent - Universal Contract Validation

**User Story:** As a platform architect, I want the Validator Agent to validate that the "Public Interface" of any changed file matches the Business Spec, regardless of language (YAML/Python/Rego/etc), so that implementation doesn't drift from requirements.

**Reference Pattern:** ✅ Universal Mental Model (Triangulation) + Fast Gate

#### Acceptance Criteria

1. WHEN analyzing a file, THE Validator Agent SHALL identify the "Contract Boundary" (Interface) and ignore implementation details
2. WHEN analyzing Infrastructure (YAML), THE agent SHALL identify Schemas/Parameters (Contract) vs Patches/Transforms (Implementation)
3. WHEN analyzing Code (Python/Go), THE agent SHALL identify Function Signatures/API Models (Contract) vs Logic/Loops (Implementation)
4. WHEN analyzing Policy (OPA/Kyverno), THE agent SHALL identify Rule Definitions (Contract) vs Rego Logic (Implementation)
5. WHEN analyzing Operations Docs, THE agent SHALL identify Trigger/Resolution Steps (Contract) vs Anecdotes (Implementation)
6. THE Validator Agent SHALL compare the extracted Contract against the Spec URL requirements
7. IF a mismatch is detected, THE Validator Agent SHALL block the PR with detailed "Interpreted Intent" comment
8. WHEN aligned, THE Validator Agent SHALL pass and allow Documentor Agent to proceed
9. THE Validator Agent SHALL NOT depend on Qdrant (stateless, fast)
10. THE Validator Agent SHALL use minimal LLM tokens (~2,000-5,000 per PR)

---

### Requirement 4: Interpreted Intent Pattern

**User Story:** As a developer, I want the Validator Agent to clearly label its interpretation of natural language specs, so that I understand it's a projection and can override if incorrect.

**Reference Pattern:** ✅ Transparent agent interpretation with disclaimer

#### Acceptance Criteria

1. WHEN Validator Agent interprets natural language spec, THE agent SHALL label it as "Interpreted Intent" (not "Spec" or "Intent")
2. WHEN showing Intent vs Reality comparison, THE agent SHALL include disclaimer comment explaining this is a projection
3. WHEN showing Intent, THE agent SHALL link to source GitHub issue for verification
4. WHEN posting Gatekeeper comment, THE agent SHALL provide three action options: update code, update spec, or override
5. WHEN developer comments `@librarian override`, THE Validator SHALL allow PR to proceed (with audit log)
6. THE Interpreted Intent SHALL be shown in `<CodeGroup>` component with side-by-side comparison
7. THE Gatekeeper comment SHALL include analysis table showing parameter-by-parameter comparison

---

### Requirement 5: Documentor Agent - MDX Twin Doc Creation

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

### Requirement 6: Documentor Agent - MDX Twin Doc Update

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

### Requirement 7: MDX Component Validation

**User Story:** As a documentation maintainer, I want strict MDX validation rules enforced, so that all Twin Docs follow consistent standards and render correctly.

**Reference Pattern:** ✅ MDX syntax validation with component-specific rules

#### Acceptance Criteria

1. WHEN validating MDX, THE validation SHALL check for unclosed tags
2. WHEN validating `<ParamField>`, THE validation SHALL require `path` and `type` attributes
3. WHEN validating `<Step>`, THE validation SHALL require `title` attribute
4. WHEN validating components, THE validation SHALL only allow approved components: `ParamField`, `Steps`, `Step`, `CodeGroup`, `Warning`, `Note`, `Tip`, `Frame`
5. WHEN validation fails, THE validation SHALL return specific error with component name and missing attribute
6. WHEN validation passes, THE validation SHALL return success status
7. THE validation SHALL check frontmatter fields match category requirements (same as v1)
8. THE validation SHALL enforce filename rules: kebab-case, max 3 words, no timestamps (same as v1)

---

### Requirement 8: Navigation Manifest Management

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

### Requirement 9: Validation with Iteration

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

### Requirement 10: Commit to PR Branch

**User Story:** As a developer, I want the Documentor Agent to commit Twin Docs to my PR branch, so that I can review changes before merge.

**Reference Pattern:** ✅ GitHub API commit to PR branch (via upsert_twin_doc)

**CRITICAL SECURITY REQUIREMENT:** Agents MUST use GitHub App Token or PAT (not default GITHUB_TOKEN)

#### Acceptance Criteria

1. WHEN Twin Doc ready, THE Documentor Agent SHALL call `upsert_twin_doc` tool (atomic operation)
2. WHEN validation passes, THE tool SHALL commit to SAME PR branch automatically using GitHub App Token or PAT
3. WHEN committing, THE commit message SHALL follow convention: "docs: update Twin Doc for {resource}"
4. WHEN committed using App Token/PAT, THE CI SHALL re-run validation (re-trigger workflows)
5. WHEN CI passes, THE PR SHALL be ready for human review
6. WHEN validation fails, THE tool SHALL NOT commit (prevents validation bypass)
7. WHEN using default GITHUB_TOKEN, THE system SHALL fail with error (prevents workflow re-trigger failure)
8. THE Documentor Agent SHALL also commit `docs.json` updates in same PR

---

### Requirement 11: MDX-Aware Qdrant Sync

**User Story:** As a platform operator, I want Twin Docs automatically indexed to Qdrant with semantic chunking, so that agents can retrieve precise information.

**Reference Pattern:** ✅ GitHub Actions workflow on merge to main with MDX-aware chunking

#### Acceptance Criteria

1. WHEN PR merges to main, THE workflow SHALL trigger `sync-docs-to-qdrant.yaml`
2. WHEN syncing, THE workflow SHALL call `sync_to_qdrant` MCP tool
3. WHEN indexing, THE tool SHALL chunk by MDX components (not arbitrary token counts)
4. WHEN indexing, THE tool SHALL create separate chunks for: frontmatter, each `<ParamField>`, each `<Step>`, regular sections
5. WHEN indexing, THE tool SHALL store component metadata in Qdrant payload (type, path, title, index)
6. WHEN indexing, THE tool SHALL generate embeddings and store in Qdrant
7. WHEN indexed, THE Twin Doc SHALL be searchable via `qdrant-find` with precise component-level retrieval
8. THE chunking SHALL preserve semantic boundaries (no splitting mid-component)

---

### Requirement 12: Agent System Prompts

**User Story:** As a platform architect, I want clear, specialized prompts for each agent stored in the repository, so that they perform their roles consistently and the "Brain" is version-controlled with the code.

**Reference Pattern:** ✅ Separate prompts for Validator and Documentor, loaded at runtime from repo

#### Acceptance Criteria

1. WHEN Validator Agent configured, THE system prompt SHALL be loaded from `platform/03-intelligence/agents/validator/prompt.md` at runtime
2. WHEN Documentor Agent configured, THE system prompt SHALL be loaded from `platform/03-intelligence/agents/documentor/prompt.md` at runtime
3. THE system prompts SHALL NOT be hardcoded inside Docker images
4. THE system prompts SHALL be version-controlled in the repository
5. WHEN prompt file changes, THE agents SHALL use updated prompt on next run (no rebuild required)
6. THE agents SHALL have access to reference guides in `platform/03-intelligence/agents/shared/` and agent-specific directories
7. WHEN Validator Agent runs, THE prompt SHALL reference Contract Boundary guide for identification logic
8. WHEN Validator Agent runs, THE prompt SHALL reference Interpreted Intent guide for pattern instructions
9. WHEN Validator Agent runs, THE prompt SHALL NOT include documentation generation logic
10. WHEN Documentor Agent runs, THE prompt SHALL reference Diataxis framework guide for content type classification
11. WHEN Documentor Agent runs, THE prompt SHALL reference MDX component guide for syntax
12. WHEN Documentor Agent runs, THE prompt SHALL embed iteration logic for validation errors
13. WHEN Documentor Agent runs, THE prompt SHALL NOT include Gatekeeper validation logic

---

### Requirement 13: Tool Mapping

**User Story:** As a developer, I want clear mapping between agent tool names and actual MCP tools, so that implementation is consistent.

**Reference Pattern:** ✅ Explicit tool mapping table per agent

#### Acceptance Criteria

**Validator Agent Tools (via GitHub MCP Server):**
1. WHEN Validator needs file content, THE agent SHALL call `github_get_file_contents` MCP tool
2. WHEN Validator needs PR metadata, THE agent SHALL call `github_get_pull_request` MCP tool
3. WHEN Validator posts comment, THE agent SHALL call `github_create_issue_comment` MCP tool
4. THE Validator SHALL NOT have access to Qdrant MCP tools (stateless, fast)
5. THE Validator SHALL NOT have access to file write tools (read-only validation)

**Documentor Agent Tools (via GitHub + Qdrant MCP Servers):**
6. WHEN Documentor searches precedent, THE agent SHALL call `qdrant_find` MCP tool
7. WHEN Documentor needs file content, THE agent SHALL call `github_get_file_contents` MCP tool
8. WHEN Documentor creates/updates file, THE agent SHALL call `github_create_or_update_file` or `github_push_files` MCP tool
9. WHEN Documentor posts comment, THE agent SHALL call `github_create_issue_comment` MCP tool
10. WHEN Documentor indexes docs, THE agent SHALL call `qdrant_store` MCP tool
11. THE Documentor SHALL use LLM reasoning for Contract Boundary extraction (no custom parsing tools)
12. THE Documentor SHALL implement MDX validation logic locally (not via MCP tool)

---

### Requirement 14: Error Handling

**User Story:** As a developer, I want clear error messages when validation fails, so that I know how to fix issues.

**Reference Pattern:** ✅ Structured error responses per agent

#### Acceptance Criteria

**Validator Agent Errors:**
1. WHEN Spec URL missing, THE CI SHALL fail with "❌ Missing GitHub Spec URL" comment
2. WHEN URL non-GitHub, THE CI SHALL fail with "❌ Spec URL must be from github.com" comment
3. WHEN Spec vs Code mismatch, THE Validator SHALL fail with detailed "Interpreted Intent" comparison
4. WHEN Validator fails, THE error SHALL include three action options and override mechanism

**Documentor Agent Errors:**
5. WHEN MDX validation fails, THE Documentor SHALL fail with specific component error and attribute name
6. WHEN `docs.json` update fails, THE Documentor SHALL fail with merge conflict details
7. WHEN max retries exceeded, THE Documentor SHALL fail with all attempted fixes listed
8. WHEN Documentor fails, THE PR SHALL remain valid (docs can be regenerated)

---

### Requirement 15: PR Template

**User Story:** As a developer, I want a PR template that guides me to add Spec URL or inline spec, so that I don't forget.

**Reference Pattern:** ✅ GitHub PR template with two options

#### Acceptance Criteria

1. WHEN creating PR, THE template SHALL display "Specification (Required)" section
2. WHEN template shown, THE section SHALL have two options: GitHub URL or Inline Specification
3. WHEN template shown, THE GitHub URL option SHALL have placeholder: "https://github.com/org/repo/issues/XXX"
4. WHEN template shown, THE Inline Specification option SHALL have sections: Business Requirements and Acceptance Criteria
5. WHEN PR created, THE CI SHALL validate this field before invoking agents
6. WHEN field empty, THE CI SHALL fail before agents run

---

### Requirement 16: Historical Precedent Search

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

### Requirement 17: Test Composition

**User Story:** As a developer, I want a test composition to validate the workflow, so that I can test without affecting production.

**Reference Pattern:** ✅ Simple test resource for end-to-end validation

#### Acceptance Criteria

1. WHEN testing, THE test composition SHALL be `platform/03-intelligence/test-webservice.yaml`
2. WHEN testing, THE composition SHALL have 2-3 simple parameters
3. WHEN testing, THE composition SHALL follow standard Crossplane structure
4. WHEN testing, THE expected Twin Doc SHALL be `artifacts/specs/test-webservice.mdx` (MDX format)
5. WHEN testing, THE workflow SHALL complete end-to-end successfully (Validator → Documentor → Qdrant sync)

---

### Requirement 18: Metrics and Observability

**User Story:** As a platform operator, I want metrics on agent performance, so that I can monitor workflow health.

**Reference Pattern:** ✅ Prometheus metrics per agent

#### Acceptance Criteria

**Validator Agent Metrics:**
1. WHEN Validator runs, THE agent SHALL emit `validator_duration_seconds` histogram
2. WHEN Validator blocks, THE agent SHALL emit `validator_blocks_total` counter
3. WHEN Validator passes, THE agent SHALL emit `validator_passes_total` counter

**Documentor Agent Metrics:**
4. WHEN Documentor runs, THE agent SHALL emit `documentor_duration_seconds` histogram
5. WHEN Twin Doc created, THE agent SHALL emit `twin_doc_created_total` counter
6. WHEN Twin Doc updated, THE agent SHALL emit `twin_doc_updated_total` counter
7. WHEN MDX validation fails, THE agent SHALL emit `mdx_validation_errors_total` counter
8. WHEN `docs.json` conflict occurs, THE agent SHALL emit `docs_json_conflicts_total` counter

**General Metrics:**
9. WHEN metrics collected, THE metrics SHALL be visible in Grafana
10. THE metrics SHALL be exported in Prometheus format

---

### Requirement 19: Distillation from docs/ to artifacts/

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

### Requirement 20: Duplicate Detection for Distillation

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

### Requirement 21: Runbook Template Compliance

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

### Requirement 22: Auto-Generated Header Warning

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

### Requirement 23: Manual Agent Triggers

**User Story:** As a developer, I want to manually trigger agents via PR comments, so that I can re-run validation or regenerate docs without pushing new commits.

**Reference Pattern:** ✅ GitHub issue comment triggers (ChatOps pattern)

#### Acceptance Criteria

1. WHEN developer comments `@librarian validate`, THE CI SHALL re-run Validator Agent only
2. WHEN developer comments `@librarian regenerate-docs`, THE CI SHALL re-run Documentor Agent only
3. WHEN developer comments `@librarian override`, THE Validator Agent SHALL check for this comment BEFORE running LLM validation
4. WHEN `@librarian override` detected, THE Validator Agent SHALL exit with success (0) immediately without LLM call
5. WHEN override used, THE system SHALL log override event with comment author and timestamp for audit purposes
6. THE workflow SHALL trigger on `issue_comment` event type `created` (in addition to `pull_request` events)
7. THE Validator Agent SHALL fetch and scan ALL PR comments for override command before validation
8. THE override command SHALL work regardless of whether "librarian" is a real GitHub user account
9. WHEN override detected, THE Validator SHALL post acknowledgment comment: "✅ Override detected. Validation skipped by {author}"

---

### Requirement 24: Shared Agent Libraries

**User Story:** As a platform maintainer, I want common code shared between Validator and Documentor agents, so that we don't duplicate logic and maintenance is easier.

**Reference Pattern:** ✅ Shared Python libraries in `.github/actions/shared/`

#### Acceptance Criteria

1. WHEN agents need common functionality, THE code SHALL be placed in `.github/actions/shared/` directory
2. THE shared directory SHALL contain: `mcp_bridge.py` (OpenAI-MCP bridge layer), `mdx_utils.py` (MDX parsing/validation), `contract_extractor.py` (Universal Mental Model logic)
3. WHEN Validator Agent builds, THE Dockerfile SHALL copy shared libraries from `../shared/`
4. WHEN Documentor Agent builds, THE Dockerfile SHALL copy shared libraries from `../shared/`
5. THE shared libraries SHALL be unit tested independently
6. THE shared libraries SHALL have clear interfaces and documentation
7. WHEN shared library changes, BOTH agents SHALL use updated code on next build
8. THE shared libraries SHALL NOT contain agent-specific logic (validation vs documentation)
9. THE `mcp_bridge.py` SHALL implement OpenAI function calling to MCP tool execution translation
10. THE `mcp_bridge.py` SHALL handle MCP client connections to multiple MCP servers
11. THE `mcp_bridge.py` SHALL convert MCP tool schemas to OpenAI function definitions

---

### Requirement 25: GitHub Actions Caching Strategy

**User Story:** As a platform operator, I want agent execution to be fast and cost-effective, so that CI doesn't become a bottleneck.

**Reference Pattern:** ✅ GitHub Actions caching for dependencies

#### Acceptance Criteria

1. WHEN Validator Agent runs, THE action SHALL cache Python dependencies using `actions/cache`
2. WHEN Documentor Agent runs, THE action SHALL cache Python dependencies using `actions/cache`
3. WHEN Documentor Agent runs, THE action SHALL cache Node.js dependencies (for MDX validation) using `actions/cache`
4. THE cache key SHALL include: OS, Python version, and `requirements.txt` hash
5. WHEN dependencies unchanged, THE agents SHALL restore from cache (< 10s)
6. WHEN dependencies changed, THE agents SHALL rebuild cache
7. THE caching strategy SHALL keep Documentor execution time < 3 minutes
8. THE caching strategy SHALL keep Validator execution time < 30 seconds

---

### Requirement 26: GitHub Actions Architecture with MCP Integration

**User Story:** As a platform architect, I want agents to run in GitHub Actions with official MCP servers, so that we have standardized tool access and autonomous agent capabilities.

**Reference Pattern:** ✅ GitHub Actions with Docker containers using OpenAI SDK + MCP Bridge

#### Acceptance Criteria

1. WHEN PR is created, THE agents SHALL run in GitHub Actions runner context (not Kubernetes cluster)
2. THE agents SHALL NOT expose cluster API to the internet
3. THE agents SHALL use native GitHub tokens and PR contexts from the runner
4. WHEN agent code changes, THE changes SHALL be versioned with the repository
5. WHEN commit is reverted, THE agent logic SHALL revert automatically
6. THE agents SHALL run as Docker containers defined in `.github/actions/validator/` and `.github/actions/documentor/`
7. THE agents SHALL NOT consume cluster resources during PR checks
8. THE GitHub Actions workflow SHALL be defined in `.github/workflows/librarian.yml`
9. THE agents SHALL use OpenAI Python SDK (`openai>=1.0.0`) for LLM interactions
10. THE agents SHALL use `gpt-4-mini` model for all LLM calls
11. THE agents SHALL configure OpenAI API key from GitHub secrets (`OPENAI_API_KEY`)
12. THE agents SHALL use MCP Python SDK (`mcp>=1.22.0`) as client to connect to MCP servers
13. THE agents SHALL use official GitHub MCP server (`@modelcontextprotocol/server-github` npm package)
14. THE agents SHALL use official Qdrant MCP server (`mcp-server-qdrant` Python package)
15. THE agents SHALL implement bridge layer to translate OpenAI function calls to MCP tool executions
16. THE agents SHALL NOT use complex frameworks (LangChain, LlamaIndex) - only OpenAI SDK + MCP client
17. THE Validator Agent SHALL connect to GitHub MCP server only (no Qdrant)
18. THE Documentor Agent SHALL connect to both GitHub MCP and Qdrant MCP servers

---

### Requirement 27: MCP Bridge Layer

**User Story:** As an agent developer, I want a bridge layer that connects OpenAI function calling to MCP tool execution, so that agents can use official MCP servers autonomously.

**Reference Pattern:** ✅ OpenAI SDK + MCP Client bridge with schema translation

#### Acceptance Criteria

1. WHEN bridge initializes, THE bridge SHALL connect to configured MCP servers using MCP Python SDK
2. WHEN bridge initializes, THE bridge SHALL list all available tools from connected MCP servers
3. WHEN bridge prepares OpenAI request, THE bridge SHALL convert MCP tool schemas to OpenAI function definitions
4. WHEN converting schemas, THE bridge SHALL map MCP `inputSchema` (JSON Schema) to OpenAI `parameters` format
5. WHEN OpenAI returns function call, THE bridge SHALL route to correct MCP server based on tool name
6. WHEN executing tool, THE bridge SHALL call MCP server's `call_tool` method with parsed arguments
7. WHEN tool execution completes, THE bridge SHALL return result to agent for next LLM iteration
8. THE bridge SHALL support multiple MCP servers simultaneously (GitHub + Qdrant)
9. THE bridge SHALL handle MCP server connection errors gracefully
10. THE bridge SHALL implement agent loop: LLM → function call → MCP execution → result → LLM (max iterations)
11. THE bridge SHALL be implemented in `.github/actions/shared/mcp_bridge.py`
12. THE bridge SHALL expose simple API: `MCPOpenAIBridge(mcp_clients).run_agent_loop(prompt, message)`

---

### Requirement 28: MCP Server Configuration in Agents

**User Story:** As an agent operator, I want MCP servers configured correctly in agent containers, so that tools are available at runtime.

**Reference Pattern:** ✅ MCP servers installed and configured in Dockerfile

#### Acceptance Criteria

**Validator Agent MCP Configuration:**
1. WHEN Validator Agent builds, THE Dockerfile SHALL install Node.js v20+
2. WHEN Validator Agent builds, THE Dockerfile SHALL install GitHub MCP server via npm
3. WHEN Validator Agent runs, THE agent SHALL start GitHub MCP server process with stdio transport
4. WHEN Validator Agent runs, THE agent SHALL pass `GITHUB_PERSONAL_ACCESS_TOKEN` to MCP server
5. WHEN Validator Agent runs, THE agent SHALL connect MCP client to GitHub MCP server
6. THE Validator Agent SHALL NOT install or connect to Qdrant MCP server

**Documentor Agent MCP Configuration:**
7. WHEN Documentor Agent builds, THE Dockerfile SHALL install Node.js v20+
8. WHEN Documentor Agent builds, THE Dockerfile SHALL install GitHub MCP server via npm
9. WHEN Documentor Agent builds, THE Dockerfile SHALL install Qdrant MCP server via pip/uvx
10. WHEN Documentor Agent runs, THE agent SHALL start both GitHub and Qdrant MCP server processes
11. WHEN Documentor Agent runs, THE agent SHALL pass `GITHUB_PERSONAL_ACCESS_TOKEN` to GitHub MCP server
12. WHEN Documentor Agent runs, THE agent SHALL pass `QDRANT_URL`, `QDRANT_API_KEY`, `COLLECTION_NAME` to Qdrant MCP server
13. WHEN Documentor Agent runs, THE agent SHALL connect MCP client to both MCP servers
14. THE Qdrant MCP server SHALL use SSE or stdio transport for communication

---

### Requirement 29: Qdrant Cloud Configuration

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

### Requirement 30: Local Documentation Preview

**User Story:** As a developer, I want to preview rendered MDX documentation locally, so that I can see how it looks before merging.

**Reference Pattern:** ✅ Makefile task for local preview

#### Acceptance Criteria

1. WHEN developer runs `make docs-preview`, THE command SHALL start local documentation server
2. WHEN server starts, THE documentation SHALL be available at `http://localhost:4242` (configurable port to avoid conflicts)
3. WHEN viewing locally, THE MDX components SHALL render correctly (`<ParamField>`, `<Steps>`, etc.)
4. THE preview SHALL use Mintlify CLI or equivalent MDX renderer
5. THE preview SHALL show same output as deployed documentation
6. WHEN port 4242 is in use, THE command SHALL find next available port or allow PORT environment variable override

---

## Success Criteria

**For Two-Agent Architecture:**

1. ✅ 100% of PRs modifying `platform/` have valid GitHub Spec URLs or inline specs
2. ✅ 100% of Spec vs Code mismatches are detected and blocked by Validator Agent
3. ✅ Validator Agent execution time < 30 seconds (with caching)
4. ✅ Documentor Agent execution time < 3 minutes (with caching)
5. ✅ Invalid PRs blocked in ~30s (before doc generation)
6. ✅ Valid PRs complete in ~2-3.5 min (Validator + Documentor)
7. ✅ 0% false positives (incorrect mismatch detection)
8. ✅ <5% false positive rate with override mechanism available
9. ✅ `@librarian override` command works instantly (< 5s to detect and skip validation)
10. ✅ Agents run in GitHub Actions context (not cluster)

**For MDX Documentation:**

9. ✅ 100% of new compositions get Twin Docs automatically in MDX format
10. ✅ 100% of Twin Docs use structured components (`<ParamField>`, `<Steps>`, `<CodeGroup>`)
11. ✅ 100% of Twin Docs pass MDX validation after agent commits
12. ✅ 100% of Twin Docs listed in `docs.json` (no orphaned files)
13. ✅ 0% merge conflicts on `docs.json` (git auto-merge + rebase)

**For Qdrant Sync:**

14. ✅ 100% of merged Twin Docs are indexed in Qdrant with MDX-aware chunking
15. ✅ 100% of indexed Twin Docs are searchable via `qdrant-find` with component-level precision
16. ✅ >90% retrieval precision (queries return exact relevant component)

**For Distillation Workflow:**

17. ✅ 100% of PRs modifying `docs/` trigger distillation workflow
18. ✅ 100% of operational knowledge extracted to structured runbooks with `<Steps>` components
19. ✅ 100% of duplicate runbooks detected (similarity > 0.85)
20. ✅ 100% of original docs/ files preserved unchanged
21. ✅ 100% of distilled artifacts pass MDX validation

---

## Non-Functional Requirements

### Performance

- Validator Agent execution time: < 30 seconds per PR (with caching)
- Documentor Agent execution time: < 3 minutes per PR (with caching)
- Override detection time: < 5 seconds (before LLM call)
- Dependency cache restore time: < 10 seconds
- MDX validation script execution: < 5 seconds per document
- Qdrant sync time: < 2 minutes for full `artifacts/` directory
- `docs.json` conflict resolution: < 10 seconds (rebase + retry)
- LLM API call latency: < 5 seconds per request (using gpt-4-mini)

### Reliability

- Validator Agent success rate: > 95% (excluding intentional blocks)
- Documentor Agent success rate: > 90% (excluding validation errors)
- Validation accuracy: 100% (no false positives/negatives)
- Qdrant sync success rate: 100%
- `docs.json` auto-merge success rate: > 95%

### Security

- GitHub token: Stored in External Secrets Operator
- Validator Agent permissions: Read-only to platform/, specs, docs/
- Documentor Agent permissions: Read-only to platform/, write to artifacts/
- Spec URL validation: Prevent injection attacks via URL parsing
- Override mechanism: Audit logged for compliance

### Maintainability

- MDX validation scripts: Unit tested with 100% coverage
- Agent prompts: Version controlled in Git
- Tool mapping: Documented in design doc
- Shared libraries: Reused between Validator and Documentor
- Component library: Limited to approved MDX components

---

## Dependencies

### GitHub Actions Environment
- GitHub Actions enabled with Docker support
- GitHub Bot Token (PAT or GitHub App Token) stored in secrets
- OpenAI API Key stored in GitHub secrets
- GitHub Actions cache enabled (for dependency caching)

### MCP Servers (Official)
- **GitHub MCP Server**: `@modelcontextprotocol/server-github` (npm package)
  - Installed via: `npx -y @modelcontextprotocol/server-github`
  - Requires: `GITHUB_PERSONAL_ACCESS_TOKEN` environment variable
- **Qdrant Cloud MCP Server**: `mcp-server-qdrant` (Python package)
  - Installed via: `uvx mcp-server-qdrant` or `pip install mcp-server-qdrant`
  - Requires: `QDRANT_URL`, `QDRANT_API_KEY`, `COLLECTION_NAME` environment variables
  - User will provide Qdrant Cloud credentials

### Agent Runtime Dependencies
- Python 3.11+ (for agent scripts)
- OpenAI Python SDK (`openai>=1.0.0`) for LLM interactions
- MCP Python SDK (`mcp>=0.1.0`) for MCP client functionality
- Node.js v20+ (for GitHub MCP server and MDX validation)
- MDX parsing library (e.g., `mdx-js/mdx`)
- Mintlify CLI or equivalent for local preview

### External Services
- Qdrant Cloud (managed vector database)
  - No self-hosted Qdrant required
  - User provides cloud URL and API key
- GitHub API (public, no special setup)

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|:-----|:-------|:-----------|
| Validator false positives block valid PRs | High | Provide `@librarian override` mechanism, target <5% false positive rate |
| Documentor Agent infinite loop on validation | High | Max 3 retry limit, clear error messages |
| LLM hallucinates invalid MDX syntax | High | Strict MDX validation with component-specific rules |
| `docs.json` merge conflicts | High | Git auto-merge + rebase logic, max 3 retry attempts |
| Agent misinterprets natural language spec | High | "Interpreted Intent" pattern with disclaimer and source link |
| MDX parsing adds latency to Qdrant sync | Medium | Optimize parser, cache parsed results |
| Raw MDX looks poor in GitHub UI | Medium | Accept trade-off, provide `make docs-preview` for local rendering |
| Existing Markdown files need migration | Medium | Automated migration script, validate all outputs |
| GitHub API rate limits | Medium | Implement exponential backoff |
| Large PRs timeout agents | Medium | Set 5-minute timeout, fail gracefully |

---

## Future Enhancements (Post-v2)

1. **Semantic Mismatch Detection** - Use LLM to detect logical inconsistencies beyond simple parameter checks
2. **Auto-Spec Generation** - Generate GitHub issue template from composition
3. **Diff Visualization** - Show before/after comparison in PR comments with visual diff
4. **Batch Processing** - Handle multiple compositions in one PR efficiently
5. **Rollback Detection** - Detect when code reverts and update Twin Doc accordingly
6. **Parallel Documentor Execution** - For PRs with 5+ changed files
7. **Advanced MDX Components** - Add more interactive components (collapsible sections, tabs, etc.)
8. **Multi-language Support** - Extend to support multiple languages (if needed)
9. **AI-Powered Spec Suggestions** - Suggest spec improvements based on code analysis
10. **Automated Spec Generation** - Generate initial spec from code for new compositions

---

**Document Version:** 2.0  
**Last Updated:** 2025-12-01  
**Status:** Ready for Review  
**Changes from v1:** Two-agent architecture, MDX format, navigation manifest, semantic chunking, interpreted intent pattern
