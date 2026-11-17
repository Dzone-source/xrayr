# Debian 12/13 amd64 KVM — ưu tiên thông lượng

Nhánh này giữ nguyên buffer kết nối, GC mặc định và giới hạn tốc độ của node/user. Không thể cam kết tốc độ tối đa trên VPS 1 CPU/512 MB nếu chưa đo với giao thức, mã hóa, số kết nối và đường truyền thực tế. BBR chỉ tác động TCP; không tăng băng thông thuê của VPS hay trực tiếp tăng tốc UDP/QUIC.

## Tải bản build sẵn

```sh
curl -fLO https://raw.githubusercontent.com/Dzone-source/xrayr/optimize/debian-512mb/dist/XrayR-debian-linux-amd64.tar.gz
curl -fLO https://raw.githubusercontent.com/Dzone-source/xrayr/optimize/debian-512mb/dist/XrayR-debian-linux-amd64.tar.gz.sha256
sha256sum -c XrayR-debian-linux-amd64.tar.gz.sha256
mkdir -p xrayr-debian
tar -xzf XrayR-debian-linux-amd64.tar.gz -C xrayr-debian
cd xrayr-debian
sha256sum -c XrayR.sha256
sudo bash install.sh ./XrayR /path/to/config.yml
```

Thay `/path/to/config.yml` bằng config thật. Với VPS đang chạy XrayR, bộ cài sẽ dừng để bảo vệ bản cũ; không xóa config hiện tại để ép cài mới. Tải theo nhánh lấy bản mới nhất; muốn cố định bản, thay tên nhánh trong URL bằng commit chứa artifact.

## Build trên máy phát triển, không build trên VPS 512 MB

Dùng Go 1.24.1, chạy từ gốc repository (hoặc chạy `bash deploy/debian/build.sh` để test và đóng gói):

```sh
go mod download
go mod verify
go test -race ./common/limiter
go test ./common/limiter -run '^$' -bench BenchmarkExistingConnection -benchmem -count=5
mkdir -p dist
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=readonly -trimpath -ldflags='-s -w' -o dist/XrayR .
sha256sum dist/XrayR > dist/XrayR.sha256
```

Chuyển binary và checksum qua SSH tới VPS; kiểm tra `sha256sum -c XrayR.sha256`. Checksum đi cùng binary phát hiện lỗi truyền; nguồn tin cậy là máy build/SSH của bạn. Binary đóng gói nằm trong `dist/XrayR-debian-linux-amd64.tar.gz`; kiểm tra checksum trước khi cài.

## Cài mới

Chuẩn bị config thật từ `release/config/config.yml.example`. Không dùng API key mẫu. Chép các file geoip/geosite, DNS, routing và chứng chỉ mà config tham chiếu vào đúng đường dẫn. Bộ cài từ chối ghi đè bản cũ; với VPS đang chạy, cần backup binary, config, unit và xác định tên service trước khi chuyển đổi.

```sh
sudo bash deploy/debian/install.sh /path/to/XrayR /path/to/config.yml
sudo systemctl enable --now xrayr
sudo journalctl -u xrayr -n 50 --no-pager
```

Service dùng `GOMAXPROCS=1` cho 1 vCPU; không ép GOMEMLIMIT/GOGC và không hạ buffer để tiết kiệm RAM. Kiểm tra RSS và CPU dưới tải; nếu vượt 512 MB thì phải giảm số kết nối hoặc tăng RAM, không có thiết lập nào đảm bảo cả thông lượng và RAM cố định dưới mọi tải. Không tự thêm swap, quota CPU hay giới hạn tốc độ mạng.

## BBR và kernel (tùy chọn, chạy thủ công)

```sh
sudo bash deploy/debian/network.sh status
sudo bash deploy/debian/network.sh bbr
# Chỉ khi cần kernel Debian mới và đã có console/recovery của nhà cung cấp:
sudo bash deploy/debian/network.sh kernel
```

Debian 12/13 thường đã hỗ trợ BBR, không cần thay kernel. Lệnh `kernel` cài metapackage `linux-image-amd64` từ repository APT đang cấu hình, không cài kernel bên thứ ba, không xóa kernel cũ, không tự reboot. Kiểm tra nguồn APT chính thức, dung lượng /boot, bootloader, console và backup trước khi chạy. Sau reboot, kiểm tra `uname -r`, kết nối SSH và service. Nếu lỗi, chọn kernel cũ từ console.

BBR được ghi vào `/etc/sysctl.d/90-xrayr-bbr.conf`; script từ chối ghi đè file này. Ghi lại các giá trị sysctl cũ trước khi chạy. Để hoàn tác: xóa file này rồi khôi phục các giá trị cũ bằng `sysctl -w`; xóa file không tự hoàn tác trạng thái đang chạy. `fq` mặc định không thay qdisc đã gắn trên interface; kiểm tra bằng `tc qdisc show`. Không tự thay qdisc interface để tránh làm gián đoạn mạng.

## Xác minh tốc độ trước khi triển khai

So sánh main và nhánh này trên cùng VPS, cùng core/config, endpoint và payload. Dùng client thực qua proxy, đo download/upload, CPU, RSS, lỗi và độ trễ ở 1/10/50 kết nối; lặp ít nhất 5 lần. Đo TCP và UDP riêng. `iperf3` trực tiếp chỉ đo đường truyền nền, không thay thế phép đo qua XrayR. Benchmark limiter chỉ đo cấp phát trong Go, không chứng minh thông lượng mạng. Chỉ chuyển service thật sau khi build, test và phép đo qua proxy đạt yêu cầu.
