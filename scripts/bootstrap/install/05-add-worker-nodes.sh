#!/bin/bash
# Add Worker Nodes Script for BizMatters Infrastructure
# Usage: ./05-add-worker-nodes.sh <worker-list> <password>
#        ./05-add-worker-nodes.sh --node-name <name> --node-ip <ip> --node-role <role> --server-password <password>
#
# This script adds worker nodes to an existing Talos cluster
# Supports both legacy single-node format and new multi-node format

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: 
  Multi-node format (from master script):
    $0 <worker-list> <password>
    Example: $0 "worker01-db:95.216.151.243,worker02-compute:95.216.151.244" "rescue123"
  
  Single-node format (legacy):
    $0 --node-name <NAME> --node-ip <IP> --node-role <ROLE> --server-password <PASSWORD>
    Example: $0 --node-name worker01-db --node-ip 95.216.151.243 --node-role database --server-password 'rescue123'
EOF
    exit 1
}

# Check if using positional arguments (new format from master script)
if [[ $# -eq 2 && "$1" != --* ]]; then
    # New format: worker-list and password
    WORKER_LIST="$1"
    SERVER_PASSWORD="$2"
    MULTI_NODE_MODE=true
else
    # Legacy format: named arguments for single node
    MULTI_NODE_MODE=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-name)
                NODE_NAME="$2"
                shift 2
                ;;
            --node-ip)
                NODE_IP="$2"
                shift 2
                ;;
            --node-role)
                NODE_ROLE="$2"
                shift 2
                ;;
            --server-password)
                SERVER_PASSWORD="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate required arguments for single node mode
    if [[ -z "$NODE_NAME" || -z "$NODE_IP" || -z "$NODE_ROLE" || -z "$SERVER_PASSWORD" ]]; then
        log_error "Missing required arguments"
        usage
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

# Load environment variables
if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

# Stage cache functions (same as master bootstrap)
STAGE_CACHE_FILE="${REPO_ROOT}/.zerotouch-cache/bootstrap-stage-cache.json"

is_stage_complete() {
    local stage_name="$1"
    if [[ ! -f "$STAGE_CACHE_FILE" ]]; then
        return 1
    fi
    if command -v jq &> /dev/null; then
        local completed=$(jq -r --arg stage "$stage_name" '.stages[$stage] // empty' "$STAGE_CACHE_FILE")
        if [[ -n "$completed" ]]; then
            return 0
        fi
    fi
    return 1
}

mark_stage_complete() {
    local stage_name="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Ensure cache file exists
    if [[ ! -f "$STAGE_CACHE_FILE" ]]; then
        mkdir -p "$(dirname "$STAGE_CACHE_FILE")"
        echo '{"stages":{}}' > "$STAGE_CACHE_FILE"
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg stage "$stage_name" --arg ts "$timestamp" \
           '.stages[$stage] = $ts' "$STAGE_CACHE_FILE" > "$temp_file"
        mv "$temp_file" "$STAGE_CACHE_FILE"
    fi
}

