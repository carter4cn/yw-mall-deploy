# yw-mall-deploy

Podman Compose deployment for the yw-mall Go microservices platform.

## 访问地址

| 服务 | 地址 | 说明 |
|---|---|---|
| 前台商城 | http://localhost:18080 | H5 前端（uni-app） |
| API 网关 | http://localhost:18888 | REST API 入口 |
| MinIO 文件存储 | http://localhost:9001 | admin / admin123 |
| etcd 控制台 | http://localhost:2380 | 服务注册查看 |
| Kafka UI | http://localhost:8080 | 消息队列监控 |
| Grafana | http://localhost:3000 | 监控面板 |

## 测试账号

| 用户名 | 密码 |
|---|---|
| alice | alice123 |
| bob | bob123 |
| demo | demo123 |

## 快速启动

**首次部署**（一条命令完成全部初始化）：

```bash
make bootstrap   # infra-up → config-push → up → seed，约 5 分钟
```

**日常启停**（etcd 中已有配置，无需重新推送）：

```bash
make start   # 等价于 make infra-up + make up
make stop    # 等价于 make down + make infra-down
```

## 常用命令

```bash
make config-push     # 将本地 etc/*.yaml 推送到 etcd（首次部署或配置变更后执行）
make config-pull     # 从 etcd 拉取所有配置并打印到 stdout
make config-diff     # 对比 etcd 配置与本地文件是否一致
make ps              # 查看所有服务状态
make logs            # 追踪所有服务日志
make logs-mall-api   # 追踪单个服务日志（替换 mall-api 为服务名）
make seed            # 重新写入 demo 数据（幂等）
make minio-init      # 重建 MinIO bucket + 上传占位图
make nuke            # 清空所有 mall_* 数据库（危险）
make nuke-mysql      # 清空 MySQL 数据目录（危险，需重跑 infra-up + seed）
make build           # 构建所有应用镜像
make rebuild         # 无缓存重新构建并启动
```

## 依赖的代码仓库

本 compose 部署依赖以下仓库，需放在同级目录：

```
workspace/go/mall/
├── env/             # 基础设施 compose（MySQL、Redis、Kafka 等）
├── yw-mall/         # Go 后端（15 个微服务）
├── yw-mall-fe/      # uni-app 前端
└── yw-mall-deploy/  # 本仓库
```

## 注意事项

- 运行在 **Podman rootless** 模式下，MySQL 数据目录由 `infra-up` 自动处理 uid 映射
- `make infra-down` 后重新 `make infra-up` 会自动刷新 Redis 缓存并重建 MinIO bucket
- MinIO 图片为彩色占位图，如需真实图片请手动上传至 `mall-shop` / `mall-product` bucket
