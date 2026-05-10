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

# Mapping: etcd key → local yaml path (relative to $BACKEND)
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

echo "==> Pushing configs to etcd $([ $DRY_RUN -eq 1 ] && echo "(DRY RUN)")"
ok=0; fail=0

for key in "${!CONFIGS[@]}"; do
    local_path="$BACKEND/${CONFIGS[$key]}"
    if [ ! -f "$local_path" ]; then
        echo "  [SKIP] $key — file not found: $local_path"
        continue
    fi
    if [ $DRY_RUN -eq 1 ]; then
        echo "  [DRY]  $key ← $local_path"
        ok=$((ok+1))
        continue
    fi
    if etcdctl put "$key" < "$local_path" > /dev/null 2>&1; then
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
