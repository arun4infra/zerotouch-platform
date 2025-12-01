I'll break down the implementation into clear checkpoints where you review and approve before I proceed. This prevents mistakes and ensures we're aligned at each stage.

Implementation Checkpoints & Testing Strategy
CHECKPOINT 0: Pre-Implementation Verification ⚠️ START HERE
Goal: Verify what already exists before writing any code

Tasks:

Check if validation scripts exist in artifacts/scripts/:
validate_doc_schemas.py
detect_prose.py
validate_filenames.py
Verify templates are complete:
artifacts/templates/spec-template.md
artifacts/templates/runbook-template.md
Check if artifacts/scripts/ directory exists
Testing:

List files in artifacts/scripts/
Read template files to verify structure
Document what exists vs. what needs to be created
Deliverable: Report showing:

✅ What exists and works
❌ What's missing
🔧 What needs enhancement
👉 STOP HERE - You review the report before I proceed

CHECKPOINT 1: Validation Scripts Foundation
Goal: Ensure validation scripts work correctly

Tasks:

If scripts exist: Test them with sample files
If scripts missing: Create them based on design doc requirements
Create test fixtures (valid/invalid docs)
Run validation scripts against test fixtures
Testing:

# Test filename validation
python3 artifacts/scripts/validate_filenames.py artifacts/specs/test-webservice.md  # Should pass
python3 artifacts/scripts/validate_filenames.py artifacts/specs/TestWebService.md   # Should fail (not kebab-case)

# Test schema validation
python3 artifacts/scripts/validate_doc_schemas.py artifacts/specs/test-webservice.md  # Should pass/fail based on frontmatter

# Test prose detection
python3 artifacts/scripts/detect_prose.py artifacts/specs/test-webservice.md  # Should pass/fail based on content
Deliverable:

Working validation scripts
Test results showing pass/fail scenarios
Documentation of validation rules
👉 STOP HERE - You review validation results before I proceed

CHECKPOINT 2: parse_composition Tool (Helper Script)
Goal: Create Python script that converts Crossplane Composition YAML → Clean JSON

Tasks:

Create artifacts/scripts/parse_composition.py
Implement YAML parsing logic
Extract parameters from spec.pipeline (Crossplane v1.14+ format)
Output clean JSON format
Testing:

# Test with simple composition
cat platform/03-intelligence/test-webservice.yaml | python3 artifacts/scripts/parse_composition.py

# Expected output:
{
  "resource_name": "test-webservice",
  "api_version": "apis.bizmatters.io/v1alpha1",
  "kind": "XTestWebService",
  "parameters": [
    {
      "name": "replicas",
      "type": "integer",
      "required": false,
      "default": "1",
      "description": "Number of pod replicas"
    }
  ]
}

# Test with malformed YAML (should return error)
echo "invalid: yaml: :" | python3 artifacts/scripts/parse_composition.py
Deliverable:

Working parse_composition.py script
Test results with sample compositions
JSON output examples
👉 STOP HERE - You review parse_composition output before I proceed

CHECKPOINT 3: parse_composition MCP Tool Wrapper
Goal: Create MCP tool that wraps the helper script

Tasks:

Create services/docs-mcp/tools/parse_composition.py
Integrate with helper script via subprocess
Add error handling
Register tool in main.py
Testing:

# Start docs-mcp server locally
cd services/docs-mcp
python3 main.py

# Test MCP tool (via MCP client or curl)
# This would call the tool with a composition file path
# Expected: JSON response with parsed parameters
Deliverable:

Working MCP tool
Integration test results
Error handling verification
👉 STOP HERE - You review MCP tool integration before I proceed

CHECKPOINT 4: upsert_twin_doc MCP Tool (Atomic Operation)
Goal: Create atomic tool that validates, writes, and commits Twin Docs

Tasks:

Create services/docs-mcp/tools/upsert_twin_doc.py
Implement validation logic (calls 3 validation scripts)
Implement atomic write + commit logic
Add error handling (return error WITHOUT committing if validation fails)
Testing:

# Test Case 1: Valid doc → Should validate, write, commit
# Test Case 2: Invalid doc (prose in forbidden section) → Should return error, NO write, NO commit
# Test Case 3: Invalid doc (missing frontmatter field) → Should return error, NO write, NO commit
# Test Case 4: Validation passes, commit fails → Should return error

# Manual test:
# 1. Create valid Twin Doc content
# 2. Call upsert_twin_doc with PR number, file path, content
# 3. Verify validation runs
# 4. Verify file written only if validation passes
# 5. Verify commit only if write succeeds
Deliverable:

Working upsert_twin_doc tool
Test results proving atomic behavior
Error scenarios documented
👉 STOP HERE - You review atomic operation guarantees before I proceed

CHECKPOINT 5: PR Template & Test Composition
Goal: Create PR template and test composition for end-to-end testing

Tasks:

Create .github/pull_request_template.md
Create platform/03-intelligence/test-webservice.yaml (simple Crossplane composition)
Create corresponding GitHub issue (Spec URL)
Manually create artifacts/specs/test-webservice.md (for comparison)
Testing:

# Test parse_composition with test composition
cat platform/03-intelligence/test-webservice.yaml | python3 artifacts/scripts/parse_composition.py

# Verify output matches expected parameters
# Verify test-webservice.md passes validation
python3 artifacts/scripts/validate_doc_schemas.py artifacts/specs/test-webservice.md
Deliverable:

