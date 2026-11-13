# Debian 12/13: kernel, ưu tiên XrayR và dịch vụ nền

Các công cụ này tách biệt với installer binary XrayR: không tự đổi kernel,
không reboot, không tắt dịch vụ khi cài XrayR. Chưa có thay đổi nào được áp
trên VPS chỉ nhờ việc lưu các file này vào GitHub.

## 1. Kiểm kê VPS (chỉ đọc)

```bash
curl -fSL https://raw.githubusercontent.com/Dzone-source/xrayr/perf/low-memory-debian/release/debian/xrayr-host.sh -o /tmp/xrayr-host.sh
bash /tmp/xrayr-host.sh audit
```

Báo cáo gồm Debian, kernel, kiểu ảo hoá, dung lượng /boot, driver mạng,
RAM/CPU, tên dịch vụ đang chạy, timers và kernel package đang có trong index
APT. Không đọc config XrayR, environment hay tham số chứa API key.
APT index có thể cũ; package policy chưa chứng minh đó là kernel mới nhất.

## 2. Ưu tiên CPU cho XrayR mà không restart

Chỉ chạy trên Debian 12/13 có systemd và cgroup v2 CPU controller:

```bash
sudo bash /tmp/xrayr-host.sh prioritize XrayR.service
```

Đặt `CPUWeight=1000` cho unit XrayR đang chạy bằng systemctl set-property;
thiết lập có hiệu lực ngay và được lưu qua reboot. Trọng số mặc định thường
là 100. Script in trọng số cũ và lệnh khôi phục **trước khi thay đổi**.
Nó chỉ thay trọng số CPU, không ghi đè config/unit, không đổi CPUQuota, nice,
GC, bộ đệm, timeout, TCP hay giới hạn RAM. Không restart XrayR.

CPUWeight phân chia CPU khi các cgroup cùng cấp cạnh tranh CPU; không tạo thêm
CPU, không giảm RSS và không bảo đảm tốc độ mạng tăng. Khi CPU đã idle
87–97%, thay trọng số thường không tạo khác biệt thấy được.

Ví dụ khôi phục nếu trọng số cũ được in là 100:

```bash
sudo bash /tmp/xrayr-host.sh restore XrayR.service 100
```

Dùng đúng tên `xrayr.service` nếu máy dùng tên đó. Khôi phục ở đây trả lại
trọng số hiệu dụng, có thể lưu mặc định 100 thành một property tường minh.

## 3. Chọn kernel mới

Cần xem báo cáo mục 1 trước khi chọn gói thực tế:

- LXC/OpenVZ/Docker: kernel do host quản lý; cài image trong container không
  thay được kernel đang chạy. Cần nhà cung cấp đổi host kernel hoặc dùng VM.
- KVM/VMware/Hyper-V hoặc máy vật lý: có thể dùng kernel image chính thức từ
  kho Debian đã cấu hình và xác thực chữ ký. Kiểm tra bootloader, driver mạng,
  lưu trữ và dung lượng /boot trước khi chọn generic/cloud image.
- Bản cloud có thể phù hợp VM dùng driver ảo hoá; không tự chuyển sang cloud
  image khi chưa biết driver NIC/root disk có được hỗ trợ.
- Không tự thêm backports, repository ngoài, kernel unsigned hoặc đổi distro.
  Phiên bản/kernel mới nhất phải dựa trên package policy và vòng đời hỗ trợ
  của đúng Debian đang dùng, không hardcode một số phiên bản theo ngày.

Quy trình sau khi đã xác định đúng meta-package (ví dụ `linux-image-amd64`,
`linux-image-cloud-amd64` hoặc `linux-image-arm64`):

```bash
# Chỉ làm mới index; không tự nâng cấp toàn bộ hệ thống.
sudo apt-get update
# Thay linux-image-amd64 bằng gói ĐÃ xác định phù hợp VPS.
apt-cache policy linux-image-amd64
sudo apt-get -s --no-remove install linux-image-amd64
```

Đọc bản mô phỏng: phải có image mới phù hợp và không gỡ kernel/bootloader
đang dùng. Giữ image hiện tại để có thể chọn lại trong bootloader; không chạy
`autoremove` kernel. Sau khi xác nhận kế hoạch, lệnh cài đúng gói là
`sudo apt-get --no-remove install linux-image-amd64` (thay bằng gói đã chọn).
Không tự reboot; cần cửa sổ bảo trì và console của nhà cung cấp để khôi phục
boot nếu kernel mới không lên mạng. Sau reboot, kiểm tra `uname -r`, SSH,
network, XrayR và kết nối client trước khi kết luận đã nâng cấp thành công.

Kernel tự biên dịch chỉ có ý nghĩa khi có yêu cầu/benchmark cụ thể. Các module
không được nạp thường không chiếm RAM runtime chỉ vì có trong gói trên đĩa;
xoá driver khỏi kernel không đồng nghĩa XrayR dùng ít RAM hơn.

## 4. Tắt dịch vụ thật sự không dùng

Không có danh sách “rác” đúng cho mọi VPS. Cần dùng báo cáo dịch vụ/timers để
xác nhận phụ thuộc trước khi chọn unit. Chỉ dừng/disable các unit đã xác định;
không dùng danh sách quét hàng loạt hoặc mask mọi unit ngoài XrayR.

Giữ SSH, network manager đang dùng, DNS resolver, đồng bộ giờ, journald,
firewall, chống brute-force, guest agent của hypervisor, cập nhật bảo mật và
các timer cần thiết. Docker/database/panel không phải dịch vụ thừa nếu có ứng
dụng phụ thuộc chúng. Ví dụ ứng viên kiểm tra trên VPS không có nhu cầu tương
ứng là dịch vụ in, mDNS hoặc Bluetooth; phải kiểm tra cả socket/path activation.

Với MỖI unit đã chọn, ghi lại trước:

```bash
systemctl is-enabled TEN.service
systemctl is-active TEN.service
systemctl list-dependencies --reverse TEN.service --no-pager
```

Lưu trạng thái enabled/active rồi mới dùng
`sudo systemctl disable --now TEN.service` và các socket/path kích hoạt nó
đã xác định không dùng. Không gỡ package ở bước đầu. Nếu cần phục hồi, enable
lại chỉ những unit trước đó enabled và start lại chỉ những unit trước đó active;
không dùng `enable --now` một cách mù quáng cho unit vốn disabled.

Chưa có unit nào được xác nhận là thừa trên VPS đích, nên bộ công cụ hiện không
chứa hành động tự động tắt dịch vụ. Bước tiếp theo là đọc báo cáo audit thực tế.
