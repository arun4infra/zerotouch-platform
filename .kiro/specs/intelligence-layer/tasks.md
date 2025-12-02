# Implementation Plan: Intelligence Layer - Documentation Automation

## MILESTONE 1: Core Infrastructure (Tasks 1-5)

- [ ] 1. Setup Crossplane Configuration structure


  - Create `platform/03-intelligence/` directory with Crossplane layout
  - Add `crossplane.yaml` Configuration metadata file
  - Create `compositions/`, `definitions/`, `examples/`, `providers/`, `test/` directories
  - Add upbound/build submodule reference in `.gitmodules`
  - Create Makefile with makelib includes for build system
  - _Requirements: 17.1, 17.2, 17.3, 17.4_

- [ ] 2. Create validation scripts and templates
- [x] 2.1 Create documentation templates
  - Write `artifacts/templates/spec-template.md` with frontmatter schema
  - Write `artifacts/templates/runbook-template.md` with Symptoms/Diagnosis/Solution tables
  - Write `artifacts/templates/adr-template.md` with decision record structure
  - _Requirements: 11.1, 11.2, 11.3, 11.4_

- [x] 2.2 Implement validation scripts
  - Write `artifacts/scripts/validate_doc_schemas.py` to check frontmatter compliance
  - Write `artifacts/scripts/detect_prose.py` to identify prose paragraphs
  - Write `artifacts/scripts/validate_filenames.py` to enforce kebab-case naming
  - Add unit tests for each validation script
  - _Requirements: 4.2, 4.3, 4.5_
  - ✅ Verified: Created test_validation_scripts.py with unit tests for all validators

- [x] 3. Build docs-mcp MCP server
- [x] 3.1 Create docs-mcp project structure
  - Create `services/docs-mcp/` directory
  - Add Python project files (pyproject.toml, requirements.txt)
  - Create `tools/` directory for MCP tool implementations
  - Add Dockerfile for containerization
  - _Requirements: 7.1, 7.5_
  - ✅ Verified: Created pyproject.toml with project metadata, dependencies, and dev tools

- [x] 3.2 Implement validation MCP tools
  - Implement `validate_doc` tool that wraps validation scripts
  - Return ValidationResult with errors list
  - Add error handling and logging
  - _Requirements: 7.2, 4.5_

- [x] 3.3 Implement document creation MCP tools
  - Implement `create_doc` tool that copies templates and fills placeholders
  - Implement `update_doc` tool that modifies specific sections (tables/lists)
  - Add validation before returning file path
  - _Requirements: 7.2, 4.1, 10.1_

- [x] 3.4 Implement GitHub integration MCP tools
  - Implement `fetch_from_git` tool using GitHub API
  - Implement `commit_to_pr` tool to commit changes to PR branches
  - Add GitHub token authentication and error handling
  - _Requirements: 7.2, 7.4, 9.3, 9.5_

- [x] 3.5 Write unit tests for docs-mcp tools
  - Mock GitHub API responses for testing
  - Test validation tool with sample documents
  - Test create/update tools with templates
  - _Requirements: 7.2_

- [ ] 4. Deploy Qdrant vector database
- [x] 4.1 Create Qdrant Composition
  - Write `platform/03-intelligence/compositions/qdrant.yaml` in Pipeline mode
  - Define StatefulSet with PVC for storage
  - Configure Service for HTTP (6333) and gRPC (6334) ports
  - Set resource requests/limits (512Mi-2Gi memory, 250m-1000m CPU)
  - _Requirements: 6.1, 17.2_

- [x] 4.2 Create Qdrant XRD (optional)
  - Write `platform/03-intelligence/definitions/xqdrant.yaml` if exposing as API
  - Define spec.parameters for storageSize, namespace, replicas
  - Add validation rules for parameters
  - _Requirements: 17.1, 17.4_

