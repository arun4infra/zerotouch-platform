# Design Document: Documentor Agent

## Overview

The Documentor Agent automatically creates and updates MDX Twin Docs for platform compositions. It uses OpenAI Agents SDK with GitHub and Qdrant MCP servers to generate structured documentation.

**Execution Time:** < 3 minutes per PR

**Location:** `.github/actions/documentor/`

---

## Architecture

### High-Level Flow

```
PR Event (Validator Passed)
       ↓
┌──────────────────────────────────────────────────────────┐
│  Documentor Agent Container                               │
│                                                           │
│  1. Parse Inputs                                         │
│     - PR number, GitHub token, OpenAI key                │
│     - Qdrant URL, Qdrant API key                         │
│                                                           │
│  2. Start MCP Servers                                    │
│     ├─ GitHub MCP Server (stdio)                         │
│     └─ Qdrant MCP Server (stdio)                         │
│                                                           │
│  3. Create Agent                                         │
│     - Load prompt from repo                              │
│     - Connect to MCP servers                             │
│                                                           │
│  4. Run Agent Loop                                       │
│     ├─ Identify changed compositions                     │
│     ├─ Search precedent (Qdrant)                         │
│     ├─ Extract contract boundary                         │
│     ├─ Generate/update MDX                               │
│     ├─ Validate MDX (max 3 retries)                      │
│     ├─ Update docs.json                                  │
│     └─ Commit to PR branch (GitHub)                      │
│                                                           │
│  5. Post Summary Comment                                 │
└──────────────────────────────────────────────────────────┘
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           Documentor Agent Container                         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  documentor.py (Main Script)                           │ │
│  │  ├─ parse_inputs()                                     │ │
│  │  ├─ start_mcp_servers()                                │ │
│  │  ├─ create_agent()                                     │ │
│  │  ├─ run_agent_loop()                                   │ │
│  │  └─ post_summary()                                     │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  template_engine.py (Documentor-Specific)              │ │
│  │  ├─ load_template()                                    │ │
│  │  ├─ fill_template()                                    │ │
│  │  └─ parse_existing_mdx()                               │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  docs_json_manager.py (Documentor-Specific)            │ │
│  │  ├─ read_docs_json()                                   │ │
│  │  ├─ update_docs_json()                                 │ │
│  │  ├─ find_navigation_group()                            │ │
│  │  └─ handle_merge_conflict()                            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Shared Libraries (from core infrastructure)           │ │
│  │  ├─ agent_runner.py                                    │ │
│  │  ├─ contract_extractor.py                              │ │
│  │  └─ mdx_validator.py                                   │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  OpenAI Agents SDK                                     │ │
│  │  ├─ Agent (with GitHub + Qdrant MCP)                   │ │
│  │  └─ Runner                                             │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────────┐
                    │   External Services  │
                    │  • GitHub API        │
                    │  • Qdrant Cloud      │
                    │  • OpenAI API        │
                    └──────────────────────┘
```

---

## Components and Interfaces

### 1. Main Script (`documentor.py`)

**Purpose:** Orchestrate documentation generation workflow

**Interface:**
```python
import os
import sys
from agents import Agent, Runner
from agents.mcp import MCPServerStdio
from shared.agent_runner import create_agent_with_mcp, load_prompt_from_file
from template_engine import load_template, fill_template
from docs_json_manager import update_docs_json

async def main():
    """Main entry point for Documentor Agent."""
    # 1. Parse inputs
    pr_number = int(os.environ["PR_NUMBER"])
    github_token = os.environ["GITHUB_TOKEN"]
    openai_key = os.environ["OPENAI_API_KEY"]
    qdrant_url = os.environ["QDRANT_URL"]
    qdrant_api_key = os.environ["QDRANT_API_KEY"]
    
    # 2. Start MCP servers
    async with MCPServerStdio(
        name="GitHub",
        params={
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"]
        },
        env={"GITHUB_PERSONAL_ACCESS_TOKEN": github_token}
    ) as github_server, \
    MCPServerStdio(
        name="Qdrant",
        params={
            "command": "python",
            "args": ["-m", "mcp_server_qdrant"]
        },
        env={
            "QDRANT_URL": qdrant_url,
            "QDRANT_API_KEY": qdrant_api_key,
            "COLLECTION_NAME": "documentation"
        }
    ) as qdrant_server:
        
        # 3. Create agent
        instructions = load_prompt_from_file(
            "platform/03-intelligence/agents/documentor/prompt.md"
        )
        
        agent = await create_agent_with_mcp(
            name="Documentor",
            instructions=instructions,
            mcp_servers=[github_server, qdrant_server]
        )
        
        # 4. Run agent loop
        task = f"""
        Generate Twin Docs for PR #{pr_number}:
        1. Identify changed compositions in platform/
        2. For each composition:
           - Search for similar docs in Qdrant
           - Extract contract boundary
           - Generate/update MDX Twin Doc
           - Validate MDX
           - Update docs.json
           - Commit to PR branch
        3. Post summary comment
        """
        
        result = await Runner.run(agent, task)
        
        # 5. Exit
        sys.exit(0)

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

---

### 2. Template Engine (`template_engine.py`)

**Purpose:** Load and fill MDX templates

**Interface:**
```python
from typing import Dict, Any, List
from dataclasses import dataclass

