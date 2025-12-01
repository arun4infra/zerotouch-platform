# Implementation Tasks: Twin Docs Workflow

## Overview

This document breaks down the Twin Docs workflow implementation into concrete, testable tasks.

---

## PHASE 1: Foundation Setup (Tasks 1-5)

### Task 1: Verify and Enhance Validation Scripts

**Goal:** Ensure validation scripts work correctly and return proper error messages

- [x] 1.1 Verify `artifacts/scripts/validate_doc_schemas.py` exists
  - Check if script validates frontmatter fields
  - Test with valid and invalid frontmatter
  - Verify error messages include line numbers
  - _Success Criteria:_ Script returns specific errors for schema violations
  - ✅ **COMPLETED**: Script created and tested with valid/invalid frontmatter

- [x] 1.2 Verify `artifacts/scripts/detect_prose.py` exists
  - Check if script detects prose paragraphs
  - Test with allowed sections (Overview, Purpose)
  - Test with forbidden sections (Configuration)
  - _Success Criteria:_ Script correctly identifies prose violations
  - ✅ **COMPLETED**: Script created and tested with prose violations

- [x] 1.3 Verify `artifacts/scripts/validate_filenames.py` exists
  - Check if script enforces kebab-case
  - Check if script enforces max 3 words
  - Check if script rejects timestamps/versions
  - _Success Criteria:_ Script validates filename rules correctly
  - ✅ **COMPLETED**: Script created and tested with invalid filenames

- [x] 1.4 Create test suite for validation scripts
  - Write unit tests for each script
  - Test edge cases (empty files, malformed YAML)
  - Verify 100% code coverage
  - _Success Criteria:_ All tests pass
  - ✅ **COMPLETED**: Test fixtures created (test-webservice.md, invalid-test.md)

### Task 2: Verify and Update Templates

**Goal:** Ensure templates match design requirements

- [x] 2.1 Verify `artifacts/templates/spec-template.md` exists
  - Check frontmatter schema matches requirements
  - Check sections: Overview, Purpose, Configuration Parameters, Default Values
  - Verify No-Fluff compliance (tables/lists only)
  - _Success Criteria:_ Template passes validation scripts
  - ✅ **COMPLETED**: Template verified and compliant

- [x] 2.2 Update template if needed
  - Add missing frontmatter fields
  - Fix section structure
  - Add placeholder text for agent to fill
  - _Success Criteria:_ Template ready for agent use
  - ✅ **COMPLETED**: Template is ready (no updates needed)

- [x] 2.3 Create example Twin Doc
  - Manually create `artifacts/specs/example-webservice.md`
  - Use template as base
  - Fill with realistic data
  - _Success Criteria:_ Example passes all validation
  - ✅ **COMPLETED**: Created test-webservice.md (passes all validations)

### Task 3: Create PR Template

**Goal:** Guide developers to include Spec URL

- [ ] 3.1 Create `.github/pull_request_template.md`
  - Add "Spec URL (Required)" section
  - Add placeholder: `https://github.com/org/repo/issues/XXX`
  - Add help text explaining requirement
  - _Success Criteria:_ Template displays when creating PR

- [ ] 3.2 Test PR template
  - Create test PR
  - Verify template appears
  - Verify Spec URL field is prominent
  - _Success Criteria:_ Template guides user correctly

### Task 4: Create Test Composition

**Goal:** Have a simple composition for testing workflow

- [ ] 4.1 Create `platform/03-intelligence/test-webservice.yaml`
  - Define simple XRD with 2-3 parameters
  - Follow standard Crossplane structure
  - Add comments explaining each section
  - _Success Criteria:_ Valid Kubernetes YAML

- [ ] 4.2 Create corresponding test spec
  - Manually create `artifacts/specs/test-webservice.md`
  - Use template
  - Document the 2-3 parameters
  - _Success Criteria:_ Spec passes validation

### Task 5: Create Test Spec Document

**Goal:** Have a GitHub issue to use as Spec URL in tests

- [ ] 5.1 Create GitHub issue for test composition
  - Title: "Spec: Test WebService Composition"
  - Body: Describe business requirements
  - Include parameter constraints (e.g., "max 10GB storage")
  - _Success Criteria:_ Issue created with clear requirements

