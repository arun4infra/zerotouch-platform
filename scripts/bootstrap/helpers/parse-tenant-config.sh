#!/bin/bash
# Parse tenant configuration and export variables
#
# Usage:
#   source ./helpers/parse-tenant-config.sh <ENV>
#   # Sets: SERVER_IP, ROOT_PASSWORD, WORKER_NODES, WORKER_PASSWORD

set -e

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch tenant config
source "$SCRIPT_DIR/fetch-tenant-config.sh" "$ENV" --use-cache

# Parse values using Python
TENANT_VALUES=$(python3 - <<EOF
import yaml
with open('$TENANT_CONFIG_FILE', 'r') as f:
    data = yaml.safe_load(f)

cp = data['controlplane']
print(f"{cp['ip']}")
print(f"{cp['rescue_password']}")

workers = data.get('workers', [])
if workers:
    for w in workers:
        print(f"{w['name']}:{w['ip']}:{w['rescue_password']}")
EOF
)

# Parse the output
IFS=$'\n' read -d '' -r -a lines <<< "$TENANT_VALUES" || true
export SERVER_IP="${lines[0]}"
export ROOT_PASSWORD="${lines[1]}"

# Build worker nodes string if workers exist
if [ ${#lines[@]} -gt 2 ]; then
    export WORKER_NODES=""
    WORKER_PASSWORDS=()
    for ((i=2; i<${#lines[@]}; i++)); do
        IFS=':' read -r name ip pwd <<< "${lines[$i]}"
        if [ -n "$WORKER_NODES" ]; then
            WORKER_NODES="$WORKER_NODES,"
        fi
        WORKER_NODES="$WORKER_NODES$name:$ip"
        WORKER_PASSWORDS+=("$pwd")
    done
    # Use first worker password (assuming all same for now)
    export WORKER_PASSWORD="${WORKER_PASSWORDS[0]}"
else
    export WORKER_NODES=""
    export WORKER_PASSWORD=""
fi

echo "✓ Configuration parsed from tenant repo" >&2
echo "  Control Plane: $SERVER_IP" >&2
[ -n "$WORKER_NODES" ] && echo "  Workers: $WORKER_NODES" >&2
