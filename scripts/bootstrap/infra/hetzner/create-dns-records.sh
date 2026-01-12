#!/bin/bash
set -euo pipefail

# Create DNS A records using Hetzner DNS API (not Cloud API)
# This script creates A records for the Gateway LoadBalancer IP

ZONE_NAME="${1:-nutgraf.in}"
GATEWAY_IP="${2:-}"
DNS_TOKEN="${HETZNER_DNS_TOKEN:-}"

if [ -z "$DNS_TOKEN" ]; then
    echo "Error: HETZNER_DNS_TOKEN environment variable is required"
    echo "Usage: HETZNER_DNS_TOKEN=your_dns_token $0 [zone_name] [gateway_ip]"
    echo ""
    echo "Note: This requires a Hetzner DNS API token, not Cloud API token"
    echo "Get it from: https://dns.hetzner.com/settings/api-token"
    exit 1
fi

# Get Gateway IP if not provided
if [ -z "$GATEWAY_IP" ]; then
    echo "Getting Gateway LoadBalancer IP..."
    GATEWAY_IP=$(kubectl get gateway public-gateway -n kube-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -z "$GATEWAY_IP" ]; then
        echo "❌ Could not get Gateway IP. Please provide it as second argument."
        exit 1
    fi
    echo "Found Gateway IP: $GATEWAY_IP"
fi

# Get zone ID using DNS API
echo "Getting zone ID for $ZONE_NAME using DNS API..."
zones_response=$(curl -s \
    -H "Auth-API-Token: $DNS_TOKEN" \
    "https://dns.hetzner.com/api/v1/zones")

zone_id=$(echo "$zones_response" | jq -r ".zones[] | select(.name == \"$ZONE_NAME\") | .id" 2>/dev/null || echo "")

if [ -z "$zone_id" ]; then
    echo "❌ Zone '$ZONE_NAME' not found in Hetzner DNS. Available zones:"
    echo "$zones_response" | jq -r '.zones[].name' 2>/dev/null || echo "None"
    echo ""
    echo "Note: The zone must exist in Hetzner DNS Console, not just Cloud Console"
    exit 1
fi

echo "Found zone ID: $zone_id"

# List of hostnames to create A records for
hostnames=(
    "test-ingress.kube-system"
    "ide-orchestrator.intelligence-orchestrator"
)

echo "Creating DNS A records using DNS API..."

for hostname in "${hostnames[@]}"; do
    full_hostname="${hostname}.${ZONE_NAME}"
    echo "Creating A record: $full_hostname -> $GATEWAY_IP"
    
    # Check if record already exists
    existing_records=$(curl -s \
        -H "Auth-API-Token: $DNS_TOKEN" \
        "https://dns.hetzner.com/api/v1/records?zone_id=$zone_id")
    
    existing_record_id=$(echo "$existing_records" | jq -r ".records[] | select(.name == \"$hostname\" and .type == \"A\") | .id" 2>/dev/null || echo "")
    
    if [ -n "$existing_record_id" ]; then
        echo "Updating existing A record (ID: $existing_record_id)"
        response=$(curl -s -w "%{http_code}" \
            -X PUT \
            -H "Auth-API-Token: $DNS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"value\": \"$GATEWAY_IP\", \"ttl\": 300}" \
            "https://dns.hetzner.com/api/v1/records/$existing_record_id")
    else
        echo "Creating new A record"
        response=$(curl -s -w "%{http_code}" \
            -X POST \
            -H "Auth-API-Token: $DNS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"zone_id\": \"$zone_id\", \"name\": \"$hostname\", \"type\": \"A\", \"value\": \"$GATEWAY_IP\", \"ttl\": 300}" \
            "https://dns.hetzner.com/api/v1/records")
    fi
    
    http_code="${response: -3}"
    response_body="${response%???}"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "✅ A record created/updated: $full_hostname -> $GATEWAY_IP"
    else
        echo "❌ Failed to create A record for $full_hostname. HTTP $http_code"
        echo "Response: $response_body"
    fi
done

echo ""
echo "✅ DNS records creation complete!"
echo ""
echo "Verifying DNS records..."

# Verify records were created
for hostname in "${hostnames[@]}"; do
    full_hostname="${hostname}.${ZONE_NAME}"
    echo "Checking: $full_hostname"
    
    records=$(curl -s \
        -H "Auth-API-Token: $DNS_TOKEN" \
        "https://dns.hetzner.com/api/v1/records?zone_id=$zone_id")
    
    record_value=$(echo "$records" | jq -r ".records[] | select(.name == \"$hostname\" and .type == \"A\") | .value" 2>/dev/null || echo "")
    
    if [ "$record_value" = "$GATEWAY_IP" ]; then
        echo "✅ $full_hostname -> $record_value"
    else
        echo "❌ $full_hostname -> $record_value (expected: $GATEWAY_IP)"
    fi
done

echo ""
echo "⚠️  Note: DNS records created but domain delegation is invalid."
echo "The domain registrar must point to Hetzner nameservers for records to resolve:"
echo "  - hydrogen.ns.hetzner.com"
echo "  - oxygen.ns.hetzner.com" 
echo "  - helium.ns.hetzner.de"
echo ""
echo "Until delegation is fixed, test with:"
echo "dig @hydrogen.ns.hetzner.com test-ingress.kube-system.nutgraf.in"