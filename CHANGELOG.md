# Changelog

All notable changes to yw-mall-deploy are documented here.

---

## [Unreleased]

### 2026-05-14

#### feat: 登录改造 P0 + P0.5 — 配套部署更新

**背景**

yw-mall 登录体系从 JWT 切换到 Opaque Token + Redis Session（详见 yw-mall-docs/feat/login-revamp.md）。
今日完成 P0（mall-api/mall-user-rpc）+ P0.5（mall-admin-api 同步切换 + admin-fe）。
部署层无 DDL 变更（session 全部走 Redis），但需推送新配置到 etcd。

**etcd 配置推送**

- `mall-user-rpc/etc/user.yaml` 新增 `Session` 块（AccessTTLSeconds=1800 / RefreshTTLSeconds=604800 / MaxRotateCount=10 / Redis）
- 已执行 `make config-push`：15 个 yaml 全部同步到 `/config/dev/yw-mall/*`

**容器镜像（待 next deploy 重建）**

下次 `make rebuild` 时会自动 rebuild 以下镜像并带上新二进制：
- mall-user-rpc — 新增 5 个 Session RPC
- mall-api — SessionAuthMiddleware + /api/auth/{login,refresh,logout}
- mall-admin-api — SessionAuthMiddleware（admin + merchant 双路由）+ 4 个新 auth handler

**Redis 依赖确认**

session/refresh/user_sessions:* key 全部写入主 Redis（已有 master + 2 slave），无需扩容。
TTL 已对齐文档（access 30min，refresh 7d）；后续 P1 加入「我的设备」会读取 `user_sessions:{uid}` SET。

**回滚预案**

如需回滚到 JWT：
1. `git revert` yw-mall + yw-mall-admin + yw-mall-fe + yw-mall-admin-fe 的 P0/P0.5 commit
2. `make config-push` 重新同步旧 yaml
3. `make rebuild`

不需要数据迁移（Redis session 自然过期；user 表无变更）。

---

### 2026-05-10

#### refactor: etcd key 全局规范化 + APP_ENV 注入

配合 yw-mall 的 key 格式重构，部署层同步更新。

**`.env`**
- 新增 `APP_ENV=dev`，控制 etcd key 中的环境层级

**`compose.yml`**
- `x-rpc-defaults` 新增 `APP_ENV=${APP_ENV:-dev}` 环境变量，注入所有 RPC 容器

**`scripts/config-push.sh` / `config-pull.sh` / `config-diff.sh`**
- 三个脚本均改用 `APP_ENV="${APP_ENV:-dev}"` + `BASE="/config/${APP_ENV}/yw-mall"` 构建 key
- 原 `declare -A` 关联数组改为两个并行数组（`KEYS` + `LOCAL_PATHS`），避免 bash 变量展开陷阱
- 服务名同步更新：`mall-api` → `api-gateway`，`activity-async-worker` → `activity-worker`
- 其余逻辑（dry-run、错误计数、etcdctl wrapper）保持不变

切换环境只需改 `APP_ENV=prod` 并重新 `make config-push`，脚本自动操作对应 prefix。

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
