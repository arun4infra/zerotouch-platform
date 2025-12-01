# Design Document: Twin Docs Workflow v2

## Overview

The Twin Docs Workflow v2 implements a two-agent architecture (Validator + Documentor) that runs in GitHub Actions to automatically validate specification alignment and generate/update MDX documentation. The system uses official MCP servers (GitHub + Qdrant Cloud) with OpenAI's gpt-4-mini model, connected via a custom bridge layer.

**Key Design Principles:**
- **Separation of Concerns**: Validator (fast gate) vs Documentor (doc generator)
- **Official MCP Servers**: Use standardized tools from ModelContextProtocol ecosystem
- **Cloud-Native**: Qdrant Cloud (no cluster exposure), GitHub Actions (no cluster resources)
- **Autonomous Agents**: LLM-driven tool calling with MCP integration
- **Version-Controlled Intelligence**: Agent prompts stored in Git

---

## Architecture

### High-Level Flow

```
PR Created/Updated
       ↓
┌──────────────────────────────────────┐
│  GitHub Actions: librarian.yml       │
│                                      │
│  Job 1: Validate                     │
│  ├─ Checkout code                    │
│  ├─ Run Validator Agent              │
│  │  ├─ Start GitHub MCP Server      │
│  │  ├─ Connect MCP Bridge           │
│  │  ├─ Load system prompt           │
│  │  ├─ Run agent loop (OpenAI)      │
│  │  └─ Post gatekeeper comment      │
│  └─ Exit (0=pass, 1=block)          │
│                                      │
│  Job 2: Document (if validate pass) │
│  ├─ Checkout PR branch              │
│  ├─ Run Documentor Agent            │
│  │  ├─ Start GitHub MCP Server      │
│  │  ├─ Start Qdrant MCP Server      │
│  │  ├─ Connect MCP Bridge           │
│  │  ├─ Load system prompt           │
│  │  ├─ Run agent loop (OpenAI)      │
│  │  ├─ Generate/update MDX docs     │
│  │  ├─ Validate MDX                 │
│  │  ├─ Update docs.json             │
│  │  └─ Commit to PR branch          │
│  └─ Post summary comment            │
└──────────────────────────────────────┘
       ↓
PR Ready for Review
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions Runner                     │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           Validator Agent Container                     │ │
│  │                                                         │ │
│  │  ┌──────────────┐      ┌─────────────────────────┐   │ │
│  │  │ Agent Script │◄────►│   MCP Bridge Layer      │   │ │
│  │  │ validator.py │      │   mcp_bridge.py         │   │ │
│  │  └──────────────┘      └─────────────────────────┘   │ │
│  │         ▲                        ▲                     │ │
│  │         │                        │                     │ │
│  │         ▼                        ▼                     │ │
│  │  ┌──────────────┐      ┌─────────────────────────┐   │ │
│  │  │ OpenAI SDK   │      │  MCP Python SDK         │   │ │
│  │  │ gpt-4-mini   │      │  (Client)               │   │ │
│  │  └──────────────┘      └─────────────────────────┘   │ │
│  │                                  │                     │ │
│  │                                  ▼                     │ │
│  │                        ┌─────────────────────────┐   │ │
│  │                        │  GitHub MCP Server      │   │ │
│  │                        │  (stdio process)        │   │ │
│  │                        └─────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │          Documentor Agent Container                     │ │
│  │                                                         │ │
│  │  ┌──────────────┐      ┌─────────────────────────┐   │ │
│  │  │ Agent Script │◄────►│   MCP Bridge Layer      │   │ │
│  │  │documentor.py │      │   mcp_bridge.py         │   │ │
│  │  └──────────────┘      └─────────────────────────┘   │ │
│  │         ▲                        ▲                     │ │
│  │         │                        │                     │ │
│  │         ▼                        ▼                     │ │
│  │  ┌──────────────┐      ┌─────────────────────────┐   │ │
│  │  │ OpenAI SDK   │      │  MCP Python SDK         │   │ │
│  │  │ gpt-4-mini   │      │  (Client)               │   │ │
│  │  └──────────────┘      └─────────────────────────┘   │ │
│  │                                  │                     │ │
│  │                                  ▼                     │ │
│  │                        ┌─────────────────────────┐   │ │
│  │                        │  GitHub MCP Server      │   │ │
│  │                        │  (stdio process)        │   │ │
│  │                        └─────────────────────────┘   │ │
│  │                                  │                     │ │
│  │                                  ▼                     │ │
│  │                        ┌─────────────────────────┐   │ │
│  │                        │  Qdrant MCP Server      │   │ │
│  │                        │  (stdio/SSE process)    │   │ │
│  │                        └─────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────────┐
                    │   External Services  │
                    │                      │
                    │  • GitHub API        │
                    │  • Qdrant Cloud      │
                    │  • OpenAI API        │
                    └──────────────────────┘
```

