#!/bin/bash
set -euo pipefail

# Verify Hetzner Cloud DNS Zone exists and show details
# This script verifies a DNS zone exists and displays nameservers

ZONE_NAME="${1:-nutgraf.in}"
API_TOKEN="${HETZNER_API_TOKEN:-}"

if [ -z "$API_TOKEN" ]; then
    echo "Error: HETZNER_API_TOKEN environment variable is required"
    echo "Usage: HETZNER_API_TOKEN=your_token $0 [zone_name]"
    exit 1
fi

echo "Verifying DNS zone: $ZONE_NAME..."

# Get zone details
zones=$(curl -s \
    -H "Authorization: Bearer $API_TOKEN" \
    "https://api.hetzner.cloud/v1/zones")

zone_found=$(echo "$zones" | jq -r ".zones[] | select(.name == \"$ZONE_NAME\") | .name" 2>/dev/null || echo "")

if [ "$zone_found" = "$ZONE_NAME" ]; then
    echo "✅ DNS zone verification successful"
    echo ""
    echo "Zone details:"
    echo "$zones" | jq ".zones[] | select(.name == \"$ZONE_NAME\")"
    
    # Extract and display nameservers
    echo ""
    echo "Assigned nameservers for $ZONE_NAME:"
    echo "$zones" | jq -r ".zones[] | select(.name == \"$ZONE_NAME\") | .authoritative_nameservers.assigned[]" 2>/dev/null || echo "None"
    
    echo ""
    echo "Delegated nameservers (current DNS setup):"
    echo "$zones" | jq -r ".zones[] | select(.name == \"$ZONE_NAME\") | .authoritative_nameservers.delegated[]" 2>/dev/null || echo "None"
    
    # Check delegation status
    delegation_status=$(echo "$zones" | jq -r ".zones[] | select(.name == \"$ZONE_NAME\") | .authoritative_nameservers.delegation_status" 2>/dev/null || echo "unknown")
    echo ""
    echo "Delegation status: $delegation_status"
    
    if [ "$delegation_status" = "invalid" ]; then
        echo ""
        echo "⚠️  DNS delegation is invalid. Update your domain registrar to use the assigned nameservers above."
    elif [ "$delegation_status" = "valid" ]; then
        echo "✅ DNS delegation is valid"
    fi
else
    echo "❌ DNS zone '$ZONE_NAME' not found"
    echo ""
    echo "Available zones:"
    echo "$zones" | jq -r '.zones[].name' 2>/dev/null || echo "None"
    exit 1
fi