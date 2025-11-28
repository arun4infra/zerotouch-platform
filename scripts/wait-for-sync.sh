#!/bin/bash
# Wait for ArgoCD applications to sync and become healthy
# Usage: ./wait-for-sync.sh [--ignore-file path/to/ignore-list.txt] [--timeout seconds]

set -e

# Default values
IGNORE_FILE=""
TIMEOUT=900
CHECK_INTERVAL=15

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ignore-file)
            IGNORE_FILE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ignore-file path] [--timeout seconds]"
            exit 1
            ;;
    esac
done

# Load ignore list
IGNORE_APPS=()
if [[ -n "$IGNORE_FILE" && -f "$IGNORE_FILE" ]]; then
    echo "Loading ignore list from: $IGNORE_FILE"
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        app=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -n "$app" ]] && IGNORE_APPS+=("$app")
    done < "$IGNORE_FILE"
    
    if [[ ${#IGNORE_APPS[@]} -gt 0 ]]; then
        echo "Ignoring OutOfSync status for: ${IGNORE_APPS[*]}"
    fi
fi
echo ""

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    echo "=== Checking application status (${ELAPSED}s / ${TIMEOUT}s) ==="
    
    APPS=$(kubectl get applications -n argocd -o json)
    TOTAL=$(echo "$APPS" | jq -r '.items | length')
    
    if [ "$TOTAL" -eq 0 ]; then
        echo "No applications found yet, waiting..."
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        continue
    fi
    
    # Build jq filter to exclude ignored apps from sync check
    IGNORE_FILTER=""
    if [ ${#IGNORE_APPS[@]} -gt 0 ]; then
        for ignore_app in "${IGNORE_APPS[@]}"; do
            IGNORE_FILTER="$IGNORE_FILTER and .metadata.name != \"$ignore_app\""
        done
    fi
    
    # Check sync status (excluding ignored apps)
    if [ -n "$IGNORE_FILTER" ]; then
        NOT_SYNCED=$(echo "$APPS" | jq "[.items[] | select(true $IGNORE_FILTER) | select(.status.sync.status != \"Synced\")] | length")
        CHECKED_TOTAL=$(echo "$APPS" | jq "[.items[] | select(true $IGNORE_FILTER)] | length")
    else
        NOT_SYNCED=$(echo "$APPS" | jq '[.items[] | select(.status.sync.status != "Synced")] | length')
        CHECKED_TOTAL=$TOTAL
    fi
    
    # Check health status (ALL apps must be healthy, even ignored ones)
    NOT_HEALTHY=$(echo "$APPS" | jq '[.items[] | select(.status.health.status != "Healthy" and .status.health.status != "Progressing")] | length')
    
    SYNCED=$((CHECKED_TOTAL - NOT_SYNCED))
    HEALTHY=$((TOTAL - NOT_HEALTHY))
    
    echo "  Apps: $TOTAL total"
    echo "  Synced: $SYNCED/$CHECKED_TOTAL (checked)"
    echo "  Healthy: $HEALTHY/$TOTAL (all)"
    
    # Show apps that are not synced or healthy
    if [ "$NOT_SYNCED" -gt 0 ] || [ "$NOT_HEALTHY" -gt 0 ]; then
        echo ""
        echo "  Waiting for:"
        
        # Show OutOfSync apps (excluding ignored)
        if [ -n "$IGNORE_FILTER" ]; then
            echo "$APPS" | jq -r "[.items[] | select(true $IGNORE_FILTER) | select(.status.sync.status != \"Synced\")] | .[].metadata.name" | while read -r app; do
                [[ -n "$app" ]] && echo "    - $app (OutOfSync)"
            done
        else
            echo "$APPS" | jq -r '[.items[] | select(.status.sync.status != "Synced")] | .[].metadata.name' | while read -r app; do
                [[ -n "$app" ]] && echo "    - $app (OutOfSync)"
            done
        fi
        
        # Show unhealthy apps
        echo "$APPS" | jq -r '.items[] | select(.status.health.status != "Healthy" and .status.health.status != "Progressing") | "\(.metadata.name) (\(.status.health.status))"' | while read -r line; do
            [[ -n "$line" ]] && echo "    - $line"
        done
    fi
    
    echo ""
    
    # Check if we're done
    if [ "$NOT_SYNCED" -eq 0 ] && [ "$NOT_HEALTHY" -eq 0 ]; then
        echo "✓ All applications synced and healthy!"
        exit 0
    fi
    
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo ""
echo "✗ Timeout waiting for applications to sync"
echo ""
echo "Final status:"
kubectl get applications -n argocd
exit 1
