# otel-cw-test

Kiểm tra OpenTelemetry Collector (`otel/opentelemetry-collector-contrib:0.130.0`) có:
**(A)** kéo được log từ AWS CloudWatch Logs, và **(B)** biến log loguru thành đúng cấu trúc OTLP như Fluent Bit.
Chỉ có 1 service Collector, kết quả ghi ra file trong `./out/`.

```
.env                          <- ĐẶT KEY AWS Ở ĐÂY (không commit)
docker-compose.yml
config/config.yaml            <- cấu hình thô  -> out/logs.jsonl
config/config-transform.yaml  <- có transform  -> out/logs-transformed.jsonl
scripts/setup.sh              <- kiểm tra key/quyền, tạo log group + stream
scripts/put-sample.sh         <- sinh 4 event mẫu lên CloudWatch
scripts/run.sh                <- chạy Collector bằng Docker (raw | transform)
scripts/cleanup.sh            <- dọn dẹp (cần --yes)
scripts/sample-events.template.json
```

> Đã chạy thử config + OTTL bằng binary 0.130.0 với endpoint CloudWatch **giả**: 4 dòng mẫu (a)-(d) ra đúng cấu trúc đích.
> **Chưa chạy** với AWS thật và chưa chạy bằng Docker: output ở các bước dưới là ví dụ, bạn tự kiểm tra.

## 0. Yêu cầu

Docker + Compose v2, AWS CLI v2. Windows: dùng Git Bash và chạy `export MSYS_NO_PATHCONV=1` trước.

## 1. Đặt key AWS vào đâu

Tạo file `.env` ở thư mục gốc repo (cùng cấp `docker-compose.yml`):

```bash
cp .env.example .env
```

Mở `.env`, sửa 3 dòng (thêm dòng thứ 4 nếu dùng credential tạm / SSO):

```
AWS_REGION=ap-northeast-2
AWS_ACCESS_KEY_ID=AKIA...............
AWS_SECRET_ACCESS_KEY=....................
# AWS_SESSION_TOKEN=....        (chỉ khi credential tạm; bỏ dấu # đầu dòng)
```

- Docker đọc `.env` này và truyền cho Collector. Collector không có ô nhập key, nó dùng chuỗi credential mặc định của AWS SDK.
- Các lệnh `aws` chạy trên máy bạn **không** tự đọc `.env`. Nạp key vào shell hiện tại bằng:

```bash
set -a; source .env; set +a
aws sts get-caller-identity      # in ra Account / Arn = key dùng được
```

Dùng SSO thay vì key dài hạn: `aws sso login --profile <p>` rồi
`aws configure export-credentials --profile <p> --format env-no-export >> .env` (key tạm sẽ hết hạn).

Quyền IAM cần: `logs:FilterLogEvents` (Collector); `logs:CreateLogGroup`, `logs:CreateLogStream`,
`logs:PutLogEvents`, `logs:DeleteLogGroup` (tạo/ghi/xóa log mẫu). Chỉ dùng log group `/otel-cw-test`.

## Cách nhanh (dùng script)

Sau khi điền `.env` (mục 1), các script tự đọc `.env`, không cần `source` thủ công:

```bash
scripts/setup.sh                 # kiểm tra key + quyền đọc, tạo log group/stream
scripts/put-sample.sh            # sinh 4 event mẫu (chạy lại để thêm 4 event nữa)
scripts/run.sh raw               # chạy Collector bản thô      -> out/logs.jsonl
scripts/run.sh transform         # chạy Collector bản transform -> out/logs-transformed.jsonl
scripts/cleanup.sh --yes         # dọn: docker down, xóa out/data và log group (thêm --env để xóa cả .env)
```

`run.sh` mặc định chạy mới hoàn toàn (xóa checkpoint `./data` và file output cũ); thêm `--keep` để giữ checkpoint.
`cleanup.sh` không có `--yes` thì chỉ in kế hoạch. Các mục 2 đến 6 bên dưới là lệnh tay tương đương, kèm output mẫu.

## 2. Kiểm tra quyền đọc (làm đầu tiên)

```bash
aws logs filter-log-events --region $AWS_REGION --log-group-name "/otel-cw-test" --limit 1
```

| Output | Ý nghĩa |
|---|---|
| JSON, kể cả `{"events": [], ...}` | Có quyền đọc |
| `AccessDeniedException` ... `logs:FilterLogEvents` | Thiếu quyền, dừng lại và xin thêm (tên action nằm trong lỗi) |
| `ResourceNotFoundException` | Chưa có log group (chạy bước 3) hoặc sai tên/region |

## 3. Tạo log group, stream và sinh log

```bash
aws logs create-log-group  --log-group-name /otel-cw-test --region $AWS_REGION
aws logs create-log-stream --log-group-name /otel-cw-test --log-stream-name test-stream --region $AWS_REGION
```
(không in gì khi thành công; `ResourceAlreadyExistsException` nghĩa là đã có sẵn, bỏ qua.)

Sinh 4 event mẫu (a) request, (b) WARNING, (c) có `extra` khác rỗng, (d) ERROR nhiều dòng:

