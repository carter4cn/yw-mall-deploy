#!/bin/bash
# Diff etcd configs against local etc/*.yaml files.
# Exits 0 if all match, 1 if any differ or are missing.
set -e

BACKEND="${BACKEND:-../yw-mall}"

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

echo "==> Diffing etcd configs vs local files"
diffs=0; missing=0

for key in "${!CONFIGS[@]}"; do
    local_path="$BACKEND/${CONFIGS[$key]}"
    etcd_val=$(etcdctl get "$key" --print-value-only 2>/dev/null || true)

    if [ -z "$etcd_val" ]; then
        echo "  [MISSING in etcd] $key"
        missing=$((missing+1))
        continue
    fi
    if [ ! -f "$local_path" ]; then
        echo "  [MISSING locally] $local_path"
        missing=$((missing+1))
        continue
    fi

    diff_out=$(diff <(echo "$etcd_val") "$local_path" || true)
    if [ -n "$diff_out" ]; then
        echo ""
        echo "  [DIFF] $key"
        echo "$diff_out" | sed 's/^/    /'
        diffs=$((diffs+1))
    else
        echo "  [OK]   $key"
    fi
done

echo ""
echo "Result: ${diffs} differ, ${missing} missing"
[ $((diffs + missing)) -eq 0 ] || exit 1
