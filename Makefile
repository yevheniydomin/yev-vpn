.PHONY: build up down configs logs restart reset deploy destroy status cloud-configs cloud-logs help

COMPARTMENT_ID ?= $(shell grep tenancy ~/.oci/config 2>/dev/null | head -1 | cut -d= -f2)
SHAPE          ?= VM.Standard.E2.1.Micro
AD_INDEX       ?= 2
SSH_KEY        ?= $(shell cat ~/.ssh/oracle-vpn.pub 2>/dev/null)
SSH_PRIVATE    ?= ~/.ssh/oracle-vpn

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ─── Local Docker workflow ───────────────────────────────────────────────────

build: ## Build the VPN Docker image locally
	docker compose build

up: ## Start the VPN locally
	docker compose up -d
	@echo ""
	@echo "VPN starting... check logs with: make logs"
	@echo "Get client configs with: make configs"

down: ## Stop the VPN locally
	docker compose down

configs: ## Print client connection configs (local)
	@docker compose exec vpn /entrypoint.sh configs

logs: ## Follow VPN logs (local)
	docker compose logs -f

restart: ## Restart the VPN (regenerates configs with current IP)
	docker compose restart

reset: ## Full reset — delete all keys and configs
	docker compose down -v
	@echo "All VPN data wiped. Run 'make up' to generate new keys."

# ─── OCI Cloud deployment (free tier) ───────────────────────────────────────

deploy: ## Deploy VPN to Oracle Cloud (free tier, no SSH needed)
	cd oracle-cloud && terraform init
	cd oracle-cloud && terraform apply \
		-var="compartment_id=$(COMPARTMENT_ID)" \
		-var="ssh_public_key=$(SSH_KEY)" \
		-var="shape=$(SHAPE)" \
		-var="availability_domain_index=$(AD_INDEX)"
	@echo ""
	@echo "Instance is provisioning. Docker build takes ~5-10 min on free tier."
	@echo "Check status: make status"

destroy: ## Destroy the cloud VPN instance
	cd oracle-cloud && terraform destroy \
		-var="compartment_id=$(COMPARTMENT_ID)" \
		-var="ssh_public_key=$(SSH_KEY)" \
		-var="shape=$(SHAPE)" \
		-var="availability_domain_index=$(AD_INDEX)"

status: ## Check cloud deployment status
	@IP=$$(cd oracle-cloud && terraform output -raw instance_public_ip 2>/dev/null) && \
	echo "Server IP: $$IP" && \
	ssh -o ConnectTimeout=5 -i $(SSH_PRIVATE) ubuntu@$$IP \
		'cat /var/log/vpn-deploy.log 2>/dev/null; echo "---"; sudo docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null || echo "Docker not ready yet"'

cloud-configs: ## Retrieve client configs from cloud instance
	@IP=$$(cd oracle-cloud && terraform output -raw instance_public_ip 2>/dev/null) && \
	ssh -i $(SSH_PRIVATE) ubuntu@$$IP \
		'sudo docker compose -f /opt/family-vpn/docker-compose.yml exec vpn /entrypoint.sh configs'

cloud-logs: ## Follow VPN logs on cloud instance
	@IP=$$(cd oracle-cloud && terraform output -raw instance_public_ip 2>/dev/null) && \
	ssh -i $(SSH_PRIVATE) ubuntu@$$IP \
		'sudo docker compose -f /opt/family-vpn/docker-compose.yml logs --tail 50 -f'