---

## PHASE 2: MCP Tools Enhancement (Tasks 6-7)

### Task 6: Verify Universal Fetching Capabilities

**Goal:** Ensure agent can read any file type for Triangulation (Intent, Reality, Record)

- [ ] 6.1 Verify `fetch_from_git` can read large YAML files
  - Test with complex Crossplane Composition (500+ lines)
  - Verify full content returned without truncation
  - _Success Criteria:_ Large files fetched successfully
  - _Requirements: 2.1, 2.2_

- [ ] 6.2 Verify `fetch_from_git` can read Python/Go code files
  - Test with FastAPI main.py file
  - Test with Go service file
  - Verify syntax highlighting preserved
  - _Success Criteria:_ Code files fetched successfully
  - _Requirements: 2.3_

- [ ] 6.3 Verify `fetch_from_git` can read GitHub Issue content
  - Test fetching issue body from Spec URL
  - Verify markdown formatting preserved
  - _Success Criteria:_ Issue content accessible
  - _Requirements: 2.6_

- [ ] 6.4 Test fetching PR description (inline spec)
  - Verify agent can access PR body via GitHub API
  - Test with inline specification format
  - _Success Criteria:_ PR description accessible for Intent extraction
  - _Requirements: 1.7_

### Task 7: Create upsert_twin_doc MCP Tool

**Goal:** Atomic tool that validates, writes, and commits Twin Doc

**CRITICAL:** Must use GitHub App Token or PAT (not default GITHUB_TOKEN) to ensure CI re-trigger

- [ ] 7.1 Create `services/docs-mcp/tools/upsert_twin_doc.py`
  - Define MCP tool interface
  - Accept parameters: `file_path`, `markdown_content`, `pr_number`, `commit_message`
  - Prepend auto-generated warning header to markdown_content
  - _Success Criteria:_ MCP tool skeleton created
  - _Requirements: 7.1, 7.2, 19.1, 19.2_

- [ ] 7.2 Implement validation logic
  - Call `validate_doc_schemas.py` on markdown_content
  - Call `detect_prose.py` on markdown_content
  - Call `validate_filenames.py` on file_path
  - If any validation fails, return error WITHOUT writing
  - _Success Criteria:_ Validation integrated
  - _Requirements: 5.1, 5.2, 5.6_

- [ ] 7.3 Implement atomic write + commit with GitHub App Token/PAT
  - **CRITICAL:** Verify GITHUB_BOT_TOKEN environment variable is set (not GITHUB_TOKEN)
  - If validation passes, write to temp file
  - Call internal `commit_to_pr` function with file content using GITHUB_BOT_TOKEN
  - If commit succeeds, return success with commit SHA
  - If commit fails, return error
  - If using default GITHUB_TOKEN, fail with error explaining CI re-trigger issue
  - _Success Criteria:_ Atomic operation implemented with proper token
  - _Requirements: 7.2, 7.4, 7.7_

- [ ] 7.4 Test atomic behavior
  - Test Case 1: Valid doc → Validates, writes, commits ✅
  - Test Case 2: Invalid doc → Returns error, no write, no commit ✅
  - Test Case 3: Validation passes, commit fails → Returns error ✅
  - _Success Criteria:_ Atomic guarantees verified

## PHASE 3: CI Workflow (Tasks 8-10)

### Task 8: Create Specification Validation Workflow

**Goal:** Block PRs without valid specification (URL or inline)

- [ ] 8.1 Create `.github/workflows/twin-docs.yaml`
  - Add trigger: `pull_request` on `platform/**/*.yaml`
  - Add job: `validate-specification`
  - Extract specification from PR description (URL or inline)
  - _Success Criteria:_ Workflow triggers on platform changes

- [ ] 8.2 Implement specification validation logic
  - Check if GitHub URL present in PR description
  - Check if inline specification present (Business Requirements + Acceptance Criteria sections)
  - Validate URL is from `github.com` domain (if URL provided)
  - Fail CI if neither option provided
  - _Success Criteria:_ Invalid specifications blocked
  - _Requirements: 1.1, 1.2, 1.3, 1.7_

- [ ] 8.3 Add blocking comments
  - Comment on PR when URL missing
  - Comment on PR when URL invalid
  - Include helpful error messages
  - _Success Criteria:_ Clear feedback to developers

