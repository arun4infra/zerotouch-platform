# Twin Docs Workflow Specification

## Overview

This spec defines the automated Twin Docs workflow where the Librarian Agent ensures every platform composition has a corresponding specification document in `artifacts/specs/` that is validated, accurate, and aligned with business intent.

---

## Workflow Trigger

**Event:** Pull Request modifies files in `platform/` directory

**Pre-requisites:**
1. PR description MUST contain a GitHub URL (issue, discussion, or doc)
2. URL MUST be from `github.com` domain
3. If URL is missing or non-GitHub, CI BLOCKS the PR immediately

---

## Workflow Steps

### Step 1: PR Validation (Pre-Agent)

**GitHub Actions Workflow:** `.github/workflows/twin-docs.yaml`

```yaml
# Pseudo-logic
if PR description does NOT contain github.com URL:
  - Fail CI with status check
  - Comment: "❌ Missing GitHub Spec URL. Please add a link to the issue/spec that describes this change."
  - STOP (do not invoke agent)
```

**Success Criteria:** PR has valid GitHub URL → Proceed to Step 2

---

### Step 2: Agent Invocation

**Trigger:** CI invokes Librarian Agent with context:
- PR number
- Changed files list (filtered to `platform/**/*.yaml`)
- Spec URL from PR description

**Agent receives:**
```json
{
  "pr_number": 123,
  "changed_files": ["platform/04-apis/compositions/webservice.yaml"],
  "spec_url": "https://github.com/org/repo/issues/456"
}
```

---

### Step 3: The Gatekeeper Process

The agent executes this cognitive loop:

#### 3.1 Gather Evidence (Triangulation)

**Tool Calls:**
1. `fetch_from_git` → Fetch Spec URL content (business intent)
2. `parse_composition` → Parse changed composition YAML to clean JSON (technical reality)
3. `qdrant-find` → Search for similar resources (historical precedent)

**Agent Reasoning:**
- "I need to understand WHAT the business wants (Spec)"
- "I need to understand WHAT the code does (Composition)" - Use parse_composition for clean parameter extraction
- "I need to understand HOW we documented similar things before (History)"

#### 3.2 Alignment Judgment (Validation)

**Agent Compares:**
- Spec requirements vs. Code parameters (from parse_composition JSON)
- Naming conventions vs. Historical patterns
- Constraints (e.g., "max 10GB") vs. Code defaults (from parse_composition JSON)

**Decision Logic:**
```
IF Spec says "storage max 10GB" AND parse_composition shows default "100GB":
  → MISMATCH DETECTED
  → Call upsert_twin_doc with BLOCKING comment (will fail validation)
  → Fail CI
  → STOP

IF Spec requirements align with Code:
  → PASS
  → Proceed to Step 3.3
```

**Blocking Comment Format:**
```markdown
## ❌ Twin Docs Validation Failed

**Mismatch Detected:**
- **Spec Requirement:** Maximum storage is 10GB (see [spec](URL))
- **Code Reality:** Composition allows `storageSize: 100Gi`

**Action Required:**
Either:
1. Update the code to enforce max 10GB, OR
2. Update the spec to allow 100GB

The code and spec must be aligned before this PR can merge.
```

#### 3.3 Twin Doc Creation/Update (Atomic Operation)

**Agent Logic:**
```
Check if artifacts/specs/{resource-name}.md exists:
  
  IF EXISTS:
    - Fetch existing doc
    - Parse Configuration Parameters table
    - Update ONLY the changed parameters (using parse_composition JSON)
    - Preserve all other sections
  
  IF NOT EXISTS:
    - Fetch template from artifacts/templates/spec-template.md
    - Fill in frontmatter (resource name, category, etc.)
    - Generate Configuration Parameters table from parse_composition JSON
    - Generate Default Values section
```

**Tool Call:** `upsert_twin_doc` (ATOMIC: Validate + Write + Commit)

**Input:**
```json
{
  "file_path": "artifacts/specs/webservice.md",
  "markdown_content": "...",
  "pr_number": 123,
  "commit_message": "docs: update Twin Doc for webservice"
}
```

