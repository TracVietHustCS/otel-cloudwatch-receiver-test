#!/usr/bin/env bash
# Kiểm tra key + quyền đọc, tạo log group /otel-cw-test và stream test-stream (đã có thì bỏ qua).
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."; [ -f .env ] && { set -a; . ./.env; set +a; }
G=/otel-cw-test; S=test-stream
region="${AWS_REGION:?hãy đặt AWS_REGION (trong .env)}"

echo "1) Key đang dùng:"; aws sts get-caller-identity --query Arn --output text --region "$region"

mk() {  # mk <mô tả> <lệnh aws...>: chấp nhận "đã tồn tại", lỗi khác thì dừng
  local what="$1"; shift; local out
  if out=$("$@" 2>&1); then echo "   đã tạo $what"
  elif grep -q ResourceAlreadyExistsException <<<"$out"; then echo "   $what đã có sẵn"
  else echo "$out" >&2; echo "LỖI khi tạo $what (thường là thiếu quyền)" >&2; exit 1; fi
}
echo "2) Tạo log group / stream:"
mk "log group $G"      aws logs create-log-group  --log-group-name "$G" --region "$region"
mk "log stream $S"     aws logs create-log-stream --log-group-name "$G" --log-stream-name "$S" --region "$region"

echo "3) Kiểm tra quyền đọc (logs:FilterLogEvents):"
if out=$(aws logs filter-log-events --region "$region" --log-group-name "$G" --limit 1 2>&1); then
  echo "   OK: có quyền đọc."
else
  echo "$out" >&2; echo "THIẾU QUYỀN hoặc sai region/tên group: xem tên action trong lỗi trên." >&2; exit 1
fi
echo "Xong. Bước tiếp: scripts/put-sample.sh"
