# Design Document: Core Infrastructure for Twin Docs Agents

## Overview

The core infrastructure provides reusable components for building agents using the OpenAI Agents SDK with native MCP support. This eliminates the need for custom bridge code and simplifies agent development.

**Key Components:**
- Agent Runner (thin wrapper around OpenAI Agents SDK)
- Contract Boundary Extractor (universal file analysis)
- MDX Validator (structured documentation validation)

**Location:** `platform/03-intelligence/agents/shared/`

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                  Core Infrastructure                         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           agent_runner.py                              │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  OpenAI Agents SDK (Native MCP Support)          │ │ │
│  │  │  - Agent class                                    │ │ │
│  │  │  - Runner class                                   │ │ │
│  │  │  - MCPServerStdio                                 │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │                                                        │ │
│  │  Helper Functions:                                    │ │
│  │  - create_agent_with_mcp()                           │ │
│  │  - load_prompt_from_file()                           │ │
│  │  - run_agent_task()                                  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           contract_extractor.py                        │ │
│  │  - extract_contract_boundary()                        │ │
│  │  - YAMLContractExtractor                             │ │
│  │  - PythonContractExtractor                           │ │
│  │  - RegoContractExtractor                             │ │
│  │  - MarkdownContractExtractor                         │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           mdx_validator.py                             │ │
│  │  - validate_mdx()                                     │ │
│  │  - validate_component()                               │ │
│  │  - validate_frontmatter()                             │ │
│  │  - validate_filename()                                │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Components and Interfaces

### 1. Agent Runner (`agent_runner.py`)

**Purpose:** Thin wrapper around OpenAI Agents SDK to simplify agent creation and execution

**Interface:**
```python
from typing import List, Dict, Any
from agents import Agent, Runner
from agents.mcp import MCPServerStdio

async def create_agent_with_mcp(
    name: str,
    instructions: str,
    mcp_servers: List[Dict[str, Any]],
    model: str = "gpt-4-mini"
) -> Agent:
    """
    Create an agent with MCP servers.
    
    Args:
        name: Agent name
        instructions: System prompt/instructions
        mcp_servers: List of MCP server configs
        model: OpenAI model to use
        
    Returns:
        Configured Agent instance
        
    Example:
        agent = await create_agent_with_mcp(
            name="Validator",
            instructions=load_prompt_from_file("..."),
            mcp_servers=[
                {
                    "name": "GitHub",
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-github"],
                    "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": token}
                }
            ]
        )
    """

def load_prompt_from_file(path: str) -> str:
    """
    Load system prompt from file.
    
    Args:
        path: Path to prompt file (relative to repo root)
        
    Returns:
        Prompt content as string
    """

async def run_agent_task(
    agent: Agent,
    task: str,
    max_iterations: int = 10
) -> str:
    """
    Run agent task with iteration limit.
    
    Args:
        agent: Configured Agent instance
        task: Task description
        max_iterations: Max tool calling iterations
        
    Returns:
        Agent response
    """
```

**Implementation Notes:**
- Uses OpenAI Agents SDK's native MCP support
- No custom schema transformation needed
- No custom tool routing needed
- SDK handles everything automatically

**Example Usage:**
```python
from shared.agent_runner import create_agent_with_mcp, load_prompt_from_file, run_agent_task

# Load prompt
instructions = load_prompt_from_file("platform/03-intelligence/agents/validator/prompt.md")

# Create agent with GitHub MCP server
agent = await create_agent_with_mcp(
    name="Validator",
    instructions=instructions,
    mcp_servers=[
        {
            "name": "GitHub",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"],
            "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": os.environ["GITHUB_TOKEN"]}
        }
    ]
)

# Run task
result = await run_agent_task(agent, f"Validate PR #{pr_number}")
```

---

### 2. Contract Boundary Extractor (`contract_extractor.py`)

**Purpose:** Extract public interface (Contract Boundary) from any file type