**Tool Logic (Inside `upsert_twin_doc`):**
1. Run `validate_doc_schemas.py` → Check frontmatter
2. Run `detect_prose.py` → Check for prose violations
3. Run `validate_filenames.py` → Check kebab-case naming
4. IF validation passes → Write file AND commit to PR (atomic)
5. IF validation fails → Return error to agent (no write, no commit)

**Agent Iteration:**
```
ATTEMPT 1: Agent generates doc
  → upsert_twin_doc returns: "❌ Prose detected in Configuration section"
  
ATTEMPT 2: Agent rewrites prose as table
  → upsert_twin_doc returns: "❌ Frontmatter missing 'resource' field"
  
ATTEMPT 3: Agent adds missing field
  → upsert_twin_doc returns: "✅ Success, committed as abc123"
  
MAX ATTEMPTS: 3
IF still failing after 3 attempts:
  → Fail CI with error details
```

**Result:** Twin Doc validated, written, and committed to PR in ONE atomic operation

**Security:** Agent does NOT have direct access to `commit_to_pr` - prevents validation bypass

---

### Step 4: CI Re-validation

**After agent commits:**
1. CI runs validation scripts again
2. Checks all `artifacts/` files pass validation
3. If pass → PR is ready for human review
4. If fail → Agent failed, manual intervention needed

---

### Step 5: Merge & Sync

**On merge to main:**
1. GitHub Actions workflow `.github/workflows/sync-docs-to-qdrant.yaml` triggers
2. Workflow calls `sync_to_qdrant` MCP tool
3. Tool chunks `artifacts/specs/webservice.md`
4. Generates embeddings
5. Indexes to Qdrant with metadata

**Qdrant Entry:**
```json
{
  "id": "artifacts-specs-webservice-001",
  "vector": [0.1, 0.2, ...],
  "payload": {
    "file_path": "artifacts/specs/webservice.md",
    "title": "WebService API Specification",
    "category": "spec",
    "resource": "webservice",
    "last_indexed_commit": "abc123",
    "last_indexed_at": "2025-11-25T12:00:00Z"
  }
}
```

---

## Tool Mapping

| Prompt Tool Name | Actual MCP Tool | Purpose |
|:-----------------|:----------------|:--------|
| `search_knowledge_base` | `qdrant-find` | Semantic search for similar docs |
| `fetch_repo_content` | `fetch_from_git` | Fetch file content from GitHub |
| `parse_composition` | `parse_composition` (MCP tool) | Convert Composition YAML → Clean JSON (name, type, default) |
| `upsert_twin_doc` | `upsert_twin_doc` (MCP tool) | Atomic: Validate + Write + Commit Twin Doc |

---

## Agent System Prompt

**Identity:** The "Guardian of Consistency"

**Mission:** Ensure every piece of code in `platform/` has a corresponding Twin Doc that is accurate, compliant, and aligned with business intent.

**Authority:** Block PRs if logic contradicts specs. Reject documentation that violates style guides.

**Core Process:**

1. **Triangulation:** Gather evidence from Spec URL, Code, and Historical docs
2. **Alignment Judgment:** Compare Spec vs Code. Block if mismatched.
3. **Drafting Loop:** Generate Twin Doc. Iterate on validation errors (max 3 attempts).
4. **Commit:** Push Twin Doc to PR branch.

**Key Behaviors:**
- Never trust vector search alone → Always fetch full live content
- Never answer from general knowledge → Only from retrieved evidence
- Never give up on validation errors → Iterate and fix
- Always cite sources → Include Git URLs in responses

---

## Validation Rules

### Frontmatter Schema (per category)

**For `category: spec`:**
```yaml
---
schema_version: "1.0"
category: spec
resource: webservice  # Must match composition filename
api_version: apis.bizmatters.io/v1alpha1
kind: XWebService
composition_file: platform/04-apis/compositions/webservice.yaml
created_at: 2025-11-25T10:00:00Z
last_updated: 2025-11-25T10:00:00Z
tags:
  - api
  - webservice
---
```

### No-Fluff Policy

**Allowed:**
- Tables
- Bullet lists
- Code blocks
- Inline code

**Forbidden:**
- Prose paragraphs (except in "Overview" and "Purpose" sections)
- Narrative text
- Conversational language

### Filename Rules

