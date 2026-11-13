# XrayR trên Debian 12/13, VPS 1 vCPU / 512 MB

Mục tiêu là giảm cấp phát và bộ nhớ giữ lại, giữ nguyên đường truyền dữ liệu.
Không thay đổi buffer kết nối, TCP congestion control, MTU, sniffing, thống kê
lưu lượng, tốc độ giới hạn của người dùng hoặc chu kỳ đồng bộ panel.

## Thay đổi trong mã nguồn

- Tái sử dụng bản đồ IP và token bucket của người dùng đang online, thay vì
  cấp phát rồi bỏ đi trên mỗi kết nối. Giữ nguyên kiểm tra giới hạn thiết bị.
- Khi xoá người dùng khỏi inbound, xoá cả thông tin limiter, bucket và IP đã
  lưu; tránh tích luỹ dữ liệu tài khoản bị xoá qua nhiều lần cập nhật panel.
- Đồng bộ danh sách người dùng bằng một map, thay cho hai map và một slice
  giao nhau. Thay đổi mật khẩu hoặc giới hạn vẫn được xử lý là xoá rồi thêm.

Các thay đổi này áp dụng cho cả bản build thông thường và bản `lowmem`.

## Cài đặt từ nhánh GitHub

Nhánh tối ưu: [`perf/low-memory-debian`](https://github.com/Dzone-source/xrayr/tree/perf/low-memory-debian).
Các bước dưới đây nâng cấp VPS **đã cài XrayR** và giữ nguyên config, chứng chỉ,
systemd unit. Không chạy lại bộ cài upstream vì nó có thể thay binary tối ưu.
Restart sẽ ngắt các kết nối đang hoạt động; chọn thời điểm bảo trì phù hợp.

### 1. Build trên máy Linux khác, có đủ RAM

Chuẩn bị Git, Go 1.24.1 và `sha256sum` trên máy build; không build trên VPS 512 MB.
Chỉ tải Go từ https://go.dev/dl/ và kiểm tra SHA256 theo trang tải chính thức.
Sau đó:

```bash
git clone --branch perf/low-memory-debian --single-branch https://github.com/Dzone-source/xrayr.git
cd xrayr

# Chọn full để giữ toàn bộ chức năng, gồm CertMode: dns.
bash release/lowmem/build.sh full amd64

# HOẶC: chỉ khi không dùng CertMode: dns.
# bash release/lowmem/build.sh lowmem amd64
```

Trên VPS, `uname -m` trả về `x86_64` thì dùng `amd64`; `aarch64` thì dùng
`arm64`. Ví dụ trên tạo `/tmp/xrayr-dist/XrayR-linux-amd64-full` và file
`.sha256` tương ứng. `XRAYR_BUILD_JOBS` chỉ giới hạn số job khi **build**,
không giới hạn CPU khi XrayR chạy.

### 2. Chuyển binary lên VPS

Chạy trên máy build, thay `user@VPS_IP` bằng tài khoản SSH của bạn. Nếu chọn
`lowmem` hoặc `arm64`, thay tên artifact tương ứng trong toàn bộ các lệnh:

```bash
scp /tmp/xrayr-dist/XrayR-linux-amd64-full \
    /tmp/xrayr-dist/XrayR-linux-amd64-full.sha256 user@VPS_IP:~/
```

### 3. Kiểm tra trên VPS trước khi thay

```bash
cd ~
sha256sum -c XrayR-linux-amd64-full.sha256
chmod 0755 XrayR-linux-amd64-full
./XrayR-linux-amd64-full version
systemctl cat XrayR.service
```

Dừng nếu checksum không khớp hoặc binary không chạy đúng kiến trúc. Đọc
`ExecStart=` trong unit để xác định đúng đường dẫn binary/config. Unit có thể
tên `xrayr.service`; dùng đúng tên thực tế. Nếu `ExecStart` gọi wrapper script,
phải xác định binary thật trước khi tiếp tục.

### 4. Sao lưu và thay binary

Mở Bash trên VPS, sửa hai biến đầu cho đúng `ExecStart` đã kiểm tra. Không dùng
đường dẫn mặc định dưới đây nếu unit của bạn trỏ đến nơi khác:

```bash
(
  set -euo pipefail
  XRAYR_UNIT=XrayR.service
  XRAYR_BIN=/usr/local/XrayR/XrayR
  XRAYR_NEW="$HOME/XrayR-linux-amd64-full"

  sudo test -f "$XRAYR_BIN"
  XRAYR_BACKUP="${XRAYR_BIN}.backup-$(date -u +%Y%m%dT%H%M%S)-$$"
  sudo cp -a -- "$XRAYR_BIN" "$XRAYR_BACKUP"
  printf 'Ghi lai duong dan rollback: %s\n' "$XRAYR_BACKUP"

  XRAYR_STAGED=$(sudo mktemp "${XRAYR_BIN}.new.XXXXXX")
  trap 'sudo rm -f -- "$XRAYR_STAGED"' EXIT
  sudo install -m 0755 -- "$XRAYR_NEW" "$XRAYR_STAGED"
  sudo mv -fT -- "$XRAYR_STAGED" "$XRAYR_BIN"

  sudo systemctl restart "$XRAYR_UNIT"
  sudo systemctl --no-pager --full status "$XRAYR_UNIT"
  sudo journalctl -u "$XRAYR_UNIT" -n 50 --no-pager
)
```

Vẫn cần kiểm tra kết nối thật từ client, tải lên/xuống và lưu lượng hiển thị
trên panel. Trạng thái `active` không đủ để kết luận proxy hoạt động.
Giữ nguyên config, buffer và kernel trong lần so sánh đầu tiên.

### 5. Quay lại bản cũ nếu có lỗi

Điền đường dẫn backup đã in ở bước 4, cùng binary/unit thực tế. Thao tác này
không sửa config hay chứng chỉ:

```bash
(
  set -euo pipefail
  XRAYR_UNIT=XrayR.service
  XRAYR_BIN=/usr/local/XrayR/XrayR
  XRAYR_BACKUP=/usr/local/XrayR/XrayR.backup-THAY_BANG_TEN_THUC_TE
  sudo test -f "$XRAYR_BACKUP"
  XRAYR_STAGED=$(sudo mktemp "${XRAYR_BIN}.rollback.XXXXXX")
  trap 'sudo rm -f -- "$XRAYR_STAGED"' EXIT
  sudo cp -a -- "$XRAYR_BACKUP" "$XRAYR_STAGED"
  sudo mv -fT -- "$XRAYR_STAGED" "$XRAYR_BIN"
  sudo systemctl restart "$XRAYR_UNIT"
  sudo systemctl --no-pager --full status "$XRAYR_UNIT"
)
```

## Build trên máy phát triển

Dùng Go 1.24.1 theo go.mod. Không build trên VPS 512 MB đang phục vụ người dùng:
quá trình biên dịch cần nhiều RAM hơn tiến trình XrayR chạy bình thường.

```sh
# Bản đầy đủ: giữ toàn bộ nhà cung cấp DNS cho ACME.
CGO_ENABLED=0 go build -mod=readonly -trimpath -ldflags='-s -w' -o XrayR .

# Tuỳ chọn: bỏ các SDK nhà cung cấp DNS cho ACME.
CGO_ENABLED=0 go build -mod=readonly -tags lowmem -trimpath -ldflags='-s -w' -o XrayR-lowmem .
```

`lowmem` giữ nguyên các giao thức proxy, transport và định tuyến đã có trong
bản đầy đủ. Nó hỗ trợ chứng chỉ `file`, ACME `http`/`tls`, và REALITY như trước;
không hỗ trợ cấp/gia hạn bằng DNS challenge. Nếu đang dùng `CertMode: dns`,
hãy dùng bản đầy đủ. Không thay đổi cách cấp chứng chỉ chỉ để dùng bản gọn.
Giảm kích thước binary không đồng nghĩa RSS sẽ giảm cùng một tỷ lệ.

Kiểm tra kiến trúc VPS bằng `uname -m`: dùng `GOOS=linux GOARCH=amd64` cho x86_64,
`GOOS=linux GOARCH=arm64` cho aarch64 khi cross-compile. Không dùng UPX.

## Cấu hình chạy giữ hiệu năng

Giữ nguyên config và systemd unit đang chạy khi triển khai lần đầu. Không hạ
`ConnectionConfig.BufferSize` từ 64 xuống 0/4/16 chỉ để giảm RAM; buffer nhỏ
có thể giảm throughput. Không tắt sniffing/rule nếu định tuyến đang cần chúng.
Không tăng `UpdatePeriodic` vì sẽ làm chậm cập nhật tài khoản và báo lưu lượng.

Không đặt `CPUQuota`, `MemoryMax`, `MemoryHigh`, `GOGC` thấp, hoặc ép
`runtime.GC()` theo timer. Chúng có thể tăng độ trễ, giảm tốc độ hoặc gây OOM.
Trên VPS đúng 1 CPU, Go tự chọn mức song song theo CPU được cấp; chỉ cân nhắc
`GOMAXPROCS=1` nếu kiểm tra thấy runtime nhận nhầm số CPU. Giới hạn RAM Go là
giới hạn mềm, không bao gồm toàn bộ RSS và bộ nhớ socket của kernel.

## Debian và kernel

Dùng kernel Debian được hỗ trợ và giữ cập nhật bảo mật. Chưa có bằng chứng
cần kernel tự biên dịch cho mục tiêu này. Không tắt mitigation CPU, firewall,
SSH, dịch vụ quản lý mạng, DNS, đồng bộ thời gian hoặc cập nhật bảo mật.
Không áp các gói sysctl tăng buffer TCP, backlog, conntrack lên hàng trăm MB:
bộ nhớ socket có thể chiếm phần lớn RAM của VPS dù RSS XrayR thấp.

Kiểm kê trên VPS trước khi quyết định bỏ dịch vụ:

```sh
free -m
ps -eo pid,comm,rss,%cpu --sort=-rss | head -20
systemctl list-units --type=service --state=running
systemctl list-unit-files --state=enabled
ss -s
cat /proc/net/sockstat
systemctl cat XrayR.service
systemctl show XrayR.service -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec
```

Tên unit có thể là `xrayr.service`; dùng đúng tên trên máy. Chỉ dừng/gỡ dịch vụ
đã xác nhận không dùng. Ví dụ Docker, database hoặc panel cục bộ có thể tốn
nhiều RAM, nhưng phải xác nhận XrayR và các ứng dụng khác không phụ thuộc chúng.
Không có danh sách dịch vụ chung nào có thể tắt an toàn trên mọi VPS.
Chỉ chạy duy nhất tiến trình XrayR sẽ mất các chức năng quản trị và mạng cần thiết.

Giữ log ở `warning` hoặc mức hiện tại nếu đang chẩn đoán. Nếu journal chiếm quá
nhiều đĩa, có thể cấu hình giới hạn kích thước journal riêng; thao tác này không
làm giảm RAM của luồng proxy. Swap chỉ là dự phòng OOM, không phải RAM thay thế
để đạt tốc độ mạng ổn định. Không tắt swap đang dùng khi máy thiếu RAM.

## Xác nhận trước khi thay binary

Chạy test cục bộ trên máy build:

```sh
go test -race ./common/limiter ./app/mydispatcher
go test service/controller/userdiff.go service/controller/userdiff_test.go
go test -tags lowmem ./common/mylego -run '^(Test_merge|Test_needRenewal|TestLowmemDNSProvider)$'
```

Giữ bản binary cũ để rollback và giữ nguyên config/chứng chỉ. Thay binary rồi
restart dịch vụ trong cửa sổ bảo trì: kết nối đang hoạt động có thể bị ngắt.
Chưa có thao tác triển khai hay thay đổi kernel nào được thực hiện trên VPS.

Đo trước/sau trên cùng VPS, cùng client, giao thức, đường mạng, số kết nối và
đích tải: ít nhất ba lượt, mỗi lượt 60 giây; so sánh throughput tải lên/xuống,
độ trễ p50/p95, CPU, RSS và `/proc/net/sockstat`. Đo cả khi nhàn rỗi và dưới tải
thực tế. Benchmark cấp phát trong repo không thay thế benchmark mạng. Nếu
throughput/độ trễ xấu đi ngoài dao động nền, rollback và kiểm tra profile;
không khẳng định hiệu năng mạng được bảo toàn khi chưa đo trên VPS.
