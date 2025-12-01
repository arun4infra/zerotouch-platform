# Implementation Tasks: Documentor Agent

## Overview

This task list covers the implementation of the Documentor Agent, which automatically creates and updates MDX Twin Docs.

**Priority:** MEDIUM - Depends on Core Infrastructure and Validator

**Depends On:** Core Infrastructure Spec, Validator Spec

**Estimated Time:** 2 weeks

---

## Tasks

- [ ] 1. Set up Documentor Agent structure
  - Create `.github/actions/documentor/` directory
  - Create `documentor.py` main script
  - Create `template_engine.py` module
  - Create `docs_json_manager.py` module
  - Create `requirements.txt`
  - Create `action.yml` (GitHub Action metadata)
  - _Requirements: All_

- [ ] 2. Implement Template Engine
  - [ ] 2.1 Create `template_engine.py` module
    - Define `MDXComponent` dataclass
    - Implement `load_template()` function
    - Implement `fill_template()` function
    - Implement `parse_existing_mdx()` function
    - Implement `update_param_fields()` function
    - _Requirements: 1, 2_
  
  - [ ] 2.2 Implement template loading
    - Load template from `artifacts/templates/spec-template.mdx`
    - Handle missing template errors
    - Cache loaded templates
    - _Requirements: 1_
  
  - [ ] 2.3 Implement template filling
    - Fill frontmatter fields (title, category, description)
    - Generate ParamField components from parameters
    - Add auto-generated warning header
    - Preserve template structure
    - _Requirements: 1, 12_
  
  - [ ] 2.4 Implement MDX parsing
    - Parse frontmatter using regex
    - Parse ParamField components
    - Parse other components (Steps, CodeGroup, etc)
    - Extract manual sections (Overview, Purpose)
    - _Requirements: 2_
  
  - [ ] 2.5 Implement surgical updates
    - Compare existing vs new parameters
    - Update only changed ParamField components
    - Preserve all manual sections
    - Maintain component order
    - _Requirements: 2_
  
  - [ ] 2.6 Write unit tests for Template Engine
    - Test template loading
    - Test template filling with sample data
    - Test MDX parsing with sample MDX
    - Test surgical updates (add, modify, remove parameters)
    - Test preservation of manual sections
    - _Requirements: 1, 2_

- [ ] 3. Implement Docs.json Manager
  - [ ] 3.1 Create `docs_json_manager.py` module
    - Implement `read_docs_json()` function
    - Implement `update_docs_json()` function
    - Implement `find_navigation_group()` function
    - Implement `handle_merge_conflict()` function
    - Implement `format_docs_json()` function
    - _Requirements: 4_
  
  - [ ] 3.2 Implement docs.json reading
    - Fetch docs.json from main branch (not PR branch)
    - Parse JSON content
    - Handle missing docs.json (create new)
    - _Requirements: 4_
  
  - [ ] 3.3 Implement docs.json updating
    - Find appropriate navigation group (Infrastructure, Runbooks, etc)
    - Append new page path (without .mdx extension)
    - Format with one entry per line for git auto-merge
    - _Requirements: 4_
  
  - [ ] 3.4 Implement merge conflict handling
    - Detect merge conflicts on docs.json
    - Fetch latest from main
    - Rebase PR branch
    - Retry update (max 3 attempts)
    - _Requirements: 4_
  
  - [ ] 3.5 Write unit tests for Docs.json Manager
    - Test reading docs.json
    - Test updating with new entry
    - Test finding navigation group
    - Test formatting for git auto-merge
    - Test merge conflict handling
    - _Requirements: 4_

