#!/bin/sh
# Ensure MinIO buckets exist, are publicly readable, and have placeholder images.
# Safe to re-run: skips uploads when objects already exist.
set -e

MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"
MINIO_USER="${MINIO_USER:-admin}"
MINIO_PASS="${MINIO_PASS:-admin123}"
MC="${MC:-/tmp/mc}"

# ── 1. Ensure mc is available ─────────────────────────────────────────────────
if ! "$MC" --version >/dev/null 2>&1; then
    echo "==> downloading mc client..."
    curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o "$MC"
    chmod +x "$MC"
fi

# ── 2. Wait for MinIO ─────────────────────────────────────────────────────────
printf "==> waiting for MinIO at %s " "$MINIO_ENDPOINT"
for i in $(seq 1 30); do
    if curl -sf "$MINIO_ENDPOINT/minio/health/live" >/dev/null 2>&1; then
        echo " ok"
        break
    fi
    printf "."
    sleep 2
done

"$MC" alias set local "$MINIO_ENDPOINT" "$MINIO_USER" "$MINIO_PASS" >/dev/null 2>&1

# ── 3. Create buckets + public policy ─────────────────────────────────────────
for bucket in mall-shop mall-product; do
    "$MC" mb --ignore-existing "local/$bucket" >/dev/null 2>&1
    "$MC" anonymous set public "local/$bucket" >/dev/null 2>&1
    echo "==> bucket $bucket: ready (public-read)"
done

# ── 4. Upload placeholder images if missing ───────────────────────────────────
# Generate minimal solid-color PNGs with Python (no deps needed).
python3 - << 'PYEOF'
import struct, zlib, os, subprocess, sys

def make_png(w, h, r, g, b):
    def chunk(name, data):
        c = name + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    raw = b''.join(b'\x00' + bytes([r,g,b]) * w for _ in range(h))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

mc  = os.environ.get('MC', '/tmp/mc')
colors = [(66,133,244),(234,67,53),(251,188,4),(52,168,83),(255,109,0),(171,71,188),(0,188,212),(255,64,129)]

specs = []
for i in range(1, 7):
    r,g,b = colors[(i-1) % len(colors)]
    specs.append(('mall-shop', f'logo_{i}.png',   make_png(200, 200, r, g, b)))
    specs.append(('mall-shop', f'banner_{i}.png',  make_png(800, 300, r, g, b)))
for i in range(1, 41):
    r,g,b = colors[(i-1) % len(colors)]
    specs.append(('mall-product', f'product_{i}.png', make_png(400, 400, r, g, b)))

tmp = '/tmp/minio-placeholders'
os.makedirs(f'{tmp}/mall-shop',    exist_ok=True)
os.makedirs(f'{tmp}/mall-product', exist_ok=True)

uploaded = 0
for bucket, name, data in specs:
    key = f'local/{bucket}/{name}'
    # check if object already exists
    r = subprocess.run([mc, 'stat', key], capture_output=True)
    if r.returncode == 0:
        continue
    path = f'{tmp}/{bucket}/{name}'
    with open(path, 'wb') as f:
        f.write(data)
    subprocess.run([mc, 'cp', path, key], check=True, capture_output=True)
    uploaded += 1

print(f'==> placeholder images: {uploaded} uploaded, {len(specs)-uploaded} already present')
PYEOF
