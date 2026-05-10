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

declare -A CONFIGS=(
    ["/mall/config/mall-api"]="mall-api/etc/mall-api.yaml"
    ["/mall/config/user-rpc"]="mall-user-rpc/etc/user.yaml"
    ["/mall/config/product-rpc"]="mall-product-rpc/etc/product.yaml"
    ["/mall/config/order-rpc"]="mall-order-rpc/etc/order.yaml"
    ["/mall/config/cart-rpc"]="mall-cart-rpc/etc/cart.yaml"
    ["/mall/config/payment-rpc"]="mall-payment-rpc/etc/payment.yaml"
    ["/mall/config/activity-rpc"]="mall-activity-rpc/etc/activity.yaml"
    ["/mall/config/workflow-rpc"]="mall-workflow-rpc/etc/workflow.yaml"
    ["/mall/config/reward-rpc"]="mall-reward-rpc/etc/reward.yaml"
    ["/mall/config/risk-rpc"]="mall-risk-rpc/etc/risk.yaml"
    ["/mall/config/review-rpc"]="mall-review-rpc/etc/review.yaml"
    ["/mall/config/logistics-rpc"]="mall-logistics-rpc/etc/logistics.yaml"
    ["/mall/config/shop-rpc"]="mall-shop-rpc/etc/shop.yaml"
    ["/mall/config/rule-rpc"]="mall-rule-rpc/etc/rule.yaml"
    ["/mall/config/activity-async-worker"]="mall-activity-async-worker/etc/worker.yaml"
)

echo "==> Pulling configs from etcd $([ $WRITE -eq 1 ] && echo "(writing to local files)")"

for key in "${!CONFIGS[@]}"; do
    local_path="$BACKEND/${CONFIGS[$key]}"
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
