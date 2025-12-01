# core-infrastructure-spec\design.md

```md
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

\`\`\`
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
\`\`\`

---

## Components and Interfaces

### 1. Agent Runner (`agent_runner.py`)

**Purpose:** Thin wrapper around OpenAI Agents SDK to simplify agent creation and execution

**Interface:**
\`\`\`python
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
\`\`\`

**Implementation Notes:**
- Uses OpenAI Agents SDK's native MCP support
- No custom schema transformation needed
- No custom tool routing needed
- SDK handles everything automatically

**Example Usage:**
\`\`\`python
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
\`\`\`

---

### 2. Contract Boundary Extractor (`contract_extractor.py`)

**Purpose:** Extract public interface (Contract Boundary) from any file type

**Interface:**
\`\`\`python
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
\`\`\`

**Implementation Strategy:**
- Use AST parsing for Python (ast module)
- Use YAML parsing for YAML (PyYAML)
- Use regex for Rego and Markdown
- Return structured data for LLM consumption

---

### 3. MDX Validator (`mdx_validator.py`)

**Purpose:** Validate MDX syntax and component structure

**Interface:**
\`\`\`python
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
\`\`\`

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
\`\`\`python
@dataclass
class ContractBoundary:
    file_path: str
    file_type: FileType
    parameters: List[Parameter]
    schemas: List[Dict[str, Any]]
    functions: List[Dict[str, Any]]
    metadata: Dict[str, Any]
\`\`\`

### Parameter
\`\`\`python
@dataclass
class Parameter:
    name: str
    type: str
    required: bool
    default: Optional[Any]
    description: Optional[str]
\`\`\`

### ValidationResult
\`\`\`python
@dataclass
class ValidationResult:
    valid: bool
    errors: List[ValidationError]
    warnings: List[ValidationError]
\`\`\`

---

## Testing Strategy

### Agent Runner Tests
\`\`\`python
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
\`\`\`

### Contract Extractor Tests
\`\`\`python
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
\`\`\`

### MDX Validator Tests
\`\`\`python
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
\`\`\`

---

## Deployment

### File Structure
\`\`\`
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
\`\`\`

### Dependencies
\`\`\`txt
# requirements.txt
agents>=0.1.0          # OpenAI Agents SDK with native MCP support
pyyaml>=6.0.0          # YAML parsing
pydantic>=2.0.0        # Data validation
pytest>=7.0.0          # Testing
pytest-asyncio>=0.21.0 # Async testing
\`\`\`

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
\`\`\`python
class MCPServerError(Exception):
    """MCP server failed to start or connect."""

class PromptLoadError(Exception):
    """Failed to load prompt from file."""

class AgentExecutionError(Exception):
    """Agent execution failed."""
\`\`\`

### Contract Extractor Errors
\`\`\`python
class UnsupportedFileTypeError(Exception):
    """File type not supported for extraction."""

class ParseError(Exception):
    """Failed to parse file content."""
\`\`\`

### MDX Validator Errors
\`\`\`python
class MDXSyntaxError(Exception):
    """MDX syntax error."""

class ComponentValidationError(Exception):
    """Component validation failed."""
\`\`\`

---

## Migration Notes

### From Custom Bridge to OpenAI Agents SDK

**Before (Custom Bridge):**
\`\`\`python
from mcp import Client as MCPClient
from openai import OpenAI

# Manual MCP client setup
github_client = MCPClient(...)
tools = github_client.list_tools()

# Manual schema conversion
openai_functions = convert_mcp_to_openai(tools)

# Manual agent loop
response = openai_client.chat.completions.create(...)
\`\`\`

**After (OpenAI Agents SDK):**
\`\`\`python
from agents import Agent, Runner
from agents.mcp import MCPServerStdio

# Automatic MCP setup
async with MCPServerStdio(...) as server:
    agent = Agent(mcp_servers=[server])
    result = await Runner.run(agent, task)
\`\`\`

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

```

# core-infrastructure-spec\requirements.md

