#!/bin/bash
set -euo pipefail

# ==============================================================================
# Generate Test Environment Variables Script
# ==============================================================================
# Dynamically generates environment variables for test jobs based on service
# dependencies declared in ci/config.yaml
# ==============================================================================

SERVICE_NAME="${1:-}"
NAMESPACE="${2:-}"

if [[ -z "$SERVICE_NAME" || -z "$NAMESPACE" ]]; then
    echo "Usage: $0 <service-name> <namespace>" >&2
    exit 1
fi

# Read internal dependencies from config
if [[ ! -f "ci/config.yaml" ]]; then
    echo "Error: ci/config.yaml not found" >&2
    exit 1
fi

INTERNAL_DEPS=$(yq eval '.dependencies.internal[]' ci/config.yaml 2>/dev/null | tr '\n' ' ' || echo "")

generate_env_vars() {
    local env_vars=""
    
    if [[ -n "$INTERNAL_DEPS" ]]; then
        # PostgreSQL environment variables
        if echo "$INTERNAL_DEPS" | grep -q "postgres"; then
            env_vars+="        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-db-conn\"
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-db-conn\"
              key: POSTGRES_PASSWORD
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-db-conn\"
              key: POSTGRES_DB
        - name: POSTGRES_HOST
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-db-conn\"
              key: POSTGRES_HOST
        - name: POSTGRES_PORT
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-db-conn\"
              key: POSTGRES_PORT
"
        fi
        
        # Redis/Dragonfly environment variables
        if echo "$INTERNAL_DEPS" | grep -qE "(redis|dragonfly)"; then
            env_vars+="        - name: DRAGONFLY_HOST
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-cache-conn\"
              key: DRAGONFLY_HOST
        - name: DRAGONFLY_PORT
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-cache-conn\"
              key: DRAGONFLY_PORT
        - name: DRAGONFLY_PASSWORD
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-cache-conn\"
              key: DRAGONFLY_PASSWORD
"
        fi
        
        # NATS environment variables
        if echo "$INTERNAL_DEPS" | grep -qE "(nats|nats-streams)"; then
            env_vars+="        - name: NATS_URL
          value: \"nats://nats.nats.svc:4222\"
"
        fi
    fi
    
    # Add standard test environment variables
    env_vars+="        - name: TEST_ENV
          value: \"integration\"
        - name: SERVICE_NAME
          value: \"$SERVICE_NAME\"
        - name: NAMESPACE
          value: \"$NAMESPACE\""
    
    echo "$env_vars"
}

# Generate and output environment variables
generate_env_vars