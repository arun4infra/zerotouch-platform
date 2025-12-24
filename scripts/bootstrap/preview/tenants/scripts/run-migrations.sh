#!/bin/bash
set -euo pipefail

# ==============================================================================
# Database Migrations Script
# ==============================================================================
# Runs database migrations using Kubernetes Job
# Used by both local testing and CI workflows
# ==============================================================================

NAMESPACE="${1:-intelligence-deepagents}"

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
        - name: POSTGRES_HOST
          valueFrom:
            secretKeyRef:
              name: ide-orchestrator-db-conn
              key: POSTGRES_HOST
        - name: POSTGRES_PORT
          valueFrom:
            secretKeyRef:
              name: ide-orchestrator-db-conn
              key: POSTGRES_PORT
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: ide-orchestrator-db-conn
              key: POSTGRES_DB
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: ide-orchestrator-db-conn
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ide-orchestrator-db-conn
              key: POSTGRES_PASSWORD
        command: ["/bin/bash"]
        args:
        - -c
        - |
          echo "Waiting for PostgreSQL to be ready..."
          until pg_isready -h \$POSTGRES_HOST -p \$POSTGRES_PORT -U \$POSTGRES_USER; do
            echo "PostgreSQL not ready, waiting..."
            sleep 2
          done
          echo "PostgreSQL is ready, running migrations..."
          
          # Run each migration file in order
          for migration in /migrations/*.up.sql; do
            if [ -f "\$migration" ]; then
              echo "Running migration: \$(basename \$migration)"
              PGPASSWORD=\$POSTGRES_PASSWORD psql -h \$POSTGRES_HOST -p \$POSTGRES_PORT -U \$POSTGRES_USER -d \$POSTGRES_DB -f "\$migration"
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