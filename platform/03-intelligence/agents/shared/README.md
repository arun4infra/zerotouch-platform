# Shared Agent Infrastructure

Core infrastructure components for all agents in the Intelligence Layer.

## Components

### Agent Runner

Thin wrapper around OpenAI Agents SDK with native MCP support.

```python
from agent_runner import create_agent_with_mcp, run_agent_task, load_prompt_from_file

# Load system prompt
instructions = load_prompt_from_file("platform/03-intelligence/agents/validator/prompt.md")

# Create agent with MCP servers
agent = await create_agent_with_mcp(
    name="Validator",
    instructions=instructions,
    mcp_servers=[
        {
            "name": "GitHub",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"],
            "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": token}
        }
    ]
)

# Run agent task
result = await run_agent_task(agent, "Validate PR #123")
```

### Contract Boundary Extractor

Extracts API contracts from various file types without implementation details.

```python
from contract_extractor import extract_contract_boundary

# Extract from Crossplane YAML
boundary = extract_contract_boundary("composition.yaml")
for param in boundary.parameters:
    print(f"{param.name}: {param.type}")

# Extract from Python file
boundary = extract_contract_boundary("service.py")
for param in boundary.parameters:
    if param.name.endswith(".return"):
        print(f"Function returns: {param.type}")
```

### MDX Validator

Validates MDX documentation files for compliance.

```python
from mdx_validator import validate_mdx

# Validate MDX file
result = validate_mdx("spec.mdx")
if not result.valid:
    for error in result.errors:
        print(f"Line {error.line}: {error.message}")
```

## Installation

```bash
cd platform/03-intelligence/agents/shared
uv sync
```

## Testing

```bash
# Run all tests
uv run pytest tests/ -v

# Run with coverage
uv run pytest tests/ --cov=. --cov-report=html

# Run specific test file
uv run pytest tests/test_agent_runner.py -v
```

## Development

```bash
# Install dev dependencies
uv add --dev pytest pytest-asyncio pytest-cov ruff mypy

# Run linter
uv run ruff check .

# Run type checker
uv run mypy .
```
