#!/bin/bash
# Update Target Revision Script
# Updates all ArgoCD Application manifests to use the target revision from config.yaml
#
# Usage: ./scripts/bootstrap/update-target-revision.sh [branch-name]
#
# If branch-name is provided, it updates config.yaml first, then applies to all manifests
# If no argument, reads from config.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/bootstrap/config.yaml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Update ArgoCD Target Revision                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠️  Config file not found: $CONFIG_FILE${NC}"
    echo "Creating default config..."
    cat > "$CONFIG_FILE" << 'EOF'
# Bootstrap Configuration
# This file contains global configuration for the bootstrap process
# Update TARGET_REVISION to change the branch/tag for all platform components

# Git repository configuration
REPO_URL: https://github.com/arun4infra/zerotouch-platform.git
TARGET_REVISION: main

# To switch to a feature branch:
# TARGET_REVISION: feature/agent-executor

# To use a specific tag/release:
# TARGET_REVISION: v1.0.0
EOF
fi

# If branch name provided, update config.yaml first
if [ -n "$1" ]; then
    NEW_REVISION="$1"
    echo -e "${BLUE}Updating config.yaml with new target revision: $NEW_REVISION${NC}"
    
    # Update TARGET_REVISION in config.yaml
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|^TARGET_REVISION:.*|TARGET_REVISION: $NEW_REVISION|" "$CONFIG_FILE"
    else
        # Linux
        sed -i "s|^TARGET_REVISION:.*|TARGET_REVISION: $NEW_REVISION|" "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Updated config.yaml${NC}"
    echo ""
fi

# Read TARGET_REVISION from config.yaml
TARGET_REVISION=$(grep "^TARGET_REVISION:" "$CONFIG_FILE" | awk '{print $2}')

if [ -z "$TARGET_REVISION" ]; then
    echo -e "${YELLOW}⚠️  Could not read TARGET_REVISION from config.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}Target Revision: $TARGET_REVISION${NC}"
echo ""

# Find all YAML files in bootstrap/ that reference zerotouch-platform repo
echo -e "${BLUE}Scanning for bootstrap manifests...${NC}"
echo ""

BOOTSTRAP_FILES=()
while IFS= read -r -d '' file; do
    # Check if file contains both repoURL with zerotouch-platform and targetRevision
    if grep -q "repoURL:.*zerotouch-platform" "$file" && grep -q "targetRevision:" "$file"; then
        BOOTSTRAP_FILES+=("$file")
    fi
done < <(find "$REPO_ROOT/bootstrap" -type f -name "*.yaml" -print0)

if [ ${#BOOTSTRAP_FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No bootstrap manifests found${NC}"
    exit 1
fi

echo -e "${GREEN}Found ${#BOOTSTRAP_FILES[@]} manifest(s) to update${NC}"
echo ""

echo -e "${BLUE}Updating bootstrap manifests...${NC}"
echo ""

UPDATED_COUNT=0

for file in "${BOOTSTRAP_FILES[@]}"; do
    filename=$(basename "$file")
    
    # Update targetRevision in the file (only for lines with zerotouch-platform repo)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - update targetRevision only if previous line contains zerotouch-platform
        awk -v target="$TARGET_REVISION" '
            /repoURL:.*zerotouch-platform/ { found=1 }
            /targetRevision:/ && found { 
                sub(/targetRevision:.*/, "targetRevision: " target)
                found=0
            }
            { print }
        ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
        # Linux - update targetRevision only if previous line contains zerotouch-platform
        awk -v target="$TARGET_REVISION" '
            /repoURL:.*zerotouch-platform/ { found=1 }
            /targetRevision:/ && found { 
                sub(/targetRevision:.*/, "targetRevision: " target)
                found=0
            }
            { print }
        ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    fi
    
    echo -e "  ${GREEN}✓${NC} Updated: $filename"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
done

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Updated $UPDATED_COUNT manifest(s) to use: $TARGET_REVISION${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Review changes: ${GREEN}git diff bootstrap/${NC}"
echo -e "  2. Commit changes: ${GREEN}git add bootstrap/ && git commit -m 'chore: Update target revision to $TARGET_REVISION'${NC}"
echo -e "  3. Push to remote: ${GREEN}git push${NC}"
echo -e "  4. Apply to cluster: ${GREEN}kubectl apply -f bootstrap/root.yaml${NC}"
echo ""

exit 0
