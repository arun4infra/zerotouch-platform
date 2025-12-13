# Basic usage (called by master bootstrap script)
./scripts/bootstrap/02-install-talos-rescue.sh \
  --server-ip 46.62.218.181 \
  --user root \
  --password 'YOUR_RESCUE_PASSWORD' \
  --yes

# Dry-run to see what it would do (safe)
./scripts/bootstrap/02-install-talos-rescue.sh \
  --server-ip 46.62.218.181 \
  --user root \
  --password 'YOUR_RESCUE_PASSWORD' \
  --dry-run
  
# Custom disk device
./scripts/bootstrap/02-install-talos-rescue.sh \
  --server-ip 46.62.218.181 \
  --user root \
  --password 'YOUR_RESCUE_PASSWORD' \
  --disk /dev/nvme0n1 \
  --yes