---

## Components and Interfaces

### 1. MCP Bridge Layer (Core Infrastructure)

**File:** `platform/03-intelligence/agents/shared/mcp_bridge.py`

**Purpose:** Core infrastructure component that translates between OpenAI function calling and MCP tool execution. This is a reusable, generic bridge that can be used by any agent in the future.

**Critical Component:** This bridge is the foundation for all agent-MCP integration. It requires rigorous unit testing and must be stable before any agent implementation begins.

**Interface:**
```python
class MCPOpenAIBridge:
    def __init__(self, mcp_clients: Dict[str, MCPClient], openai_api_key: str, model: str = "gpt-4-mini"):
        """
        Initialize bridge with MCP clients.
        
        Args:
            mcp_clients: Dict mapping server names to MCP client instances
            openai_api_key: OpenAI API key
            model: OpenAI model to use
        """
        
    def get_openai_functions(self) -> List[Dict[str, Any]]:
        """
        Convert all MCP tools to OpenAI function definitions.
        
        Returns:
            List of OpenAI function definition dicts
        """
        
    def execute_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Any:
        """
        Execute MCP tool and return result.
        
        Args:
            tool_name: Name of tool to execute
            arguments: Tool arguments
            
        Returns:
            Tool execution result
        """
        
    def run_agent_loop(
        self, 
        system_prompt: str, 
        user_message: str, 
        max_iterations: int = 10
    ) -> str:
        """
        Run agent loop with tool calling.
        
        Args:
            system_prompt: System prompt for agent
            user_message: Initial user message
            max_iterations: Max tool calling iterations
            
        Returns:
            Final agent response
        """
```

**Key Logic:**

1. **Schema Conversion (CRITICAL)**: MCP `inputSchema` (JSON Schema) → OpenAI `parameters`
   
   **MCP Format:**
   ```json
   {
     "name": "github_get_file_contents",
     "description": "Get file contents from GitHub",
     "inputSchema": {
       "type": "object",
       "properties": {
         "owner": {"type": "string"},
         "repo": {"type": "string"},
         "path": {"type": "string"}
       },
       "required": ["owner", "repo", "path"]
     }
   }
   ```
   
   **OpenAI Format:**
   ```json
   {
     "type": "function",
     "function": {
       "name": "github_get_file_contents",
       "description": "Get file contents from GitHub",
       "parameters": {
         "type": "object",
         "properties": {
           "owner": {"type": "string"},
           "repo": {"type": "string"},
           "path": {"type": "string"}
         },
         "required": ["owner", "repo", "path"]
       }
     }
   }
   ```
   
   **Transformation Rules:**
   - Wrap in `{"type": "function", "function": {...}}`
   - Rename `inputSchema` → `parameters`
   - Strip unsupported JSON Schema keywords (e.g., `$schema`, `$id`, `additionalProperties` if OpenAI rejects)
   - Preserve `type`, `properties`, `required`, `description`
   - Handle nested objects and arrays correctly

2. **Tool Routing**: Route tool calls to correct MCP server based on tool name prefix
   - `github_*` → GitHub MCP client
   - `qdrant_*` → Qdrant MCP client

3. **Agent Loop**: Implement iterative LLM → tool call → execution → result → LLM cycle
   - Max iterations to prevent infinite loops
   - Accumulate conversation history
   - Handle `finish_reason` correctly

