#!/bin/bash
set -e

# Hetzner Rescue Mode Automation Script
# Enables rescue mode for all configured servers and updates talos-values.yaml
#
# Prerequisites:
# - HETZNER_API_TOKEN environment variable must be set
# - jq must be installed
# - yq must be installed (optional - will use sed if not available)
#
# Usage:
#   export HETZNER_API_TOKEN="your-api-token"
#   ./scripts/bootstrap/00-enable-rescue-mode.sh [ENV] [-y|--yes]
#
# Arguments:
#   ENV - Environment name (default: dev)
#   -y, --yes - Skip confirmation prompt

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPERS_DIR="$SCRIPT_DIR/helpers"
ENV="${1:-dev}"
AUTO_YES=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        *)
            ENV="$arg"
            ;;
    esac
done

# Fetch tenant configuration from private repository
source "$HELPERS_DIR/fetch-tenant-config.sh" "$ENV"
VALUES_FILE="$TENANT_CONFIG_FILE"

HETZNER_API_URL="https://api.hetzner.cloud/v1"

# Function to print colored messages (all output to stderr to not interfere with function returns)
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${BLUE}==>${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Auto-load .env if it exists
if [[ -f "$REPO_ROOT/.env" ]] && [[ -z "$HETZNER_API_TOKEN" ]]; then
    source "$REPO_ROOT/.env"
fi

# Check prerequisites
log_info "════════════════════════════════════════════════════════"
log_info "Hetzner Rescue Mode Automation"
log_info "Environment: $ENV"
log_info "════════════════════════════════════════════════════════"

if [[ -z "$HETZNER_API_TOKEN" ]]; then
    log_error "HETZNER_API_TOKEN environment variable is not set"
    echo ""
    echo "Please set your Hetzner API token:"
    echo "  export HETZNER_API_TOKEN=\"your-api-token-here\""
    echo ""
    echo "Get your API token from: https://console.hetzner.cloud/projects"
    exit 1
fi

if ! command_exists jq; then
    log_error "jq is not installed"
    echo "Install jq: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

if ! command_exists yq; then
    log_warn "yq is not installed - will use sed for YAML updates"
    log_warn "For better YAML handling, install yq: brew install yq"
    USE_SED=true
else
    USE_SED=false
fi

if [[ ! -f "$VALUES_FILE" ]]; then
    log_error "Values file not found: $VALUES_FILE"
    exit 1
fi

log_success "Prerequisites checked"

# Function to make Hetzner API call
hetzner_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
            -H "Authorization: Bearer $HETZNER_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$HETZNER_API_URL$endpoint"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer $HETZNER_API_TOKEN" \
            "$HETZNER_API_URL$endpoint"
    fi
}

# Function to get server ID by IP address
get_server_id_by_ip() {
    local ip="$1"

    log_info "Looking up server ID for IP: $ip"

    local servers=$(hetzner_api "GET" "/servers")
    local server_id=$(echo "$servers" | jq -r ".servers[] | select(.public_net.ipv4.ip == \"$ip\") | .id")

    if [[ -z "$server_id" || "$server_id" == "null" ]]; then
        log_error "Could not find server with IP: $ip"
        log_info "Available servers:"
        echo "$servers" | jq -r '.servers[] | "\(.id): \(.name) - \(.public_net.ipv4.ip)"' >&2
        return 1
    fi

    echo "$server_id"
}

# Function to enable rescue mode for a server
enable_rescue_mode() {
    local server_id="$1"
    local server_name="$2"

    log_step "Enabling rescue mode for server: $server_name (ID: $server_id)"

    local response=$(hetzner_api "POST" "/servers/$server_id/actions/enable_rescue" '{"type":"linux64"}')

    # Check for errors
    local error_msg=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$error_msg" ]]; then
        log_error "Failed to enable rescue mode: $error_msg"
        log_error "Full API response:"
        echo "$response" | jq '.' >&2
        return 1
    fi

    # Extract root password
    local root_password=$(echo "$response" | jq -r '.root_password')

    if [[ -z "$root_password" || "$root_password" == "null" ]]; then
        log_error "Failed to get root password from API response"
        echo "$response" | jq '.' >&2
        return 1
    fi

    log_success "Rescue mode enabled"
    echo -e "  ${CYAN}Root Password:${NC} $root_password" >&2

    echo "$root_password"
}

# Function to reboot server
reboot_server() {
    local server_id="$1"
    local server_name="$2"

    log_step "Rebooting server: $server_name (ID: $server_id)"

    local response=$(hetzner_api "POST" "/servers/$server_id/actions/reboot" '{}')

    # Check for errors
    local error_msg=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$error_msg" ]]; then
        log_error "Failed to reboot server: $error_msg"
        log_error "Full API response:"
        echo "$response" | jq '.' >&2
        return 1
    fi

    local action_id=$(echo "$response" | jq -r '.action.id')
    log_success "Reboot initiated (action ID: $action_id)"
}

