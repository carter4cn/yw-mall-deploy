#!/bin/bash
# Applies DDL to all mall_* databases via ProxySQL.
# Runs as a one-shot Docker service before any RPC starts.
set -e

MYSQL="mysql -h proxysql -P 6033 -uproxysql -pproxysql123"

echo "⏳ Waiting for ProxySQL..."
until $MYSQL -e "SELECT 1" >/dev/null 2>&1; do
  sleep 3
done
echo "✓ ProxySQL ready"

echo "Creating databases..."
for db in mall_user mall_product mall_order mall_cart mall_payment \
          mall_shop mall_activity mall_rule mall_workflow mall_reward \
          mall_risk mall_review mall_logistics; do
  $MYSQL -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  echo "  ✓ $db"
done

echo "Applying DDL..."
apply() {
  local db=$1 f=/workspace/$2
  [ -f "$f" ] || { echo "  ⚠ missing $f"; return; }
  $MYSQL "$db" < "$f" 2>&1 | grep -v "^Warning" | grep . || true
  echo "  ✓ $db ← $(basename "$f")"
}

apply mall_user       mall-user-rpc/sql/user.sql
apply mall_product    mall-product-rpc/sql/product.sql
apply mall_order      mall-order-rpc/sql/order.sql
apply mall_cart       mall-cart-rpc/sql/cart.sql
apply mall_payment    mall-payment-rpc/sql/payment.sql
apply mall_activity   mall-activity-rpc/sql/activity.sql
apply mall_rule       mall-rule-rpc/sql/rule.sql
apply mall_workflow   mall-workflow-rpc/sql/workflow.sql
apply mall_reward     mall-reward-rpc/sql/reward.sql
apply mall_risk       mall-risk-rpc/sql/risk.sql
apply mall_review     mall-review-rpc/sql/review.sql
apply mall_logistics  mall-logistics-rpc/sql/logistics.sql
apply mall_shop       mall-shop-rpc/sql/shop.sql

echo "✅ DB bootstrap complete"