- [ ] 4.3 Deploy Qdrant to cluster
  - Apply Qdrant Composition to test cluster
  - Verify StatefulSet is running and PVC is bound
  - Test HTTP and gRPC endpoints are accessible
  - _Requirements: 6.1_
  - ❌ Verified: Pod stuck in Pending (PVC unbound - no storageClassName)
  - ✅ Resolution: Added storageClassName: local-path to volumeClaimTemplate in composition
  - 🔧 TODO: Redeploy Qdrant composition to apply storageClassName fix

- [x] 5. Implement Qdrant integration in docs-mcp
- [x] 5.1 Add Qdrant client to docs-mcp
  - Add qdrant-client Python library to requirements
  - Implement connection management with retry logic
  - Add health check for Qdrant availability
  - _Requirements: 6.3, 13.1_

- [x] 5.2 Implement search_qdrant MCP tool
  - Implement semantic search with query embedding
  - Filter by category parameter
  - Return list of SearchResult with file_path and similarity score
  - _Requirements: 7.2, 10.2, 10.3_

- [x] 5.3 Implement sync_to_qdrant MCP tool
  - Chunk markdown files (512 tokens, 50% overlap)
  - Generate embeddings using OpenAI API
  - Index to Qdrant with metadata (file_path, title, category, commit_sha)
  - Return IndexStats with file count and duration
  - _Requirements: 7.2, 6.2, 6.3, 6.4_

- [x] 5.4 Write integration tests for Qdrant tools
  - Test search with sample documents
  - Test sync with mock artifacts directory
  - Verify similarity scoring works correctly
  - _Requirements: 10.3_

## MILESTONE 2: Agent Functionality (Tasks 6-8)

- [ ] 6. Create Librarian Agent configuration
  - **Success Criteria:** Agent deployed, appears in Kagent UI, can invoke MCP tools
- [x] 6.1 Write agent system prompt
  - Embed ADR 003 standards (No-Fluff policy, naming rules)
  - Add create vs. update decision logic (Twin Docs: check existence, Runbooks: similarity >0.85)
  - Include template adherence instructions
  - Add validation-before-commit requirement
  - Include distillation workflow instructions
  - _Requirements: 8.2, 8.4, 8.5, 10.1, 10.2, 10.3, 10.4_

- [x] 6.2 Create Librarian Agent CRD manifest
  - Write `platform/03-intelligence/compositions/librarian-agent.yaml`
  - Configure Kagent Agent with system prompt
  - Reference docs-mcp server tools by name
  - Set modelConfig to default-model-config
  - _Requirements: 8.1, 8.3_

- [ ] 6.3 Deploy Librarian Agent to cluster
  - Apply Agent CRD to test cluster
  - Verify agent appears in Kagent UI
  - Test agent responds to basic queries
  - _Requirements: 8.1_
  - ❌ Verified: kubectl shows Agent CRD not available in cluster. TODO: Install Kagent and deploy agent

- [ ] 7. Deploy docs-mcp server with KEDA
- [x] 7.1 Create docs-mcp Deployment manifest
  - Write `platform/03-intelligence/compositions/docs-mcp.yaml`
  - Configure Deployment with docs-mcp container image
  - Add ServiceAccount with RBAC (read-only K8s access)
  - Create Service for MCP protocol
  - Mount GitHub token secret from External Secrets Operator
  - _Requirements: 7.1, 18.1, 18.4_

- [x] 7.2 Add KEDA ScaledObject for autoscaling
  - Configure KEDA to scale docs-mcp from 0 to 5 replicas
  - Add Prometheus trigger for HTTP request rate (threshold: 10 req/min)
  - Add CPU utilization trigger (threshold: 70%)
  - _Requirements: 7.3_
  - ✅ Verified: ScaledObject defined in composition (fixed CPU trigger bug: metadataSpec → metadata)
  - ⚠️ Note: ScaledObject will be created when docs-mcp pod starts successfully

- [x] 7.3 Configure Prometheus metrics in docs-mcp
  - Add prometheus_client library to docs-mcp
  - Expose metrics endpoint on /metrics
  - Track tool invocation count and latency
  - _Requirements: 15.2_

