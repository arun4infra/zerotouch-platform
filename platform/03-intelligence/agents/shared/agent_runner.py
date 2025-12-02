"""
Agent Runner - Thin wrapper around OpenAI Agents SDK with native MCP support.

This module provides helper functions to simplify agent creation and execution
using the OpenAI Agents SDK with MCP servers.
"""

from typing import List, Dict, Any, Optional
from pathlib import Path
import os


class MCPServerError(Exception):
    """MCP server failed to start or connect."""
    pass


class PromptLoadError(Exception):
    """Failed to load prompt from file."""
    pass


class AgentExecutionError(Exception):
    """Agent execution failed."""
    pass


async def create_agent_with_mcp(
    name: str,
    instructions: str,
    mcp_servers: List[Dict[str, Any]],
    model: str = "gpt-4o-mini"
) -> Any:
    """
    Create an agent with MCP servers using OpenAI Agents SDK.
    
    Args:
        name: Agent name
        instructions: System prompt/instructions
        mcp_servers: List of MCP server configs, each containing:
            - name: Server name
            - command: Command to run (e.g., "npx", "uvx")
            - args: Command arguments
            - env: Environment variables (optional)
        model: OpenAI model to use (default: gpt-4o-mini)
        
    Returns:
        Configured Agent instance
        
    Raises:
        MCPServerError: If MCP server fails to start
        
    Example:
        agent = await create_agent_with_mcp(
            name="Validator",
            instructions=load_prompt_from_file("..."),
            mcp_servers=[
                {
                    "name": "GitHub",
                    "command": "npx",
                    "args": ["-y", "github-mcp-server"],
                    "env": {"GITHUB_TOKEN": token}
                }
            ]
        )
    """
    try:
        from agents import Agent
        from agents.mcp import MCPServerStdio
    except ImportError as e:
        raise MCPServerError(f"Failed to import OpenAI Agents SDK: {e}")
    
    # Create and connect MCP server instances
    mcp_server_instances = []
    
    for server_config in mcp_servers:
        try:
            # Merge environment variables
            env = os.environ.copy()
            if "env" in server_config:
                env.update(server_config["env"])
            
            # Create MCP server instance
            server = MCPServerStdio(
                name=server_config["name"],
                params={
                    "command": server_config["command"],
                    "args": server_config["args"],
                    "env": env
                }
            )
            
            # Connect to MCP server
            await server.connect()
            
            mcp_server_instances.append(server)
        except Exception as e:
            raise MCPServerError(
                f"Failed to create MCP server '{server_config['name']}': {e}"
            )
    
    # Create agent with MCP servers
    try:
        agent = Agent(
            name=name,
            instructions=instructions,
            model=model,
            mcp_servers=mcp_server_instances
        )
        return agent
    except Exception as e:
        raise MCPServerError(f"Failed to create agent: {e}")


def load_prompt_from_file(path: str) -> str:
    """
    Load system prompt from file.
    
    Args:
        path: Path to prompt file (relative to repo root or absolute)
        
    Returns:
        Prompt content as string
        
    Raises:
        PromptLoadError: If file cannot be read
        
    Example:
        instructions = load_prompt_from_file(
            "platform/03-intelligence/agents/validator/prompt.md"
        )
    """
    try:
        file_path = Path(path)
        
        # If relative path, resolve from current working directory
        if not file_path.is_absolute():
            file_path = Path.cwd() / file_path
        
        # Validate path is within allowed directories
        allowed_dirs = [
            Path.cwd() / "platform" / "03-intelligence" / "agents",
        ]
        
        if not any(file_path.is_relative_to(d) for d in allowed_dirs if d.exists()):
            raise PromptLoadError(
                f"Prompt file must be in platform/03-intelligence/agents/: {path}"
            )
        
        # Read file
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        if not content.strip():
            raise PromptLoadError(f"Prompt file is empty: {path}")
        
        return content
        
    except FileNotFoundError:
        raise PromptLoadError(f"Prompt file not found: {path}")
    except PermissionError:
        raise PromptLoadError(f"Permission denied reading prompt file: {path}")
    except Exception as e:
        raise PromptLoadError(f"Failed to load prompt from {path}: {e}")


async def run_agent_task(
    agent: Any,
    task: str,
    max_iterations: int = 10
) -> str:
    """
    Run agent task with iteration limit.
    
    Args:
        agent: Configured Agent instance
        task: Task description
        max_iterations: Max tool calling iterations (default: 10)
        
    Returns:
        Agent response as string
        
    Raises:
        AgentExecutionError: If agent execution fails
        
    Example:
        result = await run_agent_task(
            agent,
            f"Validate PR #{pr_number}",
            max_iterations=15
        )
    """
    try:
        from agents import Runner
    except ImportError as e:
        raise AgentExecutionError(f"Failed to import Runner: {e}")
    
    try:
        # Run agent with task
        result = await Runner.run(
            starting_agent=agent,
            input=task,
            max_turns=max_iterations
        )
        
        # Extract response text
        if hasattr(result, "text"):
            return result.text
        elif hasattr(result, "content"):
            return result.content
        else:
            return str(result)
            
    except Exception as e:
        raise AgentExecutionError(f"Agent execution failed: {e}")