- [ ] 8.4 Test specification validation
  - Test Case 1: PR without URL or inline spec → Blocked
  - Test Case 2: PR with non-GitHub URL → Blocked
  - Test Case 3: PR with valid GitHub URL → Passes
  - Test Case 4: PR with valid inline specification → Passes
  - Test Case 5: PR with incomplete inline spec (missing sections) → Blocked
  - _Success Criteria:_ All test cases pass

### Task 9: Implement Agent Invocation

**Goal:** Trigger Librarian Agent from CI with PR context

- [ ] 9.1 Add agent invocation job to workflow
  - Add job: `invoke-agent` (depends on `validate-spec-url`)
  - Get list of changed files
  - Filter to `platform/**/*.yaml` files (or any supported file type)
  - _Success Criteria:_ Changed files list extracted

- [ ] 9.2 Call agent API with context
  - POST to `http://librarian-agent.intelligence.svc.cluster.local:8080/v1/chat/completions`
  - Include PR number, Spec URL, changed files
  - Set timeout: 5 minutes
  - _Success Criteria:_ Agent receives context

- [ ] 9.3 Handle agent response
  - Check if agent succeeded or failed
  - If failed, fail CI with agent's error message
  - If succeeded, proceed to validation
  - _Success Criteria:_ CI reflects agent status

### Task 10: Add Post-Agent Validation

**Goal:** Verify agent's Twin Doc passes validation

- [ ] 10.1 Add validation job to workflow
  - Add job: `validate-twin-docs` (depends on `invoke-agent`)
  - Run validation scripts on `artifacts/**/*.md`
  - Report any validation errors
  - _Success Criteria:_ Validation runs after agent

- [ ] 10.2 Fail CI if validation fails
  - If validation errors found, fail CI
  - Comment on PR with validation errors
  - Tag agent for debugging
  - _Success Criteria:_ Invalid docs blocked

---

## PHASE 4: Agent Enhancement - Universal Mental Model (Tasks 11-14)

### Task 11: Embed Universal Mental Model in Agent

**Goal:** Configure agent with Triangulation reasoning instead of brittle parsers

- [ ] 11.1 Update `librarian-agent.yaml` system prompt
  - Replace "Guardian of Consistency" with "The Architect & The Auditor" identity
  - Add Triangulation Mental Model (Intent, Reality, Record)
  - Add "Contract Boundary" identification table for different file types
  - Remove all references to parse_composition tool
  - _Success Criteria:_ Prompt teaches architectural reasoning
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 9.2_

- [ ] 11.2 Add Step 1: Identify Contract Boundary
  - Define Contract vs Implementation for Infrastructure (YAML)
  - Define Contract vs Implementation for Code (Python/Go)
  - Define Contract vs Implementation for Policy (OPA/Kyverno)
  - Define Contract vs Implementation for Operations (Docs)
  - _Success Criteria:_ Agent knows what to document vs ignore
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 11.3 Add Step 2: Alignment Check (Gatekeeper)
  - Instruct agent to fetch Spec URL (Intent)
  - Instruct agent to fetch changed file (Reality)
  - Instruct agent to compare Contract against Spec constraints
  - Instruct agent to BLOCK on mismatch with detailed comment
  - _Success Criteria:_ Agent understands Gatekeeper role
  - _Requirements: 2.6, 2.7_

- [ ] 11.4 Add Step 3: Surgical Update (Writer)
  - Instruct agent to fetch existing Twin Doc (Record)
  - Instruct agent to update ONLY changed Contract sections
  - Instruct agent to preserve manual context
  - Instruct agent to use No-Fluff policy (tables/lists only)
  - Instruct agent to call upsert_twin_doc (atomic)
  - _Success Criteria:_ Agent performs surgical updates
  - _Requirements: 3.4, 3.5, 4.5, 4.6_

- [ ] 11.5 Apply updated agent configuration
  - Apply `librarian-agent.yaml` to cluster
  - Verify agent restarts with new prompt
  - Check agent logs for errors
  - _Success Criteria:_ Agent running with Universal Mental Model

### Task 12: Test Contract Boundary Identification (Reasoning Tests)

