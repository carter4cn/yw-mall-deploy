#!/bin/sh
# Seed orchestrator for Docker Compose deployments.
# Waits for all required services, then runs seed programs in dependency order.
# Every seed program is idempotent — safe to re-run.
set -e

DSN_BASE="proxysql:proxysql123@tcp(proxysql:6033)"
DS_SHOP="${DSN_BASE}/mall_shop?charset=utf8mb4&parseTime=true&loc=Local"
DS_USER="${DSN_BASE}/mall_user?charset=utf8mb4&parseTime=true&loc=Local"
DS_PRODUCT="${DSN_BASE}/mall_product?charset=utf8mb4&parseTime=true&loc=Local"
DS_ORDER="${DSN_BASE}/mall_order?charset=utf8mb4&parseTime=true&loc=Local"
DS_ACTIVITY="${DSN_BASE}/mall_activity?charset=utf8mb4&parseTime=true&loc=Local"

# Wait up to 120s for a TCP port to accept connections
wait_tcp() {
    local host="$1" port="$2"
    printf 'waiting for %s:%s ' "$host" "$port"
    for i in $(seq 1 40); do
        nc -z "$host" "$port" 2>/dev/null && echo " ok" && return 0
        printf '.'
        sleep 3
    done
    echo " timeout — continuing anyway" >&2
}

echo "=== Waiting for infra ==="
wait_tcp proxysql      6033
wait_tcp minio         9000

echo "=== Waiting for RPC services ==="
wait_tcp mall-shop-rpc      9017
wait_tcp mall-user-rpc      19001
wait_tcp mall-product-rpc   9002
wait_tcp mall-order-rpc     9003
wait_tcp mall-workflow-rpc  9012
wait_tcp mall-rule-rpc      9011
wait_tcp mall-activity-rpc  9010
wait_tcp mall-reward-rpc    9013

# TCP port open does not mean gRPC is ready — services still need time to
# connect to etcd, load config, and finish registering handlers.
echo "==> waiting 20s for gRPC handlers to fully register..."
sleep 20

echo ""
echo "=== [1/7] Seeding shops ==="
./seed-mall-shop-rpc \
    --shop  "mall-shop-rpc:9017" \
    --ds    "$DS_SHOP" \
    --minio "http://minio:9000/mall-shop"

echo "=== [2/7] Seeding users & addresses ==="
./seed-mall-user-rpc \
    --ds "$DS_USER"

echo "=== [3/7] Seeding products ==="
./seed-mall-product-rpc \
    --product "mall-product-rpc:9002" \
    --ds      "$DS_PRODUCT" \
    --shop-ds "$DS_SHOP" \
    --minio   "http://minio:9000/mall-product"

echo "=== [4/7] Seeding orders ==="
./seed-mall-order-rpc \
    --order      "mall-order-rpc:9003" \
    --ds         "$DS_ORDER" \
    --user-ds    "$DS_USER" \
    --product-ds "$DS_PRODUCT"

echo "=== [5/7] Seeding workflow definitions ==="
./seed-mall-workflow-rpc \
    --workflow "mall-workflow-rpc:9012" \
    --rule     "mall-rule-rpc:9011"

# Give replication a moment to propagate workflow rows to read replicas
sleep 3

DS_WORKFLOW="${DSN_BASE}/mall_workflow?charset=utf8mb4&parseTime=true&loc=Local"

echo "=== [6/7] Seeding activities ==="
./seed-mall-activity-rpc \
    --activity   "mall-activity-rpc:9010" \
    --ds         "$DS_ACTIVITY" \
    --workflow-ds "$DS_WORKFLOW" \
    --redis      "redis-master:6379"

echo "=== [7/7] Seeding rewards ==="
./seed-mall-reward-rpc \
    --reward "mall-reward-rpc:9013"

echo ""
echo "✅ All seeds complete!"
