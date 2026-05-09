# 工作进展 — 2026-05-10

## 当前状态：部署基本跑通，前台可正常访问

### 访问地址
- 前台：http://localhost:18080
- API 网关：http://localhost:18888
- MinIO 文件存储：http://localhost:9001（admin / admin123）

### 测试账号
| 用户名 | 密码 |
|---|---|
| alice | alice123 |
| bob | bob123 |
| demo | demo123 |

---

## 今日修复内容（已全部推送到 GitHub）

### yw-mall-env repo
- `compose.yml`：MySQL 四个节点加 `user: "999:999"` + `restart: unless-stopped`，解决 Podman rootless 下重启后 chown 失败导致的 crash-restart 问题
- `mysql/proxysql.cnf`：从写组(hostgroup=10)移除 master2，只保留 master1，防止双主写入导致 auto_increment 冲突（split-brain）

### yw-mall repo
- `mall-user-rpc/cmd/seed/main.go`：改为直接 SQL INSERT，绕过 gRPC（bcrypt DefaultCost ~1900ms 超过 go-zero 2s server timeout）
- `mall-order-rpc/cmd/seed/main.go`：运行时动态解析 alice/bob/demo 真实 user_id，不再硬编码（master1 auto_increment 为奇数：1,3,5）
- `mall-activity-rpc/cmd/seed/main.go`：新增 `--workflow-ds` flag，读取正确数据库

### yw-mall-deploy repo
- `Makefile`：完整重写，支持 Podman rootless 一键启停
  - `infra-up`：自动 mkdir + podman unshare chown MySQL 数据目录
  - `infra-up`：自动启动 Created 状态的容器（sentinels, proxysql, mysql-init）
  - `infra-up`：flush Redis `cache:*` 防止旧缓存污染新数据
  - `infra-up`：自动初始化 MinIO bucket + 上传占位图
  - 新增 `minio-init`、`nuke-mysql`、`start`、`stop` targets
- `scripts/seed-run.sh`：去掉 `--user` flag；workflow seed 后加 `sleep 3` 等待主从同步
- `scripts/minio-init.sh`（新）：等待 MinIO 就绪，创建 bucket，设 public-read，生成彩色占位图上传

---

## 已知问题 / 待办

### 图片是占位色块，不是真实图片
seed 只存了图片 URL（`http://localhost:9000/mall-shop/logo_N.png`），并未上传真实图片。
当前用 Python 生成了彩色纯色占位 PNG。如需真实图片，需在 seed 中实现图片上传逻辑，或手动上传到 MinIO。

### `make seed` 幂等性限制
- 订单表：只检查总数 >= 5 才跳过，否则追加创建（中途失败后重跑会重复）
  → 如需干净重跑：先 `podman exec mysql-master1 mysql -uroot -proot123 mall_order -e "TRUNCATE TABLE order_item; TRUNCATE TABLE \`order\`;"`
- 活动/workflow：已有时 duplicate key 静默跳过，正常

### MinIO 图片重启后丢失问题
`make infra-down` 不会丢失 MinIO 数据（数据持久化到 `env/data/minio/`）。
但如果 MinIO 数据目录被手动清理，需重跑 `make minio-init`。

### 下次从零启动流程
```bash
make nuke-mysql          # 清空 MySQL 数据目录（可选，全新开始时用）
make infra-up            # 启动基础设施（自动处理 MySQL 权限、Redis 缓存、MinIO bucket）
make up                  # 启动所有应用服务
make seed                # 写入 demo 数据（幂等，安全重跑）
```

### 功能待续开发
- 前台登录页（目前是占位页面，`login/index.vue` 为 wd-empty 组件）
- 购物车、结算、支付流程的前端页面
- 营销活动页（秒杀、优惠券、签到）