@dataclass
class MDXComponent:
    """MDX component structure."""
    type: str  # ParamField, Step, etc
    attributes: Dict[str, str]
    content: str
    line_number: int

def load_template(template_name: str) -> str:
    """
    Load MDX template from artifacts/templates/.
    
    Args:
        template_name: Template filename (e.g., "spec-template.mdx")
        
    Returns:
        Template content
    """

def fill_template(
    template: str,
    frontmatter: Dict[str, Any],
    parameters: List[Dict[str, Any]],
    overview: str = ""
) -> str:
    """
    Fill template with data.
    
    Args:
        template: Template content
        frontmatter: Frontmatter fields (title, category, etc)
        parameters: List of parameters to generate ParamField components
        overview: Optional overview section
        
    Returns:
        Filled MDX content
        
    Example:
        mdx = fill_template(
            template=load_template("spec-template.mdx"),
            frontmatter={
                "title": "My Service",
                "category": "spec",
                "description": "Service description"
            },
            parameters=[
                {"name": "port", "type": "integer", "required": True, "description": "Port number"},
                {"name": "host", "type": "string", "required": False, "default": "localhost"}
            ]
        )
    """

def parse_existing_mdx(content: str) -> Dict[str, Any]:
    """
    Parse existing MDX to extract components.
    
    Args:
        content: MDX content
        
    Returns:
        Dict with:
        - frontmatter: Dict[str, Any]
        - components: List[MDXComponent]
        - sections: Dict[str, str] (Overview, Purpose, etc)
    """

def update_param_fields(
    existing_mdx: str,
    new_parameters: List[Dict[str, Any]]
) -> str:
    """
    Update only changed ParamField components.
    
    Args:
        existing_mdx: Existing MDX content
        new_parameters: New parameters from contract boundary
        
    Returns:
        Updated MDX content (surgical update)
    """
```

**Implementation Notes:**
- Use regex to parse MDX components
- Preserve manual sections (Overview, Purpose, etc.)
- Only update changed ParamField components
- Generate proper MDX syntax with attributes

---

### 3. Docs.json Manager (`docs_json_manager.py`)

**Purpose:** Manage navigation manifest updates

**Interface:**
```python
from typing import Dict, Any, List
import json

def read_docs_json(github_mcp_tool) -> Dict[str, Any]:
    """
    Read current docs.json from main branch.
    
    Args:
        github_mcp_tool: GitHub MCP tool function
        
    Returns:
        Parsed docs.json content
    """

def update_docs_json(
    docs_json: Dict[str, Any],
    file_path: str,
    category: str
) -> Dict[str, Any]:
    """
    Update docs.json with new file entry.
    
    Args:
        docs_json: Current docs.json content
        file_path: Path to new MDX file (without .mdx extension)
        category: Category (spec, runbook, adr)
        
    Returns:
        Updated docs.json
        
    Example:
        updated = update_docs_json(
            docs_json=current_docs,
            file_path="artifacts/specs/my-service",
            category="spec"
        )
    """

def find_navigation_group(category: str) -> str:
    """
    Find appropriate navigation group for category.
    
    Args:
        category: Category (spec, runbook, adr)
        
    Returns:
        Navigation group name
        
    Mapping:
    - spec → Infrastructure
    - runbook → Runbooks
    - adr → Architecture Decisions
    """

def handle_merge_conflict(
    github_mcp_tool,
    pr_branch: str,
    max_retries: int = 3
) -> bool:
    """
    Handle docs.json merge conflict with rebase.
    
    Args:
        github_mcp_tool: GitHub MCP tool function
        pr_branch: PR branch name
        max_retries: Max retry attempts
        
    Returns:
        True if resolved, False if failed
        
    Strategy:
    1. Fetch latest from main
    2. Rebase PR branch
    3. Retry update
    4. Repeat max_retries times
    """