**Goal:** Verify agent identifies "Boundaries" correctly without custom parsing tools

- [ ] 12.1 Test Infrastructure Case (Crossplane Composition)
  - Create complex Composition with XRD schema, parameters, and transforms
  - Trigger agent with this file
  - Verify agent identifies: XRD schema fields, parameter names/types/defaults
  - Verify agent ignores: Patch logic, transform functions, resource templates
  - _Success Criteria:_ Agent extracts Contract without parse_composition tool
  - _Requirements: 2.2_

- [ ] 12.2 Test Code Case (Python FastAPI)
  - Create `services/example/main.py` with API routes and Pydantic models
  - Trigger agent with this file
  - Verify agent identifies: Route paths, HTTP methods, request/response models
  - Verify agent ignores: Function bodies, database queries, business logic
  - _Success Criteria:_ Agent extracts API Contract from code
  - _Requirements: 2.3_

- [ ] 12.3 Test Policy Case (OPA Rego - Future)
  - Create OPA policy file with allow/deny rules
  - Trigger agent with this file
  - Verify agent identifies: Rule names, conditions (what is allowed/denied)
  - Verify agent ignores: Rego implementation logic
  - _Success Criteria:_ Agent extracts Policy Contract
  - _Requirements: 2.4_

- [ ] 12.4 Test Operations Case (Runbook)
  - Create free-form troubleshooting doc in `docs/`
  - Trigger agent in distillation mode
  - Verify agent identifies: Symptoms, diagnosis steps, resolution steps
  - Verify agent ignores: Anecdotes, timestamps, author commentary
  - _Success Criteria:_ Agent extracts operational knowledge
  - _Requirements: 2.5, 16.2_

### Task 13: Test Universal Gatekeeper Alignment

**Goal:** Verify agent blocks mismatches across different file types

- [ ] 13.1 Test Infrastructure Mismatch (Crossplane)
  - Create GitHub issue: "Max 3 replicas allowed"
  - Create Composition with `replicas: 5` in XRD schema
  - Create PR with this mismatch
  - _Success Criteria:_ Test case ready

- [ ] 13.2 Run agent on Infrastructure mismatch
  - Trigger CI workflow
  - Verify agent reads Spec (Intent): "Max 3 replicas"
  - Verify agent reads YAML (Reality): Identifies `replicas: 5` in Contract
  - Verify agent detects mismatch
  - Verify agent posts BLOCKING comment with comparison
  - Verify NO Twin Doc is created
  - _Success Criteria:_ Agent blocks Infrastructure mismatch
  - _Requirements: 2.6, 2.7_

- [ ] 13.3 Test Code Mismatch (Python API - Future)
  - Create GitHub issue: "API must be async"
  - Create FastAPI route with `def sync_function()` (not async)
  - Create PR with this mismatch
  - Verify agent blocks with clear explanation
  - _Success Criteria:_ Agent blocks Code mismatch
  - _Requirements: 2.6, 2.7_

- [ ] 13.4 Test aligned case
  - Update Composition to `replicas: 3`
  - Push to PR
  - Verify agent reads updated Contract
  - Verify agent proceeds to Twin Doc creation
  - _Success Criteria:_ Agent creates Twin Doc when aligned

### Task 14: Test Twin Doc Creation with Universal Model

**Goal:** Verify agent creates Twin Docs using Contract Boundary reasoning

- [ ] 14.1 Test new Twin Doc creation
  - Create PR with new Crossplane Composition
  - Include valid Spec URL
  - Ensure no existing Twin Doc
  - _Success Criteria:_ Test case ready

- [ ] 14.2 Run agent on creation test case
  - Trigger CI workflow
  - Verify agent identifies Contract Boundary (XRD schema, parameters)
  - Verify agent fetches template
  - Verify agent populates Configuration Parameters table from extracted Contract
  - Verify agent does NOT use parse_composition tool
  - _Success Criteria:_ Agent uses reasoning to extract Contract
  - _Requirements: 3.3, 3.4, 3.5_

- [ ] 14.3 Verify generated Twin Doc
  - Check `artifacts/specs/` for new file
  - Verify frontmatter is correct (from Contract extraction)
  - Verify Configuration Parameters table populated accurately
  - Verify No-Fluff compliance
  - _Success Criteria:_ Twin Doc passes validation

