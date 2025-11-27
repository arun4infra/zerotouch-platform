FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Copy artifacts (templates and scripts) from root context
# Note: This assumes build context is root of repo, or we copy them in CI
# For local dev within services/docs-mcp context, we might need a different approach
# But standard pattern is to copy what's needed. 
# We will assume the build context allows access or we copy them into the service dir before build.
# For now, let's assume we copy them to a specific location expected by the app.

# Expose port for MCP (SSE) and Metrics
EXPOSE 8080

# Environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

# Run the server
CMD ["python", "main.py"]