```md
# Requirements Document: Core Infrastructure for Twin Docs Agents

## Introduction

This document defines requirements for the core infrastructure components that enable the Twin Docs workflow agents. These are reusable, generic components that can be used by any agent in the future.

**Scope:** MCP Bridge Layer, Shared Libraries, MCP Server Configuration

**Location:** `platform/03-intelligence/agents/shared/`

---

## Glossary

- **MCP Bridge**: Translation layer between OpenAI function calling and MCP tool execution
- **MCP Server**: Model Context Protocol server that exposes tools (GitHub, Qdrant)
- **Contract Boundary**: Public interface of a file (schemas, parameters, API signatures) vs implementation details
- **MDX**: Markdown with JSX components for structured, machine-readable documentation

---

## Requirements

### Requirement 1: OpenAI Agents SDK with Native MCP Support

**User Story:** As an agent developer, I want to use OpenAI Agents SDK with native MCP support, so that agents can use official MCP servers without custom bridge code.

**Reference Pattern:** ✅ OpenAI Agents SDK with MCPServerStdio

#### Acceptance Criteria

1. WHEN agent initializes, THE agent SHALL use OpenAI Agents SDK (`agents` package)
2. WHEN agent initializes, THE agent SHALL connect to MCP servers using `MCPServerStdio` context manager
3. WHEN agent initializes, THE agent SHALL pass MCP servers to `Agent` constructor via `mcp_servers` parameter
4. WHEN agent runs, THE SDK SHALL automatically handle MCP tool discovery and execution
5. WHEN agent runs, THE SDK SHALL automatically convert MCP schemas to OpenAI function definitions
6. WHEN agent runs, THE SDK SHALL automatically route tool calls to correct MCP server
7. THE agent SHALL support multiple MCP servers simultaneously (GitHub + Qdrant)
8. THE agent SHALL use `Runner.run(agent, task)` for execution
9. THE agent SHALL NOT require custom bridge code or schema transformation logic
10. THE implementation SHALL be in `platform/03-intelligence/agents/shared/agent_runner.py`

**Example Usage:**
\`\`\`python
from agents import Agent, Runner
from agents.mcp import MCPServerStdio

async with MCPServerStdio(
    name="GitHub Server",
    params={
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-github"]
    }
) as github_server:
    agent = Agent(
        name="Validator",
        instructions="...",
        mcp_servers=[github_server]
    )
    result = await Runner.run(agent, "Validate PR")
\`\`\`

---

### Requirement 3: Contract Boundary Extractor

**User Story:** As an agent developer, I want a generic contract boundary extractor, so that agents can identify public interfaces in any file type.

**Reference Pattern:** ✅ Universal Mental Model (Triangulation)

#### Acceptance Criteria

1. WHEN extracting from YAML, THE extractor SHALL identify Schemas/Parameters (Contract) vs Patches/Transforms (Implementation)
2. WHEN extracting from Python, THE extractor SHALL identify Function Signatures/API Models (Contract) vs Logic/Loops (Implementation)
3. WHEN extracting from Rego, THE extractor SHALL identify Rule Definitions (Contract) vs Rego Logic (Implementation)
4. WHEN extracting from Markdown, THE extractor SHALL identify Trigger/Resolution Steps (Contract) vs Anecdotes (Implementation)
5. THE extractor SHALL return structured data: parameters, schemas, functions, metadata
6. THE extractor SHALL be implemented in `platform/03-intelligence/agents/shared/contract_extractor.py`
7. THE extractor SHALL be language-agnostic and reusable

---

### Requirement 4: MDX Validator

**User Story:** As an infrastructure developer, I want a generic MDX validator, so that all agents can validate MDX consistently.

**Reference Pattern:** ✅ MDX syntax validation with component-specific rules

#### Acceptance Criteria

1. WHEN validating MDX, THE validation SHALL check for unclosed tags
2. WHEN validating `<ParamField>`, THE validation SHALL require `path` and `type` attributes
3. WHEN validating `<Step>`, THE validation SHALL require `title` attribute
4. WHEN validating components, THE validation SHALL only allow approved components: `ParamField`, Steps`, `Step`, `CodeGroup`, `Warning`, `Note`, `Tip`, `Frame`
5. WHEN validation fails, THE validation SHALL return specific error with component name and missing attribute
6. WHEN validation passes, THE validation SHALL return success status
7. THE validation SHALL check frontmatter fields match category requirements
8. THE validation SHALL enforce filename rules: kebab-case, max 3 words, no timestamps
9. THE validator SHALL be implemented in `platform/03-intelligence/agents/shared/mdx_validator.py`

---

### Requirement 5: MCP Server Configuration

**User Story:** As an agent operator, I want MCP servers configured correctly in agent containers, so that tools are available at runtime.

**Reference Pattern:** ✅ MCP servers installed and configured in Dockerfile

#### Acceptance Criteria

**GitHub MCP Server:**
1. WHEN agent builds, THE Dockerfile SHALL install Node.js v20+
2. WHEN agent builds, THE Dockerfile SHALL install GitHub MCP server via npm: `@modelcontextprotocol/server-github`
3. WHEN agent runs, THE agent SHALL start GitHub MCP server process with stdio transport
4. WHEN agent runs, THE agent SHALL pass `GITHUB_PERSONAL_ACCESS_TOKEN` to MCP server
5. WHEN agent runs, THE agent SHALL connect MCP client to GitHub MCP server

**Qdrant MCP Server:**
6. WHEN agent builds, THE Dockerfile SHALL install Qdrant MCP server via pip: `mcp-server-qdrant`
7. WHEN agent runs, THE agent SHALL start Qdrant MCP server process with stdio transport
8. WHEN agent runs, THE agent SHALL pass `QDRANT_URL`, `QDRANT_API_KEY`, `COLLECTION_NAME` to MCP server
9. WHEN agent runs, THE agent SHALL connect MCP client to Qdrant MCP server

---

### Requirement 6: Shared Library Structure

**User Story:** As a platform maintainer, I want common code shared between agents, so that we don't duplicate logic and maintenance is easier.

**Reference Pattern:** ✅ Shared Python libraries in `platform/03-intelligence/agents/shared/`

#### Acceptance Criteria

1. WHEN agents need common functionality, THE code SHALL be placed in `platform/03-intelligence/agents/shared/` directory
2. THE shared directory SHALL contain: `agent_runner.py` (OpenAI Agents SDK wrapper), `mdx_validator.py`, `contract_extractor.py`
3. WHEN agent builds, THE Dockerfile SHALL copy shared libraries from `platform/03-intelligence/agents/shared/`
4. THE shared libraries SHALL be unit tested independently
5. THE shared libraries SHALL have clear interfaces and documentation
6. WHEN shared library changes, ALL agents SHALL use updated code on next build
7. THE shared libraries SHALL NOT contain agent-specific logic

---

### Requirement 7: Testing Requirements

**User Story:** As an infrastructure developer, I want comprehensive tests for core components, so that agents have a stable foundation.

**Reference Pattern:** ✅ High test coverage for critical components

#### Acceptance Criteria

**Agent Runner Tests:**
1. THE runner SHALL have tests for MCP server initialization (GitHub, Qdrant)
2. THE runner SHALL have tests for agent creation with multiple MCP servers
3. THE runner SHALL have tests for error handling (MCP connection errors, SDK errors)
4. THE runner SHALL have integration tests with real MCP servers

**Contract Extractor Tests:**
5. THE extractor SHALL have tests for YAML parameter extraction
6. THE extractor SHALL have tests for Python signature extraction
7. THE extractor SHALL have tests for Rego rule extraction
8. THE extractor SHALL have tests for Markdown section extraction

**MDX Validator Tests:**
9. THE validator SHALL have tests for ParamField validation
10. THE validator SHALL have tests for unclosed tag detection
11. THE validator SHALL have tests for Steps component validation
12. THE validator SHALL have tests for frontmatter validation

---

## Dependencies

- Python 3.11+
- OpenAI Agents SDK (`agents>=0.1.0`) - includes native MCP support
- Node.js v20+ (for GitHub MCP server)
- pytest (for testing)