- [ ] 7.4 Deploy docs-mcp to cluster
  - Apply docs-mcp Composition to test cluster
  - Verify KEDA ScaledObject is created
  - Test scale-to-zero after 5 minutes idle
  - Test scale-up when load increases
  - _Requirements: 7.1, 7.3_
  - ❌ Verified: Pod in ImagePullBackOff (image ghcr.io/bizmatters/docs-mcp:latest not found)
  - ✅ Resolution: GitHub Actions workflow created (`.github/workflows/build-docs-mcp.yaml`)
  - 🔧 TODO: Trigger workflow run to build image, then redeploy docs-mcp composition

- [ ] 8. Setup GitHub integration
- [ ] 8.1 Create GitHub bot account
  - Create @bizmatters-bot GitHub account
  - Generate GitHub App token with repo scope
  - Store token in External Secrets Operator
  - Configure GPG key for signed commits
  - _Requirements: 9.1, 9.3, 18.2, 18.3_
  - ✅ Documentation: See `platform/03-intelligence/docs/github-bot-setup.md` for complete setup guide
  - ⏸️ Action Required: Manual execution of setup steps by platform admin

- [x] 8.2 Configure CODEOWNERS file
  - Add `/artifacts/ @bizmatters-bot` rule to CODEOWNERS
  - Add `/docs/ @platform-team` rule
  - Test that human PRs modifying artifacts/ are blocked
  - _Requirements: 1.5, 9.1, 9.2_

- [ ] 8.3 Test GitHub API integration
  - Test fetch_from_git tool retrieves file content
  - Test commit_to_pr tool commits to PR branch
  - Verify commits are signed and show @bizmatters-bot as author
  - _Requirements: 9.3, 9.5, 18.3_

## MILESTONE 3: Workflows (Tasks 9-13)

- [ ] 9. Implement Twin Docs workflow
  - **Success Criteria:** Agent can create and update specs for any composition with 100% validation pass rate
- [ ] 9.1 Create test composition
  - Write `platform/03-intelligence/compositions/test-webservice.yaml`
  - Define simple XRD with 2-3 parameters
  - Add Configuration Parameters section
  - _Requirements: 3.1, 3.3_

- [ ] 9.2 Test Twin Doc creation
  - Manually invoke Librarian Agent with test composition
  - Verify agent creates `artifacts/specs/test-webservice.md`
  - Check frontmatter has correct schema_version, category, resource fields
  - Verify Configuration Parameters table is populated
  - **OBSERVABLE:** Kagent UI shows agent activity log with MCP tool calls
  - _Requirements: 3.1, 3.3, 4.1, 4.4_

- [ ] 9.3 Test Twin Doc update
  - Modify test composition (add parameter)
  - Invoke agent to update existing spec
  - Verify only Configuration Parameters table is updated
  - Check other sections remain unchanged
  - _Requirements: 3.2, 3.4_

- [ ] 9.4 Validate Twin Doc output
  - Run validation scripts on generated Twin Doc
  - Verify zero prose violations
  - Check filename follows kebab-case rules
  - _Requirements: 4.2, 4.3, 4.5_

- [ ] 10. Implement CI validation workflow
  - **Success Criteria:** CI auto-fixes all validation violations without manual intervention
- [ ] 10.1 Create GitHub Actions validation workflow
  - Write `.github/workflows/validate-docs.yaml`
  - Trigger on PR changes to `artifacts/**`
  - Run validation scripts (schema, prose, filename)
  - Report errors in PR comments
  - _Requirements: 4.5, 5.1_

