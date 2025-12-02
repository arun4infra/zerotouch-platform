# Implementation Tasks: Core Infrastructure

## Overview

This task list covers the implementation of core infrastructure components that are reusable by all agents. These components MUST be completed and tested before any agent development begins.

**Priority:** CRITICAL - Foundation for all agents

**Estimated Time:** 1 week

---

## Tasks

- [x] 1. Set up project structure with uv




  - Create `platform/03-intelligence/agents/shared/` directory
  - Create `platform/03-intelligence/agents/shared/tests/` directory
  - Create `__init__.py` files
  - Run `uv init` to initialize project
  - Create `pyproject.toml` with project metadata and dependencies
  - _Requirements: All_

- [x] 2. Implement Agent Runner



  - [x] 2.1 Create `agent_runner.py` file


    - Implement `create_agent_with_mcp()` function
    - Implement `load_prompt_from_file()` function
    - Implement `run_agent_task()` function
    - Add error handling for MCP server failures
    - Add error handling for prompt loading failures
    - _Requirements: 1_
  
  - [x] 2.2 Write unit tests for Agent Runner


    - Test `create_agent_with_mcp()` with single MCP server
    - Test `create_agent_with_mcp()` with multiple MCP servers
    - Test `load_prompt_from_file()` with valid file
    - Test `load_prompt_from_file()` with invalid path
    - Test `run_agent_task()` execution
    - Test error handling for MCP connection failures
    - _Requirements: 1, 7_
  
  - [x] 2.3 Write integration tests with real MCP servers

    - Test with GitHub MCP server (using test repository)
    - Test with Qdrant MCP server (using test collection)
    - Test with both servers simultaneously
    - Verify tool discovery works correctly
    - _Requirements: 1, 7_

  - [ ] **CHECKPOINT 1: Agent Runner Validation**

    - Run: `uv run pytest platform/03-intelligence/agents/shared/tests/test_agent_runner.py -v`
    - Verify: All tests pass
    - Verify: Agent successfully connects to GitHub MCP server
    - Verify: Agent can list tools from MCP server
    - **STOP HERE and review test results before proceeding**

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

  - [ ] **CHECKPOINT 2: Contract Extractor Validation**
    - Run: `uv run pytest platform/03-intelligence/agents/shared/tests/test_contract_extractor.py -v`
    - Verify: All tests pass
    - Verify: YAML extractor correctly identifies parameters
    - Verify: Python extractor correctly identifies function signatures
    - Test manually with real composition file: `platform/03-intelligence/test-webservice.yaml`
    - **STOP HERE and review test results before proceeding**

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

  - [ ] **CHECKPOINT 3: MDX Validator Validation**
    - Run: `uv run pytest platform/03-intelligence/agents/shared/tests/test_mdx_validator.py -v`
    - Verify: All tests pass
    - Verify: Validator catches missing required attributes
    - Verify: Validator detects unclosed tags
    - Verify: Validator validates frontmatter correctly
    - **STOP HERE and review test results before proceeding**

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

  - [ ] **CHECKPOINT 4: Full Test Suite Validation**
    - Run: `uv run pytest platform/03-intelligence/agents/shared/tests/ -v --cov=. --cov-report=html`
    - Verify: All tests pass
    - Verify: Coverage > 80%
    - Review: `htmlcov/index.html` for coverage report
    - **STOP HERE and review full test results before proceeding**

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

- [ ] 7. Verify dependencies and setup with uv
  - [ ] 7.1 Configure pyproject.toml dependencies
    - Add `openai-agents==0.6.1` (OpenAI Agents SDK with native MCP support)
    - Note: `mcp>=1.11.0, <2` is automatically included for Python 3.10+
    - Add `pyyaml>=6.0.0` (YAML parsing)
    - Add `pydantic>=2.0.0` (data validation)
    - Add dev dependencies: `pytest>=7.0.0`, `pytest-asyncio>=0.21.0`, `pytest-cov>=4.0.0`, `ruff`, `mypy`
    - Set `requires-python = ">=3.10"` for MCP support
    - Run `uv add openai-agents==0.6.1 pyyaml pydantic`
    - Run `uv add --dev pytest pytest-asyncio pytest-cov ruff mypy`
    - _Requirements: All_
  
  - [ ] 7.2 Test installation with uv
    - Run `uv sync` to create virtual environment and install dependencies
    - Run `uv run python -c "import agents; import shared"` to verify imports
    - Run `uv run pytest` to verify test suite runs
    - _Requirements: All_

  - [ ] **CHECKPOINT 5: Final Gate - Core Infrastructure Complete**
    - Run: `uv run pytest platform/03-intelligence/agents/shared/tests/ -v`
    - Run: `uv run ruff check platform/03-intelligence/agents/shared/`
    - Run: `uv run mypy platform/03-intelligence/agents/shared/`
    - Verify: All tests pass
    - Verify: No linting errors
    - Verify: Type checking passes
    - Verify: Coverage > 80%
    - Verify: Agent Runner works with real MCP servers
    - Verify: Contract Extractor works on real files
    - Verify: MDX Validator catches all error cases
    - **GATE: DO NOT proceed to Validator/Documentor until all checks pass**
    - **STOP HERE for final review before moving to next spec**

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