# Function to update YAML file with new password
update_yaml_password() {
    local node_type="$1"  # "controlplane" or "worker"
    local node_name="$2"
    local new_password="$3"

    log_step "Updating $VALUES_FILE with new password for $node_name"

    if [[ "$USE_SED" == "true" ]]; then
        # Create backup
        cp "$VALUES_FILE" "${VALUES_FILE}.bak"

        # Use awk for context-aware password replacement
        if [[ "$node_type" == "controlplane" ]]; then
            # For controlplane, replace the first rescue_password
            awk -v pwd="$new_password" '
                BEGIN { found=0 }
                /rescue_password:/ && found==0 {
                    print "  rescue_password: \"" pwd "\""
                    found=1
                    next
                }
                { print }
            ' "$VALUES_FILE" > "${VALUES_FILE}.tmp" && mv "${VALUES_FILE}.tmp" "$VALUES_FILE"
        else
            # For workers, find the worker by IP and replace password after it
            local node_ip=$(grep -A 5 "name: $node_name" "$VALUES_FILE" | grep "ip:" | head -1 | awk '{print $2}' | tr -d '"')
            awk -v ip="$node_ip" -v pwd="$new_password" '
                /ip:/ && $2 == "\"" ip "\"" { in_section=1 }
                /rescue_password:/ && in_section==1 {
                    print "    rescue_password: \"" pwd "\""
                    in_section=0
                    next
                }
                { print }
            ' "$VALUES_FILE" > "${VALUES_FILE}.tmp" && mv "${VALUES_FILE}.tmp" "$VALUES_FILE"
        fi

        log_success "Password updated in YAML file (backup: ${VALUES_FILE}.bak)"
    else
        # Use yq for more precise YAML manipulation
        if [[ "$node_type" == "controlplane" ]]; then
            yq eval ".controlplane.rescue_password = \"$new_password\"" -i "$VALUES_FILE"
        else
            # For workers, find the worker by name
            local worker_index=$(yq eval ".workers[] | select(.name == \"$node_name\") | key" "$VALUES_FILE")
            yq eval ".workers[$worker_index].rescue_password = \"$new_password\"" -i "$VALUES_FILE"
        fi

        log_success "Password updated in YAML file using yq"
    fi
    
    # Push changes to tenant repository
    "$HELPERS_DIR/update-tenant-config.sh" "$VALUES_FILE" "Update rescue password for $node_name ($ENV)"
}

# Function to process a single server
process_server() {
    local server_ip="$1"
    local server_name="$2"
    local node_type="$3"  # "controlplane" or "worker"

    echo "" >&2
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Processing: $server_name ($server_ip)"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Get server ID
    local server_id=$(get_server_id_by_ip "$server_ip")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    log_success "Server ID: $server_id"

    # Enable rescue mode
    local root_password=$(enable_rescue_mode "$server_id" "$server_name")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Reboot server
    reboot_server "$server_id" "$server_name"
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Update YAML file
    update_yaml_password "$node_type" "$server_name" "$root_password"

    log_success "Server $server_name is rebooting into rescue mode"
}

# Main execution
echo "" >&2
log_step "Reading configuration from: $VALUES_FILE"

# Parse YAML file to get server IPs
# Using grep/awk for simple parsing (works without yq)
CONTROLPLANE_IP=$(grep -A 10 "^controlplane:" "$VALUES_FILE" | grep "ip:" | head -1 | awk '{print $2}' | tr -d '"')
CONTROLPLANE_NAME=$(grep -A 10 "^controlplane:" "$VALUES_FILE" | grep "name:" | head -1 | awk '{print $2}' | tr -d '"')

log_info "Control Plane: $CONTROLPLANE_NAME ($CONTROLPLANE_IP)"

# Get worker IPs
WORKER_IPS=$(grep -A 5 "  - name:" "$VALUES_FILE" | grep "ip:" | awk '{print $2}' | tr -d '"')
WORKER_NAMES=$(grep -A 5 "^workers:" "$VALUES_FILE" | grep "  - name:" | awk '{print $3}' | tr -d '"')

echo "" >&2
log_info "Workers:"
paste <(echo "$WORKER_NAMES") <(echo "$WORKER_IPS") | while read -r name ip; do
    log_info "  - $name ($ip)"
done

echo "" >&2
if [[ "$AUTO_YES" == "false" ]]; then
    read -p "$(echo -e "${YELLOW}Continue with rescue mode activation for all servers? [Y/n]:${NC} ")" -r >&2
    echo >&2
    # Default to Yes if empty response
    REPLY=${REPLY:-Y}
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Operation cancelled"
        exit 0
    fi
else
    log_info "Auto-confirm enabled, proceeding with rescue mode activation"
fi

# Process control plane
process_server "$CONTROLPLANE_IP" "$CONTROLPLANE_NAME" "controlplane"

# Process workers
paste <(echo "$WORKER_NAMES") <(echo "$WORKER_IPS") | while read -r name ip; do
    process_server "$ip" "$name" "worker"
done

# Wait for servers to boot
echo "" >&2
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "All servers are rebooting into rescue mode"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "" >&2
log_info "Servers typically take 60-90 seconds to boot into rescue mode"
log_info "You can monitor status at: https://console.hetzner.cloud/projects"
echo "" >&2
log_success "Updated configuration saved to: $VALUES_FILE"
log_info "Backup available at: ${VALUES_FILE}.bak"
echo "" >&2
log_step "Next steps:"
echo "  1. Wait ~90 seconds for servers to boot into rescue mode" >&2
echo "  2. Run bootstrap: make bootstrap ENV=$ENV" >&2
echo "" >&2