4. **Error Handling**: Graceful handling of MCP server errors, tool execution failures
   - Retry logic for transient errors
   - Clear error messages back to LLM
   - Fail gracefully if max retries exceeded

### 2. Validator Agent

**File:** `.github/actions/validator/validator.py`

**Purpose:** Fast gate validation of Spec vs Code alignment

**Interface:**
```python
def main():
    """Main entry point for Validator Agent."""
    # 1. Parse inputs (PR number, GitHub token, OpenAI key)
    # 2. Start GitHub MCP server
    # 3. Initialize MCP bridge
    # 4. Check for @librarian override comment (via GitHub MCP tool)
    # 5. If override found, post acknowledgment and exit(0)
    # 6. Load system prompt from repo
    # 7. Fetch PR diff and spec (via GitHub MCP tools)
    # 8. Run agent loop (OpenAI + MCP bridge)
    # 9. Post gatekeeper comment if mismatch
    # 10. Exit with appropriate code (0=pass, 1=block)
```

**Note:** Override check happens AFTER MCP server starts so we can use `github_list_issue_comments` MCP tool instead of duplicating GitHub API logic.

**Key Components:**
- `platform/03-intelligence/agents/shared/contract_extractor.py`: Extract Contract Boundary (generic, reusable)
- `.github/actions/validator/override_checker.py`: Check for override comments (validator-specific)
- System prompt: `platform/03-intelligence/agents/validator/prompt.md`

**MCP Tools Used:**
- `github_get_file_contents`: Fetch spec, code files
- `github_get_pull_request`: Get PR metadata
- `github_create_issue_comment`: Post gatekeeper comment
- `github_list_commits`: Get changed files

### 3. Documentor Agent

**File:** `.github/actions/documentor/documentor.py`

**Purpose:** Generate/update MDX Twin Docs with validation

**Interface:**
```python
def main():
    """Main entry point for Documentor Agent."""
    # 1. Parse inputs (PR number, GitHub token, Qdrant credentials)
    # 2. Start GitHub MCP server
    # 3. Start Qdrant MCP server
    # 4. Initialize MCP bridge
    # 5. Load system prompt from repo
    # 6. Identify changed compositions
    # 7. Run agent loop
    # 8. Validate generated MDX
    # 9. Update docs.json
    # 10. Commit to PR branch
    # 11. Post summary comment
```

**Key Components:**
- `platform/03-intelligence/agents/shared/mdx_validator.py`: Validate MDX syntax (generic, reusable)
- `.github/actions/documentor/template_engine.py`: Load and fill MDX templates (documentor-specific)
- `.github/actions/documentor/docs_json_manager.py`: Update navigation manifest (documentor-specific)
- System prompt: `platform/03-intelligence/agents/documentor/prompt.md`

**MCP Tools Used:**
- `qdrant_find`: Search for similar documentation
- `qdrant_store`: Index new documentation (post-merge)
- `github_get_file_contents`: Fetch templates, existing docs, code
- `github_create_or_update_file`: Create/update Twin Docs
- `github_push_files`: Batch commit multiple files
- `github_create_issue_comment`: Post summary comment

### 4. MCP Server Configurations

#### GitHub MCP Server

**Installation:**
```dockerfile
# In Dockerfile
RUN apt-get update && apt-get install -y nodejs npm
RUN npm install -g @modelcontextprotocol/server-github
```

**Startup:**
```python
# In agent script
import subprocess
github_mcp_process = subprocess.Popen(
    ["npx", "-y", "@modelcontextprotocol/server-github"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env={
        "GITHUB_PERSONAL_ACCESS_TOKEN": os.environ["GITHUB_TOKEN"]
    }
)

# Connect MCP client
from mcp import Client as MCPClient
github_client = MCPClient(transport="stdio", process=github_mcp_process)
```

**Available Tools:**
- `github_get_file_contents(owner, repo, path, ref)`
- `github_create_or_update_file(owner, repo, path, content, message, branch, sha?)`
- `github_push_files(owner, repo, branch, files[], message)`
- `github_create_issue_comment(owner, repo, issue_number, body)`
- `github_get_pull_request(owner, repo, pull_number)`
- `github_list_commits(owner, repo, sha?, path?)`
- `github_search_code(q, sort?, order?)`

