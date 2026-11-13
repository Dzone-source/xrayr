# XrayR tối ưu — cài sẵn cho Debian 12/13

Nhánh này chỉ phân phối **bản tối ưu**, phiên bản `0.9.5-lowmem.4`.
Binary Linux `amd64` và `arm64` đã được build bằng Go 1.24.1, nén trong
[`dist/`](dist/), kèm SHA256. VPS không cần Git, Go hoặc tự biên dịch.

## Nâng cấp VPS đang chạy XrayR

SSH vào VPS và chạy:

```bash
curl -fSL https://raw.githubusercontent.com/Dzone-source/xrayr/perf/low-memory-debian/release/lowmem/install.sh -o /tmp/install-xrayr-lowmem.sh
sudo bash /tmp/install-xrayr-lowmem.sh
```

Installer tự nhận kiến trúc CPU, tải binary đã build, kiểm tra SHA256, chạy
`version`, sao lưu binary cũ, thay binary và restart dịch vụ. Nếu restart thất
bại hoặc dịch vụ không active sau 2 giây, installer phục hồi binary cũ.
Installer in và lưu log lỗi riêng trước khi rollback (quyền 0600), sau đó kiểm tra
lại dịch vụ cũ. Nó giữ nguyên config, chứng chỉ, systemd unit, buffer, timeout và kernel.
Restart ngắt các kết nối đang hoạt động; chọn thời điểm bảo trì phù hợp.

Cần có `curl`, `tar`, `sha256sum` trên VPS. Nếu thiếu, cài bằng kho Debian:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl tar coreutils
```

Nếu unit hoặc đường dẫn khác mặc định, đọc `systemctl cat TEN_UNIT` rồi chỉ rõ:

```bash
sudo bash /tmp/install-xrayr-lowmem.sh \
  --service XrayR.service --bin /usr/local/XrayR/XrayR
