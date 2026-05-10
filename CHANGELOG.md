# Changelog

All notable changes to yw-mall-deploy are documented here.

---

## [Unreleased] — feature/etcd-config-center

### 2026-05-10

#### feat: etcd 配置中心运维脚本 + 容器环境变量注入

**背景**

配合 yw-mall 的 etcd 配置中心改造，部署层需要提供：配置初始化（将本地 YAML 推送到 etcd）、配置查看（从 etcd 拉取）、配置校验（本地 vs etcd diff），以及让容器服务在启动时能找到 etcd 集群。

---

#### 新增 — scripts/

**`scripts/config-push.sh`**
- 将 `../yw-mall` 下 15 个服务的本地 `etc/*.yaml` 推送到 etcd
- 支持 `--dry-run` 模式（只打印，不写入）
- 文件不存在时跳过并统计，推送完成后汇总 `pushed / skipped / failed` 计数
- etcd 访问通过 `podman exec -i etcd1 etcdctl --endpoints=http://127.0.0.1:2379`

**`scripts/config-pull.sh`**
- 从 etcd 拉取全部 15 个服务配置
- 默认打印到 stdout；加 `--write` 参数时覆盖写入本地 `etc/*.yaml`
- key 缺失时标记 `[MISSING]` 并继续

**`scripts/config-diff.sh`**
- 逐 key 对比 etcd 值与本地 YAML 文件
- 输出 `[OK]` / `[DIFF]` / `[MISSING in etcd]` / `[MISSING locally]`
- 有任何差异或缺失时以退出码 1 返回，便于 CI 检查

etcd key 到本地路径映射（15 个服务）：

| etcd key | 本地路径（相对 `../yw-mall`）|
|----------|--------------------------|
| `/mall/config/mall-api` | `mall-api/etc/mall-api.yaml` |
| `/mall/config/user-rpc` | `mall-user-rpc/etc/user.yaml` |
| `/mall/config/product-rpc` | `mall-product-rpc/etc/product.yaml` |
| `/mall/config/order-rpc` | `mall-order-rpc/etc/order.yaml` |
| `/mall/config/cart-rpc` | `mall-cart-rpc/etc/cart.yaml` |
| `/mall/config/payment-rpc` | `mall-payment-rpc/etc/payment.yaml` |
| `/mall/config/activity-rpc` | `mall-activity-rpc/etc/activity.yaml` |
| `/mall/config/workflow-rpc` | `mall-workflow-rpc/etc/workflow.yaml` |
| `/mall/config/reward-rpc` | `mall-reward-rpc/etc/reward.yaml` |
| `/mall/config/risk-rpc` | `mall-risk-rpc/etc/risk.yaml` |
| `/mall/config/review-rpc` | `mall-review-rpc/etc/review.yaml` |
| `/mall/config/logistics-rpc` | `mall-logistics-rpc/etc/logistics.yaml` |
| `/mall/config/shop-rpc` | `mall-shop-rpc/etc/shop.yaml` |
| `/mall/config/rule-rpc` | `mall-rule-rpc/etc/rule.yaml` |
| `/mall/config/activity-async-worker` | `mall-activity-async-worker/etc/worker.yaml` |

---

#### 修改 — compose.yml

`x-rpc-defaults` anchor 新增 environment 块：

```yaml
environment:
  - ETCD_HOSTS=${ETCD_HOSTS:-etcd1:2379,etcd2:2379,etcd3:2379}
```

所有继承此 anchor 的 RPC 服务（mall-user-rpc、mall-product-rpc 等共 14 个）自动获得该环境变量，服务启动时 configcenter 读取它来定位 etcd 集群。

---

#### 修改 — .env

新增：

```
ETCD_HOSTS=etcd1:2379,etcd2:2379,etcd3:2379
```

与 env/compose.yml 中 etcd 集群的容器名保持一致，供 docker/podman compose 注入到容器环境。

---

#### 修改 — Makefile

新增三个 target：

```makefile
config-push:  ## Push all local etc/*.yaml configs to etcd (first deploy or manual sync)
config-pull:  ## Pull configs from etcd and print to stdout
config-diff:  ## Diff etcd configs against local etc/*.yaml files
```

典型使用流程：

```bash
# 首次部署：推送所有配置到 etcd
make config-push

# 验证推送结果
make config-diff

# 查看 etcd 中某服务的当前配置
make config-pull
```

---

#### 典型运维流程

```
本地修改 etc/*.yaml
       ↓
make config-push        # 推送到 etcd（服务自动热更新，无需重启）
       ↓
make config-diff        # 确认 etcd 与本地一致（退出码 0）
```

---

## 历史版本

### 2026-05-09

#### feat: 一键部署 + MinIO 初始化

- 新增 `scripts/minio-init.sh`：自动创建 bucket、设置公共读策略、上传占位图片
- `infra-up` 自动执行 minio-init，首次部署免手动操作
- `infra-up` 自动刷新 Redis `cache:*` 键，防止重启后读到过期缓存
- compose.yml 完成：db-init → RPC 服务 → mall-api → mall-fe 启动顺序
- 新增 `make seed`：通过独立容器执行种子数据脚本
- 前端 mall-fe 暴露 18080，后端 mall-api 暴露 18888
