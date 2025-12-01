# Requirements Document: Validator Agent

## Introduction

This document defines requirements for the Validator Agent, a fast gate that validates Spec vs Code alignment in PRs.

**Scope:** PR validation, gatekeeper logic, override mechanism, GitHub MCP integration

**Execution Time:** < 30 seconds per PR

**Location:** `.github/actions/validator/`

---

## Glossary

- **Validator Agent**: Fast gate agent that validates Spec vs Code alignment (~20-30s execution)
- **Gatekeeper**: Validation logic that compares Spec (business intent) vs Code (technical reality)
- **Spec URL**: GitHub URL in PR description pointing to issue/doc describing business intent
- **Inline Spec**: Specification embedded directly in PR description (for small changes)
- **Contract Boundary**: Public interface of a file (schemas, parameters, API signatures) vs implementation details
- **Interpreted Intent**: Agent's projection of natural language requirements into structured format

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

### Requirement 2: Universal Contract Validation

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

### Requirement 3: Interpreted Intent Pattern

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

### Requirement 4: Override Mechanism

**User Story:** As a developer, I want to manually override validation via PR comment, so that I can proceed when the agent is incorrect.

**Reference Pattern:** ✅ GitHub issue comment triggers (ChatOps pattern)

**Implementation Note:** Override check MUST use direct GitHub API call (not Agent/LLM) to keep execution time < 5 seconds.

#### Acceptance Criteria

1. WHEN developer comments `@librarian override`, THE Validator Agent SHALL check for this comment BEFORE running LLM validation
2. WHEN checking for override, THE Validator SHALL use direct GitHub API call (via `requests` library) NOT via Agent/LLM
3. WHEN `@librarian override` detected, THE Validator Agent SHALL exit with success (0) immediately without LLM call
4. WHEN override used, THE system SHALL log override event with comment author and timestamp for audit purposes
5. THE Validator Agent SHALL fetch and scan ALL PR comments for override command before validation
6. THE override command SHALL work regardless of whether "librarian" is a real GitHub user account
7. WHEN override detected, THE Validator SHALL post acknowledgment comment: "✅ Override detected. Validation skipped by {author}"
8. THE override check execution time SHALL be < 5 seconds

---

### Requirement 5: Manual Validation Trigger

**User Story:** As a developer, I want to manually trigger validation via PR comment, so that I can re-run validation without pushing new commits.

**Reference Pattern:** ✅ GitHub issue comment triggers (ChatOps pattern)

#### Acceptance Criteria

1. WHEN developer comments `@librarian validate`, THE CI SHALL re-run Validator Agent only
2. THE workflow SHALL trigger on `issue_comment` event type `created` (in addition to `pull_request` events)

---

### Requirement 6: GitHub MCP Tools

**User Story:** As a Validator Agent, I want to use GitHub MCP tools for all GitHub operations, so that I leverage standardized tooling.

**Reference Pattern:** ✅ Official GitHub MCP server

#### Acceptance Criteria

1. WHEN Validator needs file content, THE agent SHALL call `github_get_file_contents` MCP tool
2. WHEN Validator needs PR metadata, THE agent SHALL call `github_get_pull_request` MCP tool
3. WHEN Validator needs PR comments, THE agent SHALL call `github_list_issue_comments` MCP tool
4. WHEN Validator posts comment, THE agent SHALL call `github_create_issue_comment` MCP tool
5. THE Validator SHALL NOT have access to Qdrant MCP tools (stateless, fast)
6. THE Validator SHALL NOT have access to file write tools (read-only validation)

---

### Requirement 7: Error Handling

**User Story:** As a developer, I want clear error messages when validation fails, so that I know how to fix issues.

**Reference Pattern:** ✅ Structured error responses

#### Acceptance Criteria

1. WHEN Spec URL missing, THE CI SHALL fail with "❌ Missing GitHub Spec URL" comment
2. WHEN URL non-GitHub, THE CI SHALL fail with "❌ Spec URL must be from github.com" comment
3. WHEN Spec vs Code mismatch, THE Validator SHALL fail with detailed "Interpreted Intent" comparison
4. WHEN Validator fails, THE error SHALL include three action options and override mechanism