**Note:** OpenAI Agents SDK includes built-in MCP support, eliminating the need for custom bridge code or separate MCP Python SDK.

---

## Success Criteria

1. ✅ OpenAI Agents SDK successfully connects to MCP servers
2. ✅ Agent runner handles multiple MCP servers (GitHub + Qdrant)
3. ✅ Contract extractor works for YAML, Python, Rego, Markdown
4. ✅ MDX validator catches all syntax errors
5. ✅ Shared libraries are reusable by any agent
6. ✅ No agent-specific logic in shared components
7. ✅ No custom bridge code required (SDK handles MCP natively)

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** Ready for Implementation  
**Priority:** CRITICAL - Must be completed before agent development

```

# core-infrastructure-spec\tasks.md

```md
# Implementation Tasks: Core Infrastructure

## Overview

This task list covers the implementation of core infrastructure components that are reusable by all agents. These components MUST be completed and tested before any agent development begins.

**Priority:** CRITICAL - Foundation for all agents

**Estimated Time:** 1 week

---

## Tasks

- [ ] 1. Set up project structure
  - Create `platform/03-intelligence/agents/shared/` directory
  - Create `platform/03-intelligence/agents/shared/tests/` directory
  - Create `__init__.py` files
  - Create `requirements.txt` with dependencies
  - _Requirements: All_

- [ ] 2. Implement Agent Runner
  - [ ] 2.1 Create `agent_runner.py` file
    - Implement `create_agent_with_mcp()` function
    - Implement `load_prompt_from_file()` function
    - Implement `run_agent_task()` function
    - Add error handling for MCP server failures
    - Add error handling for prompt loading failures
    - _Requirements: 1_
  
  - [ ] 2.2 Write unit tests for Agent Runner
    - Test `create_agent_with_mcp()` with single MCP server
    - Test `create_agent_with_mcp()` with multiple MCP servers
    - Test `load_prompt_from_file()` with valid file
    - Test `load_prompt_from_file()` with invalid path
    - Test `run_agent_task()` execution
    - Test error handling for MCP connection failures
    - _Requirements: 1, 7_
  
  - [ ] 2.3 Write integration tests with real MCP servers
    - Test with GitHub MCP server (using test repository)
    - Test with Qdrant MCP server (using test collection)
    - Test with both servers simultaneously
    - Verify tool discovery works correctly
    - _Requirements: 1, 7_

- [ ] 3. Implement Contract Boundary Extractor
  - [ ] 3.1 Create `contract_extractor.py` file
    - Define `FileType` enum
    - Define `Parameter` dataclass
    - Define `ContractBoundary` dataclass
    - Implement `extract_contract_boundary()` main function
    - _Requirements: 3_
  
  - [ ] 3.2 Implement YAML Contract Extractor
    - Create `YAMLContractExtractor` class
    - Implement `extract()` method for Crossplane YAML
    - Extract `spec.forProvider.*` parameters
    - Extract `spec.compositeTypeRef` schemas
    - Extract `metadata.*` fields
    - Ignore `status.*` and `patches.*`
    - _Requirements: 3_
  
  - [ ] 3.3 Implement Python Contract Extractor
    - Create `PythonContractExtractor` class
    - Implement `extract()` method using AST parsing
    - Extract function signatures (def, async def)
    - Extract class definitions (dataclass, Pydantic models)
    - Extract type hints
    - Ignore function bodies and private methods
    - _Requirements: 3_
  
  - [ ] 3.4 Implement Rego Contract Extractor
    - Create `RegoContractExtractor` class
    - Implement `extract()` method using regex
    - Extract rule names
    - Extract input/output schemas
    - Ignore rule logic
    - _Requirements: 3_
  
  - [ ] 3.5 Implement Markdown Contract Extractor
    - Create `MarkdownContractExtractor` class
    - Implement `extract()` method using regex
    - Extract ## Symptoms, ## Diagnosis, ## Resolution sections
    - Ignore anecdotes and background information
    - _Requirements: 3_
  
  - [ ] 3.6 Write unit tests for Contract Extractor
    - Test YAML parameter extraction with sample Crossplane file
    - Test Python signature extraction with sample Python file
    - Test Rego rule extraction with sample Rego file
    - Test Markdown section extraction with sample runbook
    - Test error handling for invalid files
    - Test error handling for unsupported file types
    - _Requirements: 3, 7_

- [ ] 4. Implement MDX Validator
  - [ ] 4.1 Create `mdx_validator.py` file
    - Define `ComponentType` enum
    - Define `ValidationError` dataclass
    - Define `ValidationResult` dataclass
    - Implement `validate_mdx()` main function
    - _Requirements: 4_
  
  - [ ] 4.2 Implement component validation
    - Implement `validate_component()` function
    - Add validation for ParamField (requires `path` and `type`)
    - Add validation for Step (requires `title`)
    - Add validation for Steps (must contain Step children)
    - Add validation for unclosed tags
    - Add whitelist check for approved components
    - _Requirements: 4_
  
  - [ ] 4.3 Implement frontmatter validation
    - Implement `validate_frontmatter()` function
    - Check required fields: title, category, description
    - Validate category values: spec, runbook, adr
    - Check optional fields: tags, author, date
    - _Requirements: 4_
  
  - [ ] 4.4 Implement filename validation
    - Implement `validate_filename()` function
    - Check kebab-case format
    - Check max 3 words
    - Check no timestamps
    - Check .mdx extension
    - _Requirements: 4_
  
  - [ ] 4.5 Write unit tests for MDX Validator
    - Test ParamField validation with missing required attributes
    - Test Step validation with missing title
    - Test unclosed tag detection
    - Test frontmatter validation with missing fields
    - Test frontmatter validation with invalid category
    - Test filename validation with invalid formats
    - Test filename validation with too many words
    - Test filename validation with timestamps
    - _Requirements: 4, 7_

