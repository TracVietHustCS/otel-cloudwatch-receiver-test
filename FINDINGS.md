# FINDINGS

Ngày 2026-11-12. Collector: **otelcol-contrib 0.130.0** (tag cũ, theo yêu cầu).

## Kết luận

Với bản 0.130.0, receiver `awscloudwatch` + processor `transform` (OTTL) + exporter `file` **tạo ra đúng cấu trúc đích cho cả 4 dạng dòng
(a)-(d), 0 mục lệch** trong test cục bộ. **Điều kiện:** kết quả lấy từ endpoint CloudWatch **giả** (xem "Cách đã test"),
chưa kiểm chứng với AWS thật, chưa chạy bằng Docker.

## Cách đã test (và giới hạn)

- Sandbox không có Docker và không có credential AWS, nên **không chạy được `docker compose` và không gọi được AWS thật**.
- Thay vào đó chạy trực tiếp binary `otelcol-contrib 0.130.0` (tải từ GitHub release), với config **y hệt** trong repo,
  chỉ đổi đường dẫn `/out` và `/var/lib/otelcol/storage` sang thư mục cục bộ. Receiver được trỏ tới một server Python
  giả lập `FilterLogEvents` bằng `AWS_ENDPOINT_URL` (server này **không** nằm trong repo). Server giả dùng đúng 4 event mẫu
  trong `scripts/sample-events.template.json`.
- Vì vậy các kết quả PASS chứng minh được: receiver đọc được, OTTL biến đổi đúng, checkpoint hoạt động, exporter file ghi đúng.
  **Chưa chứng minh:** quyền IAM thật, hành vi của CloudWatch thật (thứ tự event, trễ ingest, phân trang), image Docker, `put-sample.sh`
  và `cleanup.sh` với AWS thật (chỉ test logic bằng stub `aws`: JSON hợp lệ, tiếng Hàn và `\n` giữ nguyên, timestamp tăng dần, dry-run không gọi `aws`).
- **Kiểm tra quyền (mục 4 của đề): CHƯA chạy.** Phải chạy lệnh `filter-log-events` trong README bằng credential thật.

## Kết quả T1..T9

| Test | Kết quả | Bằng chứng (thật, từ lần chạy sandbox) |
|---|---|---|
| T1 | PASS | File `logs.jsonl` xuất hiện sau 32s kể từ khi start; 4 record, 4 id khác nhau. Body là nguyên dòng thô `2026-08-27 21:22:58.688 \| INFO     \| app.main:... - 요청 완료 ... 상태코드: 200 ...`; không có `severityText`; attribute duy nhất là `id`. |
| T2 | PASS | Resource attributes đúng 3 khóa: `aws.region=ap-northeast-2`, `cloudwatch.log.group.name=/otel-cw-test`, `cloudwatch.log.stream=test-stream`. Scope `{}`. |
| T3 | PASS | Record (a): `timeUnixNano` 07:46:23.860Z (giờ event), `observedTimeUnixNano` 07:46:53.985Z (giờ poll), chênh 30.1s = `poll_interval`. |
| T4 | PASS | Ghi thêm 4 event: 4 → 8 record, 8 id khác nhau, 0 trùng. |
| T5 | PASS | Dừng (SIGTERM) rồi chạy lại cùng thư mục `data`: 8 record trước và sau, 0 trùng sau 2 chu kỳ poll. Log: `Resuming from previously known checkpoint(s)`. |
| T6 | PASS | Event (d) là 1 record, body giữ nguyên 4 ký tự `\n` của traceback (xem record (d) bên dưới). |
| T7 | PASS | Bảng so sánh: mọi mục KHỚP cho (a)-(d), 0 LỆCH, 0 THIẾU (bảng bên dưới). |
| T8 | PASS | `timeUnixNano` của (a) = `2026-08-27T12:22:58.688Z` = 21:22:58.688 KST (trừ 9 giờ). Severity giữ nguyên (INFO/WARNING/INFO/ERROR) và attr `time` đã xóa ở cả 4 record. |
| T9 | PASS (với endpoint CloudWatch hỏng) | Trỏ `AWS_ENDPOINT_URL` vào cổng đóng: collector chạy tiếp, 0 dòng `panic`, mỗi chu kỳ log 1 lỗi `there was an error during the poll`: `failed to retrieve logs from log group /otel-cw-test: operation error CloudWatch Logs: FilterLogEvents, exceeded maximum number of attempts, 3, ...request send failed`. |

