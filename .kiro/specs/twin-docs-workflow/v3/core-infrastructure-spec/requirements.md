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
```python
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
```

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

- Python 3.10+ (required for MCP support)
- OpenAI Agents SDK (`openai-agents==0.6.1`) - includes native MCP support
- MCP SDK (`mcp>=1.11.0, <2`) - automatically included with openai-agents for Python 3.10+
- Node.js v20+ (for GitHub MCP server)
- pytest (for testing)

**Note:** OpenAI Agents SDK v0.6.1 includes built-in MCP support via `MCPServerStdio`, eliminating the need for custom bridge code.

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