#### Qdrant Cloud MCP Server

**Installation:**
```dockerfile
# In Dockerfile
RUN pip install mcp-server-qdrant
```

**Startup:**
```python
# In agent script
import subprocess
qdrant_mcp_process = subprocess.Popen(
    ["python", "-m", "mcp_server_qdrant"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env={
        "QDRANT_URL": os.environ["QDRANT_URL"],
        "QDRANT_API_KEY": os.environ["QDRANT_API_KEY"],
        "COLLECTION_NAME": "documentation",
        "EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2"
    }
)

# Connect MCP client
qdrant_client = MCPClient(transport="stdio", process=qdrant_mcp_process)
```

**Available Tools:**
- `qdrant_store(information, metadata?, collection_name?)`
- `qdrant_find(query, collection_name?)`

---

## Data Models

### 1. Agent Configuration

```python
@dataclass
class AgentConfig:
    """Configuration for agent execution."""
    pr_number: int
    github_token: str
    openai_api_key: str
    repo_owner: str
    repo_name: str
    system_prompt_path: str
    max_iterations: int = 10
    
@dataclass
class ValidatorConfig(AgentConfig):
    """Validator-specific configuration."""
    pass
    
@dataclass
class DocumentorConfig(AgentConfig):
    """Documentor-specific configuration."""
    qdrant_url: str
    qdrant_api_key: str
    collection_name: str = "documentation"
```

### 2. Contract Boundary

```python
@dataclass
class ContractBoundary:
    """Extracted contract boundary from code file."""
    file_path: str
    file_type: str  # yaml, python, rego, markdown
    parameters: List[Parameter]
    schemas: List[Schema]
    functions: List[Function]
    metadata: Dict[str, Any]
    
@dataclass
class Parameter:
    """Parameter in contract boundary."""
    name: str
    type: str
    required: bool
    default: Optional[Any]
    description: Optional[str]
```

### 3. MDX Document

```python
@dataclass
class MDXDocument:
    """MDX document structure."""
    frontmatter: Dict[str, Any]
    content: str
    components: List[MDXComponent]
    
@dataclass
class MDXComponent:
    """MDX component (ParamField, Step, etc)."""
    type: str  # ParamField, Step, CodeGroup, etc
    attributes: Dict[str, str]
    content: str
    line_number: int
```

### 4. Validation Result

```python
@dataclass
class ValidationResult:
    """Result of spec vs code validation."""
    aligned: bool
    mismatches: List[Mismatch]
    interpreted_intent: Dict[str, Any]
    spec_source: str  # URL or "inline"
    
@dataclass
class Mismatch:
    """Specific mismatch between spec and code."""
    parameter_name: str
    expected: Any  # From spec
    actual: Any  # From code
    severity: str  # error, warning
    message: str
```

---

## Error Handling

### 1. MCP Server Errors

**Scenario:** MCP server fails to start or crashes

**Handling:**
```python
try:
    mcp_client = MCPClient(transport="stdio", process=mcp_process)
    tools = mcp_client.list_tools()
except Exception as e:
    logger.error(f"Failed to connect to MCP server: {e}")
    # Post error comment to PR
    # Exit with failure code
    sys.exit(1)
```

### 2. OpenAI API Errors

**Scenario:** OpenAI API rate limit, timeout, or error

**Handling:**
```python
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=4, max=10)
)
def call_openai(messages, functions):
    return client.chat.completions.create(
        model="gpt-4-mini",
        messages=messages,
        functions=functions
    )
```

### 3. MDX Validation Errors

**Scenario:** Generated MDX has syntax errors

**Handling:**
```python
max_retries = 3
for attempt in range(max_retries):
    mdx_content = agent_loop(...)
    validation_result = validate_mdx(mdx_content)
    
    if validation_result.valid:
        break
    else:
        # Feed error back to agent
        error_message = f"MDX validation failed: {validation_result.errors}"
        # Agent will fix and retry
        
if not validation_result.valid:
    # Post error comment
    # Exit without committing
    sys.exit(1)
```

