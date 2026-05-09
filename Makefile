# Auto-detect compose command: podman-compose preferred (infra runs in Podman),
# docker compose fallback.
COMPOSE ?= $(shell \
  if command -v podman-compose >/dev/null 2>&1; then echo "podman-compose"; \
  elif docker compose version >/dev/null 2>&1; then echo "docker compose"; \
  else echo "podman-compose"; fi)

# Infra project-name must match so yw-mall-deploy can find the "env_infra" network.
INFRA_PROJECT ?= env
ENV_DIR       := ../env
BACKEND       := ../yw-mall
FRONTEND      := ../yw-mall-fe
MYSQL_DATA    := $(ENV_DIR)/data/mysql2

.PHONY: help start stop infra-up infra-down minio-init up down build rebuild seed logs ps clean nuke nuke-mysql

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'
	@echo ""
	@echo "  After 'make start + make seed':"
	@echo "    Frontend  →  http://localhost:18080"
	@echo "    API       →  http://localhost:18888"
	@echo "    MinIO UI  →  http://localhost:9001  (admin / admin123)"

# ── One-click ─────────────────────────────────────────────────────────────

start: infra-up up ## One-click: start infra + app (first run builds images, takes ~5 min)

stop: down infra-down ## Stop everything: app first, then infra

# ── Infra layer (env project) ─────────────────────────────────────────────

infra-up: ## Start infra containers (MySQL, Redis, etcd, Kafka, MinIO …)
	@echo "==> preparing MySQL data directories (Podman rootless: uid 999 → host uid 100998)..."
	@mkdir -p $(MYSQL_DATA)/master1 $(MYSQL_DATA)/master2 \
	          $(MYSQL_DATA)/slave1  $(MYSQL_DATA)/slave2
	@podman unshare chown 999:999 \
	    $(MYSQL_DATA)/master1 $(MYSQL_DATA)/master2 \
	    $(MYSQL_DATA)/slave1  $(MYSQL_DATA)/slave2 2>/dev/null || true
	$(COMPOSE) -f $(ENV_DIR)/compose.yml --project-name $(INFRA_PROJECT) up -d
	@sleep 5
	@echo "==> starting containers podman-compose leaves in Created state..."
	@podman start mysql-init redis-sentinel1 redis-sentinel2 redis-sentinel3 proxysql 2>/dev/null || true
	@echo "==> flushing stale go-zero cache:* keys from Redis..."
	@podman exec redis-master redis-cli KEYS "cache:*" 2>/dev/null | xargs -r podman exec -i redis-master redis-cli DEL 2>/dev/null || true
	@$(MAKE) minio-init

minio-init: ## Create MinIO buckets, set public-read, upload placeholder images
	@bash scripts/minio-init.sh

infra-down: ## Stop infra containers
	$(COMPOSE) -f $(ENV_DIR)/compose.yml --project-name $(INFRA_PROJECT) down

# ── App layer ─────────────────────────────────────────────────────────────

build: ## Build all app images (backend RPCs + frontend + seed)
	$(COMPOSE) build
	$(COMPOSE) --profile seed build db-seed

up: ## Start app services (db-init → RPCs → API → frontend)
	$(COMPOSE) up -d

down: ## Stop app services (infra stays up)
	$(COMPOSE) down

restart: down up ## Restart all app services

rebuild: ## Full no-cache rebuild then start
	$(COMPOSE) build --no-cache
	$(COMPOSE) --profile seed build --no-cache db-seed
	$(COMPOSE) up -d

# ── Seed ─────────────────────────────────────────────────────────────────

seed: ## Populate demo data (run once after first start, or after 'make nuke')
	$(COMPOSE) --profile seed run --rm db-seed

# ── Observability ────────────────────────────────────────────────────────

logs: ## Tail logs for all running services
	$(COMPOSE) logs -f

logs-%: ## Tail logs for one service, e.g. make logs-mall-api
	$(COMPOSE) logs -f $*

ps: ## Show service status
	$(COMPOSE) ps

# ── Cleanup ───────────────────────────────────────────────────────────────

clean: down ## Stop and remove locally-built images
	$(COMPOSE) down --rmi local --volumes

nuke: ## Drop all mall_* databases — DANGER: destroys all data
	@cd $(BACKEND) && bash start.sh nuke

nuke-mysql: ## Wipe MySQL data dirs without sudo (uses podman unshare) — DANGER
	@echo "WARNING: destroying all MySQL data in $(MYSQL_DATA)..."
	@podman unshare rm -rf \
	    $(MYSQL_DATA)/master1 $(MYSQL_DATA)/master2 \
	    $(MYSQL_DATA)/slave1  $(MYSQL_DATA)/slave2
	@echo "Done. Run 'make infra-up' then 'make seed' to reinitialize."