def format_docs_json(docs_json: Dict[str, Any]) -> str:
    """
    Format docs.json for git auto-merge.
    
    Args:
        docs_json: docs.json content
        
    Returns:
        Formatted JSON string (one entry per line)
        
    Example:
        {
          "groups": [
            {
              "group": "Infrastructure",
              "pages": [
                "artifacts/specs/service-1",
                "artifacts/specs/service-2"
              ]
            }
          ]
        }
    """
```

**Implementation Notes:**
- Read docs.json from main branch (not PR branch)
- Append new entry to appropriate group
- Format with one entry per line for git auto-merge
- Handle merge conflicts with rebase + retry

---

## Data Models

### MDX Document Structure
```python
@dataclass
class MDXDocument:
    """Complete MDX document."""
    frontmatter: Dict[str, Any]
    overview: str
    parameters: List[MDXComponent]
    sections: Dict[str, str]  # Custom sections
    
@dataclass
class MDXComponent:
    """MDX component (ParamField, Step, etc)."""
    type: str
    attributes: Dict[str, str]
    content: str
    line_number: int
```

### Docs.json Structure
```json
{
  "groups": [
    {
      "group": "Infrastructure",
      "pages": [
        "artifacts/specs/my-service",
        "artifacts/specs/another-service"
      ]
    },
    {
      "group": "Runbooks",
      "pages": [
        "artifacts/runbooks/troubleshooting-guide"
      ]
    }
  ]
}
```

---

## Agent System Prompt

**Location:** `platform/03-intelligence/agents/documentor/prompt.md`

**Key Instructions:**
```markdown
# Documentor Agent System Prompt

You are the Documentor Agent. Your role is to generate and update MDX Twin Docs for platform compositions.

## Your Capabilities

You have access to these MCP tools:

**GitHub Tools:**
- `github_get_file_contents`: Fetch files from repository
- `github_create_or_update_file`: Create/update files
- `github_push_files`: Batch commit multiple files
- `github_create_issue_comment`: Post comments

**Qdrant Tools:**
- `qdrant_find`: Search for similar documentation
- `qdrant_store`: Index new documentation

## Your Workflow

1. **Identify Changed Compositions**
   - Use `github_get_file_contents` to fetch PR diff
   - Identify changed files in `platform/`

2. **For Each Composition:**
   
   a. **Search Precedent**
      - Use `qdrant_find` to search for similar docs
      - Query: "similar to {resource_type}"
      - Review top 3 results for patterns
   
   b. **Extract Contract Boundary**
      - Fetch composition file
      - Identify parameters, schemas (Contract)
      - Ignore patches, transforms (Implementation)
   
   c. **Generate/Update MDX**
      - If new: Fetch template from `artifacts/templates/spec-template.mdx`
      - If existing: Fetch current Twin Doc
      - Generate ParamField components (not tables)
      - Preserve manual sections (Overview, Purpose)
      - Add auto-generated warning header
   
   d. **Validate MDX**
      - Check for unclosed tags
      - Verify ParamField has `path` and `type`
      - Verify frontmatter fields
      - If validation fails: Fix and retry (max 3 attempts)
   
   e. **Update docs.json**
      - Fetch current docs.json from main branch
      - Find appropriate navigation group
      - Append new page path (without .mdx extension)
      - Format with one entry per line
   
   f. **Commit to PR Branch**
      - Use `github_push_files` to commit both:
        - Twin Doc (artifacts/specs/...)
        - docs.json
      - Commit message: "docs: update Twin Doc for {resource}"

3. **Post Summary Comment**
   - Use `github_create_issue_comment`
   - List all generated/updated docs
   - Include links to files

## MDX Component Examples

**ParamField:**
```mdx
<ParamField path="spec.forProvider.port" type="integer" required>
  Port number for the service
</ParamField>
```

**Steps:**
```mdx
<Steps>
  <Step title="Check logs">
    Run `kubectl logs pod-name`
  </Step>
  <Step title="Restart service">
    Run `kubectl rollout restart deployment/service`
  </Step>
</Steps>
```

## Important Rules

- ALWAYS use structured components (ParamField, Steps), NEVER use Markdown tables
- ALWAYS preserve manual sections when updating
- ALWAYS validate MDX before committing
- ALWAYS update docs.json atomically with Twin Doc
- NEVER edit implementation details (patches, transforms)
- NEVER create orphaned files (always update docs.json)
```

---

## Error Handling

### MDX Validation Errors
```python
# In agent loop
for attempt in range(3):
    mdx_content = generate_mdx(...)
    validation_result = validate_mdx(mdx_content)
    
    if validation_result.valid:
        break
    else:
        # Feed error back to agent
        error_message = format_validation_errors(validation_result.errors)
        # Agent will fix and retry