- [ ] 5. Create comprehensive test suite
  - [ ] 5.1 Set up pytest configuration
    - Create `pytest.ini` file
    - Configure test discovery
    - Configure coverage reporting
    - _Requirements: 7_
  
  - [ ] 5.2 Create test fixtures
    - Create sample YAML files for testing
    - Create sample Python files for testing
    - Create sample Rego files for testing
    - Create sample Markdown files for testing
    - Create sample MDX files for testing
    - _Requirements: 7_
  
  - [ ] 5.3 Run full test suite
    - Run all unit tests
    - Run all integration tests
    - Generate coverage report
    - Verify high coverage (>80%)
    - _Requirements: 7_

- [ ] 6. Create documentation
  - [ ] 6.1 Write README for shared libraries
    - Document purpose of each component
    - Provide usage examples
    - Document interfaces and data models
    - Add installation instructions
    - _Requirements: 6_
  
  - [ ] 6.2 Write API documentation
    - Document all public functions
    - Document all classes and methods
    - Add docstrings with examples
    - Generate API docs (Sphinx or similar)
    - _Requirements: 6_

- [ ] 7. Verify dependencies and setup
  - [ ] 7.1 Create requirements.txt
    - Add `agents>=0.1.0` (OpenAI Agents SDK)
    - Add `pyyaml>=6.0.0` (YAML parsing)
    - Add `pydantic>=2.0.0` (data validation)
    - Add `pytest>=7.0.0` (testing)
    - Add `pytest-asyncio>=0.21.0` (async testing)
    - Add `pytest-cov>=4.0.0` (coverage)
    - _Requirements: All_
  
  - [ ] 7.2 Test installation
    - Create clean virtual environment
    - Install dependencies from requirements.txt
    - Verify all imports work
    - Run test suite in clean environment
    - _Requirements: All_

---

## Success Criteria

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Test coverage > 80%
- [ ] Agent Runner successfully connects to MCP servers
- [ ] Contract Extractor works for YAML, Python, Rego, Markdown
- [ ] MDX Validator catches all syntax errors
- [ ] Documentation is complete and clear
- [ ] No agent-specific logic in shared components

---

## Notes

- **CRITICAL:** This spec must be completed before Validator or Documentor development
- **Testing:** Focus on high test coverage for Agent Runner and Contract Extractor
- **MCP Servers:** Use test instances for integration tests (test GitHub repo, test Qdrant collection)
- **Error Handling:** Ensure graceful error handling for all failure modes

---

**Estimated Effort:**
- Agent Runner: 2 days (including tests)
- Contract Extractor: 2 days (including tests)
- MDX Validator: 1 day (including tests)
- Documentation: 1 day
- Buffer: 1 day

**Total: 7 days (1 week)**

```

# documentor-spec\design.md

```md
# Design Document: Documentor Agent

## Overview

The Documentor Agent automatically creates and updates MDX Twin Docs for platform compositions. It uses OpenAI Agents SDK with GitHub and Qdrant MCP servers to generate structured documentation.

**Execution Time:** < 3 minutes per PR

**Location:** `.github/actions/documentor/`

---

## Architecture

### High-Level Flow

\`\`\`
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
\`\`\`

### Component Architecture

\`\`\`
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
\`\`\`

---

## Components and Interfaces

### 1. Main Script (`documentor.py`)

**Purpose:** Orchestrate documentation generation workflow

**Interface:**
\`\`\`python
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
\`\`\`

---

### 2. Template Engine (`template_engine.py`)

**Purpose:** Load and fill MDX templates

**Interface:**
\`\`\`python
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
\`\`\`

**Implementation Notes:**
- Use regex to parse MDX components
- Preserve manual sections (Overview, Purpose, etc.)
- Only update changed ParamField components
- Generate proper MDX syntax with attributes

---

### 3. Docs.json Manager (`docs_json_manager.py`)

**Purpose:** Manage navigation manifest updates

**Interface:**
\`\`\`python
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
\`\`\`

**Implementation Notes:**
- Read docs.json from main branch (not PR branch)
- Append new entry to appropriate group
- Format with one entry per line for git auto-merge
- Handle merge conflicts with rebase + retry

---

## Data Models

### MDX Document Structure
\`\`\`python
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
\`\`\`

### Docs.json Structure
\`\`\`json
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
\`\`\`

---

## Agent System Prompt

**Location:** `platform/03-intelligence/agents/documentor/prompt.md`

**Key Instructions:**
\`\`\`markdown
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
\`\`\`mdx
<ParamField path="spec.forProvider.port" type="integer" required>
  Port number for the service
</ParamField>
\`\`\`

**Steps:**
\`\`\`mdx
<Steps>
  <Step title="Check logs">
    Run `kubectl logs pod-name`
  </Step>
  <Step title="Restart service">
    Run `kubectl rollout restart deployment/service`
  </Step>
</Steps>
\`\`\`

## Important Rules

- ALWAYS use structured components (ParamField, Steps), NEVER use Markdown tables
- ALWAYS preserve manual sections when updating
- ALWAYS validate MDX before committing
- ALWAYS update docs.json atomically with Twin Doc
- NEVER edit implementation details (patches, transforms)
- NEVER create orphaned files (always update docs.json)
\`\`\`

---

## Error Handling

### MDX Validation Errors
\`\`\`python
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
\`\`\`

### Docs.json Merge Conflicts
\`\`\`python
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
\`\`\`

---

## Testing Strategy

### Unit Tests
\`\`\`python
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
\`\`\`

### Integration Tests
\`\`\`python
# tests/integration/test_documentor.py
@pytest.mark.asyncio
async def test_documentor_end_to_end():
    """Test complete Documentor workflow."""
    # Use test repository
    # Create test PR
    # Run Documentor
    # Verify MDX committed
    # Verify docs.json updated
\`\`\`

---

## Deployment

### Dockerfile
\`\`\`dockerfile
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
\`\`\`

**Build Command:**
\`\`\`bash
docker build -f .github/actions/documentor/Dockerfile -t documentor:latest .
\`\`\`

### GitHub Action
\`\`\`yaml
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
\`\`\`

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

\`\`\`python
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
\`\`\`

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-02  
**Status:** Ready for Implementation  
**Depends On:** Core Infrastructure Spec, Validator Spec

```