- Kebab-case only: `web-service.md` ✅, `WebService.md` ❌
- Max 3 words: `web-service.md` ✅, `web-service-api-gateway.md` ❌
- No timestamps: `web-service.md` ✅, `web-service-2025.md` ❌
- No versions: `web-service.md` ✅, `web-service-v2.md` ❌

---

## Error Handling

### Scenario 1: Missing Spec URL

**CI Action:**
- Fail immediately
- Comment: "❌ Missing GitHub Spec URL"
- Do not invoke agent

### Scenario 2: Non-GitHub URL

**CI Action:**
- Fail immediately
- Comment: "❌ Spec URL must be from github.com domain"
- Do not invoke agent

### Scenario 3: Spec vs Code Mismatch

**Agent Action:**
- Call `commit_to_pr` with blocking comment
- Fail CI
- Do not create Twin Doc

### Scenario 4: Validation Fails After 3 Attempts

**Agent Action:**
- Fail CI
- Comment with all validation errors
- Tag human for manual intervention

### Scenario 5: Agent Cannot Parse Composition

**Agent Action:**
- Fail CI
- Comment: "❌ Cannot parse composition YAML. Please check syntax."
- Include parsing error details

---

## Success Criteria

**For Milestone 3:**

1. ✅ PR without GitHub URL is blocked
2. ✅ PR with non-GitHub URL is blocked
3. ✅ Agent detects Spec vs Code mismatch and blocks PR
4. ✅ Agent creates Twin Doc for new composition
5. ✅ Agent updates Twin Doc for modified composition
6. ✅ Agent iterates on validation errors (max 3 attempts)
7. ✅ Twin Doc passes all validation scripts
8. ✅ Twin Doc committed to same PR branch
9. ✅ On merge, Qdrant sync indexes the Twin Doc
10. ✅ `qdrant-find` can retrieve the Twin Doc semantically

---

## Files to Create/Modify

### New Files:
1. `.github/workflows/twin-docs.yaml` - CI workflow (Twin Docs + Distillation)
2. `.github/pull_request_template.md` - PR template with Spec URL field
3. `artifacts/templates/spec-template.md` - Twin Doc template (verify/update)
4. `artifacts/templates/runbook-template.md` - Runbook template for distillation
5. `artifacts/scripts/parse_composition.py` - Helper script for YAML → JSON
6. `services/docs-mcp/tools/parse_composition.py` - MCP tool wrapper
7. `services/docs-mcp/tools/upsert_twin_doc.py` - Atomic validate+write+commit tool
8. `platform/03-intelligence/test-webservice.yaml` - Test composition

### Existing Files to Enhance:
1. `artifacts/scripts/validate_doc_schemas.py` - Verify schema validation
2. `artifacts/scripts/detect_prose.py` - Verify prose detection
3. `artifacts/scripts/validate_filenames.py` - Verify filename rules
4. `services/docs-mcp/tools/` - Enhance MCP tools for upsert logic

### Agent Configuration:
1. `platform/03-intelligence/compositions/kagents/librarian/librarian-agent.yaml` - Update system prompt

---

## Implementation Order

1. **Verify/Create Templates** - Ensure `artifacts/templates/spec-template.md` and `runbook-template.md` exist
2. **Verify/Enhance Validation Scripts** - Test all 3 validation scripts
3. **Create PR Template** - Add Spec URL field requirement
4. **Create parse_composition Helper** - Implement Python script for YAML → JSON
5. **Create MCP Tools** - Implement parse_composition and upsert_twin_doc
6. **Update Agent System Prompt** - Embed Gatekeeper logic and distillation mode
7. **Create CI Workflow** - Implement twin-docs.yaml (Twin Docs + Distillation)
8. **Create Test Composition** - Add test-webservice.yaml
9. **Test Twin Docs End-to-End** - Create test PR and verify full cycle
10. **Create Qdrant Sync Workflow** - Implement sync-docs-to-qdrant.yaml
11. **Test Distillation** - Create test docs/ file and verify runbook creation
12. **Validate** - Verify Qdrant indexing works for both Twin Docs and runbooks

---

## Testing Plan

### Test Case 1: Missing Spec URL
- Create PR without Spec URL
- Expected: CI fails immediately with comment

### Test Case 2: Non-GitHub URL
- Create PR with `https://example.com/spec`
- Expected: CI fails with "must be github.com" error