### 4. GitHub API Errors

**Scenario:** File commit fails, merge conflict on docs.json

**Handling:**
```python
max_retries = 3
for attempt in range(max_retries):
    try:
        # Commit via GitHub MCP tool
        result = mcp_bridge.execute_tool(
            "github_create_or_update_file",
            {
                "owner": owner,
                "repo": repo,
                "path": file_path,
                "content": content,
                "message": commit_message,
                "branch": pr_branch
            }
        )
        break
    except ConflictError:
        # Rebase and retry
        fetch_latest_from_main()
        merge_changes()
        
if attempt == max_retries - 1:
    # Post error comment
    sys.exit(1)
```

---

## Testing Strategy

### 1. Unit Tests

**MCP Bridge Layer (CRITICAL - Must Pass Before Agent Development):**
```python
# platform/03-intelligence/agents/shared/tests/test_mcp_bridge.py
def test_schema_conversion_simple():
    """Test basic MCP schema → OpenAI function conversion."""
    
def test_schema_conversion_complex():
    """Test complex nested schemas with arrays and objects."""
    
def test_schema_conversion_optional_params():
    """Test handling of optional vs required parameters."""
    
def test_tool_routing_github():
    """Test routing GitHub tool calls to correct MCP server."""
    
def test_tool_routing_qdrant():
    """Test routing Qdrant tool calls to correct MCP server."""
    
def test_tool_routing_unknown():
    """Test error handling for unknown tool names."""
    
def test_agent_loop_single_iteration():
    """Test agent loop with single tool call."""
    
def test_agent_loop_multiple_iterations():
    """Test agent loop with multiple tool calls."""
    
def test_agent_loop_max_iterations():
    """Test agent loop respects max iteration limit."""
    
def test_agent_loop_error_handling():
    """Test agent loop handles MCP errors gracefully."""
    
def test_mcp_server_connection_failure():
    """Test handling of MCP server connection failures."""
    
def test_openai_api_error_retry():
    """Test retry logic for OpenAI API errors."""

# Target: 100% code coverage on mcp_bridge.py
```

**Contract Extractor (Generic Core Logic):**
```python
# platform/03-intelligence/agents/shared/tests/test_contract_extractor.py
def test_extract_yaml_parameters():
    """Test extracting parameters from YAML."""
    
def test_extract_python_signatures():
    """Test extracting function signatures from Python."""
    
def test_extract_rego_rules():
    """Test extracting rules from Rego policy files."""
    
def test_extract_markdown_sections():
    """Test extracting sections from Markdown runbooks."""
```

**MDX Validator (Generic Core Logic):**
```python
# platform/03-intelligence/agents/shared/tests/test_mdx_validator.py
def test_validate_param_field():
    """Test ParamField validation."""
    
def test_validate_unclosed_tags():
    """Test detection of unclosed tags."""
    
def test_validate_steps_component():
    """Test Steps component validation."""
    
def test_validate_frontmatter():
    """Test frontmatter validation."""
```

### 2. Integration Tests

**Validator Agent:**
```python
# tests/integration/test_validator.py
def test_validator_with_real_mcp():
    """Test Validator with real GitHub MCP server."""
    # Use test repository
    # Create test PR
    # Run validator
    # Verify comment posted
```

**Documentor Agent:**
```python
# tests/integration/test_documentor.py
def test_documentor_end_to_end():
    """Test Documentor with real MCP servers."""
    # Use test repository
    # Use test Qdrant collection
    # Create test PR
    # Run documentor
    # Verify MDX committed
    # Verify docs.json updated
```

### 3. End-to-End Tests

**Full Workflow:**
```python
# tests/e2e/test_workflow.py
def test_full_workflow():
    """Test complete workflow: Validator → Documentor."""
    # Create test PR with spec
    # Trigger workflow
    # Verify validation passes
    # Verify docs generated
    # Verify docs indexed to Qdrant
```

---

## Deployment

### File Structure