# documentor-spec\requirements.md

```md
# Requirements Document: Documentor Agent

## Introduction

This document defines requirements for the Documentor Agent, which automatically creates and updates MDX Twin Docs for platform compositions.

**Scope:** MDX documentation generation, Qdrant integration, docs.json management, distillation workflow

**Execution Time:** < 3 minutes per PR

**Location:** `.github/actions/documentor/`

---

## Glossary

- **Twin Doc**: Specification file in `artifacts/specs/` (MDX format) that mirrors a platform composition 1:1
- **Documentor Agent**: Documentation generator agent that creates/updates Twin Docs (~1-3 min execution)
- **Upsert**: Create or update operation with validation (atomic: validate + write + commit)
- **MDX**: Markdown with JSX components for structured, machine-readable documentation
- **Navigation Manifest**: `docs.json` file that defines documentation structure and prevents orphaned files
- **Contract Boundary**: Public interface of a file (schemas, parameters, API signatures) vs implementation details

---

## Requirements

### Requirement 1: MDX Twin Doc Creation

**User Story:** As a developer, I want the Documentor Agent to automatically create Twin Docs in MDX format with structured components, so that documentation is machine-readable and never missing.

**Reference Pattern:** ✅ Template-based MDX generation with Contract Boundary extraction

#### Acceptance Criteria

1. WHEN resource is new, THE Documentor Agent SHALL check if Twin Doc exists
2. WHEN Twin Doc missing, THE agent SHALL fetch template from `artifacts/templates/spec-template.mdx`
3. WHEN creating, THE agent SHALL identify the Contract Boundary in the changed file
4. WHEN creating, THE agent SHALL fill frontmatter with resource metadata extracted from the Contract
5. WHEN creating, THE agent SHALL generate `<ParamField>` components (not Markdown tables) from Contract Boundary data
6. WHEN creating, THE agent SHALL update `docs.json` navigation manifest with new file entry
7. WHEN created, THE agent SHALL call `upsert_twin_doc` (atomic: validate MDX + write + commit)
8. THE generated MDX SHALL use structured components: `<ParamField>`, `<CodeGroup>`, `<Warning>`, `<Note>`, `<Tip>`

---

### Requirement 2: MDX Twin Doc Update

**User Story:** As a developer, I want the Documentor Agent to update only changed parameters in existing Twin Docs, so that manual documentation sections are preserved.

**Reference Pattern:** ✅ Surgical updates (component-level, not table rows)

#### Acceptance Criteria

1. WHEN resource modified, THE Documentor Agent SHALL fetch existing Twin Doc
2. WHEN updating, THE agent SHALL parse existing `<ParamField>` components
3. WHEN updating, THE agent SHALL identify the Contract Boundary in the changed file
4. WHEN updating, THE agent SHALL compare existing components with extracted Contract data to identify changes
5. WHEN updating, THE agent SHALL modify ONLY changed `<ParamField>` components
6. WHEN updating, THE agent SHALL preserve all other sections (Overview, Purpose, etc.)
7. WHEN updating, THE agent SHALL update `docs.json` if file path or navigation group changed
8. WHEN updated, THE agent SHALL call `upsert_twin_doc` (atomic: validate MDX + write + commit)

---

### Requirement 3: MDX Component Validation

**User Story:** As a documentation maintainer, I want strict MDX validation rules enforced, so that all Twin Docs follow consistent standards and render correctly.

**Reference Pattern:** ✅ MDX syntax validation with component-specific rules

#### Acceptance Criteria

1. WHEN validating MDX, THE validation SHALL check for unclosed tags
2. WHEN validating `<ParamField>`, THE validation SHALL require `path` and `type` attributes
3. WHEN validating `<Step>`, THE validation SHALL require `title` attribute
4. WHEN validating components, THE validation SHALL only allow approved components: `ParamField`, `Steps`, `Step`, `CodeGroup`, `Warning`, `Note`, `Tip`, `Frame`
5. WHEN validation fails, THE validation SHALL return specific error with component name and missing attribute
6. WHEN validation passes, THE validation SHALL return success status
7. THE validation SHALL check frontmatter fields match category requirements
8. THE validation SHALL enforce filename rules: kebab-case, max 3 words, no timestamps

---

### Requirement 4: Navigation Manifest Management

**User Story:** As a platform operator, I want all Twin Docs explicitly listed in a navigation manifest, so that documentation is organized and discoverable with no orphaned files.

**Reference Pattern:** ✅ `docs.json` as single source of truth for navigation

#### Acceptance Criteria

1. WHEN Documentor Agent creates Twin Doc, THE agent SHALL update `artifacts/docs.json` with new file entry
2. WHEN updating `docs.json`, THE agent SHALL read current manifest from main branch
3. WHEN updating `docs.json`, THE agent SHALL find appropriate navigation group (Infrastructure, APIs, Runbooks)
4. WHEN updating `docs.json`, THE agent SHALL append new page path (without `.mdx` extension)
5. WHEN updating `docs.json`, THE agent SHALL format JSON with one entry per line (for git auto-merge)
6. WHEN merge conflict detected on `docs.json`, THE agent SHALL rebase and retry (max 3 attempts)
7. WHEN `docs.json` update fails, THE entire Twin Doc creation SHALL fail (atomic guarantee)
8. THE `docs.json` SHALL use simplified structure: only `groups` and `pages` (no tabs, dropdowns, products)

---

### Requirement 5: Validation with Iteration

**User Story:** As a platform maintainer, I want the Documentor Agent to automatically fix validation errors, so that PRs are not blocked by formatting issues.

**Reference Pattern:** ✅ Self-correcting agent loop with MDX validation

#### Acceptance Criteria

1. WHEN Documentor Agent generates doc, THE agent SHALL call `upsert_twin_doc` tool (atomic operation)
2. WHEN MDX validation fails, THE tool SHALL return specific error message WITHOUT committing
3. WHEN error received, THE agent SHALL analyze error and fix issue
4. WHEN fixed, THE agent SHALL retry `upsert_twin_doc` (max 3 attempts)
5. WHEN max attempts exceeded, THE agent SHALL fail CI with all errors (but PR remains valid)
6. WHEN validation passes, THE tool SHALL write AND commit in one atomic operation
7. THE validation SHALL include both MDX syntax validation and frontmatter validation

---

### Requirement 6: Commit to PR Branch

**User Story:** As a developer, I want the Documentor Agent to commit Twin Docs to my PR branch, so that I can review changes before merge.

**Reference Pattern:** ✅ GitHub API commit to PR branch (via GitHub MCP tools)

**CRITICAL SECURITY REQUIREMENT:** Agents MUST use GitHub App Token or PAT (not default GITHUB_TOKEN)

#### Acceptance Criteria

1. WHEN Twin Doc ready, THE Documentor Agent SHALL use GitHub MCP tools to commit
2. WHEN validation passes, THE agent SHALL commit to SAME PR branch automatically using BOT_GITHUB_TOKEN
3. WHEN committing, THE commit message SHALL follow convention: "docs: update Twin Doc for {resource}"
4. WHEN committed using App Token/PAT, THE CI SHALL re-run validation (re-trigger workflows)
5. WHEN CI passes, THE PR SHALL be ready for human review
6. WHEN validation fails, THE agent SHALL NOT commit (prevents validation bypass)
7. THE Documentor Agent SHALL also commit `docs.json` updates in same PR

---

### Requirement 7: Historical Precedent Search

**User Story:** As the Documentor Agent, I want to search for similar past documentation, so that I maintain consistency with historical patterns.

**Reference Pattern:** ✅ Qdrant semantic search with MDX-aware retrieval

#### Acceptance Criteria

1. WHEN Documentor Agent runs, THE agent SHALL call `qdrant_find` with resource type query
2. WHEN searching, THE query SHALL be: "similar to {resource_type}"
3. WHEN results returned, THE agent SHALL review top 3 results
4. WHEN reviewing, THE agent SHALL extract naming patterns, component structure, and frontmatter conventions
5. WHEN creating new doc, THE agent SHALL follow historical patterns
6. THE search SHALL leverage MDX component metadata for precise matching

---

### Requirement 8: MDX-Aware Qdrant Sync

**User Story:** As a platform operator, I want Twin Docs automatically indexed to Qdrant with semantic chunking, so that agents can retrieve precise information.

**Reference Pattern:** ✅ GitHub Actions workflow on merge to main with MDX-aware chunking

#### Acceptance Criteria

1. WHEN PR merges to main, THE workflow SHALL trigger `sync-docs-to-qdrant.yaml`
2. WHEN syncing, THE workflow SHALL call `qdrant_store` MCP tool
3. WHEN indexing, THE tool SHALL chunk by MDX components (not arbitrary token counts)
4. WHEN indexing, THE tool SHALL create separate chunks for: frontmatter, each `<ParamField>`, each `<Step>`, regular sections
5. WHEN indexing, THE tool SHALL store component metadata in Qdrant payload (type, path, title, index)
6. WHEN indexing, THE tool SHALL generate embeddings and store in Qdrant
7. WHEN indexed, THE Twin Doc SHALL be searchable via `qdrant_find` with precise component-level retrieval
8. THE chunking SHALL preserve semantic boundaries (no splitting mid-component)

---

### Requirement 9: Distillation from docs/ to artifacts/

**User Story:** As a developer, I want to write free-form troubleshooting notes in docs/, and have the Documentor Agent extract operational knowledge into structured runbooks in artifacts/.

**Reference Pattern:** ⚠️ CUSTOM - Agent reads docs/, creates artifacts/, preserves original

#### Acceptance Criteria

1. WHEN PR modifies docs/**/*.md, THE CI SHALL invoke Documentor Agent in distillation mode
2. WHEN agent reads docs/ file, THE agent SHALL identify operational knowledge (runbooks, procedures)
3. WHEN operational knowledge found, THE agent SHALL create structured artifact using `runbook-template.mdx`
4. WHEN creating artifact, THE agent SHALL use `<Steps>` components for diagnosis and resolution
5. WHEN creating artifact, THE agent SHALL preserve original docs/ file unchanged
6. WHEN distilling, THE agent SHALL commit only artifacts/ changes to PR
7. THE distilled runbook SHALL be in MDX format with structured components

---

### Requirement 10: Duplicate Detection for Distillation

**User Story:** As a platform operator, I want the Documentor Agent to detect duplicate runbooks and merge information, so that we don't have fragmented knowledge.

**Reference Pattern:** ✅ Qdrant similarity search with MDX component matching

#### Acceptance Criteria

1. WHEN distilling content, THE Documentor Agent SHALL call `qdrant_find` to search for similar artifacts
2. WHEN similarity score > 0.85, THE agent SHALL update existing artifact (not create new)
3. WHEN updating, THE agent SHALL merge new information into existing `<Steps>` components
4. WHEN no match found, THE agent SHALL create new artifact
5. WHEN merging, THE agent SHALL preserve existing structure and add new details
6. THE duplicate detection SHALL leverage MDX component metadata for precise matching

---

### Requirement 11: Runbook Template Compliance

**User Story:** As an on-call engineer, I want all runbooks to follow the same MDX structure, so that I can quickly find diagnosis and resolution steps.

**Reference Pattern:** ✅ Template-based MDX generation with `<Steps>` components

#### Acceptance Criteria

1. WHEN creating runbook, THE Documentor Agent SHALL use `artifacts/templates/runbook-template.mdx`
2. WHEN filling template, THE agent SHALL include sections: Symptoms, Diagnosis, Resolution, Prevention
3. WHEN filling Diagnosis section, THE agent SHALL use `<Steps>` component with `<Step>` children
4. WHEN filling Resolution section, THE agent SHALL use `<Steps>` component with `<Step>` children
5. WHEN validating runbook, THE validation SHALL enforce category: runbook in frontmatter
6. WHEN validating runbook, THE validation SHALL enforce MDX component structure
7. WHEN runbook created, THE runbook SHALL pass all MDX validation scripts

---

### Requirement 12: Auto-Generated Header Warning

**User Story:** As a developer, I want clear warnings on auto-generated files, so that I don't accidentally edit them directly and lose my changes.

**Reference Pattern:** ✅ MDX comment header in all artifacts/ files

#### Acceptance Criteria

1. WHEN Documentor Agent creates Twin Doc, THE agent SHALL prepend auto-generated warning using `<Warning>` component
2. WHEN Documentor Agent creates runbook, THE agent SHALL prepend auto-generated warning using `<Warning>` component
3. WHEN warning added, THE component SHALL include: "DO NOT EDIT DIRECTLY" message
4. WHEN warning added, THE component SHALL include: Source location (composition path or docs/ path)
5. WHEN warning added, THE component SHALL include: Last generated timestamp
6. WHEN human edits artifacts/ file directly, THE validation SHALL detect and warn (optional enforcement)

---

### Requirement 13: Manual Documentor Trigger

**User Story:** As a developer, I want to manually trigger documentation generation via PR comment, so that I can regenerate docs without pushing new commits.

**Reference Pattern:** ✅ GitHub issue comment triggers (ChatOps pattern)

#### Acceptance Criteria

1. WHEN developer comments `@librarian regenerate-docs`, THE CI SHALL re-run Documentor Agent only
2. THE workflow SHALL trigger on `issue_comment` event type `created` (in addition to `pull_request` events)

---

### Requirement 14: GitHub and Qdrant MCP Tools

**User Story:** As a Documentor Agent, I want to use MCP tools for all operations, so that I leverage standardized tooling.

**Reference Pattern:** ✅ Official GitHub and Qdrant MCP servers

#### Acceptance Criteria

**GitHub MCP Tools:**
1. WHEN Documentor needs file content, THE agent SHALL call `github_get_file_contents` MCP tool
2. WHEN Documentor creates/updates file, THE agent SHALL call `github_create_or_update_file` or `github_push_files` MCP tool
3. WHEN Documentor posts comment, THE agent SHALL call `github_create_issue_comment` MCP tool

**Qdrant MCP Tools:**
4. WHEN Documentor searches precedent, THE agent SHALL call `qdrant_find` MCP tool
5. WHEN Documentor indexes docs, THE agent SHALL call `qdrant_store` MCP tool

**Local Logic:**
6. THE Documentor SHALL use LLM reasoning for Contract Boundary extraction (no custom parsing tools)
7. THE Documentor SHALL implement MDX validation logic locally (not via MCP tool)

---

### Requirement 15: Qdrant Cloud Configuration

**User Story:** As a platform operator, I want to use Qdrant Cloud instead of self-hosted Qdrant, so that I don't need to expose cluster services.

**Reference Pattern:** ✅ Qdrant Cloud with API key authentication

#### Acceptance Criteria

1. WHEN configuring Qdrant, THE system SHALL use Qdrant Cloud (not self-hosted cluster instance)
2. WHEN configuring Qdrant, THE user SHALL provide `QDRANT_URL` (Qdrant Cloud endpoint)
3. WHEN configuring Qdrant, THE user SHALL provide `QDRANT_API_KEY` (Qdrant Cloud API key)
4. WHEN storing secrets, THE `QDRANT_URL` and `QDRANT_API_KEY` SHALL be stored in GitHub secrets
5. WHEN Documentor Agent runs, THE agent SHALL pass Qdrant credentials to MCP server via environment variables
6. THE Qdrant MCP server SHALL connect to Qdrant Cloud using provided credentials
7. THE Qdrant MCP server SHALL use collection name: `documentation`
8. THE Qdrant MCP server SHALL use embedding model: `sentence-transformers/all-MiniLM-L6-v2`
9. THE system SHALL NOT require exposing self-hosted Qdrant via ingress
10. THE system SHALL NOT require cluster networking for Qdrant access

---

### Requirement 16: Error Handling

**User Story:** As a developer, I want clear error messages when documentation generation fails, so that I know how to fix issues.

**Reference Pattern:** ✅ Structured error responses

#### Acceptance Criteria

1. WHEN MDX validation fails, THE Documentor SHALL fail with specific component error and attribute name
2. WHEN `docs.json` update fails, THE Documentor SHALL fail with merge conflict details
3. WHEN max retries exceeded, THE Documentor SHALL fail with all attempted fixes listed
4. WHEN Documentor fails, THE PR SHALL remain valid (docs can be regenerated)

---

### Requirement 17: System Prompt

**User Story:** As a platform architect, I want the Documentor prompt stored in the repository, so that the "Brain" is version-controlled with the code.

**Reference Pattern:** ✅ Prompt loaded at runtime from repo

#### Acceptance Criteria

1. WHEN Documentor Agent runs, THE system prompt SHALL be loaded from `platform/03-intelligence/agents/documentor/prompt.md` at runtime
2. THE system prompt SHALL NOT be hardcoded inside Docker image
3. THE system prompt SHALL be version-controlled in the repository
4. WHEN prompt file changes, THE agent SHALL use updated prompt on next run (no rebuild required)
5. THE prompt SHALL reference Diataxis framework guide for content type classification
6. THE prompt SHALL reference MDX component guide for syntax
7. THE prompt SHALL embed iteration logic for validation errors
8. THE prompt SHALL NOT include Gatekeeper validation logic

---

### Requirement 18: Metrics

**User Story:** As a platform operator, I want metrics on Documentor performance, so that I can monitor workflow health.

**Reference Pattern:** ✅ Prometheus metrics

#### Acceptance Criteria

1. WHEN Documentor runs, THE agent SHALL emit `documentor_duration_seconds` histogram
2. WHEN Twin Doc created, THE agent SHALL emit `twin_doc_created_total` counter
3. WHEN Twin Doc updated, THE agent SHALL emit `twin_doc_updated_total` counter
4. WHEN MDX validation fails, THE agent SHALL emit `mdx_validation_errors_total` counter
5. WHEN `docs.json` conflict occurs, THE agent SHALL emit `docs_json_conflicts_total` counter
6. THE metrics SHALL be exported in Prometheus format

---

### Requirement 19: Execution Flow

**User Story:** As a Documentor Agent, I want a clear execution flow, so that I generate documentation efficiently.

**Reference Pattern:** ✅ Sequential execution with validation loops

#### Acceptance Criteria

1. WHEN Documentor starts, THE agent SHALL parse inputs (PR number, GitHub token, OpenAI key, Qdrant credentials)
2. WHEN Documentor starts, THE agent SHALL start GitHub MCP server
3. WHEN Documentor starts, THE agent SHALL start Qdrant MCP server
4. WHEN Documentor starts, THE agent SHALL initialize MCP bridge
5. WHEN Documentor starts, THE agent SHALL load system prompt from repo
6. WHEN Documentor starts, THE agent SHALL identify changed compositions
7. WHEN Documentor starts, THE agent SHALL run agent loop (OpenAI + MCP bridge)
8. WHEN doc generated, THE agent SHALL validate MDX (max 3 retries)
9. WHEN validation passes, THE agent SHALL update docs.json
10. WHEN complete, THE agent SHALL commit to PR branch
11. WHEN complete, THE agent SHALL post summary comment

---

## Dependencies

- Core Infrastructure (MCP bridge, contract extractor, MDX validator)
- OpenAI API Key
- GitHub Bot Token (BOT_GITHUB_TOKEN)
- Qdrant Cloud URL and API Key
- GitHub MCP Server (`@modelcontextprotocol/server-github`)
- Qdrant MCP Server (`mcp-server-qdrant`)

---

## Success Criteria

1. ✅ 100% of new compositions get Twin Docs automatically in MDX format
2. ✅ 100% of Twin Docs use structured components (`<ParamField>`, `<Steps>`, `<CodeGroup>`)
3. ✅ 100% of Twin Docs pass MDX validation after agent commits
4. ✅ 100% of Twin Docs listed in `docs.json` (no orphaned files)
5. ✅ 0% merge conflicts on `docs.json` (git auto-merge + rebase)
6. ✅ Documentor execution time < 3 minutes (with caching)
7. ✅ 100% of merged Twin Docs are indexed in Qdrant with MDX-aware chunking
8. ✅ >90% retrieval precision (queries return exact relevant component)
9. ✅ 100% of PRs modifying `docs/` trigger distillation workflow
10. ✅ 100% of operational knowledge extracted to structured runbooks

---

## Non-Functional Requirements

### Performance
- Execution time: < 3 minutes per PR (with caching)
- MDX validation: < 5 seconds per document
- Qdrant sync time: < 2 minutes for full `artifacts/` directory
- `docs.json` conflict resolution: < 10 seconds (rebase + retry)

### Reliability
- Success rate: > 90% (excluding validation errors)
- Qdrant sync success rate: 100%
- `docs.json` auto-merge success rate: > 95%

### Security
- Read-only access to platform/, specs, docs/
- Write access to artifacts/ only
- Qdrant Cloud credentials stored securely

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** Ready for Implementation  
**Depends On:** Core Infrastructure Spec

```