- [ ] 4. Implement main Documentor script
  - [ ] 4.1 Create `documentor.py` entry point
    - Implement `parse_inputs()` function
    - Implement `main()` async function
    - Add error handling and logging
    - Add exit codes
    - _Requirements: 19_
  
  - [ ] 4.2 Implement MCP server initialization
    - Start GitHub MCP server with stdio transport
    - Start Qdrant MCP server with stdio transport
    - Pass environment variables (tokens, URLs, API keys)
    - Handle MCP server startup errors
    - _Requirements: 14, 15, 19_
  
  - [ ] 4.3 Implement agent creation
    - Load system prompt from `platform/03-intelligence/agents/documentor/prompt.md`
    - Create agent with GitHub + Qdrant MCP servers
    - Use `create_agent_with_mcp()` from shared library
    - _Requirements: 17, 19_
  
  - [ ] 4.4 Implement agent execution flow
    - Identify changed compositions in PR
    - For each composition:
      - Search precedent in Qdrant
      - Extract contract boundary
      - Generate/update MDX
      - Validate MDX (max 3 retries)
      - Update docs.json
      - Commit to PR branch
    - Post summary comment
    - _Requirements: 1, 2, 5, 6, 7, 19_

- [ ] 5. Create Documentor system prompt
  - [ ] 5.1 Create prompt file
    - Create `platform/03-intelligence/agents/documentor/` directory
    - Create `prompt.md` file
    - _Requirements: 17_
  
  - [ ] 5.2 Write system prompt content
    - Define Documentor role and capabilities
    - List available GitHub and Qdrant MCP tools
    - Define documentation generation workflow
    - Include MDX component examples
    - Include validation and iteration logic
    - Add rules for structured components (no tables)
    - _Requirements: 1, 2, 3, 17_
  
  - [ ] 5.3 Create reference guides
    - Create `platform/03-intelligence/agents/documentor/guides/` directory
    - Create `diataxis-framework.md` guide
    - Create `mdx-components.md` guide
    - _Requirements: 17_

- [ ] 6. Implement MDX validation with iteration
  - [ ] 6.1 Add validation loop to agent flow
    - Generate MDX content
    - Validate using `validate_mdx()` from shared library
    - If validation fails: feed error back to agent
    - Retry generation (max 3 attempts)
    - If max attempts exceeded: fail with all errors
    - _Requirements: 5_
  
  - [ ] 6.2 Test validation iteration
    - Test with invalid MDX (missing attributes)
    - Verify agent fixes errors
    - Test with max retries exceeded
    - Verify error messages are clear
    - _Requirements: 5, 16_

- [ ] 7. Implement commit to PR branch
  - [ ] 7.1 Add commit logic
    - Use GitHub MCP tool `github_push_files`
    - Commit both Twin Doc and docs.json
    - Use commit message: "docs: update Twin Doc for {resource}"
    - Handle commit errors
    - _Requirements: 6_
  
  - [ ] 7.2 Test commit functionality
    - Test committing new Twin Doc
    - Test updating existing Twin Doc
    - Test committing docs.json
    - Verify workflow re-triggers after commit
    - _Requirements: 6_

- [ ] 8. Implement historical precedent search
  - [ ] 8.1 Add precedent search to agent flow
    - Use Qdrant MCP tool `qdrant_find`
    - Query: "similar to {resource_type}"
    - Review top 3 results
    - Extract naming patterns and conventions
    - _Requirements: 7_
  
  - [ ] 8.2 Test precedent search
    - Index sample Twin Docs to test Qdrant collection
    - Search for similar docs
    - Verify relevant results returned
    - _Requirements: 7_

- [ ] 9. Implement Qdrant sync workflow
  - [ ] 9.1 Create sync workflow file
    - Create `.github/workflows/sync-docs-to-qdrant.yml`
    - Trigger on push to main branch
    - Filter for changes in `artifacts/`
    - _Requirements: 8_
  
  - [ ] 9.2 Implement MDX-aware chunking
    - Chunk by MDX components (not arbitrary tokens)
    - Create separate chunks for: frontmatter, each ParamField, each Step
    - Store component metadata in Qdrant payload
    - Generate embeddings using Qdrant MCP server
    - _Requirements: 8_
  
  - [ ] 9.3 Test Qdrant sync
    - Merge test PR to main
    - Verify sync workflow triggers
    - Verify docs indexed to Qdrant
    - Verify component-level retrieval works
    - _Requirements: 8_

