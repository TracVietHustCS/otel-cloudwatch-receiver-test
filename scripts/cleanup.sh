#!/usr/bin/env bash
# Dọn dẹp. Không có --yes thì chỉ in kế hoạch. Thêm --env để xóa luôn file .env (chứa key).
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."; [ -f .env ] && { set -a; . ./.env; set +a; }
G=/otel-cw-test; region="${AWS_REGION:?hãy đặt AWS_REGION (trong .env)}"
yes=0; env=0
for a in "$@"; do [ "$a" = "--yes" ] && yes=1; [ "$a" = "--env" ] && env=1; done
echo "Sẽ làm:"
echo "  1. docker compose down"
echo "  2. xóa ./out và ./data"
echo "  3. xóa log group $G (region $region), chỉ group này"
[ "$env" = 1 ] && echo "  4. xóa file .env"
[ "$yes" = 1 ] || { echo "Chưa làm gì. Chạy lại với --yes (thêm --env nếu muốn xóa .env)."; exit 0; }
docker compose down >/dev/null 2>&1 || true
rm -rf out data 2>/dev/null || sudo rm -rf out data
aws logs delete-log-group --log-group-name "$G" --region "$region" 2>&1 | grep -v ResourceNotFoundException || true
left=$(aws logs describe-log-groups --log-group-name-prefix "$G" --region "$region" --query 'logGroups[].logGroupName' --output text)
[ -z "$left" ] && echo "OK: log group $G đã xóa." || { echo "CÒN: $left" >&2; exit 1; }
[ "$env" = 1 ] && rm -f .env && echo "đã xóa .env"
exit 0