```

Chỉ dùng đường dẫn binary thực tế trong `ExecStart`, không phải wrapper hay
symlink. Installer chỉ nâng cấp một dịch vụ đã có; không tạo config/panel mới.
Nó không gửi API key hoặc private key của bạn lên GitHub.

## Kiểm tra và quay lại bản cũ

```bash
systemctl status XrayR.service --no-pager
journalctl -u XrayR.service -n 50 --no-pager
```

Dùng đúng tên unit của bạn (`XrayR.service` hoặc `xrayr.service`). Sau cài,
kiểm tra kết nối thật từ client, upload/download và số liệu trên panel.
Trạng thái `active` không đủ để kết luận mọi chức năng proxy hoạt động.
Installer in đường dẫn backup và lệnh rollback; lưu lại chúng trước khi đóng SSH.

Có thể tải và kiểm tra binary mà chưa thay dịch vụ, không cần root:

```bash
bash /tmp/install-xrayr-lowmem.sh --download-only "$HOME/xrayr-ready"
"$HOME/xrayr-ready/XrayR" version
```

## Tương thích config VLESS Vision + REALITY

Giữ nguyên SSpanel, VLESS với `xtls-rprx-vision`, REALITY, các transport,
định tuyến, sniffing, thống kê và các giới hạn tốc độ/thiết bị đã có.
`EnableREALITY: true` và `CertMode: none` phù hợp với bản này.
Test cấu hình REALITY dùng khoá sinh tạm, không dùng API key/khoá triển khai.

Bản này bỏ các SDK ACME DNS provider, không hỗ trợ cấp/gia hạn bằng DNS
challenge (`CertMode: dns`). Các chế độ `none`, `file`, `http`, `tls` vẫn còn.
Không còn lựa chọn `full`; build mặc định cũng là bản tối ưu.

Không đưa config chứa API key hay private key REALITY vào GitHub. Nếu các khoá
đã bị chia sẻ công khai, thay khoá trên panel và cập nhật client tương ứng.

## Bộ nhớ và tốc độ mạng

- Tái sử dụng map IP/token bucket khi người dùng đã online, giảm cấp phát mỗi
  lần xử lý kết nối từ 304–400 byte xuống 0 byte trong benchmark.
- Thu hồi dữ liệu limiter khi xoá người dùng.
- Dùng một map khi so sánh danh sách user; benchmark 10.000 user giảm bộ nhớ tạm
  từ khoảng 11,6 MB xuống 1,84 MB. Đây không phải số RSS tiết kiệm trên VPS.

Không hạ buffer, ép GC, đặt trần CPU/RAM hoặc tự sửa sysctl. Đặc biệt,
`BufferSize: 1024` là 1024 KiB, timeout dài có thể giữ bộ nhớ lâu. Installer
không tự thay các giá trị này vì thay đổi có thể ảnh hưởng throughput hoặc
kết nối dài. Tối ưu cấp phát không bảo đảm 512 MB đủ cho mọi tải.

Đo trước/sau trên cùng VPS, cùng client, giao thức, đích tải và số kết nối:
ít nhất ba lượt 60 giây; so sánh upload/download, độ trễ p50/p95, CPU và RSS.
Rollback nếu kết quả xấu đi ngoài dao động nền. Benchmark cục bộ không thay
thế phép đo mạng thật; chưa có phép đo trên VPS của bạn.

```bash
free -m
ps -eo pid,comm,rss,%cpu --sort=-rss | head -20
ss -s
cat /proc/net/sockstat
```

Giữ kernel Debian được hỗ trợ. Không tắt SSH, mạng, DNS, đồng bộ giờ,
firewall hoặc cập nhật bảo mật. Chỉ dừng các dịch vụ thừa sau khi kiểm kê
phụ thuộc trên máy; không có danh sách tắt dịch vụ an toàn cho mọi VPS.

## Chỉ dành cho người phát triển

Không cần phần này để cài trên VPS. Build bằng Go 1.24.1 trên máy đủ RAM:

```bash
bash release/lowmem/build.sh amd64
bash release/lowmem/build.sh arm64
```

Kết quả ở `/tmp/xrayr-dist/`, gồm binary, archive `.tar.gz` và checksum.
`XRAYR_BUILD_JOBS` chỉ giới hạn job biên dịch, không giới hạn CPU khi chạy.
Không chạy `go mod download` để lấy toàn bộ SDK đã không còn sử dụng;
`go build -mod=readonly` chỉ tải các dependency cần thiết.

Xem [VALIDATION.md](VALIDATION.md) để biết các test đã chạy và giới hạn.

## Bản sửa SSpanel (`lowmem.2`)

Sửa panic khi panel trả `server` không có đủ các phần phân cách bằng dấu `;`.
Nếu không có định dạng legacy hợp lệ nhưng có `custom_config` với port/network,
parser dùng custom config thay vì chỉ dựa vào trường version. Vẫn tôn trọng
`DisableCustomConfig`; phản hồi thiếu dữ liệu trả lỗi rõ ràng thay vì panic.
Không ghi toàn bộ node response (có thể chứa private key) vào thông báo lỗi.

## Chẩn đoán định dạng panel khi bản cũ chạy được nhưng bản tối ưu không chạy

Không cài lại nhiều lần khi chưa rõ định dạng API. Giữ dịch vụ cũ đang chạy,
chỉ đọc cấu trúc node bằng Python 3 (không cần thêm thư viện YAML):

```bash
curl -fSL https://raw.githubusercontent.com/Dzone-source/xrayr/perf/low-memory-debian/release/lowmem/inspect_panel.py -o /tmp/xrayr-inspect-panel.py
python3 /tmp/xrayr-inspect-panel.py --config /etc/XrayR/config.yml --node-id 2
```

Thay `2` bằng NodeID thực tế. Công cụ lấy thông tin API từ một block ApiConfig
đơn giản trong config hiện có, chỉ gửi GET tới node info. Nó không sửa config,
không restart dịch vụ, không in ApiKey, private key, hostname hay giá trị chuỗi
tuỳ ý. Báo cáo giữ tên trường, kiểu dữ liệu, các giá trị port/giao thức đã
allowlist và số phần của `server`; có thể gửi báo cáo này để sửa parser theo
phản hồi thực tế. Không gửi file config hoặc JSON phản hồi gốc chứa bí mật.
Công cụ không đi theo HTTP redirect để tránh chuyển query credential sang host khác.

## Bản sửa scalar JSON (`lowmem.3`)

Hỗ trợ `offset_port_node` dạng số hoặc chuỗi; các cờ `enable_vless`,
`enable_xtls`, `allow_insecure`, `enable_reality`, `verify_cert` nhận boolean,
0/1 hoặc chuỗi tương đương. Phản hồi có version `1.0.0` nhưng custom_config
hợp lệ được nhận dạng theo cấu trúc, giữ nguyên TCP + VLESS Vision + REALITY.
Dữ liệu không hợp lệ vẫn bị từ chối; không tự đoán port hay đổi giao thức.
Test khởi động panel giả lập đã dùng đúng kiểu trường của báo cáo chẩn đoán,
API user giả lập, khoá REALITY sinh tạm và các giá trị timeout/buffer của config
được cung cấp. Không dùng khóa hoặc phản hồi bí mật của khách hàng trong test.

## Báo CPU/RAM của panel trả HTTP 405 (`lowmem.4`)

Một số fork dùng version `1.0.0` nhưng node-info chỉ nhận GET, không nhận POST
báo CPU/RAM/uptime theo API legacy. Khi chính POST báo trạng thái nhận HTTP
405, client ghi một cảnh báo ngắn và ngừng chức năng đó đến lúc restart.
GET cập nhật node, báo lưu lượng và báo IP online vẫn hoạt động như trước;
401/403/500 và lỗi ở các endpoint khác vẫn được báo, không bị che đi.
Lỗi HTTP chỉ ghi method/endpoint/status, không ghi cả trang HTML của panel.
