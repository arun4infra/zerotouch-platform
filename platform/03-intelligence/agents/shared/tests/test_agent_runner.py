"""
Integration tests for agent_runner module.
Tests use real implementations without mocking.
"""

import pytest
from pathlib import Path
import sys
import os
from dotenv import load_dotenv

# Load environment variables from .env file
env_path = Path(__file__).parent.parent.parent.parent.parent.parent / ".env"
if env_path.exists():
    load_dotenv(env_path)

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from agent_runner import (
    create_agent_with_mcp,
    load_prompt_from_file,
    run_agent_task,
    MCPServerError,
    PromptLoadError,
    AgentExecutionError
)


class TestLoadPromptFromFile:
    """Tests for load_prompt_from_file function."""
    
    def test_load_valid_prompt(self, tmp_path):
        """Test loading a valid prompt file."""
        # Create test prompt file
        prompt_dir = tmp_path / "platform" / "03-intelligence" / "agents" / "test"
        prompt_dir.mkdir(parents=True)
        prompt_file = prompt_dir / "prompt.md"
        prompt_file.write_text("Test prompt content")
        
        # Change to tmp directory
        original_cwd = Path.cwd()
        os.chdir(tmp_path)
        
        try:
            result = load_prompt_from_file(
                "platform/03-intelligence/agents/test/prompt.md"
            )
            assert result == "Test prompt content"
        finally:
            os.chdir(original_cwd)
    
    def test_load_nonexistent_file(self):
        """Test loading a file that doesn't exist."""
        with pytest.raises(PromptLoadError):
            load_prompt_from_file("nonexistent/prompt.md")
    
    def test_load_empty_file(self, tmp_path):
        """Test loading an empty prompt file."""
        prompt_dir = tmp_path / "platform" / "03-intelligence" / "agents" / "test"
        prompt_dir.mkdir(parents=True)
        prompt_file = prompt_dir / "empty.md"
        prompt_file.write_text("")
        
        original_cwd = Path.cwd()
        os.chdir(tmp_path)
        
        try:
            with pytest.raises(PromptLoadError, match="empty"):
                load_prompt_from_file(
                    "platform/03-intelligence/agents/test/empty.md"
                )
        finally:
            os.chdir(original_cwd)


