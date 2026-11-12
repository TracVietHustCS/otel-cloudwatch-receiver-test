#!/usr/bin/env bash
# Xóa log group /otel-cw-test. Cần --yes để thực hiện. Không xóa ./out và ./data.
set -euo pipefail
export MSYS_NO_PATHCONV=1
G=/otel-cw-test
region="${AWS_REGION:?hãy đặt AWS_REGION}"
echo "Sẽ xóa log group $G ở region $region (chỉ group này)."
echo "Sau đó tự chạy: docker compose down   (./out và ./data được giữ lại, xóa tay nếu muốn)"
[ "${1:-}" = "--yes" ] || { echo "Chưa làm gì. Chạy lại với --yes để xóa."; exit 0; }
aws logs delete-log-group --log-group-name "$G" --region "$region" && echo "đã xóa $G"
