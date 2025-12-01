# Implementation Tasks: Validator Agent

## Overview

This task list covers the implementation of the Validator Agent, which validates Spec vs Code alignment in PRs.

**Priority:** HIGH - Must be completed before Documentor

**Depends On:** Core Infrastructure Spec

**Estimated Time:** 1 week

---

## Tasks

- [ ] 1. Set up Validator Agent structure
  - Create `.github/actions/validator/` directory
  - Create `validator.py` main script
  - Create `override_checker.py` module
  - Create `requirements.txt`
  - Create `action.yml` (GitHub Action metadata)
  - _Requirements: All_

- [ ] 2. Implement main Validator script
  - [ ] 2.1 Create `validator.py` entry point
    - Implement `parse_inputs()` function to read environment variables
    - Implement `main()` async function
    - Add error handling and logging
    - Add exit codes (0=pass, 1=block)
    - _Requirements: 10_
  
  - [ ] 2.2 Implement MCP server initialization
    - Start GitHub MCP server with stdio transport
    - Pass `GITHUB_PERSONAL_ACCESS_TOKEN` environment variable
    - Handle MCP server startup errors
    - _Requirements: 6, 10_
  
  - [ ] 2.3 Implement agent creation
    - Load system prompt from `platform/03-intelligence/agents/validator/prompt.md`
    - Create agent with GitHub MCP server
    - Use `create_agent_with_mcp()` from shared library
    - _Requirements: 8, 10_
  
  - [ ] 2.4 Implement agent execution flow
    - Check for override comment FIRST (via direct GitHub API, NOT Agent)
    - If override found: post acknowledgment and exit(0) WITHOUT starting MCP/Agent
    - If no override: start GitHub MCP server
    - If no override: create Agent with MCP server
    - If no override: run agent task to validate PR
    - Post gatekeeper comment if mismatch detected
    - Exit with appropriate code (0=pass, 1=block)
    - _Requirements: 2, 4, 10_

- [ ] 3. Implement Override Checker
  - [ ] 3.1 Create `override_checker.py` module
    - Implement `check_for_override()` function
    - Use `requests` library for direct GitHub API call (NOT Agent/MCP)
    - Call GitHub API: `GET /repos/{owner}/{repo}/issues/{pr_number}/comments`
    - Scan all PR comments for `@librarian override` (case-insensitive)
    - Return override status and author
    - Keep execution time < 5 seconds
    - _Requirements: 4_
  
  - [ ] 3.2 Implement override acknowledgment
    - Post comment: "✅ Override detected. Validation skipped by {author}"
    - Use direct GitHub API call: `POST /repos/{owner}/{repo}/issues/{pr_number}/comments`
    - Log override event for audit (author, timestamp)
    - _Requirements: 4_
  
  - [ ] 3.3 Write unit tests for Override Checker
    - Test detection of override comment
    - Test case-insensitive matching
    - Test with multiple comments
    - Test with no override comment
    - Test execution time < 5 seconds
    - Mock GitHub API responses
    - _Requirements: 4_

- [ ] 4. Create Validator system prompt
  - [ ] 4.1 Create prompt file
    - Create `platform/03-intelligence/agents/validator/` directory
    - Create `prompt.md` file
    - _Requirements: 8_
  
  - [ ] 4.2 Write system prompt content
    - Define Validator role and capabilities
    - List available GitHub MCP tools
    - Define validation workflow steps
    - Include Contract Boundary identification instructions
    - Include Interpreted Intent pattern instructions
    - Add examples of gatekeeper comments
    - _Requirements: 2, 3, 8_
  
  - [ ] 4.3 Create reference guides
    - Create `platform/03-intelligence/agents/validator/guides/` directory
    - Create `contract-boundary.md` guide
    - Create `interpreted-intent.md` guide
    - _Requirements: 8_

- [ ] 5. Implement PR specification enforcement
  - [ ] 5.1 Add spec validation logic to prompt
    - Instruct agent to check PR description for GitHub URL or inline spec
    - Define validation rules (github.com domain, required sections)
    - Define error messages for missing/invalid specs
    - _Requirements: 1_
  
  - [ ] 5.2 Test spec validation
    - Test with valid GitHub URL
    - Test with invalid URL (non-GitHub)
    - Test with inline spec
    - Test with missing spec
    - _Requirements: 1_

- [ ] 6. Create Dockerfile
  - [ ] 6.1 Write Dockerfile
    - Base image: `python:3.11-slim`
    - Install Node.js v20+ for GitHub MCP server
    - Install GitHub MCP server via npm
    - Copy requirements.txt and install Python dependencies
    - Copy core infrastructure from `platform/03-intelligence/agents/shared/`
    - Copy Validator code from `.github/actions/validator/`
    - Set entrypoint to `python validator/validator.py`
    - _Requirements: All_
  
  - [ ] 6.2 Test Docker build
    - Build from repo root: `docker build -f .github/actions/validator/Dockerfile -t validator:latest .`
    - Verify all files copied correctly
    - Verify dependencies installed
    - Test container startup
    - _Requirements: All_

