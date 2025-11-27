import os
import logging
import asyncio
from mcp.server.fastmcp import FastMCP
from prometheus_client import start_http_server

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("docs-mcp")

# Initialize FastMCP server
mcp = FastMCP("docs-mcp")

# Import tools
from tools.validation import register_validation_tools
from tools.creation import register_creation_tools
from tools.github import register_github_tools
from tools.qdrant import register_qdrant_tools

@mcp.tool()
async def echo(message: str) -> str:
    """
    Echo back a message. Useful for testing connectivity.
    """
    logger.info(f"Echo tool called with: {message}")
    return f"Echo: {message}"

def main():
    """Main entrypoint for the docs-mcp server."""
    try:
        # Start Prometheus metrics server on port 8000 (separate from MCP if needed, or same)
        # For simplicity in K8s, we often run metrics on a separate port or path.
        # FastMCP runs on SSE/Stdio. If running over SSE with uvicorn, it handles HTTP.
        # Let's assume FastMCP's run method handles the server.
        
        logger.info("Starting docs-mcp server...")
        
        # Register tools
        register_validation_tools(mcp)
        register_creation_tools(mcp)
        register_github_tools(mcp)
        register_qdrant_tools(mcp)
        
        # Run the server
        # In production, we might use 'mcp run main:mcp' but for now calling run() directly
        mcp.run()
        
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        raise

if __name__ == "__main__":
    main()
