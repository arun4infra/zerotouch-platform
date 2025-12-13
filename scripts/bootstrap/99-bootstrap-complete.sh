#!/bin/bash
# Tier 3 Script: Bootstrap Complete Summary
# Displays completion message and next steps
#
# Arguments:
#   $1 - Mode: "production" or "preview"
#   $2 - Credentials file path (production only)
#   $3 - Server IP (production only)
#   $4 - Worker nodes (production only, optional)
#
# Exit Codes:
#   0 - Success

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="${1:-production}"
CREDENTIALS_FILE="${2:-}"
SERVER_IP="${3:-}"
WORKER_NODES="${4:-}"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║             Bootstrap Complete!                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$MODE" = "production" ]; then
    echo -e "${GREEN}✓ Talos OS installed and configured${NC}"
    if [ -n "$WORKER_NODES" ]; then
        echo -e "${GREEN}✓ Worker nodes installed and joined cluster${NC}"
    fi
    echo -e "${GREEN}✓ ArgoCD bootstrapped and managing platform${NC}"
    echo -e "${GREEN}✓ Cluster validation complete${NC}"
    echo ""
    echo -e "${YELLOW}📝 Credentials saved to:${NC}"
    echo -e "   ${GREEN}$CREDENTIALS_FILE${NC}"
    echo ""
    echo -e "${YELLOW}📌 Next Steps:${NC}"
    echo -e "   1. Review credentials file and ${RED}BACK UP${NC} important credentials"
    echo -e "   2. Port-forward ArgoCD UI: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
    echo -e "   3. Monitor applications: ${GREEN}kubectl get applications -n argocd${NC}"
    echo ""
    echo -e "${BLUE}Happy deploying! 🚀${NC}"
    echo ""
    
    # Display credentials file content
    if [ -f "$CREDENTIALS_FILE" ]; then
        cat "$CREDENTIALS_FILE"
    fi
else
    echo -e "${GREEN}✓ Kind cluster created and configured${NC}"
    echo -e "${GREEN}✓ ArgoCD bootstrapped and managing platform${NC}"
    echo -e "${GREEN}✓ Platform validation complete${NC}"
    echo ""
    echo -e "${YELLOW}📌 Preview Environment Ready:${NC}"
    echo -e "   Cluster: ${GREEN}kind-zerotouch-preview${NC}"
    echo -e "   Context: ${GREEN}kind-zerotouch-preview${NC}"
    echo ""
    echo -e "${YELLOW}📌 Monitor Deployment:${NC}"
    echo -e "   kubectl get applications -n argocd"
    echo -e "   kubectl get pods --all-namespaces"
    echo ""
    echo -e "${YELLOW}📌 Cleanup:${NC}"
    echo -e "   kind delete cluster --name zerotouch-preview"
    echo ""
    echo -e "${BLUE}Platform ready for testing! 🚀${NC}"
    echo ""
fi

exit 0