- [ ] 7. Create GitHub Action metadata
  - [ ] 7.1 Write `action.yml`
    - Define action name and description
    - Define inputs: pr_number, github_token, openai_api_key
    - Set runs.using to 'docker'
    - Set runs.image to 'Dockerfile'
    - Map inputs to environment variables
    - _Requirements: All_
  
  - [ ] 7.2 Test action locally
    - Use `act` tool to test GitHub Action locally
    - Verify inputs passed correctly
    - Verify environment variables set
    - _Requirements: All_

- [ ] 8. Implement metrics
  - [ ] 8.1 Add Prometheus metrics
    - Add `validator_duration_seconds` histogram
    - Add `validator_blocks_total` counter
    - Add `validator_passes_total` counter
    - Add `validator_overrides_total` counter
    - _Requirements: 9_
  
  - [ ] 8.2 Export metrics
    - Configure Prometheus format export
    - Add metrics endpoint (if needed)
    - Test metrics collection
    - _Requirements: 9_

- [ ] 9. Write integration tests
  - [ ] 9.1 Create test repository
    - Create test GitHub repository
    - Add sample compositions
    - Add sample specs (GitHub issues)
    - _Requirements: All_
  
  - [ ] 9.2 Test end-to-end validation
    - Create test PR with valid spec
    - Run Validator
    - Verify validation passes
    - _Requirements: 2, 3_
  
  - [ ] 9.3 Test mismatch detection
    - Create test PR with spec/code mismatch
    - Run Validator
    - Verify gatekeeper comment posted
    - Verify PR blocked (exit code 1)
    - _Requirements: 2, 3, 7_
  
  - [ ] 9.4 Test override mechanism
    - Create test PR with mismatch
    - Post `@librarian override` comment
    - Run Validator
    - Verify override detected
    - Verify acknowledgment comment posted
    - Verify PR passes (exit code 0)
    - _Requirements: 4_
  
  - [ ] 9.5 Test manual trigger
    - Post `@librarian validate` comment
    - Verify workflow triggers
    - Verify Validator runs
    - _Requirements: 5_

- [ ] 10. Create GitHub Actions workflow
  - [ ] 10.1 Create workflow file
    - Create `.github/workflows/librarian.yml`
    - Define `validate` job
    - Add trigger on `pull_request` events
    - Add trigger on `issue_comment` events
    - _Requirements: All_
  
  - [ ] 10.2 Configure workflow
    - Checkout code
    - Call Validator action
    - Pass required inputs (pr_number, tokens)
    - Handle success/failure
    - _Requirements: All_
  
  - [ ] 10.3 Test workflow
    - Create test PR
    - Verify workflow triggers
    - Verify Validator runs
    - Verify comments posted
    - _Requirements: All_

- [ ] 11. Create documentation
  - [ ] 11.1 Write README
    - Document Validator purpose
    - Document usage and configuration
    - Document override mechanism
    - Add troubleshooting guide
    - _Requirements: All_
  
  - [ ] 11.2 Write developer guide
    - Document how to modify system prompt
    - Document how to add new validation rules
    - Document testing procedures
    - _Requirements: All_

- [ ] 12. Performance optimization
  - [ ] 12.1 Add caching
    - Cache Python dependencies in GitHub Actions
    - Cache npm dependencies
    - Test cache restore time (< 10s)
    - _Requirements: All_
  
  - [ ] 12.2 Optimize execution time
    - Profile Validator execution
    - Identify bottlenecks
    - Optimize slow operations
    - Verify execution time < 30s
    - _Requirements: 2_

---

## Success Criteria

- [ ] Validator detects 100% of spec/code mismatches
- [ ] Validator execution time < 30 seconds (with caching)
- [ ] Override mechanism works instantly (< 5s)
- [ ] All integration tests pass
- [ ] Gatekeeper comments are clear and actionable
- [ ] Manual trigger (`@librarian validate`) works
- [ ] Metrics are exported correctly

---

## Notes

- **Dependencies:** Requires Core Infrastructure to be completed first
- **Testing:** Use test repository for integration tests
- **System Prompt:** Iterate on prompt based on validation accuracy
- **Performance:** Focus on fast execution (< 30s target)

---

**Estimated Effort:**
- Main script + MCP setup: 1 day
- Override checker: 0.5 days
- System prompt: 1 day
- Dockerfile + Action: 1 day
- Integration tests: 1.5 days
- Workflow + Documentation: 1 day
- Buffer: 1 day

**Total: 7 days (1 week)**
