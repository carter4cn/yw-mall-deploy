#!/bin/bash
# Push all service configs from local etc/*.yaml files to etcd.
# Run this after first deploy or whenever you want etcd to reflect local files.
# Usage: bash scripts/config-push.sh [--dry-run]
set -e

BACKEND="${BACKEND:-../yw-mall}"
DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

# etcdctl helper: runs inside the etcd1 container
etcdctl() { podman exec -i etcd1 etcdctl --endpoints=http://127.0.0.1:2379 "$@"; }

APP_ENV="${APP_ENV:-dev}"
BASE="/config/${APP_ENV}/yw-mall"

# Mapping: etcd key → local yaml path (relative to $BACKEND)
KEYS=(
    "${BASE}/api-gateway"
    "${BASE}/user-rpc"
    "${BASE}/shop-rpc"
    "${BASE}/product-rpc"
    "${BASE}/order-rpc"
    "${BASE}/cart-rpc"
    "${BASE}/payment-rpc"
    "${BASE}/activity-rpc"
    "${BASE}/activity-worker"
    "${BASE}/workflow-rpc"
    "${BASE}/rule-rpc"
    "${BASE}/reward-rpc"
    "${BASE}/risk-rpc"
    "${BASE}/review-rpc"
    "${BASE}/logistics-rpc"
)
LOCAL_PATHS=(
    "mall-api/etc/mall-api.yaml"
    "mall-user-rpc/etc/user.yaml"
    "mall-shop-rpc/etc/shop.yaml"
    "mall-product-rpc/etc/product.yaml"
    "mall-order-rpc/etc/order.yaml"
    "mall-cart-rpc/etc/cart.yaml"
    "mall-payment-rpc/etc/payment.yaml"
    "mall-activity-rpc/etc/activity.yaml"
    "mall-activity-async-worker/etc/worker.yaml"
    "mall-workflow-rpc/etc/workflow.yaml"
    "mall-rule-rpc/etc/rule.yaml"
    "mall-reward-rpc/etc/reward.yaml"
    "mall-risk-rpc/etc/risk.yaml"
    "mall-review-rpc/etc/review.yaml"
    "mall-logistics-rpc/etc/logistics.yaml"
)

# Rewrite 127.0.0.1 loopback addresses to container names so configs work
# inside Docker/Podman containers. Local YAML files keep 127.0.0.1 for dev.
transform_for_deploy() {
    sed \
        -e 's|127\.0\.0\.1:2379|etcd1:2379|g' \
        -e 's|127\.0\.0\.1:6033|proxysql:6033|g' \
        -e 's|127\.0\.0\.1:6379|redis-master:6379|g' \
        -e 's|127\.0\.0\.1:9000|minio:9000|g' \
        -e 's|127\.0\.0\.1:19092|kafka1:9092|g' \
        -e 's|127\.0\.0\.1:19093|kafka2:9092|g' \
        -e 's|127\.0\.0\.1:19094|kafka3:9092|g' \
        -e 's|127\.0\.0\.1:36789|dtm:36789|g' \
        -e 's|127\.0\.0\.1:18888|mall-api:18888|g'
}

echo "==> Pushing configs to etcd $([ $DRY_RUN -eq 1 ] && echo "(DRY RUN)")"
ok=0; fail=0

for i in "${!KEYS[@]}"; do
    key="${KEYS[$i]}"
    local_path="$BACKEND/${LOCAL_PATHS[$i]}"
    if [ ! -f "$local_path" ]; then
        echo "  [SKIP] $key — file not found: $local_path"
        continue
    fi
    if [ $DRY_RUN -eq 1 ]; then
        echo "  [DRY]  $key ← $local_path"
        ok=$((ok+1))
        continue
    fi
    if transform_for_deploy < "$local_path" | etcdctl put "$key" > /dev/null 2>&1; then
        echo "  [OK]   $key ← $local_path"
        ok=$((ok+1))
    else
        echo "  [FAIL] $key ← $local_path"
        fail=$((fail+1))
    fi
done

echo ""
echo "Done: ${ok} pushed, ${fail} failed"
[ $fail -eq 0 ] || exit 1