**Interface:**
```python
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
from enum import Enum

class FileType(Enum):
    YAML = "yaml"
    PYTHON = "python"
    REGO = "rego"
    MARKDOWN = "markdown"
    UNKNOWN = "unknown"

@dataclass
class Parameter:
    """Parameter in contract boundary."""
    name: str
    type: str
    required: bool
    default: Optional[Any]
    description: Optional[str]

@dataclass
class ContractBoundary:
    """Extracted contract boundary from code file."""
    file_path: str
    file_type: FileType
    parameters: List[Parameter]
    schemas: List[Dict[str, Any]]
    functions: List[Dict[str, Any]]
    metadata: Dict[str, Any]

def extract_contract_boundary(
    file_path: str,
    content: str
) -> ContractBoundary:
    """
    Extract contract boundary from file.
    
    Args:
        file_path: Path to file
        content: File content
        
    Returns:
        ContractBoundary with extracted data
    """

class YAMLContractExtractor:
    """Extract contract from YAML files (Crossplane, Kubernetes)."""
    
    def extract(self, content: str) -> ContractBoundary:
        """
        Extract schemas and parameters from YAML.
        
        Identifies:
        - spec.forProvider.* (parameters)
        - spec.compositeTypeRef (schemas)
        - metadata.* (metadata)
        
        Ignores:
        - status.* (implementation)
        - patches.* (implementation)
        """

class PythonContractExtractor:
    """Extract contract from Python files."""
    
    def extract(self, content: str) -> ContractBoundary:
        """
        Extract function signatures and API models.
        
        Identifies:
        - Function signatures (def, async def)
        - Class definitions (dataclass, Pydantic models)
        - Type hints
        
        Ignores:
        - Function bodies
        - Private methods (_method)
        """

class RegoContractExtractor:
    """Extract contract from Rego policy files."""
    
    def extract(self, content: str) -> ContractBoundary:
        """
        Extract rule definitions.
        
        Identifies:
        - Rule names
        - Input/output schemas
        
        Ignores:
        - Rule logic
        """

class MarkdownContractExtractor:
    """Extract contract from Markdown runbooks."""
    
    def extract(self, content: str) -> ContractBoundary:
        """
        Extract trigger and resolution steps.
        
        Identifies:
        - ## Symptoms
        - ## Diagnosis
        - ## Resolution
        
        Ignores:
        - Anecdotes
        - Background information
        """
```

**Implementation Strategy:**
- Use AST parsing for Python (ast module)
- Use YAML parsing for YAML (PyYAML)
- Use regex for Rego and Markdown
- Return structured data for LLM consumption

---

### 3. MDX Validator (`mdx_validator.py`)

**Purpose:** Validate MDX syntax and component structure

**Interface:**
```python
from dataclasses import dataclass
from typing import List, Optional
from enum import Enum

class ComponentType(Enum):
    PARAM_FIELD = "ParamField"
    STEPS = "Steps"
    STEP = "Step"
    CODE_GROUP = "CodeGroup"
    WARNING = "Warning"
    NOTE = "Note"
    TIP = "Tip"
    FRAME = "Frame"

@dataclass
class ValidationError:
    """MDX validation error."""
    line_number: int
    component: Optional[str]
    error_type: str
    message: str

@dataclass
class ValidationResult:
    """Result of MDX validation."""
    valid: bool
    errors: List[ValidationError]
    warnings: List[ValidationError]

def validate_mdx(content: str, file_path: str) -> ValidationResult:
    """
    Validate MDX content.
    
    Args:
        content: MDX content
        file_path: File path (for filename validation)
        
    Returns:
        ValidationResult with errors/warnings
    """

def validate_component(
    component_type: ComponentType,
    attributes: Dict[str, str],
    line_number: int
) -> List[ValidationError]:
    """
    Validate specific component.
    
    Args:
        component_type: Type of component
        attributes: Component attributes
        line_number: Line number in file
        
    Returns:
        List of validation errors
    """

def validate_frontmatter(frontmatter: Dict[str, Any]) -> List[ValidationError]:
    """
    Validate frontmatter fields.
    
    Required fields:
    - title
    - category (spec, runbook, adr)
    - description
    
    Optional fields:
    - tags
    - author
    - date
    """

def validate_filename(file_path: str) -> List[ValidationError]:
    """
    Validate filename rules.
    
    Rules:
    - kebab-case
    - max 3 words
    - no timestamps
    - .mdx extension
    """
```

**Validation Rules:**

**ParamField:**
- Required: `path`, `type`
- Optional: `required`, `default`, `description`

**Step:**
- Required: `title`
- Optional: `description`

**Steps:**
- Must contain at least one `<Step>` child

**Frontmatter:**
- Required: `title`, `category`, `description`
- Category must be: `spec`, `runbook`, or `adr`

**Filename:**
- Must be kebab-case: `my-service.mdx`
- Max 3 words: `my-web-service.mdx` ✅, `my-very-long-service-name.mdx` ❌
- No timestamps: `service-2024-01-01.mdx` ❌

---

## Data Models

### ContractBoundary
```python
@dataclass
class ContractBoundary:
    file_path: str
    file_type: FileType
    parameters: List[Parameter]
    schemas: List[Dict[str, Any]]
    functions: List[Dict[str, Any]]
    metadata: Dict[str, Any]
```

### Parameter
```python
@dataclass
class Parameter:
    name: str
    type: str
    required: bool
    default: Optional[Any]
    description: Optional[str]
```

### ValidationResult
```python
@dataclass
class ValidationResult:
    valid: bool
    errors: List[ValidationError]
    warnings: List[ValidationError]
```

---

## Testing Strategy

### Agent Runner Tests
```python
# tests/test_agent_runner.py

@pytest.mark.asyncio
async def test_create_agent_with_single_mcp_server():
    """Test creating agent with GitHub MCP server."""
    agent = await create_agent_with_mcp(
        name="Test",
        instructions="Test instructions",
        mcp_servers=[{
            "name": "GitHub",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"]
        }]
    )
    assert agent.name == "Test"

@pytest.mark.asyncio
async def test_create_agent_with_multiple_mcp_servers():
    """Test creating agent with GitHub + Qdrant MCP servers."""
    # Test with both servers

@pytest.mark.asyncio
async def test_load_prompt_from_file():
    """Test loading prompt from file."""
    prompt = load_prompt_from_file("test_prompt.md")
    assert len(prompt) > 0

@pytest.mark.asyncio
async def test_run_agent_task():
    """Test running agent task."""
    # Mock agent and test execution
```