```bash
scripts/put-sample.sh
```
Output: `đã ghi 4 event vào /otel-cw-test / test-stream (timestamp gốc 1794...)`.
Chạy lại lệnh này bao nhiêu lần cũng được, mỗi lần thêm 4 event mới (timestamp = giờ hiện tại).

Kiểm tra log đã vào CloudWatch:

```bash
aws logs filter-log-events --region $AWS_REGION --log-group-name /otel-cw-test --limit 4 --query 'events[].message' --output text
```

## 4. Chạy Collector, bản thô

```bash
docker compose up -d
docker compose logs -f otel-collector      # Ctrl+C để thoát; đợi ~30s (poll_interval)
```

Sau ~30s, file `out/logs.jsonl` xuất hiện:

```bash
cat out/logs.jsonl
```

Mỗi event là một logRecord, **body là cả dòng thô**, chưa có `severityText`. Ví dụ rút gọn:

```json
{"resourceLogs":[{"resource":{"attributes":[
  {"key":"aws.region","value":{"stringValue":"ap-northeast-2"}},
  {"key":"cloudwatch.log.group.name","value":{"stringValue":"/otel-cw-test"}},
  {"key":"cloudwatch.log.stream","value":{"stringValue":"test-stream"}}]},
 "scopeLogs":[{"scope":{},"logRecords":[{
  "timeUnixNano":"1794469583860000000","observedTimeUnixNano":"1794469613985672221",
  "body":{"stringValue":"2026-08-27 21:22:58.688 | INFO     | app.main:log_requests:362 | {} - 요청 완료 - ... 상태코드: 200 - ..."},
  "attributes":[{"key":"id","value":{"stringValue":"<event id CloudWatch>"}}]}]}]}]}
```

`timeUnixNano` = giờ event trong CloudWatch, `observedTimeUnixNano` = giờ Collector poll.

## 5. Chạy bản transform (đúng cấu trúc Fluent Bit)

Checkpoint nằm trong `./data`; xóa đi để đọc lại từ đầu:

```bash
docker compose down
rm -rf data
OTEL_CONFIG=config-transform.yaml docker compose up -d
sleep 35 && cat out/logs-transformed.jsonl
```

Kết quả mong đợi cho dòng (a) (đã chạy thật với endpoint giả; `id` thật của CloudWatch dài hơn):

```json
{"severityText":"INFO",
 "body":{"stringValue":"요청 완료 - 10.1.2.3 - admin - GET /api/v1/projects - 상태코드: 200 - 처리시간: 0.011초"},
 "attributes":[
  {"key":"id","value":{"stringValue":"<event id>"}},
  {"key":"event","value":{"stringValue":"요청 완료"}},
  {"key":"host","value":{"stringValue":"test-stream"}},
  {"key":"logger","value":{"stringValue":"app.main:log_requests:362"}},
  {"key":"extra","value":{"stringValue":"{}"}},
  {"key":"source","value":{"stringValue":"devai-backend-service"}},
  {"key":"status_code","value":{"stringValue":"200"}}]}
```

Các dòng còn lại: (b) `severityText` `WARNING`, không có `status_code`/`event`; (c) `extra` = `{'request_id': 'abc123'}`;
(d) một record `ERROR`, body giữ nguyên các dòng traceback (`\n`). Không còn attribute `level`, `message`, `time`.

Xem nhanh các trường chính (cần python3):

```bash
python3 - <<'PY'
import json
for line in open('out/logs-transformed.jsonl', encoding='utf-8'):
    for rl in json.loads(line)['resourceLogs']:
        for lr in rl['scopeLogs'][0]['logRecords']:
            a = {x['key']: x['value']['stringValue'] for x in lr['attributes']}
            print(lr.get('severityText'), '|', a.get('logger'), '|', a.get('extra'), '|', a.get('status_code'), '|', a.get('event'))
PY
```

Tùy chọn: lấy `timeUnixNano` từ giờ trong dòng loguru (KST). Thêm câu sau vào `config/config-transform.yaml`,
ngay trước câu `delete_key(attributes, "level")`:

```yaml
          - 'set(time, Time(Concat([attributes["time"], " +0900"], ""), "%Y-%m-%d %H:%M:%S.%L %z")) where attributes["time"] != nil'
```

## 6. Dọn dẹp

```bash
docker compose down
rm -rf out data
aws logs delete-log-group --log-group-name /otel-cw-test --region $AWS_REGION
aws logs describe-log-groups --log-group-name-prefix /otel-cw-test --region $AWS_REGION   # phải ra "logGroups": []
rm .env
```

## Lưu ý

- Checkpoint (`./data`) lưu vị trí đã đọc, restart không đọc lại. Xóa `data` khi muốn đọc lại từ đầu.
- Container chạy bằng root nên trên Linux `out/` và `data/` thuộc root: dùng `sudo rm -rf out data`.
- Exporter `file` đã bật `append: true` để restart không ghi đè file.
- Receiver không nối dòng multiline: nếu agent gửi từng dòng riêng lên CloudWatch thì Collector không nối lại.
- `source` đang gán cứng cho group `/otel-cw-test`; group khác cần thêm điều kiện tương ứng.