# documentor-spec\tasks.md

```md
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

```

# validator-spec\design.md

```md

```

# validator-spec\requirements.md

```md
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

#### Acceptance Criteria

1. WHEN developer comments `@librarian override`, THE Validator Agent SHALL check for this comment BEFORE running LLM validation
2. WHEN `@librarian override` detected, THE Validator Agent SHALL exit with success (0) immediately without LLM call
3. WHEN override used, THE system SHALL log override event with comment author and timestamp for audit purposes
4. THE Validator Agent SHALL fetch and scan ALL PR comments for override command before validation
5. THE override command SHALL work regardless of whether "librarian" is a real GitHub user account
6. WHEN override detected, THE Validator SHALL post acknowledgment comment: "✅ Override detected. Validation skipped by {author}"

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
2. WHEN Validator starts, THE agent SHALL start GitHub MCP server
3. WHEN Validator starts, THE agent SHALL initialize MCP bridge
4. WHEN Validator starts, THE agent SHALL check for `@librarian override` comment (via GitHub MCP tool)
5. WHEN override found, THE agent SHALL post acknowledgment and exit(0)
6. WHEN no override, THE agent SHALL load system prompt from repo
7. WHEN no override, THE agent SHALL fetch PR diff and spec (via GitHub MCP tools)
8. WHEN no override, THE agent SHALL run agent loop (OpenAI + MCP bridge)
9. WHEN mismatch detected, THE agent SHALL post gatekeeper comment
10. WHEN complete, THE agent SHALL exit with appropriate code (0=pass, 1=block)

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

```

# validator-spec\tasks.md

```md
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
    - Check for override comment first (before LLM call)
    - If override found: post acknowledgment and exit(0)
    - If no override: fetch PR diff and spec
    - Run agent loop with validation task
    - Post gatekeeper comment if mismatch detected
    - Exit with appropriate code
    - _Requirements: 2, 4, 10_

- [ ] 3. Implement Override Checker
  - [ ] 3.1 Create `override_checker.py` module
    - Implement `check_for_override()` function
    - Use GitHub MCP tool `github_list_issue_comments`
    - Scan all PR comments for `@librarian override`
    - Return override status and author
    - _Requirements: 4_
  
  - [ ] 3.2 Implement override acknowledgment
    - Post comment: "✅ Override detected. Validation skipped by {author}"
    - Use GitHub MCP tool `github_create_issue_comment`
    - Log override event for audit
    - _Requirements: 4_
  
  - [ ] 3.3 Write unit tests for Override Checker
    - Test detection of override comment
    - Test case-insensitive matching
    - Test with multiple comments
    - Test with no override comment
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

```

