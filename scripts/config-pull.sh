#!/bin/bash
# Pull all service configs from etcd and optionally write to local etc/*.yaml files.
# Usage:
#   bash scripts/config-pull.sh           -- print to stdout only
#   bash scripts/config-pull.sh --write   -- overwrite local files
set -e

BACKEND="${BACKEND:-../yw-mall}"
WRITE=0
[ "$1" = "--write" ] && WRITE=1

etcdctl() { podman exec -i etcd1 etcdctl --endpoints=http://127.0.0.1:2379 "$@"; }

APP_ENV="${APP_ENV:-dev}"
BASE="/config/${APP_ENV}/yw-mall"

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

echo "==> Pulling configs from etcd $([ $WRITE -eq 1 ] && echo "(writing to local files)")"

for i in "${!KEYS[@]}"; do
    key="${KEYS[$i]}"
    local_path="$BACKEND/${LOCAL_PATHS[$i]}"
    value=$(etcdctl get "$key" --print-value-only 2>/dev/null || true)
    if [ -z "$value" ]; then
        echo "  [MISSING] $key"
        continue
    fi
    if [ $WRITE -eq 1 ]; then
        echo "$value" > "$local_path"
        echo "  [WRITTEN] $key → $local_path"
    else
        echo ""
        echo "  ─── $key ───"
        echo "$value"
    fi
done
