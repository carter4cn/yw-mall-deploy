#!/bin/bash
# Diff etcd configs against local etc/*.yaml files.
# Exits 0 if all match, 1 if any differ or are missing.
set -e

BACKEND="${BACKEND:-../yw-mall}"

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

echo "==> Diffing etcd configs vs local files"
diffs=0; missing=0

for i in "${!KEYS[@]}"; do
    key="${KEYS[$i]}"
    local_path="$BACKEND/${LOCAL_PATHS[$i]}"
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