if not validation_result.valid:
    post_error_comment(pr_number, validation_result.errors)
    sys.exit(1)  # PR remains valid, docs can be regenerated
```

### Docs.json Merge Conflicts
```python
max_retries = 3
for attempt in range(max_retries):
    try:
        update_docs_json_and_commit(...)
        break
    except MergeConflictError:
        # Rebase and retry
        rebase_pr_branch()
        
if attempt == max_retries - 1:
    post_error_comment(pr_number, "docs.json merge conflict")
    sys.exit(1)
```

---

## Testing Strategy

### Unit Tests
```python
# tests/test_template_engine.py
def test_fill_template():
    """Test filling template with parameters."""
    
def test_parse_existing_mdx():
    """Test parsing existing MDX."""
    
def test_update_param_fields():
    """Test surgical update of ParamField components."""

# tests/test_docs_json_manager.py
def test_update_docs_json():
    """Test adding new entry to docs.json."""
    
def test_find_navigation_group():
    """Test finding correct navigation group."""
    
def test_format_docs_json():
    """Test formatting for git auto-merge."""
```

### Integration Tests
```python
# tests/integration/test_documentor.py
@pytest.mark.asyncio
async def test_documentor_end_to_end():
    """Test complete Documentor workflow."""
    # Use test repository
    # Create test PR
    # Run Documentor
    # Verify MDX committed
    # Verify docs.json updated
```

---

## Deployment

### Dockerfile
```dockerfile
FROM python:3.11-slim

# Install Node.js for GitHub MCP server
RUN apt-get update && apt-get install -y nodejs npm git
RUN npm install -g @modelcontextprotocol/server-github

# Install Python dependencies
COPY .github/actions/documentor/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Install Qdrant MCP server
RUN pip install mcp-server-qdrant

# Copy core infrastructure
COPY platform/03-intelligence/agents/shared/ /app/shared/

# Copy agent code
COPY .github/actions/documentor/ /app/documentor/

WORKDIR /app
ENTRYPOINT ["python", "documentor/documentor.py"]
```

**Build Command:**
```bash
docker build -f .github/actions/documentor/Dockerfile -t documentor:latest .
```

### GitHub Action
```yaml
# .github/actions/documentor/action.yml
name: 'Documentor Agent'
description: 'Generate Twin Docs for platform compositions'

inputs:
  pr_number:
    description: 'PR number'
    required: true
  github_token:
    description: 'GitHub token'
    required: true
  openai_api_key:
    description: 'OpenAI API key'
    required: true
  qdrant_url:
    description: 'Qdrant Cloud URL'
    required: true
  qdrant_api_key:
    description: 'Qdrant Cloud API key'
    required: true

runs:
  using: 'docker'
  image: 'Dockerfile'
  env:
    PR_NUMBER: ${{ inputs.pr_number }}
    GITHUB_TOKEN: ${{ inputs.github_token }}
    OPENAI_API_KEY: ${{ inputs.openai_api_key }}
    QDRANT_URL: ${{ inputs.qdrant_url }}
    QDRANT_API_KEY: ${{ inputs.qdrant_api_key }}
```

---

## Performance Considerations

### Execution Time Breakdown
- MCP server startup: ~2s (GitHub + Qdrant)
- Agent initialization: ~1s
- Per composition:
  - Precedent search: ~2s
  - Contract extraction: ~1s
  - MDX generation: ~5s
  - Validation: ~1s
  - Commit: ~2s
- Total: ~15s per composition

**Target:** < 3 minutes for typical PR (5-10 compositions)

### Optimization Strategies
1. **Parallel Processing:** Process multiple compositions in parallel (future)
2. **Caching:** Cache templates, precedent search results
3. **Batch Commits:** Use `github_push_files` to commit multiple files at once

---

## Metrics

```python
from prometheus_client import Histogram, Counter

documentor_duration = Histogram(
    'documentor_duration_seconds',
    'Documentor execution time'
)

twin_doc_created = Counter(
    'twin_doc_created_total',
    'Twin Docs created'
)

twin_doc_updated = Counter(
    'twin_doc_updated_total',
    'Twin Docs updated'
)

mdx_validation_errors = Counter(
    'mdx_validation_errors_total',
    'MDX validation failures'
)

docs_json_conflicts = Counter(
    'docs_json_conflicts_total',
    'docs.json merge conflicts'
)
```

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-02  
**Status:** Ready for Implementation  
**Depends On:** Core Infrastructure Spec, Validator Spec