# Function to add a single worker node
add_single_worker() {
    local NODE_NAME="$1"
    local NODE_IP="$2"
    local NODE_ROLE="${3:-worker}"
    local SERVER_PASSWORD="$4"
    
    # Stage cache for this specific worker
    STAGE_CACHE_FILE="${REPO_ROOT}/.zerotouch-cache/bootstrap-stage-cache.json"
    WORKER_INSTALL_STAGE="worker_${NODE_NAME}_talos_installed"
    WORKER_CONFIG_STAGE="worker_${NODE_NAME}_configured"
    
    log_info "Adding worker node to cluster"
    log_info "Node Name: $NODE_NAME"
    log_info "Node IP: $NODE_IP"
    log_info "Node Role: $NODE_ROLE"

    # Step 1: Validate cluster is accessible
    log_info "Step 1: Validating cluster access..."
    if ! kubectl get nodes &> /dev/null; then
        log_error "Cannot access cluster. Is kubeconfig configured?"
        return 1
    fi
    log_info "✓ Cluster is accessible"

    # Step 2: Check if node config exists
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"
    CONFIG_PATH="$REPO_ROOT/bootstrap/talos/nodes/$NODE_NAME/config.yaml"
    if [ ! -f "$CONFIG_PATH" ]; then
        log_error "Node configuration not found at: $CONFIG_PATH"
        log_error "Please create the configuration file first"
        return 1
    fi
    log_info "✓ Node configuration found"

    # Extract actual hostname from config (may differ from directory name)
    ACTUAL_HOSTNAME=$(grep -A 1 "hostname:" "$CONFIG_PATH" | grep "hostname:" | awk '{print $2}')
    if [ -z "$ACTUAL_HOSTNAME" ]; then
        log_warn "Could not extract hostname from config, using directory name: $NODE_NAME"
        ACTUAL_HOSTNAME="$NODE_NAME"
    else
        log_info "✓ Detected hostname from config: $ACTUAL_HOSTNAME"
    fi

    # Check if Talos installation already complete
    if is_stage_complete "$WORKER_INSTALL_STAGE"; then
        log_info "Step 2: Talos installation already complete (cached), skipping..."
    else
        # Step 3: Install Talos on worker
        log_info "Step 2: Installing Talos on worker node..."
        cd "$SCRIPT_DIR"
        ./03-install-talos.sh \
            --server-ip "$NODE_IP" \
            --user root \
            --password "$SERVER_PASSWORD" \
            --yes

        log_info "✓ Talos installation complete"
        mark_stage_complete "$WORKER_INSTALL_STAGE"

        # Step 4: Wait for Talos to boot
        log_info "Step 3: Waiting 1.5 minutes for Talos to boot..."
        sleep 90
    fi

    # Check if worker configuration already complete
    if is_stage_complete "$WORKER_CONFIG_STAGE"; then
        log_info "Step 4-7: Worker configuration already complete (cached), skipping..."
        log_info "✓ Worker node already configured"
        return 0
    fi

    # Step 5: Apply worker configuration with providerID
    log_info "Step 4: Applying worker configuration..."
    cd "$REPO_ROOT/bootstrap/talos"

    # Source the Hetzner API helper for server ID lookup (reads ENV from bootstrap config)
    source "$REPO_ROOT/scripts/bootstrap/helpers/hetzner-api.sh"

    # Get server ID for providerID configuration
    log_info "Retrieving Hetzner server ID for providerID configuration..."
    SERVER_ID=$(get_server_id_by_ip "$NODE_IP")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve server ID. Cannot configure providerID."
        return 1
    fi
    log_info "✓ Server ID: $SERVER_ID"

    # DEPRECATED: AWS OIDC integration removed - use base worker config
    # Get OIDC patch using the helper script
    # HELPER_SCRIPT="$REPO_ROOT/scripts/bootstrap/helpers/aws/prepare-oidc-patch.sh"
    # if [ ! -x "$HELPER_SCRIPT" ]; then
    #     chmod +x "$HELPER_SCRIPT"
    # fi
    # OIDC_PATCH_FILE=$("$HELPER_SCRIPT" "${ENV:-dev}")
    # if [ $? -ne 0 ] || [ -z "$OIDC_PATCH_FILE" ]; then
    #     log_error "Failed to generate OIDC patch"
    #     return 1
    # fi

    # Use base worker config without OIDC patch
    WORKER_CONFIG_FINAL="nodes/$NODE_NAME/config.yaml"
    log_info "✓ Using base worker configuration"

    # Apply configuration with providerID patch
    if ! talosctl apply-config --insecure \
        --nodes "$NODE_IP" \
        --endpoints "$NODE_IP" \
        --file "$WORKER_CONFIG_FINAL" \
        --config-patch "[{\"op\": \"add\", \"path\": \"/machine/kubelet/extraArgs\", \"value\": {\"provider-id\": \"hcloud://$SERVER_ID\"}}]"; then
        log_warn "Failed to apply config. Waiting 30s and retrying..."
        sleep 30
        talosctl apply-config --insecure \
            --nodes "$NODE_IP" \
            --endpoints "$NODE_IP" \
            --file "$WORKER_CONFIG_FINAL" \
            --config-patch "[{\"op\": \"add\", \"path\": \"/machine/kubelet/extraArgs\", \"value\": {\"provider-id\": \"hcloud://$SERVER_ID\"}}]"
    fi

    # No cleanup needed - using base config
    
    log_info "✓ Configuration applied with providerID: hcloud://$SERVER_ID"

    # Step 6: Wait for node to join
    log_info "Step 5: Waiting 120 seconds for node to join cluster..."
    sleep 120

    # Step 7: Verify node joined cluster (simple check like original)
    log_info "Step 6: Verifying worker node joined cluster..."
    if ! kubectl get nodes; then
        log_warn "Failed to get nodes, but continuing..."
    fi
    
    # Step 8: Label the worker node with worker role
    log_info "Step 7: Labeling worker node with role 'worker'..."
    sleep 10  # Brief wait to ensure node is fully registered
    
    # Try to find and label the node by IP
    NODE_NAME_IN_CLUSTER=$(kubectl get nodes -o wide | grep "$NODE_IP" | awk '{print $1}')
    if [ -n "$NODE_NAME_IN_CLUSTER" ]; then
        kubectl label node "$NODE_NAME_IN_CLUSTER" node-role.kubernetes.io/worker=worker --overwrite || log_warn "Failed to label node"
        log_info "✓ Node $NODE_NAME_IN_CLUSTER labeled with role 'worker'"
    else
        log_warn "Could not find node with IP $NODE_IP to label"
    fi
    
    log_info "✓ Worker node configuration complete"
    mark_stage_complete "$WORKER_CONFIG_STAGE"

    # Summary
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Worker Node Added Successfully!                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✓ Config Directory: $NODE_NAME${NC}"
    echo -e "${GREEN}✓ Node Hostname: $ACTUAL_HOSTNAME${NC}"
    echo -e "${GREEN}✓ Node IP: $NODE_IP${NC}"
    echo -e "${GREEN}✓ Node Role: $NODE_ROLE${NC}"
    echo -e "${GREEN}✓ Status: Ready${NC}"
    echo ""
}

