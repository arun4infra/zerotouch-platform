#!/bin/bash
# Production Credentials Helper
# Usage: ./add-credentials.sh <credentials-file> <section> <content>
#
# Adds credential sections to the production credentials file

set -e

CREDENTIALS_FILE="$1"
SECTION="$2"
CONTENT="$3"

if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "Error: Credentials file not found: $CREDENTIALS_FILE"
    exit 1
fi

cat >> "$CREDENTIALS_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$SECTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$CONTENT

EOF

exit 0