- [ ] 10.2 Add CI auto-fix workflow
  - Update validation workflow to invoke Librarian Agent on failure
  - Pass validation error messages to agent
  - Agent fetches offending files, fixes issues, commits back to PR
  - CI re-runs automatically after agent commit
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 10.3 Test CI auto-fix loop
  - Create PR with prose paragraph in artifacts/
  - Verify CI fails with prose detection error
  - Verify agent auto-invoked and fixes prose
  - Verify CI re-runs and passes
  - **OBSERVABLE:** PR shows agent commit with "Fix prose violation" message within 30 seconds
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 11. Implement distillation workflow
- [ ] 11.1 Create distillation trigger in CI
  - Update CI workflow to detect changes in `docs/**`
  - Invoke Librarian Agent in distillation mode
  - Pass list of changed files to agent
  - _Requirements: 2.1, 12.2_

- [ ] 11.2 Test runbook distillation
  - Create `docs/troubleshooting/postgres-disk-issue.md` with free-form notes
  - Create PR and trigger distillation workflow
  - Verify agent searches Qdrant for similar runbooks
  - Verify agent creates `artifacts/runbooks/postgres/disk-issue.md` with structured format
  - Check original docs/ file remains unchanged
  - **OBSERVABLE:** PR shows new structured runbook in artifacts/, original docs/ file untouched
  - _Requirements: 2.2, 2.3, 2.4, 2.5, 12.1, 12.2, 12.3, 12.4, 12.5_

- [ ] 11.3 Test runbook update (duplicate detection)
  - Create second similar note in docs/
  - Verify agent searches Qdrant and finds existing runbook (score >0.85)
  - Verify agent updates existing runbook instead of creating new one
  - _Requirements: 2.4, 10.2, 10.3_

- [ ] 12. Implement Qdrant sync on merge
  - **Success Criteria:** All merged artifacts/ content is searchable in Qdrant within 5 minutes
- [ ] 12.1 Create Qdrant sync workflow
  - Write `.github/workflows/sync-docs-to-qdrant.yaml`
  - Trigger on push to main branch with changes to `artifacts/**`
  - Invoke sync_to_qdrant MCP tool with commit SHA
  - Log indexed file count and duration
  - _Requirements: 6.5, 15.4_

- [ ] 12.2 Test Qdrant sync workflow
  - Merge PR with new runbook to main
  - Verify sync workflow triggers
  - Verify Qdrant collection size increases
  - Query Qdrant for new content and verify it's searchable
  - _Requirements: 6.5_

- [ ] 13. Integrate with real platform compositions
- [ ] 13.1 Point agent at WebService composition
  - Update agent configuration to monitor `platform/04-apis/compositions/webservice.yaml`
  - Create PR modifying webservice composition (add parameter)
  - Verify agent creates/updates `artifacts/specs/webservice.md`
  - Check Twin Doc matches XRD schema exactly
  - **OBSERVABLE:** Modify composition → Check artifacts/ → See updated spec within 1 minute
  - _Requirements: 3.1, 3.2, 16.2_

- [ ] 13.2 Test multi-composition updates
  - Create PR modifying postgresql.yaml and dragonfly.yaml
  - Verify agent updates both specs in same PR
  - Check all specs have corresponding compositions
  - _Requirements: 3.1, 3.2_

- [ ] 13.3 Test new composition detection
  - Add new composition (e.g., redis.yaml) to platform/
  - Verify agent detects and creates new Twin Doc
  - _Requirements: 3.1_

## MILESTONE 4: Production Readiness (Tasks 14-18)

- [ ] 14. Implement observability
  - **Success Criteria:** Full visibility into agent activity via Grafana dashboard and traces
- [ ] 14.1 Configure OpenTelemetry for Librarian Agent
  - Enable OpenTelemetry tracing in Kagent Agent config
  - Configure trace export to observability stack
  - _Requirements: 15.1_

- [ ] 14.2 Create Grafana dashboard
  - Create "Documentation Automation Metrics" dashboard
  - Add panels for: docs created, docs updated, validation failures
  - Add panel for MCP tool invocations and latency
  - Add panel for agent traces (query → tool call → commit)
  - _Requirements: 15.2, 15.3_

- [ ] 14.3 Configure Robusta alerting
  - Add alert for agent failures
  - Add alert for validation failures exceeding threshold
  - Test alerts trigger correctly
  - _Requirements: 15.5_