- [ ] 10. Implement distillation workflow
  - [ ] 10.1 Add distillation mode to Documentor
    - Detect changes in `docs/` directory
    - Read free-form troubleshooting notes
    - Identify operational knowledge
    - Create structured runbook using `runbook-template.mdx`
    - Use Steps components for diagnosis and resolution
    - Preserve original docs/ file
    - _Requirements: 9, 11_
  
  - [ ] 10.2 Implement duplicate detection
    - Use Qdrant MCP tool `qdrant_find` to search for similar runbooks
    - If similarity > 0.85: update existing runbook
    - If no match: create new runbook
    - Merge information into existing Steps components
    - _Requirements: 10_
  
  - [ ] 10.3 Test distillation workflow
    - Create test PR modifying docs/
    - Run Documentor in distillation mode
    - Verify structured runbook created
    - Verify original docs/ file preserved
    - Test duplicate detection
    - _Requirements: 9, 10, 11_

- [ ] 11. Create Dockerfile
  - [ ] 11.1 Write Dockerfile
    - Base image: `python:3.11-slim`
    - Install Node.js v20+ for GitHub MCP server
    - Install GitHub MCP server via npm
    - Install Qdrant MCP server via pip
    - Copy requirements.txt and install Python dependencies
    - Copy core infrastructure from `platform/03-intelligence/agents/shared/`
    - Copy Documentor code from `.github/actions/documentor/`
    - Set entrypoint to `python documentor/documentor.py`
    - _Requirements: All_
  
  - [ ] 11.2 Test Docker build
    - Build from repo root: `docker build -f .github/actions/documentor/Dockerfile -t documentor:latest .`
    - Verify all files copied correctly
    - Verify dependencies installed
    - Test container startup
    - _Requirements: All_

- [ ] 12. Create GitHub Action metadata
  - [ ] 12.1 Write `action.yml`
    - Define action name and description
    - Define inputs: pr_number, github_token, openai_api_key, qdrant_url, qdrant_api_key
    - Set runs.using to 'docker'
    - Set runs.image to 'Dockerfile'
    - Map inputs to environment variables
    - _Requirements: All_
  
  - [ ] 12.2 Test action locally
    - Use `act` tool to test GitHub Action locally
    - Verify inputs passed correctly
    - Verify environment variables set
    - _Requirements: All_

- [ ] 13. Implement metrics
  - [ ] 13.1 Add Prometheus metrics
    - Add `documentor_duration_seconds` histogram
    - Add `twin_doc_created_total` counter
    - Add `twin_doc_updated_total` counter
    - Add `mdx_validation_errors_total` counter
    - Add `docs_json_conflicts_total` counter
    - _Requirements: 18_
  
  - [ ] 13.2 Export metrics
    - Configure Prometheus format export
    - Add metrics endpoint (if needed)
    - Test metrics collection
    - _Requirements: 18_

- [ ] 14. Write integration tests
  - [ ] 14.1 Test Twin Doc creation
    - Create test PR with new composition
    - Run Documentor
    - Verify Twin Doc created
    - Verify docs.json updated
    - Verify files committed to PR branch
    - _Requirements: 1, 4, 6_
  
  - [ ] 14.2 Test Twin Doc update
    - Create test PR modifying existing composition
    - Run Documentor
    - Verify only changed parameters updated
    - Verify manual sections preserved
    - _Requirements: 2_
  
  - [ ] 14.3 Test MDX validation iteration
    - Mock validation failure
    - Verify agent retries
    - Verify error handling
    - _Requirements: 5_
  
  - [ ] 14.4 Test docs.json merge conflict
    - Create concurrent PRs
    - Trigger merge conflict on docs.json
    - Verify rebase and retry logic
    - _Requirements: 4_
  
  - [ ] 14.5 Test manual trigger
    - Post `@librarian regenerate-docs` comment
    - Verify workflow triggers
    - Verify Documentor runs
    - _Requirements: 13_