### Test Case 3: Spec vs Code Mismatch
- Spec says "max 10GB", Code allows "100GB"
- Expected: Agent blocks PR with mismatch explanation

### Test Case 4: New Twin Doc Creation
- Create new composition `test-webservice.yaml`
- Expected: Agent creates `artifacts/specs/test-webservice.md`

### Test Case 5: Twin Doc Update
- Modify existing composition (add parameter)
- Expected: Agent updates only Configuration Parameters table

### Test Case 6: Validation Error Iteration
- Agent generates doc with prose
- Expected: Agent detects error, rewrites as table, succeeds

### Test Case 7: Qdrant Sync
- Merge PR to main
- Expected: Twin Doc indexed in Qdrant, searchable via `qdrant-find`

---

## Metrics

**Success Metrics:**
- 100% of platform compositions have Twin Docs
- 0% validation failures after agent commits
- < 30 seconds agent execution time per PR
- 0% false positives (incorrect mismatch detection)

**Quality Metrics:**
- Twin Doc accuracy: 100% (parameters match composition)
- Schema compliance: 100% (all frontmatter valid)
- No-Fluff compliance: 100% (no prose violations)

---

## Distillation Workflow (Phase 8)

**Event:** Pull Request modifies files in `docs/` directory

**Purpose:** Extract operational knowledge from free-form developer notes and convert to structured artifacts

### Distillation Steps

#### Step 1: Detect docs/ Changes

**GitHub Actions Workflow:** `.github/workflows/twin-docs.yaml` (extended)

```yaml
# Pseudo-logic
if PR modifies docs/**/*.md:
  - Invoke Librarian Agent in distillation mode
  - Pass list of changed docs/ files
  - Pass PR number for commit
```

#### Step 2: Agent Distillation Process

**Agent Logic:**
1. Read changed docs/ files
2. Identify operational knowledge (runbooks, troubleshooting, procedures)
3. Call `qdrant-find` to search for similar existing artifacts
4. IF similarity score > 0.85 → Update existing artifact
5. IF no match → Create new structured artifact
6. Preserve original docs/ file unchanged

**Tool Calls:**
- `fetch_from_git` → Read docs/ file content
- `qdrant-find` → Search for similar runbooks/procedures
- `upsert_twin_doc` → Create/update structured artifact (atomic)

**Example:**
```
Input: docs/troubleshooting/postgres-disk-issue.md (free-form notes)
Output: artifacts/runbooks/postgres/disk-issue.md (structured template)
Original: docs/troubleshooting/postgres-disk-issue.md (unchanged)
```

#### Step 3: Structured Artifact Creation

**Template:** `artifacts/templates/runbook-template.md`

**Sections:**
- Frontmatter (category: runbook, severity, affected_services)
- Symptoms (bullet list)
- Diagnosis Steps (numbered list)
- Resolution (numbered list)
- Prevention (bullet list)

**Validation:** Same rules as Twin Docs (No-Fluff, schema, filename)

#### Step 4: Duplicate Detection

**Logic:**
```
Agent calls qdrant-find("similar to postgres disk issue")
IF top result score > 0.85:
  → Update existing artifacts/runbooks/postgres/disk-issue.md
  → Merge new information into existing sections
ELSE:
  → Create new artifacts/runbooks/postgres/disk-issue.md
```

**Benefit:** Prevents duplicate runbooks, consolidates knowledge

---

## Future Enhancements (Post-Phase 8)

1. **Semantic Mismatch Detection** - Use LLM to detect logical inconsistencies
2. **Auto-Spec Generation** - Generate GitHub issue from composition
3. **Diff Visualization** - Show before/after in PR comments
4. **Batch Processing** - Handle multiple compositions in one PR
5. **Rollback Detection** - Detect when code reverts to old state
6. **Multi-language Distillation** - Extract knowledge from code comments, logs, etc.

---

## References

- Design Doc: `.kiro/specs/twin-docs-workflow/design.md`
- Requirements: `.kiro/specs/twin-docs-workflow/requirements.md`
- Tasks: `.kiro/specs/twin-docs-workflow/tasks.md`
- Intelligence Layer Spec: `.kiro/specs/intelligence-layer/` (parent spec)
- ADR 003: No-Fluff Policy (to be created in `artifacts/architecture/`)
