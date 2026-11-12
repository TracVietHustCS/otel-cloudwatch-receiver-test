# otel-cw-test

Stack tối giản để kiểm tra 2 việc, chỉ với 1 service Collector (không Elasticsearch, không Fluent Bit):

- **A.** OpenTelemetry Collector kéo được log từ AWS CloudWatch Logs không.
- **B.** Collector biến đổi (enrich) log loguru của `devai-backend-service` thành đúng cấu trúc OTLP như Fluent Bit.

Image mặc định: `otel/opentelemetry-collector-contrib:0.130.0` (đổi bằng `OTEL_VERSION`).
Kết quả test nằm ở [FINDINGS.md](FINDINGS.md).

> **Trạng thái:** config và OTTL đã chạy thật bằng binary `otelcol-contrib 0.130.0` với endpoint CloudWatch **giả**
> (không phải AWS thật). **CHƯA chạy:** `docker compose`, AWS thật, kiểm tra quyền, `put-sample.sh`/`cleanup.sh` với AWS.
> Chi tiết ở FINDINGS.md.

## Yêu cầu

Docker + Compose v2, AWS CLI v2, một credential AWS có quyền ghi/đọc CloudWatch Logs.
Quyền cần: Collector `logs:FilterLogEvents`; script mẫu `logs:CreateLogGroup`, `CreateLogStream`, `PutLogEvents`, `DeleteLogGroup`.
Chỉ dùng log group `/otel-cw-test`. Trên Git Bash (Windows) chạy `export MSYS_NO_PATHCONV=1` trước.

## 1. Kiểm tra quyền (làm đầu tiên)

```bash
aws logs filter-log-events --region $AWS_REGION --log-group-name "/otel-cw-test" --limit 1
```

- In ra JSON (kể cả `events: []`) = có quyền.
- `AccessDeniedException` = thiếu quyền (tên action nằm trong lỗi). **Dừng lại** và xin thêm quyền đó.
- `ResourceNotFoundException` = sai tên group hoặc region (hoặc chưa chạy bước 2.2).

## 2. Các bước chạy

```bash
cp .env.example .env            # điền AWS_REGION và credential (không commit)
export AWS_REGION=ap-northeast-2
scripts/put-sample.sh           # 2.2: tạo group/stream và ghi 4 event mẫu (a)-(d)
docker compose up -d            # config thô -> out/logs.jsonl (đợi ~30s)
docker compose logs -f otel-collector
```

Chạy bản transform (ghi `out/logs-transformed.jsonl`):

```bash
docker compose down && rm -rf data/*     # xóa checkpoint để đọc lại từ đầu
OTEL_CONFIG=config-transform.yaml docker compose up -d
```

Lưu ý: checkpoint nằm ở `./data`. Đổi config mà không xóa `data/*` thì collector chỉ đọc event **mới**.
Mỗi lần chạy lại `put-sample.sh` thêm đúng 4 event mới.

Tùy chọn (T8), lấy `timeUnixNano` từ giờ trong dòng loguru (KST): thêm câu này vào `config-transform.yaml`,
ngay trước câu `delete_key(attributes, "level")`:

```yaml
          - 'set(time, Time(Concat([attributes["time"], " +0900"], ""), "%Y-%m-%d %H:%M:%S.%L %z")) where attributes["time"] != nil'
```

## 3. Bảng test

Kết quả chi tiết và bằng chứng trong FINDINGS.md. "Sandbox" = binary 0.130.0 + endpoint CloudWatch giả; "AWS thật" = chưa chạy.

| Test | Nội dung | Sandbox | AWS thật |
|---|---|---|---|
| T1 | Kéo đủ 4 event sau ~30s, config thô: body là dòng thô, không có severityText | PASS | CHƯA chạy |
| T2 | Resource attributes aws.region / group / stream | PASS | CHƯA chạy |
| T3 | `timeUnixNano` = giờ event, `observedTimeUnixNano` = giờ poll | PASS | CHƯA chạy |
| T4 | Chạy lại put-sample: đúng 4 record mới, không lặp | PASS | CHƯA chạy |
| T5 | Restart: không đọc lại từ đầu | PASS | CHƯA chạy |
| T6 | Event (d) là MỘT record, còn nguyên `\n` | PASS | CHƯA chạy |
| T7 | So từng record (a)-(d) với cấu trúc đích | PASS (0 lệch) | CHƯA chạy |
| T8 | Timestamp lấy từ dòng loguru (KST) | PASS | CHƯA chạy |
| T9 | Endpoint hỏng: collector có panic không | PASS (không panic) | CHƯA chạy |

## 4. Dọn dẹp

```bash
scripts/cleanup.sh          # chỉ in kế hoạch
scripts/cleanup.sh --yes    # xóa log group /otel-cw-test
docker compose down         # dừng collector
rm -rf out/* data/* .env    # xóa tay nếu muốn (script không tự xóa)
```