**Core Infrastructure (Reusable):**
```
platform/03-intelligence/agents/
├── shared/                          # Generic, reusable components
│   ├── mcp_bridge.py               # OpenAI-MCP bridge (CRITICAL)
│   ├── contract_extractor.py       # Contract boundary extraction
│   ├── mdx_validator.py            # MDX validation logic
│   ├── tests/
│   │   ├── test_mcp_bridge.py      # 100% coverage required
│   │   ├── test_contract_extractor.py
│   │   └── test_mdx_validator.py
│   └── __init__.py
│
├── validator/
│   ├── prompt.md                   # Validator system prompt
│   └── guides/                     # Reference guides
│       ├── contract-boundary.md
│       └── interpreted-intent.md
│
└── documentor/
    ├── prompt.md                   # Documentor system prompt
    └── guides/                     # Reference guides
        ├── diataxis-framework.md
        └── mdx-components.md
```

**Agent Implementations (Specific):**
```
.github/actions/
├── validator/
│   ├── Dockerfile
│   ├── action.yml
│   ├── validator.py                # Main agent script
│   ├── override_checker.py         # Validator-specific logic
│   └── requirements.txt
│
└── documentor/
    ├── Dockerfile
    ├── action.yml
    ├── documentor.py               # Main agent script
    ├── template_engine.py          # Documentor-specific logic
    ├── docs_json_manager.py        # Documentor-specific logic
    └── requirements.txt
```

**Note:** Agent implementations in `.github/actions/` will copy and use the core infrastructure from `platform/03-intelligence/agents/shared/` during Docker build.

### 1. GitHub Actions Workflow

**File:** `.github/workflows/librarian.yml`

```yaml
name: Librarian Pipeline

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - 'platform/**'
      - 'docs/**'
  issue_comment:
    types: [created]

env:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  GITHUB_TOKEN: ${{ secrets.GITHUB_BOT_TOKEN }}
  QDRANT_URL: ${{ secrets.QDRANT_URL }}
  QDRANT_API_KEY: ${{ secrets.QDRANT_API_KEY }}

jobs:
  validate:
    name: Validate Spec Alignment
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' || (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@librarian'))
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Run Validator
        uses: ./.github/actions/validator
        with:
          pr_number: ${{ github.event.pull_request.number || github.event.issue.number }}
          github_token: ${{ secrets.GITHUB_BOT_TOKEN }}
          openai_api_key: ${{ secrets.OPENAI_API_KEY }}

  document:
    name: Generate Twin Docs
    needs: validate
    runs-on: ubuntu-latest
    if: success()
    
    steps:
      - name: Checkout PR branch
        uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}
          token: ${{ secrets.GITHUB_BOT_TOKEN }}
      
      - name: Run Documentor
        uses: ./.github/actions/documentor
        with:
          pr_number: ${{ github.event.pull_request.number }}
          github_token: ${{ secrets.GITHUB_BOT_TOKEN }}
          openai_api_key: ${{ secrets.OPENAI_API_KEY }}
          qdrant_url: ${{ secrets.QDRANT_URL }}
          qdrant_api_key: ${{ secrets.QDRANT_API_KEY }}
```

### 2. Dockerfile Pattern

**Validator Agent:**
```dockerfile
FROM python:3.11-slim

# Install Node.js for GitHub MCP server
RUN apt-get update && apt-get install -y nodejs npm git
RUN npm install -g @modelcontextprotocol/server-github

# Install Python dependencies
COPY .github/actions/validator/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy core infrastructure from platform/03-intelligence/agents/shared/
# NOTE: Docker build must be run from repo root with context set to root
# Build command: docker build -f .github/actions/validator/Dockerfile .
COPY platform/03-intelligence/agents/shared/ /app/shared/

# Copy agent-specific code
COPY .github/actions/validator/ /app/validator/

WORKDIR /app
ENTRYPOINT ["python", "validator/validator.py"]
```

**Build Context Note:** The Dockerfile must be built from the repository root to access `platform/` directory. The GitHub Action will use:
```yaml
- name: Build Validator
  run: docker build -f .github/actions/validator/Dockerfile -t validator:latest .
```

**Documentor Agent:**
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

