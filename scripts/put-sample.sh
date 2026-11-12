#!/usr/bin/env bash
# Tạo log group /otel-cw-test + stream test-stream (nếu chưa có), rồi ghi 4 event mẫu (a)-(d)
# với timestamp = giờ hiện tại. Chạy lại được nhiều lần (mỗi lần thêm 4 event mới).
set -euo pipefail
export MSYS_NO_PATHCONV=1            # Git Bash trên Windows: không đổi /otel-cw-test thành đường dẫn Windows
export AWS_CLI_FILE_ENCODING=UTF-8   # có tiếng Hàn trong file JSON
G=/otel-cw-test; S=test-stream
cd "$(dirname "$0")/.."; [ -f .env ] && { set -a; . ./.env; set +a; }; cd scripts
region="${AWS_REGION:?hãy đặt AWS_REGION (trong .env)}"

aws logs create-log-group  --log-group-name "$G" --region "$region" 2>/dev/null || true
aws logs create-log-stream --log-group-name "$G" --log-stream-name "$S" --region "$region" 2>/dev/null || true

now=$(( $(date +%s) * 1000 ))
tmp="$(mktemp ./.sample.XXXXXX)"; trap 'rm -f "$tmp"' EXIT
sed -e "s/__TS0__/$now/" -e "s/__TS1__/$((now+1))/" -e "s/__TS2__/$((now+2))/" -e "s/__TS3__/$((now+3))/" \
    sample-events.template.json > "$tmp"
aws logs put-log-events --log-group-name "$G" --log-stream-name "$S" \
  --log-events "file://$tmp" --region "$region" >/dev/null
echo "đã ghi 4 event vào $G / $S (timestamp gốc $now)"
