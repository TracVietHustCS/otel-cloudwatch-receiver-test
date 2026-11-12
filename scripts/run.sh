#!/usr/bin/env bash
# Chạy Collector bằng Docker. Dùng: scripts/run.sh [raw|transform] [--keep]
#   raw       config/config.yaml           -> out/logs.jsonl
#   transform config/config-transform.yaml -> out/logs-transformed.jsonl
# Mặc định chạy mới hoàn toàn (xóa checkpoint ./data và file output cũ); --keep để giữ lại.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "Chưa có .env: cp .env.example .env rồi điền key" >&2; exit 1; }
mode="${1:-raw}"; keep="${2:-}"
case "$mode" in
  raw)       cfg=config.yaml;           outf=logs.jsonl ;;
  transform) cfg=config-transform.yaml; outf=logs-transformed.jsonl ;;
  *) echo "dùng: scripts/run.sh [raw|transform] [--keep]" >&2; exit 2 ;;
esac

docker compose down >/dev/null 2>&1 || true
if [ "$keep" != "--keep" ]; then
  rm -rf data "out/$outf" 2>/dev/null || sudo rm -rf data "out/$outf"   # container chạy root nên có thể cần sudo
fi
mkdir -p out data
OTEL_CONFIG="$cfg" docker compose up -d
echo "Đang đợi Collector poll CloudWatch (mỗi 30s), tối đa 120s..."
t0=$(date +%s)
until [ -s "out/$outf" ] || [ $(( $(date +%s) - t0 )) -ge 120 ]; do sleep 2; done
if [ -s "out/$outf" ]; then
  echo "OK sau $(( $(date +%s) - t0 ))s: out/$outf có $(wc -l < "out/$outf") dòng JSON (mỗi dòng là một batch)."
  echo "Xem: cat out/$outf"
else
  echo "Chưa có out/$outf sau 120s. Xem lỗi: docker compose logs otel-collector" >&2; exit 1
fi
