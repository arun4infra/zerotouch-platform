#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
TALOS_VERSION="v1.11.5"
DISK_DEVICE="/dev/sda"
TALOS_IMAGE_URL="https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/${TALOS_VERSION}/metal-amd64.raw.xz"

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
Usage: $0 --server-ip <IP> --user <USER> --password <PASSWORD> [OPTIONS]

Required Arguments:
  --server-ip <IP>        Server IP address
  --user <USER>           SSH user (usually 'root' for rescue mode)
  --password <PASSWORD>   SSH password for rescue mode

Optional Arguments:
  --disk <DEVICE>         Disk device to flash Talos (default: /dev/sda)
  --talos-version <VER>   Talos version to install (default: v1.11.5)
  --yes                   Auto-confirm disk wipe (skip confirmation prompt)
  --dry-run               Show commands without executing
  -h, --help              Show this help message

Example:
  $0 --server-ip 46.62.218.181 --user root --password 'rescue123' --yes
EOF
    exit 1
}

# Parse arguments
DRY_RUN=false
AUTO_CONFIRM=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --password)
            SSH_PASSWORD="$2"
            shift 2
            ;;
        --disk)
            DISK_DEVICE="$2"
            shift 2
            ;;
        --talos-version)
            TALOS_VERSION="$2"
            TALOS_IMAGE_URL="https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/${TALOS_VERSION}/metal-amd64.raw.xz"
            shift 2
            ;;
        --yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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

# Validate required arguments
if [[ -z "$SERVER_IP" || -z "$SSH_USER" || -z "$SSH_PASSWORD" ]]; then
    log_error "Missing required arguments"
    usage
fi

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    log_error "sshpass is not installed. Install it first:"
    echo "  macOS: brew install sshpass"
    echo "  Linux: sudo apt-get install sshpass"
    exit 1
fi

log_info "Starting Talos installation on rescue machine"
log_info "Server IP: $SERVER_IP"
log_info "SSH User: $SSH_USER"
log_info "Disk Device: $DISK_DEVICE"
log_info "Talos Version: $TALOS_VERSION"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

# SSH command wrapper
ssh_exec() {
    local cmd="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute on remote: $cmd"
    else
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SERVER_IP" "$cmd"
    fi
}

# Step 1: Check connectivity
log_info "Step 1: Testing SSH connectivity..."
if ! ssh_exec "echo 'Connection successful'"; then
    log_error "Failed to connect to server. Is rescue mode enabled?"
    exit 1
fi
log_info "✓ SSH connection successful"

# Step 2: Detect disk device
log_info "Step 2: Detecting disk devices..."
ssh_exec "lsblk"
log_warn "Using disk device: $DISK_DEVICE"
log_warn "⚠️  ALL DATA ON $DISK_DEVICE WILL BE ERASED!"

if [[ "$DRY_RUN" == "false" && "$AUTO_CONFIRM" == "false" ]]; then
    read -p "Continue? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        log_error "Installation cancelled by user"
        exit 1
    fi
elif [[ "$AUTO_CONFIRM" == "true" ]]; then
    log_info "Auto-confirmed (--yes flag)"
fi

# Step 3: Download Talos image
log_info "Step 3: Downloading Talos ${TALOS_VERSION} image..."
ssh_exec "curl -L -o /tmp/talos.raw.xz '$TALOS_IMAGE_URL'"

# Step 4: Verify download
log_info "Step 4: Verifying download..."
ssh_exec "ls -lh /tmp/talos.raw.xz"

# Step 5: Flash Talos to disk
log_info "Step 5: Flashing Talos to $DISK_DEVICE (this may take 5-10 minutes)..."
log_warn "⚠️  DESTRUCTIVE OPERATION - Wiping $DISK_DEVICE now!"
ssh_exec "xz -d -c /tmp/talos.raw.xz | dd of=$DISK_DEVICE bs=4M status=progress && sync"

log_info "✓ Talos image written successfully"

# Step 6: Reboot
log_info "Step 6: Rebooting server into Talos..."
if [[ "$DRY_RUN" == "false" ]]; then
    ssh_exec "reboot" || true  # SSH will disconnect, so ignore error
    log_info "✓ Reboot initiated"
else
    log_info "[DRY-RUN] Would execute: reboot"
fi

# Final instructions
cat << EOF

${GREEN}════════════════════════════════════════════════════════${NC}
${GREEN}✓ Talos installation on rescue machine completed!${NC}
${GREEN}════════════════════════════════════════════════════════${NC}

Next Steps:
1. Wait 2-3 minutes for Talos to boot
2. Run the Talos configuration script:

   cd bootstrap/talos
   
   # Apply configuration
   talosctl apply-config --insecure \\
     --nodes $SERVER_IP \\
     --endpoints $SERVER_IP \\
     --file nodes/cp01-main/config.yaml
   
   # Bootstrap cluster
   talosctl bootstrap --nodes $SERVER_IP \\
     --endpoints $SERVER_IP \\
     --talosconfig talosconfig
   
   # Get kubeconfig
   talosctl kubeconfig --nodes $SERVER_IP \\
     --endpoints $SERVER_IP \\
     --talosconfig talosconfig
   
   # Verify
   kubectl get nodes

${YELLOW}Note: If you get connection errors, wait a bit longer for Talos to fully boot.${NC}

EOF
