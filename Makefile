# BizMatters Infrastructure - Bootstrap Automation
# Zero-touch Kubernetes platform deployment

.PHONY: help bootstrap embed-cilium verify clean

ENV ?= dev
SCRIPTS_DIR := scripts/bootstrap

help:  ## Show this help
	@echo "BizMatters Infrastructure - Bootstrap Automation"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

bootstrap:  ## Full cluster bootstrap (ENV=dev|staging|prod)
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║  Bootstrapping BizMatters Infrastructure ($(ENV))            ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@if [ ! -f environments/$(ENV)/talos-values.yaml ]; then \
		echo "ERROR: environments/$(ENV)/talos-values.yaml not found"; \
		echo "Copy environments/$(ENV)/talos-values.yaml.example and fill in values"; \
		exit 1; \
	fi
	@echo "Logging to: bootstrap-$(ENV).log"
	@VALUES=$$($(SCRIPTS_DIR)/parse-values.sh $(ENV)); \
	CP_IP=$$(echo "$$VALUES" | sed -n '1p'); \
	CP_PASS=$$(echo "$$VALUES" | sed -n '2p'); \
	WORKER_NAME=$$(echo "$$VALUES" | sed -n '3p'); \
	WORKER_IP=$$(echo "$$VALUES" | sed -n '4p'); \
	WORKER_PASS=$$(echo "$$VALUES" | sed -n '5p'); \
	$(SCRIPTS_DIR)/01-master-bootstrap.sh \
		"$$CP_IP" "$$CP_PASS" \
		--worker-nodes "$$WORKER_NAME:$$WORKER_IP" \
		--worker-password "$$WORKER_PASS" 2>&1 | tee bootstrap-$(ENV).log

embed-cilium:  ## Embed Cilium manifest in control plane config
	@echo "Embedding Cilium CNI in Talos control plane config..."
	@$(SCRIPTS_DIR)/embed-cilium.sh

verify:  ## Verify agent-executor deployment
	@$(SCRIPTS_DIR)/08-verify-agent-executor-deployment.sh

clean:  ## Clean generated Talos configs (keeps templates)
	@echo "Cleaning generated Talos configs..."
	@rm -rf bootstrap/talos/nodes/*/config.yaml
	@rm -f bootstrap/talos/talosconfig
	@echo "✓ Cleaned (templates preserved)"

# Environment-specific shortcuts
dev-bootstrap:  ## Bootstrap dev environment
	$(MAKE) bootstrap ENV=dev

staging-bootstrap:  ## Bootstrap staging environment
	$(MAKE) bootstrap ENV=staging

prod-bootstrap:  ## Bootstrap production environment
	$(MAKE) bootstrap ENV=production