PR template with Spec URL field
Test composition (valid Kubernetes YAML)
Test Twin Doc (passes validation)
GitHub issue URL for testing
👉 STOP HERE - You review test fixtures before I proceed

CHECKPOINT 6: CI Workflow (Spec URL Validation)
Goal: Create GitHub Actions workflow that validates Spec URLs

Tasks:

Create .github/workflows/twin-docs.yaml
Implement Spec URL extraction from PR description
Implement URL validation (must be from github.com)
Add blocking comments for invalid PRs
Testing:

# Manual test (cannot fully test without GitHub):
# 1. Create test PR without Spec URL → Should fail CI
# 2. Create test PR with non-GitHub URL → Should fail CI
# 3. Create test PR with valid GitHub URL → Should pass validation step

# Dry-run test:
# Extract URL validation logic into separate script
# Test script with sample PR descriptions
Deliverable:

Working CI workflow (at least the validation job)
Test results with sample PR descriptions
Error message examples
👉 STOP HERE - You review CI workflow before I proceed

CHECKPOINT 7: Agent System Prompt Update
Goal: Update Librarian Agent with Gatekeeper logic

Tasks:

Locate agent configuration file
Update system prompt with:
"Guardian of Consistency" identity
Gatekeeper validation logic
Tool mapping (parse_composition, upsert_twin_doc)
Iteration loop instructions
Remove direct access to commit_to_pr (security)
Testing:

# Verify YAML syntax
kubectl apply --dry-run=client -f platform/03-intelligence/compositions/kagents/librarian/librarian-agent.yaml

# Manual review of system prompt:
# - Check Gatekeeper logic is clear
# - Check tool mapping is correct
# - Check iteration loop is explained
# - Check security constraints (no direct commit_to_pr access)
Deliverable:

Updated agent configuration
System prompt review document
YAML validation results
👉 STOP HERE - You review agent prompt before I proceed

CHECKPOINT 8: End-to-End Integration Test
Goal: Test complete workflow from PR to Twin Doc creation

Tasks:

Create test PR with:
Modified test-webservice.yaml
Valid Spec URL in description
Aligned Spec and Code
Manually simulate agent workflow:
Fetch Spec URL
Parse composition
Generate Twin Doc
Validate Twin Doc
Commit to PR
Testing:

# Step-by-step manual test:
# 1. Parse composition
cat platform/03-intelligence/test-webservice.yaml | python3 artifacts/scripts/parse_composition.py > /tmp/parsed.json

# 2. Generate Twin Doc (manually or via agent)
# 3. Validate Twin Doc
python3 artifacts/scripts/validate_doc_schemas.py artifacts/specs/test-webservice.md
python3 artifacts/scripts/detect_prose.py artifacts/specs/test-webservice.md
python3 artifacts/scripts/validate_filenames.py artifacts/specs/test-webservice.md

# 4. Verify all validations pass
# 5. Verify Twin Doc content matches parsed JSON
Deliverable:

End-to-end test results
Twin Doc generated by workflow
Validation results
Issues/bugs discovered
👉 STOP HERE - You review integration test results before I proceed

CHECKPOINT 9: Qdrant Sync Workflow
Goal: Create workflow to index Twin Docs after merge

Tasks:

Create .github/workflows/sync-docs-to-qdrant.yaml
Implement sync logic (calls sync_to_qdrant MCP tool)
Add verification step
Testing:

# Manual test:
# 1. Merge test PR to main
# 2. Trigger sync workflow
# 3. Query Qdrant for indexed doc
# 4. Verify Twin Doc is searchable

# Dry-run test:
# Test sync logic locally with sample Twin Doc
Deliverable:

Working sync workflow
Test results showing indexing
Qdrant query results
👉 STOP HERE - You review sync workflow before I proceed

CHECKPOINT 10: Distillation Workflow (Phase 8)
Goal: Enable agent to extract runbooks from docs/

Tasks:

Extend CI workflow to detect docs/ changes
Update agent prompt with distillation mode
Test runbook extraction
Testing:

# Manual test:
# 1. Create free-form troubleshooting doc in docs/troubleshooting/
# 2. Create PR
# 3. Verify agent extracts structured runbook to artifacts/runbooks/
# 4. Verify original docs/ file unchanged
# 5. Verify duplicate detection works (similarity > 0.85)
Deliverable:

Extended CI workflow
Updated agent prompt
Test runbook examples
Duplicate detection results
👉 STOP HERE - You review distillation workflow before completion

Summary of Checkpoints
| Checkpoint | Focus | Key Test | Stop for Review | |:-----------|:------|:---------|:----------------| | 0 | Pre-verification | List existing files | ✅ | | 1 | Validation scripts | Run against test fixtures | ✅ | | 2 | parse_composition helper | YAML → JSON conversion | ✅ | | 3 | parse_composition MCP | MCP tool integration | ✅ | | 4 | upsert_twin_doc | Atomic operation guarantees | ✅ | | 5 | Test fixtures | PR template + test composition | ✅ | | 6 | CI workflow | Spec URL validation | ✅ | | 7 | Agent prompt | Gatekeeper logic | ✅ | | 8 | Integration test | End-to-end workflow | ✅ | | 9 | Qdrant sync | Indexing after merge | ✅ | | 10 | Distillation | Runbook extraction | ✅ |

Your Decision
Option 1: Start with Checkpoint 0 (Pre-verification) - I'll scan the codebase and report what exists

Option 2: You want to modify the checkpoint plan first

Option 3: You want to focus on specific phases only (e.g., skip Phase 8 distillation for now)

Which option would you like to proceed with?