FROM python:3.12-slim

WORKDIR /app

# Install kubectl
RUN apt-get update && apt-get install -y curl && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Python dependencies
RUN pip install requests pytest

# Copy validation scripts
COPY 02-validate-test-endpoint.py /app/
COPY 03-validate-gateway-config.py /app/
COPY 04-validate-platform-auth.py /app/

# Install additional dependencies for gateway config validation
RUN pip install pyyaml

# Default CMD - can be overridden by shell scripts
CMD ["python", "--version"]