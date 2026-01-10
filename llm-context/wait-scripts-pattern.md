# Wait Scripts Pattern Guide

This document defines the consistent logging pattern that all wait scripts in the platform should follow for debugging visibility.

## Core Pattern Requirements

All wait scripts MUST implement these elements for consistent debugging experience:

### 1. Continuous Status Headers
```bash
echo -e "${BLUE}=== Checking [Resource] status (${ELAPSED}s / ${TIMEOUT}s) ===${NC}"
```
- Shows every poll interval (not just on status changes)
- Includes elapsed time and timeout for progress tracking
- Uses consistent format across all wait scripts

### 2. Progress Indicators
```bash
echo -e "${GREEN}✓ Resource ready${NC}"
echo -e "${YELLOW}⏳ Waiting for resource...${NC}"
echo -e "${RED}⚠️ Resource in error state${NC}"
```
- Use consistent emoji symbols: ✓ (ready), ⏳ (waiting), ⚠️ (warning/error)
- Color coding: GREEN for success, YELLOW for waiting, RED for errors
- Clear, descriptive status messages

### 3. Resource Status Display
```bash
echo -e "${BLUE}Current [Resource] status:${NC}"
kubectl get [resource] [name] -n [namespace] --no-headers 2>/dev/null || echo "   Resource not found"
```
- Show actual Kubernetes resource status each iteration
- Use custom columns for better visibility when needed
- Handle missing resources gracefully
- Include related resources (services, pods, etc.) when relevant

### 4. Detailed Diagnostics on Issues
```bash
# Show not ready items with details
echo -e "${YELLOW}Not ready [resources]:${NC}"
for item in "${NOT_READY_ITEMS[@]}"; do
    echo -e "  - $item: [status/reason]"
    # Show additional diagnostic info
done
```
- List specific items that are not ready
- Include status/phase information
- Show relevant error messages or conditions
- Limit output to prevent log spam (e.g., head -3)

### 5. Comprehensive Timeout Diagnostics
```bash
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: [Resource] not ready after ${TIMEOUT}s           ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

echo -e "${YELLOW}=== DIAGNOSTICS ===${NC}"
# Show detailed resource status
# Show related logs
# Show debug commands
```
- Clear timeout indication with visual separator
- Comprehensive diagnostic information
- Suggested debug commands for manual investigation

## Example Implementation

Reference implementations following this pattern:
- `wait-for-gateway.sh` - Gateway infrastructure provisioning
- `12a-wait-apps-healthy.sh` - ArgoCD applications health
- `09a-wait-argocd-pods.sh` - Pod readiness checking
- `wait-for-pods.sh` - Multi-namespace pod waiting

## Color Standards

```bash
RED='\033[0;31m'      # Errors, failures, timeouts
GREEN='\033[0;32m'    # Success, ready states
YELLOW='\033[1;33m'   # Waiting, warnings, progress
BLUE='\033[0;34m'     # Information, headers, diagnostics
NC='\033[0m'          # No color (reset)
```

## Debugging Benefits

This consistent pattern provides:
- **Real-time visibility**: Continuous status updates show progress
- **Issue identification**: Detailed diagnostics help identify problems quickly
- **Consistent experience**: Same logging format across all wait scripts
- **Troubleshooting support**: Clear debug commands and resource status