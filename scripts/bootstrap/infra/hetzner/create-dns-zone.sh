#!/bin/bash
set -euo pipefail

# Create Hetzner Cloud DNS Zone
# This script creates a DNS zone in Hetzner Cloud for external-dns integration

ZONE_NAME="${1:-nutgraf.in}"
API_TOKEN="${HETZNER_API_TOKEN:-}"

if [ -z "$API_TOKEN" ]; then
    echo "Error: HETZNER_API_TOKEN environment variable is required"
    echo "Usage: HETZNER_API_TOKEN=your_token $0 [zone_name]"
    exit 1
fi

echo "Creating DNS zone: $ZONE_NAME in Hetzner Cloud..."

# Try different mode values based on Hetzner Cloud API
for mode in "primary" "secondary" "managed"; do
    echo "Trying mode: $mode"
    
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$ZONE_NAME\", \"ttl\": 3600, \"mode\": \"$mode\"}" \
        "https://api.hetzner.cloud/v1/zones")
    
    http_code="${response: -3}"
    response_body="${response%???}"
    
    if [ "$http_code" = "201" ]; then
        echo "✅ DNS zone '$ZONE_NAME' created successfully with mode: $mode"
        echo "Response: $response_body"
        break
    elif [ "$http_code" = "422" ]; then
        error_msg=$(echo "$response_body" | jq -r '.error.message' 2>/dev/null || echo "Unknown error")
        if [[ "$error_msg" == *"already exists"* ]]; then
            echo "✅ DNS zone '$ZONE_NAME' already exists"
            break
        else
            echo "Mode $mode failed: $error_msg"
            continue
        fi
    else
        echo "Mode $mode failed with HTTP $http_code: $response_body"
        continue
    fi
done

echo ""
echo "✅ DNS zone creation complete!"
echo ""
echo "To verify the zone and get nameservers, run:"
echo "  ./verify-dns-zone.sh $ZONE_NAME"
echo ""
echo "To restart external-dns:"
echo "  kubectl rollout restart deployment/external-dns -n kube-system"