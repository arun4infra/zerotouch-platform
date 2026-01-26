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
CONFIG_FILE="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: ci/config.yaml not found at $CONFIG_FILE" >&2
    exit 1
fi

INTERNAL_DEPS=$(yq eval '.dependencies.internal[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
EXTERNAL_DEPS=$(yq eval '.dependencies.external[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
ALL_DEPS="$INTERNAL_DEPS $EXTERNAL_DEPS"

generate_env_vars() {
    local env_vars=""
    
    if [[ -n "$ALL_DEPS" ]]; then
        # PostgreSQL environment variables (check both internal and external deps)
        if echo "$ALL_DEPS" | grep -qE "(postgres|neon-db)"; then
            # Check if secret has DATABASE_URL or individual keys
            DATABASE_URL_CHECK=$(kubectl get secret "$SERVICE_NAME-db-conn" -n "$NAMESPACE" -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null || echo "")
            if [[ -n "$DATABASE_URL_CHECK" ]]; then
                # Use DATABASE_URL (for services like ide-orchestrator with external Neon DB)
                env_vars+="        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: \"$SERVICE_NAME-db-conn\"
              key: DATABASE_URL
"
            else
                # Use individual keys (for services like identity-service, ide-orchestrator)
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
          value: \"$NAMESPACE\"
        - name: PYTHONPATH
          value: \"/app\""
    
    echo "$env_vars"
}

# Generate and output environment variables
generate_env_vars