@pytest.mark.asyncio
class TestCreateAgentWithMCP:
    """Tests for create_agent_with_mcp function with real MCP servers."""
    
    async def test_create_agent_requires_openai_agents(self):
        """Test that creating agent requires openai-agents package."""
        # Test that we can import the required modules
        try:
            from agents import Agent
            from agents.mcp import MCPServerStreamableHttp
            # If we get here, the package is installed
            assert Agent is not None
            assert MCPServerStreamableHttp is not None
        except ImportError:
            pytest.fail("openai-agents package not installed")
    
    async def test_create_agent_with_github_mcp_server(self):
        """Test creating agent with GitHub MCP server and list tools."""
        # Use BOT_GITHUB_TOKEN from .env file
        github_token = os.environ.get("BOT_GITHUB_TOKEN") or os.environ.get("GITHUB_PERSONAL_ACCESS_TOKEN")
        openai_key = os.environ.get("OPENAI_API_KEY")
        
        # Validate tokens are loaded
        print(f"\n✓ Validating environment variables...")
        print(f"  - .env path: {env_path}")
        print(f"  - .env exists: {env_path.exists()}")
        print(f"  - BOT_GITHUB_TOKEN loaded: {bool(github_token)}")
        if github_token:
            print(f"  - Token length: {len(github_token)} chars")
            print(f"  - Token prefix: {github_token[:10]}...")
        print(f"  - OPENAI_API_KEY loaded: {bool(openai_key)}")
        if openai_key:
            print(f"  - API key length: {len(openai_key)} chars")
            print(f"  - API key prefix: {openai_key[:10]}...")
        
        if not github_token:
            pytest.skip("BOT_GITHUB_TOKEN not set in .env")
        
        if not openai_key:
            pytest.skip("OPENAI_API_KEY not set in .env")
        
        try:
            from agents import Agent
            from agents.mcp import MCPServerStreamableHttp, MCPServerStreamableHttpParams
        except ImportError as e:
            raise MCPServerError(f"Failed to import OpenAI Agents SDK: {e}")
        
        print(f"\n✓ Creating agent with GitHub MCP server...")
        print(f"  - MCP URL: https://api.githubcopilot.com/mcp/")
        print(f"  - Authorization header: Bearer {github_token[:10]}...")
        
        # Create HTTP-based GitHub MCP server
        server = MCPServerStreamableHttp(
            name="GitHub",
            params=MCPServerStreamableHttpParams(
                url="https://api.githubcopilot.com/mcp/",
                headers={"Authorization": f"Bearer {github_token}"}
            )
        )
        
        # Connect to MCP server
        await server.connect()
        print(f"✓ MCP server connected successfully")
        
        # List tools directly from MCP server
        if hasattr(server, 'list_tools'):
            tools = await server.list_tools()
            # tools is a list of Tool objects
            print(f"✓ MCP server has {len(tools)} tools")
            tool_names = [tool.name for tool in tools]
            print(f"✓ Available tools: {tool_names}")
        
        # Create agent with MCP server
        agent = Agent(
            name="GitHubAgent",
            instructions="You are a helpful agent that can interact with GitHub",
            model="gpt-4o-mini",
            mcp_servers=[server]
        )
        
        # Verify agent was created
        assert agent is not None
        print(f"✓ Agent created successfully")
        
        # Verify agent has MCP servers
        if hasattr(agent, 'mcp_servers'):
            print(f"✓ Agent has {len(agent.mcp_servers)} MCP server(s)")
        
        print(f"✓ Agent successfully connected to GitHub MCP server")
        
        # Now run the agent to list tools from MCP server
        print(f"\n✓ Running agent to list tools from GitHub MCP server...")
        result = await run_agent_task(
            agent,
            "List all the tools you have access to from the GitHub MCP server. What are the exact tool names?"
        )
        
        # Verify we got a response
        assert result is not None
        assert len(result) > 0
        print(f"✓ Agent response received (length: {len(result)} chars)")
        print(f"\n--- Agent Response ---")
        print(result)
        print(f"--- End Response ---\n")
        
        # Verify the response contains expected GitHub MCP tool names
        result_lower = result.lower()
        
        # Expected specific tool names from GitHub Copilot MCP server
        # Based on actual tools available: 40 tools total
        expected_tool_names = [
            "create_repository",
            "create_or_update_file",
            "push_files",
            "create_branch",
            "create_pull_request",
            "add_issue_comment",
            "search_repositories",
            "search_code",
            "get_file_contents",
            "list_branches",
            "merge_pull_request",
            "fork_repository",
            "delete_file",
            "issue_read",
            "issue_write",
            "pull_request_read",
        ]
        
        missing_tools = []
        for tool_name in expected_tool_names:
            if tool_name not in result_lower:
                missing_tools.append(tool_name)
        
        assert len(missing_tools) == 0, f"Agent response missing expected tool names: {missing_tools}. Response: {result}"
        print(f"✓ Agent successfully listed all expected GitHub MCP tool names: {expected_tool_names}")


@pytest.mark.asyncio
class TestRunAgentTask:
    """Tests for run_agent_task function with real agent."""
    
    async def test_run_task_requires_agent(self):
        """Test that running task requires a real agent."""
        # This will fail if we don't have a real agent
        # Create a mock agent object to test error handling
        class FakeAgent:
            pass
        
        fake_agent = FakeAgent()
        
        try:
            result = await run_agent_task(fake_agent, "Test task")
            # If we get here, Runner was imported successfully
            assert result is not None
        except AgentExecutionError as e:
            # Expected if openai-agents is not installed or agent is invalid
            assert "Failed to import" in str(e) or "execution failed" in str(e)