---

### Requirement 8: System Prompt

**User Story:** As a platform architect, I want the Validator prompt stored in the repository, so that the "Brain" is version-controlled with the code.

**Reference Pattern:** ✅ Prompt loaded at runtime from repo

#### Acceptance Criteria

1. WHEN Validator Agent runs, THE system prompt SHALL be loaded from `platform/03-intelligence/agents/validator/prompt.md` at runtime
2. THE system prompt SHALL NOT be hardcoded inside Docker image
3. THE system prompt SHALL be version-controlled in the repository
4. WHEN prompt file changes, THE agent SHALL use updated prompt on next run (no rebuild required)
5. THE prompt SHALL reference Contract Boundary guide for identification logic
6. THE prompt SHALL reference Interpreted Intent guide for pattern instructions
7. THE prompt SHALL NOT include documentation generation logic

---

### Requirement 9: Metrics

**User Story:** As a platform operator, I want metrics on Validator performance, so that I can monitor workflow health.

**Reference Pattern:** ✅ Prometheus metrics

#### Acceptance Criteria

1. WHEN Validator runs, THE agent SHALL emit `validator_duration_seconds` histogram
2. WHEN Validator blocks, THE agent SHALL emit `validator_blocks_total` counter
3. WHEN Validator passes, THE agent SHALL emit `validator_passes_total` counter
4. WHEN override used, THE agent SHALL emit `validator_overrides_total` counter
5. THE metrics SHALL be exported in Prometheus format

---

### Requirement 10: Execution Flow

**User Story:** As a Validator Agent, I want a clear execution flow, so that I perform validation efficiently.

**Reference Pattern:** ✅ Sequential execution with early exits

#### Acceptance Criteria

1. WHEN Validator starts, THE agent SHALL parse inputs (PR number, GitHub token, OpenAI key)
2. WHEN Validator starts, THE agent SHALL check for `@librarian override` comment (via direct GitHub API call, NOT via Agent)
3. WHEN override found, THE agent SHALL post acknowledgment and exit(0) WITHOUT starting MCP servers or Agent
4. WHEN no override, THE agent SHALL start GitHub MCP server
5. WHEN no override, THE agent SHALL create Agent with GitHub MCP server (using `create_agent_with_mcp()`)
6. WHEN no override, THE agent SHALL load system prompt from repo
7. WHEN no override, THE agent SHALL run agent task to validate PR
8. WHEN mismatch detected, THE agent SHALL post gatekeeper comment
9. WHEN complete, THE agent SHALL exit with appropriate code (0=pass, 1=block)
10. THE override check SHALL complete in < 5 seconds to save tokens and time

---

## Dependencies

- Core Infrastructure (MCP bridge, contract extractor)
- OpenAI API Key
- GitHub Bot Token (BOT_GITHUB_TOKEN)
- GitHub MCP Server (`@modelcontextprotocol/server-github`)

---

## Success Criteria

1. ✅ 100% of PRs modifying `platform/` have valid GitHub Spec URLs or inline specs
2. ✅ 100% of Spec vs Code mismatches are detected and blocked
3. ✅ Validator execution time < 30 seconds (with caching)
4. ✅ Invalid PRs blocked in ~30s
5. ✅ <5% false positive rate with override mechanism available
6. ✅ `@librarian override` command works instantly (< 5s to detect and skip validation)

---

## Non-Functional Requirements

### Performance
- Execution time: < 30 seconds per PR (with caching)
- Override detection time: < 5 seconds (before LLM call)
- LLM token usage: 2,000-5,000 tokens per PR

### Reliability
- Success rate: > 95% (excluding intentional blocks)
- Validation accuracy: 100% (no false positives/negatives with override available)

### Security
- Read-only access to platform/, specs, docs/
- No write permissions
- Audit log for override usage

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** Ready for Implementation  
**Depends On:** Core Infrastructure Spec