Lưu ý T9: đề yêu cầu chặn **STS**. Receiver 0.130.0 **không gọi STS** (grep `sts`/`GetCallerIdentity` trong `logs.go`: không có kết quả),
nên test STS không áp dụng; đã test lỗi endpoint CloudWatch thay thế. Từ bản mới hơn (đọc source v0.165.0) receiver gọi `sts.GetCallerIdentity` và thêm
resource attribute `cloud.account.id`. Bản 0.165.0 **chưa được test** ở đây.

### T7: bảng so sánh (áp dụng cho từng record a-d)

| Trường | (a) | (b) | (c) | (d) |
|---|---|---|---|---|
| resource: 3 khóa đích, không khóa thừa | KHỚP | KHỚP | KHỚP | KHỚP |
| severityText | INFO KHỚP | WARNING KHỚP | INFO KHỚP | ERROR KHỚP |
| severityNumber không đặt | KHỚP | KHỚP | KHỚP | KHỚP |
| body (chỉ phần message, bỏ khoảng trắng cuối) | KHỚP | KHỚP | KHỚP | KHỚP (còn `\n`) |
| logger | KHỚP | KHỚP | KHỚP | KHỚP |
| extra (nguyên chuỗi) | `{}` KHỚP | `{}` KHỚP | `{'request_id': 'abc123'}` KHỚP | `{}` KHỚP |
| source = devai-backend-service | KHỚP | KHỚP | KHỚP | KHỚP |
| host = tên stream | KHỚP | KHỚP | KHỚP | KHỚP |
| status_code | "200" KHỚP | không có, KHỚP | không có, KHỚP | không có, KHỚP |
| event | "요청 완료" KHỚP | không có, KHỚP | không có, KHỚP | không có, KHỚP |
| id (từ receiver) | có | có | có | có |
| level / message / time đã xóa | KHỚP | KHỚP | KHỚP | KHỚP |

### Bản ghi thật, nguyên văn (config transform)

(a)
```json
{"resource":{"attributes":{"aws.region":"ap-northeast-2","cloudwatch.log.group.name":"/otel-cw-test","cloudwatch.log.stream":"test-stream"}},"scope":{},"logRecord":{"timeUnixNano":"1794470012178000000","observedTimeUnixNano":"1794470042295659029","severityText":"INFO","body":{"stringValue":"요청 완료 - 10.1.2.3 - admin - GET /api/v1/projects - 상태코드: 200 - 처리시간: 0.011초"},"attributes":[{"key":"id","value":{"stringValue":"00000000000000000000000000000000000001"}},{"key":"event","value":{"stringValue":"요청 완료"}},{"key":"host","value":{"stringValue":"test-stream"}},{"key":"logger","value":{"stringValue":"app.main:log_requests:362"}},{"key":"extra","value":{"stringValue":"{}"}},{"key":"source","value":{"stringValue":"devai-backend-service"}},{"key":"status_code","value":{"stringValue":"200"}}],"traceId":"","spanId":""}}
```
(b)
```json
{"resource":{"attributes":{"aws.region":"ap-northeast-2","cloudwatch.log.group.name":"/otel-cw-test","cloudwatch.log.stream":"test-stream"}},"scope":{},"logRecord":{"timeUnixNano":"1794470012179000000","observedTimeUnixNano":"1794470042295659029","severityText":"WARNING","body":{"stringValue":"토큰 만료 임박 - 사용자: admin"},"attributes":[{"key":"id","value":{"stringValue":"00000000000000000000000000000000000002"}},{"key":"source","value":{"stringValue":"devai-backend-service"}},{"key":"host","value":{"stringValue":"test-stream"}},{"key":"logger","value":{"stringValue":"app.services.auth:verify_token:88"}},{"key":"extra","value":{"stringValue":"{}"}}],"traceId":"","spanId":""}}
```
(c)
```json
{"resource":{"attributes":{"aws.region":"ap-northeast-2","cloudwatch.log.group.name":"/otel-cw-test","cloudwatch.log.stream":"test-stream"}},"scope":{},"logRecord":{"timeUnixNano":"1794470012180000000","observedTimeUnixNano":"1794470042295659029","severityText":"INFO","body":{"stringValue":"프로젝트 생성 완료 - id: 7"},"attributes":[{"key":"id","value":{"stringValue":"00000000000000000000000000000000000003"}},{"key":"source","value":{"stringValue":"devai-backend-service"}},{"key":"host","value":{"stringValue":"test-stream"}},{"key":"logger","value":{"stringValue":"app.services.project:create:41"}},{"key":"extra","value":{"stringValue":"{'request_id': 'abc123'}"}}],"traceId":"","spanId":""}}
```
(d)
```json
{"resource":{"attributes":{"aws.region":"ap-northeast-2","cloudwatch.log.group.name":"/otel-cw-test","cloudwatch.log.stream":"test-stream"}},"scope":{},"logRecord":{"timeUnixNano":"1794470012181000000","observedTimeUnixNano":"1794470042295659029","severityText":"ERROR","body":{"stringValue":"처리 중 오류 발생\nTraceback (most recent call last):\n  File \"/app/app/main.py\", line 118, in handler\n    result = 1 / 0\nZeroDivisionError: division by zero"},"attributes":[{"key":"id","value":{"stringValue":"00000000000000000000000000000000000004"}},{"key":"source","value":{"stringValue":"devai-backend-service"}},{"key":"host","value":{"stringValue":"test-stream"}},{"key":"logger","value":{"stringValue":"app.main:handler:120"}},{"key":"extra","value":{"stringValue":"{}"}}],"traceId":"","spanId":""}}
```
(Hiển thị đã chuyển từ định dạng đa dòng của công cụ so sánh sang một dòng; `id` là id do server giả sinh, id thật của CloudWatch dài hơn.)