- [ ] 15. Update GitHub Actions workflow
  - [ ] 15.1 Add Documentor job to workflow
    - Update `.github/workflows/librarian.yml`
    - Add `document` job (depends on `validate`)
    - Checkout PR branch
    - Call Documentor action
    - Pass required inputs
    - _Requirements: All_
  
  - [ ] 15.2 Test complete workflow
    - Create test PR
    - Verify Validator runs first
    - Verify Documentor runs only if Validator passes
    - Verify Twin Docs committed
    - Verify workflow re-triggers after commit
    - _Requirements: All_

- [ ] 16. Create documentation
  - [ ] 16.1 Write README
    - Document Documentor purpose
    - Document usage and configuration
    - Document MDX component usage
    - Add troubleshooting guide
    - _Requirements: All_
  
  - [ ] 16.2 Write developer guide
    - Document how to modify system prompt
    - Document how to add new MDX components
    - Document testing procedures
    - Document distillation workflow
    - _Requirements: All_

- [ ] 17. Performance optimization
  - [ ] 17.1 Add caching
    - Cache Python dependencies in GitHub Actions
    - Cache npm dependencies
    - Cache Node.js dependencies
    - Test cache restore time (< 10s)
    - _Requirements: All_
  
  - [ ] 17.2 Optimize execution time
    - Profile Documentor execution
    - Identify bottlenecks
    - Optimize slow operations
    - Verify execution time < 3 minutes
    - _Requirements: All_

- [ ] 18. Create MDX templates
  - [ ] 18.1 Create spec template
    - Create `artifacts/templates/spec-template.mdx`
    - Define frontmatter structure
    - Add placeholder sections (Overview, Parameters, etc)
    - Add auto-generated warning header
    - _Requirements: 1, 12_
  
  - [ ] 18.2 Create runbook template
    - Create `artifacts/templates/runbook-template.mdx`
    - Define frontmatter structure
    - Add sections: Symptoms, Diagnosis, Resolution, Prevention
    - Use Steps components
    - _Requirements: 11_

- [ ] 19. Create local documentation preview
  - [ ] 19.1 Create Makefile task
    - Add `docs-preview` target
    - Start Mintlify dev server on port 4242
    - Allow PORT environment variable override
    - _Requirements: All_
  
  - [ ] 19.2 Test local preview
    - Run `make docs-preview`
    - Verify server starts on port 4242
    - Verify MDX components render correctly
    - Test with sample Twin Docs
    - _Requirements: All_

---

## Success Criteria

- [ ] 100% of new compositions get Twin Docs automatically
- [ ] 100% of Twin Docs use structured components (no tables)
- [ ] 100% of Twin Docs pass MDX validation
- [ ] 100% of Twin Docs listed in docs.json (no orphaned files)
- [ ] Documentor execution time < 3 minutes (with caching)
- [ ] All integration tests pass
- [ ] Distillation workflow works for docs/ files
- [ ] Qdrant sync indexes docs with component-level precision

---

## Notes

- **Dependencies:** Requires Core Infrastructure and Validator to be completed first
- **Testing:** Use test repository and test Qdrant collection
- **System Prompt:** Iterate on prompt based on documentation quality
- **Performance:** Focus on execution time < 3 minutes
- **MDX Components:** Enforce structured components (no Markdown tables)

---

**Estimated Effort:**
- Template Engine: 2 days
- Docs.json Manager: 1 day
- Main script + MCP setup: 2 days
- System prompt: 1 day
- Validation iteration: 1 day
- Distillation workflow: 2 days
- Dockerfile + Action: 1 day
- Integration tests: 2 days
- Workflow + Documentation: 1 day
- Buffer: 1 day

**Total: 14 days (2 weeks)**