- [ ] 15. Test disaster recovery
- [ ] 15.1 Test Qdrant crash recovery
  - Delete Qdrant pod
  - Verify agent falls back to GitHub search API
  - Rebuild Qdrant index from Git
  - Verify search works again after rebuild
  - **OBSERVABLE:** Agent continues working during Qdrant downtime, full recovery after rebuild
  - _Requirements: 13.1, 13.2, 13.3_

- [ ] 15.2 Test Qdrant data corruption recovery
  - Corrupt Qdrant data (delete collection)
  - Re-index from artifacts/ directory
  - Verify re-index completes in <5 minutes
  - Verify all content is searchable again
  - _Requirements: 13.2, 13.3, 13.4_

- [ ] 16. Build Crossplane package
  - **Success Criteria:** Intelligence layer deploys via standard Crossplane workflow with ArgoCD
- [ ] 16.1 Configure package build system
  - Verify Makefile includes upbound/build makelib
  - Add .xpkgignore file to exclude non-package files
  - Configure XPKG_REG_ORGS for package registry
  - _Requirements: 17.3_

- [ ] 16.2 Build and test package
  - Run `make build` in platform/03-intelligence/
  - Install package in test cluster
  - Verify Qdrant, docs-mcp, agent deploy successfully
  - Verify `kubectl get configurations` shows bizmatters-intelligence-layer
  - _Requirements: 17.1, 17.2_

- [ ] 16.3 Test ArgoCD sync
  - Configure ArgoCD to sync intelligence layer from package
  - Verify ArgoCD syncs successfully
  - Test sync waves work correctly (bootstrap → platform APIs → intelligence)
  - _Requirements: 16.3_

- [ ] 17. Production hardening
- [ ] 17.1 Add rate limiting to docs-mcp
  - Implement rate limiting for MCP API endpoints
  - Configure per-client rate limits
  - Test rate limiting works correctly
  - _Requirements: 18.1_

- [ ] 17.2 Add retry logic for GitHub API
  - Implement exponential backoff for GitHub API calls
  - Handle rate limit errors gracefully
  - Test retry logic during GitHub API outage simulation
  - _Requirements: 18.2_

- [ ] 17.3 Configure security and RBAC
  - Review docs-mcp ServiceAccount RBAC (read-only K8s access)
  - Verify GitHub token has repo scope only (no admin)
  - Verify secrets stored in External Secrets Operator
  - Review RBAC for no cluster-admin or write to platform/
  - _Requirements: 18.1, 18.2, 18.4, 18.5_

- [ ] 17.4 Perform load testing
  - **Success Criteria:** System handles 10 concurrent PRs without degradation
  - Simulate 10 concurrent PRs modifying different compositions
  - Verify all specs updated within 2 minutes
  - Verify docs-mcp scales to 5 replicas under load
  - Verify no GitHub API rate limit errors
  - _Requirements: 7.3_

- [ ] 18. Agent acceptance testing
  - **Success Criteria:** All end-to-end workflows complete successfully, full platform is self-documented
- [ ] 18.1 Test content migration
  - Agent moves docs/templates/ → artifacts/templates/ (preserving Git history)
  - Agent moves docs/architecture/ → artifacts/architecture/
  - Agent moves scripts/ → artifacts/scripts/
  - Verify `git log --follow` shows continuous history
  - Verify all validation passes for migrated content
  - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

- [ ] 18.2 Test end-to-end workflows
  - Test Twin Doc creation from real composition
  - Test distillation from docs/ to artifacts/
  - Test CI auto-fix for validation violations
  - Test Qdrant sync on merge
  - Verify all workflows complete successfully
  - _Requirements: 3.1, 2.2, 5.1, 6.5_

- [ ] 18.3 Verify integration with other platform layers
  - Test bootstrap CLI → intelligence layer discovers compositions
  - Test new Crossplane API deployment → agent creates spec
  - Verify full platform is self-documented
  - _Requirements: 16.1, 16.2, 16.4_