### Contract Extractor Tests
```python
# tests/test_contract_extractor.py

def test_extract_yaml_parameters():
    """Test extracting parameters from YAML."""
    yaml_content = """
    apiVersion: v1
    kind: Service
    spec:
      forProvider:
        name: my-service
        port: 8080
    """
    result = extract_contract_boundary("test.yaml", yaml_content)
    assert len(result.parameters) == 2
    assert result.parameters[0].name == "name"

def test_extract_python_signatures():
    """Test extracting function signatures from Python."""
    python_content = """
    def my_function(param1: str, param2: int = 10) -> bool:
        return True
    """
    result = extract_contract_boundary("test.py", python_content)
    assert len(result.functions) == 1
    assert result.functions[0]["name"] == "my_function"
```

### MDX Validator Tests
```python
# tests/test_mdx_validator.py

def test_validate_param_field_missing_required():
    """Test ParamField validation with missing required attributes."""
    content = "<ParamField path='test'></ParamField>"
    result = validate_mdx(content, "test.mdx")
    assert not result.valid
    assert any("type" in e.message for e in result.errors)

def test_validate_unclosed_tags():
    """Test detection of unclosed tags."""
    content = "<ParamField path='test' type='string'>"
    result = validate_mdx(content, "test.mdx")
    assert not result.valid

def test_validate_filename_kebab_case():
    """Test filename validation."""
    errors = validate_filename("MyService.mdx")
    assert len(errors) > 0
    assert "kebab-case" in errors[0].message
```

---

## Deployment

### File Structure
```
platform/03-intelligence/agents/shared/
├── __init__.py
├── agent_runner.py
├── contract_extractor.py
├── mdx_validator.py
└── tests/
    ├── __init__.py
    ├── test_agent_runner.py
    ├── test_contract_extractor.py
    └── test_mdx_validator.py
```

### Dependencies
```txt
# requirements.txt
agents>=0.1.0          # OpenAI Agents SDK with native MCP support
pyyaml>=6.0.0          # YAML parsing
pydantic>=2.0.0        # Data validation
pytest>=7.0.0          # Testing
pytest-asyncio>=0.21.0 # Async testing
```

---

## Performance Considerations

### Agent Runner
- Prompt loading: < 100ms (cached after first load)
- MCP server startup: < 2s per server
- Agent initialization: < 1s

### Contract Extractor
- YAML parsing: < 50ms per file
- Python AST parsing: < 100ms per file
- Regex extraction: < 10ms per file

### MDX Validator
- Validation: < 100ms per document
- Component parsing: < 50ms per document

---

## Security Considerations

1. **Prompt Loading**
   - Only load from trusted paths (platform/03-intelligence/agents/)
   - Validate file paths to prevent directory traversal

2. **MCP Server Configuration**
   - Environment variables for credentials (not hardcoded)
   - Validate MCP server commands (whitelist)

3. **Contract Extraction**
   - Sanitize file paths
   - Limit file size (max 1MB)
   - Timeout for parsing (max 5s)

---

## Error Handling

### Agent Runner Errors
```python
class MCPServerError(Exception):
    """MCP server failed to start or connect."""

class PromptLoadError(Exception):
    """Failed to load prompt from file."""

class AgentExecutionError(Exception):
    """Agent execution failed."""
```

### Contract Extractor Errors
```python
class UnsupportedFileTypeError(Exception):
    """File type not supported for extraction."""

class ParseError(Exception):
    """Failed to parse file content."""
```

### MDX Validator Errors
```python
class MDXSyntaxError(Exception):
    """MDX syntax error."""

class ComponentValidationError(Exception):
    """Component validation failed."""
```

---

## Migration Notes

### From Custom Bridge to OpenAI Agents SDK

**Before (Custom Bridge):**
```python
from mcp import Client as MCPClient
from openai import OpenAI

# Manual MCP client setup
github_client = MCPClient(...)
tools = github_client.list_tools()

# Manual schema conversion
openai_functions = convert_mcp_to_openai(tools)

# Manual agent loop
response = openai_client.chat.completions.create(...)
```

**After (OpenAI Agents SDK):**
```python
from agents import Agent, Runner
from agents.mcp import MCPServerStdio

# Automatic MCP setup
async with MCPServerStdio(...) as server:
    agent = Agent(mcp_servers=[server])
    result = await Runner.run(agent, task)
```

**Benefits:**
- ✅ No custom bridge code
- ✅ No schema transformation
- ✅ No manual tool routing
- ✅ Simpler, more maintainable
- ✅ Official SDK support

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-02  
**Status:** Ready for Implementation  
**Key Change:** Using OpenAI Agents SDK with native MCP support (no custom bridge)