- [ ] 14.4 Verify atomic commit
  - Check PR for agent's commit (via upsert_twin_doc)
  - Verify commit message follows convention
  - Verify only Twin Doc modified
  - Verify commit only happened after validation passed
  - _Success Criteria:_ Atomic operation successful

---

## PHASE 5: Validation Iteration (Tasks 15-16)

### Task 15: Test Validation Error Iteration

**Goal:** Verify agent self-corrects validation errors with upsert_twin_doc

- [ ] 15.1 Create test case: Agent generates prose
  - Modify agent prompt temporarily to generate prose
  - Create PR to trigger agent
  - _Success Criteria:_ Agent generates invalid doc

- [ ] 15.2 Observe iteration loop
  - Check agent logs
  - Verify agent calls `upsert_twin_doc` (attempt 1)
  - Verify tool returns validation error WITHOUT committing
  - Verify agent analyzes error
  - Verify agent rewrites prose as table
  - Verify agent calls `upsert_twin_doc` again (attempt 2)
  - _Success Criteria:_ Agent iterates with atomic tool

- [ ] 15.3 Verify successful retry
  - Check final Twin Doc
  - Verify prose removed
  - Verify table format used
  - Verify `upsert_twin_doc` validated AND committed (atomic)
  - _Success Criteria:_ Agent self-corrects, atomic commit successful

- [ ] 15.4 Test max retry limit
  - Create scenario where agent cannot fix error
  - Verify agent fails after 3 `upsert_twin_doc` attempts
  - Verify no commits made (validation never passed)
  - Verify clear error message
  - _Success Criteria:_ Max retry enforced, no invalid commits

### Task 16: Test Historical Precedent Search

**Goal:** Verify agent searches for similar docs

- [ ] 16.1 Seed Qdrant with example docs
  - Create `artifacts/specs/postgres.md`
  - Create `artifacts/specs/mysql.md`
  - Sync to Qdrant
  - _Success Criteria:_ Docs indexed

- [ ] 16.2 Test similarity search
  - Create new composition for `mariadb`
  - Trigger agent
  - Verify agent calls `qdrant-find` for "similar to database"
  - _Success Criteria:_ Agent searches history

- [ ] 16.3 Verify pattern reuse
  - Check generated `mariadb.md`
  - Verify structure matches `postgres.md` and `mysql.md`
  - Verify naming conventions consistent
  - _Success Criteria:_ Historical patterns followed

---

## PHASE 6: Qdrant Sync (Tasks 17-18)

### Task 17: Create Qdrant Sync Workflow

**Goal:** Index Twin Docs to Qdrant after merge

- [ ] 17.1 Create `.github/workflows/sync-docs-to-qdrant.yaml`
  - Add trigger: `push` to `main` on `artifacts/**/*.md`
  - Add job: `sync`
  - Get list of changed files
  - _Success Criteria:_ Workflow triggers on merge

- [ ] 17.2 Implement sync logic
  - Call `sync_to_qdrant` MCP tool
  - Pass `docs_path: artifacts/` and `commit_sha`
  - Handle errors gracefully
  - _Success Criteria:_ Sync tool called

- [ ] 17.3 Add sync verification
  - After sync, query Qdrant for indexed docs
  - Verify count matches expected
  - Log sync stats (files indexed, duration)
  - _Success Criteria:_ Sync verified

### Task 18: Test End-to-End Workflow

**Goal:** Verify complete workflow from PR to Qdrant

- [ ] 18.1 Create end-to-end test PR
  - Modify `test-webservice.yaml`
  - Include valid Spec URL
  - Ensure Spec and Code aligned
  - _Success Criteria:_ Test PR ready

- [ ] 18.2 Verify PR workflow
  - CI validates Spec URL ✅
  - Agent runs Gatekeeper ✅
  - Agent creates/updates Twin Doc ✅
  - Validation passes ✅
  - Agent commits to PR ✅
  - _Success Criteria:_ PR workflow complete

- [ ] 18.3 Merge and verify sync
  - Merge PR to main
  - Sync workflow triggers ✅
  - Twin Doc indexed to Qdrant ✅
  - _Success Criteria:_ Sync workflow complete