## Phát hiện cần biết

1. **Exporter `file` mặc định ghi đè file khi khởi động.** Lần restart đầu, `logs.jsonl` bị về 0 record. Đã thêm `append: true` vào cả hai config (T5 chỉ PASS sau khi sửa).
2. **Cú pháp `named`:** `names:` đặt ngay dưới tên group (khớp ví dụ trong README receiver), không có lớp `streams:`. Config đã `validate` được.
3. **YAML:** các câu OTTL phải đặt trong dấu nháy đơn vì chứa `: ` (ví dụ `상태코드: `); lần đầu không nháy thì config không parse được.
4. **Timestamp KST không cần tzdata:** nối `" +0900"` rồi parse bằng `%z` chạy được ở 0.130.0, tránh phụ thuộc múi giờ trong image container (chưa kiểm tra image có tzdata hay không).
5. **Checkpoint chỉ chính xác tới giây:** sau restart, request đầu có `startTime=...896000` trong khi lần poll trước kết thúc ở `...896042` (log của server giả). Suy ra: event nằm trong phần chồng lấn (tối đa ~1s) có thể bị đọc lại. Không quan sát thấy bản ghi trùng nào trong test này (không có event ở khoảng đó), nên đây là rủi ro suy luận, chưa gặp thực tế.
6. **SDK tự retry:** lỗi kết nối bị thử 3 lần trước khi receiver log lỗi (T9).
7. **`source` đang gán cứng theo tên group** (`/otel-cw-test`). Thêm group mới thì cần thêm điều kiện/câu `set` tương ứng.

## OTel KHÔNG làm được / khác Fluent Bit

- **Nối dòng multiline ở nguồn:** receiver không có tùy chọn multiline (không có trường nào trong `config.go`). Test này chỉ dùng event (d) đã là **một** event CloudWatch nên giữ nguyên `\n`; nếu agent ghi log lên CloudWatch từng dòng một thì Collector **không** nối lại (suy từ cấu hình receiver, chưa chạy thử).
- **`host`** chỉ là tên log stream (CloudWatch không có host thật), `source` suy ra từ tên group.
- Resource attributes luôn có sẵn 3 khóa; không thêm được `cloud.account.id` ở bản 0.130.0.

## Chưa làm / chưa kiểm chứng

- Chạy với AWS thật, docker compose, kiểm tra quyền IAM, `put-sample.sh` và `cleanup.sh` thật: **CHƯA chạy**.
- Tag `0.165.1` do đề nghị **không tồn tại**; bản mới nhất có thật khi kiểm tra là `v0.165.0` (2026-11-07). Theo yêu cầu cuối cùng đã dùng `0.130.0`; 0.165.0 chưa test.
- Tag image `otel/opentelemetry-collector-contrib:0.130.0` trên Docker Hub chưa được pull (binary release 0.130.0 thì có thật và đã chạy).