# Copy core infrastructure from platform/03-intelligence/agents/shared/
# NOTE: Docker build must be run from repo root with context set to root
# Build command: docker build -f .github/actions/documentor/Dockerfile .
COPY platform/03-intelligence/agents/shared/ /app/shared/

# Copy agent-specific code
COPY .github/actions/documentor/ /app/documentor/

WORKDIR /app
ENTRYPOINT ["python", "documentor/documentor.py"]
```

**Build Context Note:** The Dockerfile must be built from the repository root to access `platform/` directory. The GitHub Action will use:
```yaml
- name: Build Documentor
  run: docker build -f .github/actions/documentor/Dockerfile -t documentor:latest .
```

### 3. GitHub Secrets Configuration

Required secrets:
- `OPENAI_API_KEY`: OpenAI API key for gpt-4-mini
- `GITHUB_BOT_TOKEN`: GitHub PAT or App token (not default GITHUB_TOKEN)
- `QDRANT_URL`: Qdrant Cloud endpoint (e.g., `https://xyz.cloud.qdrant.io:6333`)
- `QDRANT_API_KEY`: Qdrant Cloud API key

---

## Performance Considerations

### 1. Caching Strategy

**Python Dependencies:**
```yaml
- name: Cache Python dependencies
  uses: actions/cache@v3
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
```

**Node.js Dependencies:**
```yaml
- name: Cache npm dependencies
  uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
```

### 2. Parallel Execution

- Validator and Documentor run sequentially (Documentor only if Validator passes)
- Within each agent, MCP tool calls can be parallelized where independent
- Multiple file operations can be batched using `github_push_files`

### 3. Token Optimization

**Validator Agent:**
- Target: 2,000-5,000 tokens per PR
- Strategy: Only send Contract Boundary (not full file)
- Use gpt-4-mini for cost efficiency

**Documentor Agent:**
- Target: 5,000-10,000 tokens per PR
- Strategy: Use Qdrant search to find relevant examples (not full history)
- Batch multiple file operations

---

## Security Considerations

### 1. Token Management