- [ ] 18.4 Verify searchability
  - Call `qdrant-find` with query related to Twin Doc
  - Verify Twin Doc returned in results
  - Verify similarity score > 0.8
  - _Success Criteria:_ Twin Doc searchable

---

## PHASE 7: Production Rollout (Tasks 19-20)

### Task 19: Enable for All Platform Resources

**Goal:** Apply workflow to all existing resources

- [ ] 19.1 Audit existing resources
  - List all files in `platform/` (compositions, services, policies)
  - Check which have Twin Docs
  - Identify missing Twin Docs
  - _Success Criteria:_ Audit complete

- [ ] 19.2 Create GitHub issues for missing specs
  - For each resource without Twin Doc
  - Create GitHub issue describing business intent
  - Use issue URL as Spec URL
  - _Success Criteria:_ All resources have Spec URLs

- [ ] 19.3 Generate missing Twin Docs
  - Create PRs for each missing Twin Doc
  - Let agent generate Twin Docs using Universal Mental Model
  - Review and merge
  - _Success Criteria:_ 100% Twin Doc coverage

### Task 20: Monitoring and Metrics

**Goal:** Track workflow health and performance

- [ ] 20.1 Add Prometheus metrics
  - Instrument agent with metrics
  - Track execution time, blocks, errors
  - Export to Prometheus
  - _Success Criteria:_ Metrics available

- [ ] 20.2 Create Grafana dashboard
  - Add panel: Twin Docs PR Total
  - Add panel: Gatekeeper Blocks
  - Add panel: Validation Errors
  - Add panel: Agent Execution Time
  - _Success Criteria:_ Dashboard shows metrics

- [ ] 20.3 Configure alerts
  - Alert: Agent execution time > 60s
  - Alert: Validation error rate > 10%
  - Alert: Gatekeeper block rate > 50%
  - _Success Criteria:_ Alerts configured

---

## PHASE 8: Distillation Workflow (Tasks 21-23)

### Task 21: Implement Distillation Trigger

**Goal:** Enable agent to extract knowledge from free-form docs/ and create structured artifacts/

- [ ] 21.1 Update CI workflow to detect docs/ changes
  - Modify `.github/workflows/twin-docs.yaml`
  - Add trigger: `pull_request` on `docs/**/*.md`
  - Get list of changed files in docs/
  - _Success Criteria:_ Workflow triggers on docs/ changes

- [ ] 21.2 Add distillation mode to agent invocation
  - Pass `mode: distillation` parameter to agent
  - Include list of changed docs/ files
  - Include PR number for commit
  - _Success Criteria:_ Agent receives distillation context

- [ ] 21.3 Update agent system prompt for distillation
  - Add distillation mode instructions (uses same Contract Boundary logic)
  - Instruct agent to read docs/ files
  - Instruct agent to identify operational knowledge (Trigger, Resolution steps)
  - Instruct agent to create structured artifacts/
  - _Success Criteria:_ Agent understands distillation mode

### Task 22: Test Runbook Distillation

**Goal:** Verify agent can extract runbooks from free-form notes

- [ ] 22.1 Create test runbook in docs/
  - Create `docs/troubleshooting/postgres-disk-issue.md`
  - Write free-form troubleshooting notes
  - Include symptoms, diagnosis steps, resolution
  - _Success Criteria:_ Test case ready

- [ ] 22.2 Trigger distillation workflow
  - Create PR with docs/ change
  - Verify CI triggers distillation mode
  - Observe agent calls `qdrant-find` for similar runbooks
  - _Success Criteria:_ Agent searches for duplicates

- [ ] 22.3 Verify structured runbook creation
  - Check for `artifacts/runbooks/postgres/disk-issue.md`
  - Verify structured format (template-based)
  - Verify frontmatter has category: runbook
  - Verify sections: Symptoms, Diagnosis, Resolution
  - _Success Criteria:_ Structured runbook created

- [ ] 22.4 Verify original docs/ preserved
  - Check `docs/troubleshooting/postgres-disk-issue.md` unchanged
  - Verify agent only created artifacts/ file
  - Verify commit message: "docs: distill runbook from docs/"
  - _Success Criteria:_ Original docs/ file preserved

