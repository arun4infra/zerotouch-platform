#!/bin/bash
# Verify External Secrets Operator (ESO) and Force Re-sync
# Usage: ./11-verify-eso.sh
#
# This script:
# 1. Verifies ESO credentials exist
# 2. Verifies ClusterSecretStore is valid
# 3. Forces re-sync of all ExternalSecrets (to handle timing issues)
# 4. Waits and verifies all ExternalSecrets are SecretSynced

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MAX_WAIT=100  # 100 seconds max wait for secrets to sync
CHECK_INTERVAL=10

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi
        exitCode=$?
        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done
    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Verifying External Secrets Operator                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check ESO credentials
echo -e "${BLUE}Step 1: Checking ESO credentials...${NC}"
if ! kubectl_retry get secret aws-access-token -n external-secrets &>/dev/null; then
    echo -e "${RED}✗ AWS credentials not found in external-secrets namespace${NC}"
    echo -e "${BLUE}ℹ  Run: ./scripts/bootstrap/install/07-inject-eso-secrets.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ESO credentials found${NC}"
echo ""

# Step 2: Wait for ClusterSecretStore to be valid
echo -e "${BLUE}Step 2: Waiting for ClusterSecretStore to be valid...${NC}"
ELAPSED=0
while [ $ELAPSED -lt 120 ]; do
    STORE_STATUS=$(kubectl_retry get clustersecretstore aws-parameter-store -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    STORE_REASON=$(kubectl_retry get clustersecretstore aws-parameter-store -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
    
    if [ "$STORE_STATUS" = "True" ]; then
        echo -e "${GREEN}✓ ClusterSecretStore 'aws-parameter-store' is valid${NC}"
        break
    fi
    
    echo -e "${YELLOW}  Waiting... Status: $STORE_REASON${NC}"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ "$STORE_STATUS" != "True" ]; then
    echo -e "${RED}✗ ClusterSecretStore not ready after 2 minutes${NC}"
    kubectl_retry get clustersecretstore aws-parameter-store -o yaml
    exit 1
fi
echo ""

# Step 3: Force re-sync all ExternalSecrets
echo -e "${BLUE}Step 3: Force re-syncing all ExternalSecrets...${NC}"
EXTERNAL_SECRETS=$(kubectl get externalsecrets -A -o json 2>/dev/null)
TOTAL=$(echo "$EXTERNAL_SECRETS" | jq -r '.items | length')

if [ "$TOTAL" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No ExternalSecrets found - skipping${NC}"
    exit 0
fi

echo -e "${BLUE}   Found $TOTAL ExternalSecrets${NC}"

# Annotate each to trigger re-sync
SYNC_TIMESTAMP=$(date +%s)
while IFS='|' read -r namespace name; do
    # Skip resources without a namespace (e.g., ClusterSecretStore)
    if [ -z "$namespace" ] || [ "$namespace" = "null" ]; then
        continue
    fi
    
    if kubectl annotate externalsecret "$name" -n "$namespace" \
        force-sync="$SYNC_TIMESTAMP" --overwrite 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} Triggered: $namespace/$name"
    else
        echo -e "   ${YELLOW}⚠️${NC} Failed to trigger: $namespace/$name"
    fi
done < <(echo "$EXTERNAL_SECRETS" | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)"')
echo ""

# Step 4: Wait and verify all ExternalSecrets are synced
echo -e "${BLUE}Step 4: Waiting for ExternalSecrets to sync (max ${MAX_WAIT}s)...${NC}"
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    
    # Get current status of all ExternalSecrets
    SECRETS_JSON=$(kubectl get externalsecrets -A -o json 2>/dev/null)
    
    TOTAL=$(echo "$SECRETS_JSON" | jq -r '.items | length')
    SYNCED=$(echo "$SECRETS_JSON" | jq -r '[.items[] | select(.status.conditions[0].reason == "SecretSynced")] | length')
    FAILED=$(echo "$SECRETS_JSON" | jq -r '[.items[] | select(.status.conditions[0].reason == "SecretSyncedError")] | length')
    PENDING=$((TOTAL - SYNCED - FAILED))
    
    echo -e "   [${ELAPSED}s] Total: $TOTAL | ${GREEN}Synced: $SYNCED${NC} | ${RED}Failed: $FAILED${NC} | Pending: $PENDING"
    
    # All synced successfully
    if [ "$SYNCED" -eq "$TOTAL" ]; then
        echo ""
        echo -e "${GREEN}✓ All $TOTAL ExternalSecrets synced successfully!${NC}"
        echo ""
        kubectl get externalsecrets -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].reason,READY:.status.conditions[0].status'
        echo ""
        exit 0
    fi
    
    # Early exit: If only repo-* ExternalSecrets are pending/failed, we can stop waiting
    if [ "$PENDING" -gt 0 ] || [ "$FAILED" -gt 0 ]; then
        # Check if all pending/failed are tenant repositories
        NON_REPO_PENDING=$(echo "$SECRETS_JSON" | jq '[.items[] | select(.status.conditions[0].reason != "SecretSynced") | select(.metadata.name | startswith("repo-") | not)] | length')
        
        if [ "$NON_REPO_PENDING" -eq 0 ]; then
            echo ""
            echo -e "${BLUE}ℹ  Only tenant repository ExternalSecrets are pending/failed${NC}"
            echo -e "${GREEN}✓ All core platform ExternalSecrets synced - continuing${NC}"
            break
        fi
    fi
done

# Final status check
echo ""
echo -e "${YELLOW}⚠️  Timeout reached. Current ExternalSecret status:${NC}"
kubectl get externalsecrets -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].reason,MESSAGE:.status.conditions[0].message'
echo ""

# Check if any critical secrets failed
FAILED_SECRETS_JSON=$(kubectl get externalsecrets -A -o json | jq '[.items[] | select(.status.conditions[0].reason == "SecretSyncedError")]')
FAILED_COUNT=$(echo "$FAILED_SECRETS_JSON" | jq 'length')

if [ "$FAILED_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  $FAILED_COUNT ExternalSecrets failed to sync:${NC}"
    echo "$FAILED_SECRETS_JSON" | jq -r '.[] | "  - \(.metadata.namespace)/\(.metadata.name): \(.status.conditions[0].message)"'
    
    # Check if all failures are tenant repositories (repo-*)
    NON_REPO_COUNT=$(echo "$FAILED_SECRETS_JSON" | jq '[.[] | select(.metadata.name | startswith("repo-") | not)] | length')
    
    if [ "$NON_REPO_COUNT" -eq 0 ]; then
        echo ""
        echo -e "${BLUE}ℹ  All failures are tenant repository credentials (expected in preview/testing)${NC}"
        echo -e "${GREEN}✓ Core platform ExternalSecrets are working${NC}"
    else
        echo ""
        echo -e "${RED}✗ Critical ExternalSecrets are failing (not just tenant repositories)${NC}"
        echo -e "${BLUE}ℹ  Check SSM parameters exist: aws ssm get-parameters-by-path --path /zerotouch/prod${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ ESO verification complete${NC}"
exit 0
