#!/bin/bash
# Rebuild all images with three optimizations:
#   1. Parallel builds (JOBS concurrent Go services)
#   2. Per-service minimal COPY (only what go.mod replace directives need)
#   3. go.mod+go.sum cached layer before source copy
set -euo pipefail

COMPOSE="${COMPOSE:-podman-compose}"
BASE=/home/carter/workspace/go/mall/yw-mall
JOBS=4

# ── Tunables (env overrides) ──────────────────────────────────────────────
#   NO_CACHE=1   force --no-cache for podman build (default: 1, full rebuild)
#                set NO_CACHE=0 for fast incremental rebuilds — go.mod caching
#                layer + BuildKit cache mounts make this 5-10× faster
#   GOPROXY      forwarded as build-arg; useful in CN: GOPROXY=https://goproxy.cn,direct
NO_CACHE="${NO_CACHE:-1}"
GOPROXY="${GOPROXY:-}"
NO_CACHE_FLAG=""
[ "$NO_CACHE" = "1" ] && NO_CACHE_FLAG="--no-cache"

GO_SERVICES=(
  mall-user-rpc      mall-shop-rpc       mall-product-rpc
  mall-order-rpc     mall-cart-rpc       mall-payment-rpc
  mall-activity-rpc  mall-rule-rpc       mall-workflow-rpc
  mall-reward-rpc    mall-risk-rpc       mall-review-rpc
  mall-logistics-rpc mall-activity-async-worker mall-api
)
TOTAL_GO=${#GO_SERVICES[@]}

# ── Shared state (files, readable across subprocesses) ────────────────────
DONE_F=$(mktemp)
FAIL_F=$(mktemp)
SEM_DIR=$(mktemp -d)   # semaphore: one file per running job
LOG_DIR=$(mktemp -d)
echo 0 > "$DONE_F"; echo 0 > "$FAIL_F"
# Cleanup on EXIT — but KEEP $LOG_DIR if any build failed, so the user can
# read the logs to diagnose. Path is printed in the failure summary below.
cleanup() {
  local fails=0
  [ -f "$FAIL_F" ] && fails=$(cat "$FAIL_F" 2>/dev/null || echo 0)
  rm -f "$DONE_F" "$FAIL_F"
  rm -rf "$SEM_DIR"
  if [ "$fails" -gt 0 ]; then
    echo "  (logs preserved at $LOG_DIR)" >&2
  else
    rm -rf "$LOG_DIR"
  fi
}
trap cleanup EXIT

inc_done() { printf '%d\n' $(( $(cat "$DONE_F") + 1 )) > "$DONE_F"; }
inc_fail() { printf '%d\n' $(( $(cat "$FAIL_F") + 1 )) > "$FAIL_F"; }

# ── Dep parsing: replace directives → list of needed dirs ─────────────────
# Handles BOTH single-line (`replace foo => ../bar`) and block-form
#   replace (
#       foo => ../bar
#       baz => ../qux
#   )
# Earlier version only matched single-line, silently dropping block deps and
# causing `go mod download` to fail with "no such file or directory".
get_deps() {
  local svc=$1
  echo "$svc"
  awk '
    /^[[:space:]]*replace[[:space:]]*\(/ { in_block=1; next }
    in_block && /^[[:space:]]*\)/        { in_block=0; next }
    in_block                              { print $NF; next }
    /^[[:space:]]*replace[[:space:]]/    { print $NF }
  ' "$BASE/$svc/go.mod" 2>/dev/null \
    | grep '^\.\.' | sed 's|^\.\./||' | sort -u
}

# ── Per-service Dockerfile: minimal COPY + go.mod caching layer ───────────
gen_dockerfile() {
  local svc=$1 dep deps
  deps=$(get_deps "$svc")
  cat <<'HDR'
# syntax=docker/dockerfile:1
FROM docker.io/library/golang:1.26-alpine AS builder
ARG GOPROXY=
ENV GOPROXY=${GOPROXY:+$GOPROXY}
WORKDIR /workspace

HDR
  echo "# Layer 1: go.mod + go.sum — cached when only source changes"
  for dep in $deps; do
    printf 'COPY %s/go.mod %s/go.sum ./%s/\n' "$dep" "$dep" "$dep"
  done
  cat <<'MOD'

ARG SERVICE
# Cache mounts share GOPATH/build-cache across concurrent and repeated builds —
# downloaded modules and compiled artifacts persist on the host BuildKit cache.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    cd /workspace/${SERVICE} && go mod download

# Layer 2: full source
MOD
  for dep in $deps; do
    printf 'COPY %s ./%s\n' "$dep" "$dep"
  done
  cat <<'TAIL'

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    mkdir -p /out && \
    cd /workspace/${SERVICE} && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/server . && \
    cp -r etc /out/etc

FROM docker.io/library/alpine:3.21
RUN apk add --no-cache ca-certificates tzdata
ENV TZ=Asia/Shanghai
WORKDIR /app
COPY --from=builder /out/server  ./server
COPY --from=builder /out/etc     ./etc
COPY docker-entrypoint.sh        ./entrypoint.sh
RUN chmod +x ./entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
TAIL
}

# ── Build one service (runs in subshell, updates counters directly) ────────
build_one() {
  local svc=$1 log="$LOG_DIR/$1.log" tmpdf
  tmpdf=$(mktemp /tmp/Dockerfile-${svc}-XXXXXX)
  gen_dockerfile "$svc" > "$tmpdf"
  podman build $NO_CACHE_FLAG \
    -f "$tmpdf" --build-arg SERVICE="$svc" \
    ${GOPROXY:+--build-arg GOPROXY="$GOPROXY"} \
    -t "localhost/yw-mall-deploy_${svc}:latest" \
    "$BASE" >> "$log" 2>&1
  local rc=$?
  rm -f "$tmpdf"
  return $rc
}

# ── Progress bar ──────────────────────────────────────────────────────────
show_progress() {
  local total=$1 label=$2 start=$SECONDS
  while true; do
    local done fail elapsed min sec filled bar i
    done=$(cat "$DONE_F" 2>/dev/null || echo 0)
    fail=$(cat "$FAIL_F" 2>/dev/null || echo 0)
    elapsed=$(( SECONDS - start )); min=$(( elapsed/60 )); sec=$(( elapsed%60 ))
    filled=$(( total > 0 ? done * 20 / total : 0 ))
    bar=""; i=0
    while [ $i -lt $filled ]; do bar="${bar}="; i=$(( i+1 )); done
    [ "$done" -lt "$total" ] && bar="${bar}>"
    i=$(( filled+1 )); while [ $i -lt 20 ]; do bar="${bar} "; i=$(( i+1 )); done
    printf '\r  %-24s [%-20s] %2d/%-2d  %02d:%02d' \
      "$label" "$bar" "$done" "$total" "$min" "$sec"
    sleep 5
  done
}

finish_bar() {
  local label=$1 total=$2 start=$3 prog_pid=$4
  kill "$prog_pid" 2>/dev/null; wait "$prog_pid" 2>/dev/null || true
  local done fail elapsed min sec
  done=$(cat "$DONE_F"); fail=$(cat "$FAIL_F")
  elapsed=$(( SECONDS - start )); min=$(( elapsed/60 )); sec=$(( elapsed%60 ))
  printf '\r  %-24s [%-20s] %2d/%-2d  %02d:%02d  %s\n' \
    "$label" "====================" "$done" "$total" "$min" "$sec" \
    "$([ "$fail" -eq 0 ] && echo OK || echo "FAIL:$fail")"
}

# ── Parallel runner using semaphore directory ─────────────────────────────
# Collect each spawned PID and `wait $pid` only on those — `wait` without
# args waits for ALL background jobs in this shell, which would include the
# show_progress infinite loop and hang forever.
run_parallel() {
  local svc pids=()
  for svc in "${GO_SERVICES[@]}"; do
    while [ "$(ls "$SEM_DIR" | wc -l)" -ge "$JOBS" ]; do sleep 1; done
    (
      touch "$SEM_DIR/$svc"
      if build_one "$svc"; then
        inc_done
      else
        inc_fail
        printf '\n  [FAIL] %s  →  %s\n' "$svc" "$LOG_DIR/$svc.log" >&2
      fi
      rm -f "$SEM_DIR/$svc"
    ) &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}

# ── Main ──────────────────────────────────────────────────────────────────
# Guard: refuse to run when the script is sourced (only execute when invoked
# as `bash scripts/rebuild.sh`). Tools that probe for a build command may
# `source` this file; without the guard, sourcing would spawn real podman
# builds in the caller's shell.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

echo "==> rebuild  $([ "$NO_CACHE" = "1" ] && echo no-cache || echo cached)  parallel=${JOBS}${GOPROXY:+  GOPROXY=$GOPROXY}"
echo ""

# [1/3] Go services
printf '[1/3] Go services (%d, %d parallel)\n' "$TOTAL_GO" "$JOBS"
START=$SECONDS
show_progress "$TOTAL_GO" "Go services (${TOTAL_GO})" &
PROG=$!
run_parallel
finish_bar "Go services (${TOTAL_GO})" "$TOTAL_GO" "$START" "$PROG"
[ "$(cat "$FAIL_F")" -eq 0 ] || { echo "Go build failed — aborting."; exit 1; }

# [2/3] Frontend + seed + admin-api (in parallel with each other)
echo 0 > "$DONE_F"; echo 0 > "$FAIL_F"
printf '[2/3] Frontend + seed + admin-api\n'
START=$SECONDS
show_progress 3 "fe + seed + admin" &
PROG=$!
(
  $COMPOSE build $NO_CACHE_FLAG mall-fe >> "$LOG_DIR/mall-fe.log" 2>&1 && inc_done \
    || { inc_fail; printf '\n  [FAIL] mall-fe\n' >&2; }
) &
FE_PID=$!
(
  $COMPOSE --profile seed build $NO_CACHE_FLAG db-seed >> "$LOG_DIR/db-seed.log" 2>&1 && inc_done \
    || { inc_fail; printf '\n  [FAIL] db-seed\n' >&2; }
) &
SEED_PID=$!
(
  $COMPOSE build $NO_CACHE_FLAG mall-admin-api >> "$LOG_DIR/mall-admin-api.log" 2>&1 && inc_done \
    || { inc_fail; printf '\n  [FAIL] mall-admin-api\n' >&2; }
) &
ADMIN_PID=$!
# Only wait on the build subshells — bare `wait` would also block on the
# show_progress infinite loop in $PROG.
wait "$FE_PID" 2>/dev/null || true
wait "$SEED_PID" 2>/dev/null || true
wait "$ADMIN_PID" 2>/dev/null || true
finish_bar "fe + seed + admin" 3 "$START" "$PROG"
[ "$(cat "$FAIL_F")" -eq 0 ] || { echo "Frontend/seed/admin build failed — aborting."; exit 1; }

# [3/3] Start
printf '[3/3] Starting services...\n'
$COMPOSE up -d
echo "==> Done."