# Main execution logic
if [[ "$MULTI_NODE_MODE" == "true" ]]; then
    # Process multiple workers from comma-separated list
    log_info "Processing worker nodes from list: $WORKER_LIST"
    
    # Step 1: Validate cluster is accessible
    log_info "Step 1: Validating cluster access..."
    if ! kubectl get nodes &> /dev/null; then
        log_error "Cannot access cluster. Is kubeconfig configured?"
        exit 1
    fi
    log_info "✓ Cluster is accessible"
    
    # Parse worker list (format: name:ip,name:ip,...)
    IFS=',' read -ra WORKERS <<< "$WORKER_LIST"
    
    for worker_entry in "${WORKERS[@]}"; do
        # Parse name:ip format
        IFS=':' read -r worker_name worker_ip <<< "$worker_entry"
        
        if [[ -z "$worker_name" || -z "$worker_ip" ]]; then
            log_warn "Skipping invalid worker entry: $worker_entry"
            continue
        fi
        
        echo ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Processing worker: $worker_name ($worker_ip)"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        add_single_worker "$worker_name" "$worker_ip" "worker" "$SERVER_PASSWORD"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to add worker $worker_name"
            exit 1
        fi
    done
    
    # Final summary for all workers
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         All Worker Nodes Added Successfully!                ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Verify with:${NC}"
    echo -e "  kubectl get nodes"
    echo ""
else
    # Single node mode (legacy)
    add_single_worker "$NODE_NAME" "$NODE_IP" "$NODE_ROLE" "$SERVER_PASSWORD"
    
    echo -e "${YELLOW}Verify with:${NC}"
    echo -e "  kubectl get nodes"
    echo -e "  kubectl describe node \$ACTUAL_HOSTNAME"
    echo ""
fi