- Use GitHub Bot Token (PAT or App) stored in secrets
- Never use default `GITHUB_TOKEN` (can't re-trigger workflows)
- Rotate tokens regularly
- Limit token scope to minimum required permissions

### 2. MCP Server Isolation

- MCP servers run in isolated Docker containers
- No network access except to external APIs
- Environment variables for credentials (not hardcoded)

### 3. Input Validation

- Validate PR description format before agent execution
- Sanitize file paths to prevent directory traversal
- Validate MDX content before committing

### 4. Audit Logging

- Log all override commands with author and timestamp
- Log all tool executions for debugging
- Export metrics to Prometheus for monitoring

---

## Monitoring and Observability

### 1. Metrics

**Prometheus Metrics:**
```python
from prometheus_client import Counter, Histogram

validator_duration = Histogram('validator_duration_seconds', 'Validator execution time')
validator_blocks = Counter('validator_blocks_total', 'Number of PRs blocked')
validator_passes = Counter('validator_passes_total', 'Number of PRs passed')

documentor_duration = Histogram('documentor_duration_seconds', 'Documentor execution time')
twin_doc_created = Counter('twin_doc_created_total', 'Twin Docs created')
twin_doc_updated = Counter('twin_doc_updated_total', 'Twin Docs updated')
mdx_validation_errors = Counter('mdx_validation_errors_total', 'MDX validation failures')
```

### 2. Logging

**Structured Logging:**
```python
import logging
import json

logger = logging.getLogger("validator")
logger.setLevel(logging.INFO)

# Log with context
logger.info(json.dumps({
    "event": "validation_started",
    "pr_number": pr_number,
    "repo": repo_name,
    "timestamp": datetime.utcnow().isoformat()
}))
```

### 3. Alerting

**Alert Rules:**
- Validator failure rate > 10%
- Documentor failure rate > 20%
- Average execution time > 5 minutes
- MDX validation error rate > 5%

---

## Migration Plan

### Phase 1: Core Infrastructure (Week 1) - CRITICAL FOUNDATION
1. Create `platform/03-intelligence/agents/shared/` directory structure
2. **Implement MCP Bridge Layer** (`mcp_bridge.py`)
   - Schema conversion logic
   - Tool routing logic
   - Agent loop implementation
3. **Write comprehensive unit tests** (target: 100% coverage)
   - Test all edge cases
   - Test error handling
   - Test with mocked MCP servers
4. **Implement Contract Extractor** (`contract_extractor.py`)
   - YAML parameter extraction
   - Python signature extraction
   - Generic, reusable logic
5. **Implement MDX Validator** (`mdx_validator.py`)
   - Component validation
   - Frontmatter validation
   - Generic, reusable logic
6. Set up GitHub secrets
7. Create Qdrant Cloud instance

**Gate:** All core infrastructure tests must pass before proceeding to Phase 2

### Phase 2: Validator Agent (Week 2)
1. Create `.github/actions/validator/` directory structure
2. Implement Validator agent script (`validator.py`)
3. Implement override checker (validator-specific)
4. Create system prompt (`platform/03-intelligence/agents/validator/prompt.md`)
5. Create Dockerfile (copies core infrastructure)
6. Test with sample PRs

### Phase 3: Documentor Agent (Week 3)
1. Create `.github/actions/documentor/` directory structure
2. Implement Documentor agent script (`documentor.py`)
3. Implement template engine (documentor-specific)
4. Implement docs.json manager (documentor-specific)
5. Create system prompt (`platform/03-intelligence/agents/documentor/prompt.md`)
6. Create Dockerfile (copies core infrastructure)
7. Test with sample PRs

### Phase 4: Integration (Week 4)
1. Set up GitHub Actions workflow (`.github/workflows/librarian.yml`)
2. End-to-end testing
3. Documentation
4. Rollout to production

---

## Critical Implementation Notes

### 1. Docker Build Context

**Problem:** Dockerfiles in `.github/actions/validator/` and `.github/actions/documentor/` need to copy files from `platform/03-intelligence/agents/shared/`, but Docker build context is typically the subdirectory.

**Solution:** Build Docker images from repository root with explicit Dockerfile path:
```bash
docker build -f .github/actions/validator/Dockerfile -t validator:latest .
docker build -f .github/actions/documentor/Dockerfile -t documentor:latest .
```

**GitHub Actions Implementation:**
```yaml
- name: Build Validator
  run: docker build -f .github/actions/validator/Dockerfile -t validator:latest .
  working-directory: ${{ github.workspace }}
```

### 2. MCP-OpenAI Schema Transformation

**Complexity:** The MCP bridge must handle subtle differences between MCP's JSON Schema format and OpenAI's function calling format.

**Known Issues:**
- OpenAI may reject certain JSON Schema keywords (`$schema`, `$id`, `additionalProperties`)
- Nested objects and arrays require careful handling
- Optional vs required parameters must be preserved correctly

**Testing Strategy:**
- Test with real MCP server schemas (GitHub, Qdrant)
- Test with complex nested schemas
- Test with edge cases (empty schemas, optional-only parameters)
- Validate against OpenAI API before agent development begins

**Failure Mode:** If schema conversion is incorrect, the LLM will hallucinate tool arguments or fail to execute tools, causing agent failures.

### 3. Port Configuration for Local Preview

**Issue:** Port 3000 is commonly used (React dev servers, etc.)

**Solution:** Use port 4242 by default, allow override via environment variable:
```makefile
docs-preview:
	PORT=${PORT:-4242} mintlify dev --port $(PORT)
```

## Open Questions

1. **Qdrant Collection Setup**: Should we create collection automatically or require manual setup?
   - **Decision**: Auto-create if not exists (in Documentor agent)

2. **MDX Template Location**: Should templates be in `artifacts/templates/` or `.github/templates/`?
   - **Decision**: `artifacts/templates/` (version-controlled with docs)

3. **Override Audit**: Where should override events be logged?
   - **Decision**: GitHub issue comment + Prometheus metric

4. **System Prompt Updates**: How to handle prompt changes without rebuilding Docker images?
   - **Decision**: Load from repo at runtime (already in requirements)

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** Ready for Review  
**Next Step:** Create implementation tasks
