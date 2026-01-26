#!/bin/bash
set -euo pipefail

# ==============================================================================
# Database Migrations Script
# ==============================================================================
# Runs database migrations using Kubernetes Job
# Used by both local testing and CI workflows
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

main() {
    log_info "Running database migrations..."
    
    # Read service name and namespace from config
    CONFIG_FILE="${SERVICE_ROOT:-$(pwd)}/ci/config.yaml"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    
    SERVICE_NAME=$(yq eval '.service.name' "$CONFIG_FILE")
    NAMESPACE=$(yq eval '.service.namespace' "$CONFIG_FILE")
    
    if [[ -z "$SERVICE_NAME" || "$SERVICE_NAME" == "null" ]]; then
        log_error "Service name not found in config"
        return 1
    fi
    
    if [[ -z "$NAMESPACE" || "$NAMESPACE" == "null" ]]; then
        log_error "Namespace not found in config"
        return 1
    fi
    
    log_info "Using service: $SERVICE_NAME"
    log_info "Using namespace: $NAMESPACE"
    
    # Create ConfigMap with migration files
    kubectl create configmap migration-files -n $NAMESPACE \
        --from-file=migrations/ \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Run migrations using a simple job
    MIGRATION_JOB="migration-job-$(date +%s)"
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $MIGRATION_JOB
  namespace: $NAMESPACE
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: postgres:15
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: ${SERVICE_NAME}-db-conn
              key: DATABASE_URL
        command: ["/bin/bash"]
        args:
        - -c
        - |
          echo "Waiting for PostgreSQL to be ready..."
          # Extract connection details from DATABASE_URL
          POSTGRES_USER=\$(echo "\$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')
          POSTGRES_HOST=\$(echo "\$DATABASE_URL" | sed -n 's|.*@\([^:/]*\).*|\1|p')
          POSTGRES_PORT=\$(echo "\$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
          
          until pg_isready -h "\$POSTGRES_HOST" -p "\$POSTGRES_PORT" -U "\$POSTGRES_USER"; do
            echo "PostgreSQL not ready, waiting..."
            sleep 2
          done
          echo "PostgreSQL is ready, running migrations..."
          
          # Run each migration file in order
          for migration in /migrations/*.up.sql; do
            if [ -f "\$migration" ]; then
              echo "Running migration: \$(basename \$migration)"
              psql "\$DATABASE_URL" -f "\$migration"
            fi
          done
          
          echo "Migrations completed successfully!"
        volumeMounts:
        - name: migrations
          mountPath: /migrations
      volumes:
      - name: migrations
        configMap:
          name: migration-files
      restartPolicy: Never
  backoffLimit: 0
EOF

    # Wait for migration job to complete
    log_info "Waiting for migration job to complete..."
    kubectl wait --for=condition=complete --timeout=120s job/$MIGRATION_JOB -n $NAMESPACE || {
        log_error "Migration job failed or timed out"
        kubectl logs -l job-name=$MIGRATION_JOB -n $NAMESPACE || true
        return 1
    }
    
    # Show migration logs
    kubectl logs -l job-name=$MIGRATION_JOB -n $NAMESPACE
    
    # Clean up migration job
    kubectl delete job $MIGRATION_JOB -n $NAMESPACE --ignore-not-found=true
    
    log_success "Database migrations completed"
}

main "$@"