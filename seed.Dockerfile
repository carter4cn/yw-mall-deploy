# syntax=docker/dockerfile:1
# Seed image — compiles all cmd/seed programs and runs them in dependency order.
#
# Build context: .. (parent of yw-mall-deploy, i.e. the mall root).
# A seed.Dockerfile.dockerignore next to this file limits what gets sent.
#
# Used via:  docker compose --profile seed run --rm db-seed
#        or: make seed

FROM docker.io/library/golang:1.26-alpine AS builder
WORKDIR /workspace

# Only the services that have cmd/seed programs
COPY yw-mall/mall-common        ./mall-common
COPY yw-mall/mall-shop-rpc      ./mall-shop-rpc
COPY yw-mall/mall-user-rpc      ./mall-user-rpc
COPY yw-mall/mall-product-rpc   ./mall-product-rpc
COPY yw-mall/mall-order-rpc     ./mall-order-rpc
COPY yw-mall/mall-workflow-rpc  ./mall-workflow-rpc
COPY yw-mall/mall-rule-rpc      ./mall-rule-rpc
COPY yw-mall/mall-activity-rpc  ./mall-activity-rpc
COPY yw-mall/mall-reward-rpc    ./mall-reward-rpc

RUN set -e; \
    mkdir -p /out; \
    for svc in \
        mall-shop-rpc \
        mall-user-rpc \
        mall-product-rpc \
        mall-order-rpc \
        mall-workflow-rpc \
        mall-activity-rpc \
        mall-reward-rpc; \
    do \
        [ -f "/workspace/$svc/cmd/seed/main.go" ] || continue; \
        echo "==> building seed/$svc"; \
        cd /workspace/$svc && \
            CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/seed-$svc ./cmd/seed; \
        cd /workspace; \
    done

FROM docker.io/library/alpine:3.21
RUN apk add --no-cache ca-certificates tzdata netcat-openbsd
ENV TZ=Asia/Shanghai
WORKDIR /app
COPY --from=builder /out/ ./
COPY yw-mall-deploy/scripts/seed-run.sh /app/seed.sh
RUN chmod +x /app/seed.sh
CMD ["/app/seed.sh"]