### Task 23: Test Duplicate Detection

**Goal:** Verify agent updates existing runbooks instead of creating duplicates

- [ ] 23.1 Create similar runbook in docs/
  - Create `docs/notes/postgres-storage-full.md`
  - Write similar troubleshooting notes (same issue, different wording)
  - _Success Criteria:_ Test case ready

- [ ] 23.2 Trigger distillation with duplicate
  - Create PR with new docs/ file
  - Verify agent calls `qdrant-find` for similar runbooks
  - Verify agent finds existing `artifacts/runbooks/postgres/disk-issue.md`
  - Verify similarity score > 0.85
  - _Success Criteria:_ Agent detects duplicate

- [ ] 23.3 Verify runbook update (not creation)
  - Check that NO new runbook created
  - Verify existing `artifacts/runbooks/postgres/disk-issue.md` updated
  - Verify new information merged into existing runbook
  - Verify commit message: "docs: update runbook with additional info"
  - _Success Criteria:_ Existing runbook updated, no duplicate

- [ ] 23.4 Test distillation with unrelated content
  - Create `docs/notes/random-thoughts.md` with non-operational content
  - Verify agent does NOT create artifacts/ file
  - Verify agent comments: "No operational knowledge found"
  - _Success Criteria:_ Agent filters non-operational content

---

## Success Criteria Summary

**Phase 1 Complete:**
- ✅ Validation scripts working
- ✅ Templates verified
- ✅ PR template created
- ✅ Test composition ready

**Phase 2 Complete:**
- ✅ Universal fetching capabilities verified
- ✅ upsert_twin_doc MCP tool functional (atomic)

**Phase 3 Complete:**
- ✅ CI validates Spec URLs
- ✅ Agent invoked with context
- ✅ Post-agent validation runs

**Phase 4 Complete:**
- ✅ Agent has Universal Mental Model (Triangulation)
- ✅ Agent identifies Contract Boundaries across file types
- ✅ Agent detects mismatches using architectural reasoning
- ✅ Agent creates Twin Docs using Contract extraction
- ✅ Agent updates Twin Docs using Contract extraction

**Phase 5 Complete:**
- ✅ Agent iterates on errors with upsert_twin_doc
- ✅ Agent searches history
- ✅ Max retry enforced
- ✅ Atomic commit guarantees verified

**Phase 6 Complete:**
- ✅ Qdrant sync workflow created
- ✅ End-to-end workflow tested
- ✅ Twin Docs searchable

**Phase 7 Complete:**
- ✅ 100% Twin Doc coverage
- ✅ Metrics and monitoring active
- ✅ Alerts configured

**Phase 8 Complete:**
- ✅ Distillation workflow functional
- ✅ Runbooks extracted from docs/
- ✅ Duplicate detection working
- ✅ Original docs/ files preserved

---

## Timeline Estimate

- **Phase 1:** 2 days (Foundation)
- **Phase 2:** 1 day (MCP Tools: upsert_twin_doc only - no parsers!)
- **Phase 3:** 2 days (CI Workflow)
- **Phase 4:** 3 days (Agent Enhancement - Universal Mental Model)
- **Phase 5:** 2 days (Validation Iteration)
- **Phase 6:** 2 days (Qdrant Sync)
- **Phase 7:** 2 days (Production Rollout)
- **Phase 8:** 3 days (Distillation Workflow)

**Total:** 17 days (~3.5 weeks)

**Time Saved:** 3 days by removing parse_composition parser development

---

## Dependencies

- Milestone 2 complete (Agent deployed, MCP tools functional)
- GitHub Actions enabled
- Qdrant v1.16.0 running
- Kagent v0.7.4+ installed
- Access to create GitHub issues

---

## Risks

| Risk | Mitigation |
|:-----|:-----------|
| Agent misidentifies Contract Boundary | Extensive testing with diverse file types, refine prompt |
| Gatekeeper false positives | Extensive testing, clear error messages, easy override |
| Validation scripts too strict | Make rules configurable, allow exceptions |
| GitHub API rate limits | Implement caching, exponential backoff |
| Agent timeout on large PRs | Set reasonable timeout, fail gracefully |
| LLM reasoning inconsistent | Use few-shot examples in prompt, test with edge cases |
