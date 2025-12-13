FROM python:3.11-slim

WORKDIR /app

# Install uv for package management
RUN pip install --no-cache-dir uv

# Install the mcp-server-qdrant package with pinned fastmcp version to avoid ctx bug
RUN uv pip install --system --no-cache-dir "mcp-server-qdrant==0.6.2" "fastmcp<2.0.0"

# Expose the default port for SSE transport
EXPOSE 8000

# Set environment variables with defaults that can be overridden at runtime
ENV QDRANT_URL=""
ENV QDRANT_API_KEY=""
ENV COLLECTION_NAME="default-collection"
ENV EMBEDDING_MODEL="sentence-transformers/all-MiniLM-L6-v2"

# Run the server with streamable-http transport (compatible with Kagent)
CMD uvx mcp-server-qdrant --transport streamable-http
