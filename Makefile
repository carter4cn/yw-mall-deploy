COMPOSE  := docker compose
ENV_DIR  := ../env
BACKEND  := ../yw-mall
FRONTEND := ../yw-mall-fe

.PHONY: help infra-up infra-down up down build rebuild seed logs ps clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

# ── Infra (env project) ───────────────────────────────────────────────────

infra-up: ## Start infra containers (MySQL, Redis, etcd, Kafka, MinIO…)
	$(COMPOSE) -f $(ENV_DIR)/compose.yml up -d

infra-down: ## Stop infra containers
	$(COMPOSE) -f $(ENV_DIR)/compose.yml down

# ── App layer ─────────────────────────────────────────────────────────────

build: ## Build all app images (backend + frontend)
	$(COMPOSE) build

up: ## Start all app services (db-init → RPCs → API → frontend)
	$(COMPOSE) up -d

down: ## Stop all app services (infra stays up)
	$(COMPOSE) down

restart: down up ## Restart all app services

rebuild: ## Rebuild images then start
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

# ── Seed ─────────────────────────────────────────────────────────────────

seed: ## Run DB seed (requires RPCs to be up; runs via start.sh bootstrap)
	@echo "Running seed against running services..."
	@cd $(BACKEND) && bash start.sh bootstrap

# ── Observability ────────────────────────────────────────────────────────

logs: ## Tail logs for all services
	$(COMPOSE) logs -f

logs-%: ## Tail logs for a specific service, e.g. make logs-mall-api
	$(COMPOSE) logs -f $*

ps: ## Show service status
	$(COMPOSE) ps

# ── Cleanup ───────────────────────────────────────────────────────────────

clean: down ## Stop services and remove images
	$(COMPOSE) down --rmi local --volumes

nuke: ## Drop all mall_* databases (DANGER: data loss)
	@cd $(BACKEND) && bash start.sh nuke
