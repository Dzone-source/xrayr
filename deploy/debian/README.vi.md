# Debian 12/13 amd64 KVM — ưu tiên thông lượng

Nhánh này giữ nguyên buffer kết nối, GC mặc định và giới hạn tốc độ của node/user. Không thể cam kết tốc độ tối đa trên VPS 1 CPU/512 MB nếu chưa đo với giao thức, mã hóa, số kết nối và đường truyền thực tế. BBR chỉ tác động TCP; không tăng băng thông thuê của VPS hay trực tiếp tăng tốc UDP/QUIC.

## One-click: bản build sẵn + kernel Debian

Chạy trên VPS Debian 12/13 amd64 KVM (cần `curl`, quyền sudo/root và console/recovery của nhà cung cấp):

```sh
curl -fsSL https://raw.githubusercontent.com/Dzone-source/xrayr/feature/device-profiles/deploy/debian/oneclick.sh -o xrayr-oneclick.sh && sudo bash xrayr-oneclick.sh
```

Lệnh tự tải gói binary đã build từ một commit cố định, kiểm tra SHA-256 của gói và binary, cài/cập nhật kernel `linux-image-amd64`, cài các file geo/cấu hình mẫu và khởi động dịch vụ XrayR. Không biên dịch trên VPS. Không ghi đè bản XrayR đã có, không tự reboot, không tự bật BBR.

Mặc định `/etc/XrayR/config.yml` có `Nodes: []`: dịch vụ chạy nhưng **chưa phục vụ node proxy**. Điền panel/API key/node thật theo `/etc/XrayR/config.yml.example`, rồi chạy `sudo systemctl restart xrayr`. Không gửi API key trong lệnh hoặc chat. Nếu đã chuẩn bị config thật từ trước, dùng `sudo bash xrayr-oneclick.sh /path/to/config.yml`; kiểm tra các đường dẫn file mà config tham chiếu.

Sau khi cài, reboot thủ công khi sẵn sàng để nạp kernel mới. Kiểm tra `uname -r`, `systemctl status xrayr` và `journalctl -u xrayr -n 50 --no-pager`. Cài kernel mới không đảm bảo tăng tốc mạng.

## Máy đã có XrayR: nâng cấp giữ cấu hình

Nếu thấy `Existing XrayR found`, không xóa `/etc/XrayR`. Tải lại bootstrap mới và chạy chế độ nâng cấp:

```sh
curl -fsSL https://raw.githubusercontent.com/Dzone-source/xrayr/feature/device-profiles/deploy/debian/oneclick.sh -o xrayr-oneclick.sh && sudo bash xrayr-oneclick.sh --upgrade
```

Hỗ trợ service `xrayr.service` hoặc `XrayR.service` với binary ở `/usr/local/bin/XrayR`, `/usr/local/XrayR/XrayR` hoặc `/usr/bin/XrayR`, cấu hình chuẩn trong `/etc/XrayR`. Script đọc service thực tế để chọn binary; nếu phát hiện nhiều service khác nhau hoặc đường dẫn tùy biến, nó dừng trước khi đổi kernel/binary.

Bản sao lưu binary, thư mục cấu hình và unit được lưu tại `/var/backups/XrayR/upgrade-*` (chỉ root truy cập). Sau đó script cập nhật kernel, thay binary bằng rename nguyên tử và restart service đang chạy. Không đổi API key/node, geo assets, unit hoặc trạng thái enable/disable. Service vốn dừng sẽ tiếp tục dừng. Restart làm ngắt các kết nối đang có; nên chạy lúc ít người dùng.

Nếu restart lỗi hoặc service không active sau 3 giây, script thử khôi phục binary cũ và restart lại; backup được giữ để xử lý thủ công nếu khôi phục cũng lỗi. Đây là kiểm tra trạng thái service, không chứng minh các node truyền tải thành công; cần kiểm tra journal và lưu lượng thực sau nâng cấp. Không hoàn tác kernel APT và không tự reboot.

## Tải bản build sẵn

```sh
curl -fLO https://raw.githubusercontent.com/Dzone-source/xrayr/feature/device-profiles/dist/XrayR-debian-linux-amd64.tar.gz
curl -fLO https://raw.githubusercontent.com/Dzone-source/xrayr/feature/device-profiles/dist/XrayR-debian-linux-amd64.tar.gz.sha256
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

## Cài mới — tự cài kernel Debian

`install.sh` mặc định kiểm tra Debian 12/13 amd64 KVM rồi chạy APT để cài/cập nhật `linux-image-amd64` trước khi ghi file XrayR. Cần mạng tới nguồn APT, đủ dung lượng `/boot` và console/recovery của nhà cung cấp. Nếu bước kernel lỗi, bộ cài dừng và chưa ghi file XrayR; APT có thể đã thay đổi một phần trạng thái package, cần xử lý lỗi APT trước khi chạy lại. Nếu đã có kernel mới nhất, APT giữ nguyên; không ép cài kernel khác.

Giữ kernel cũ, không tự reboot. Kernel đang chạy chỉ đổi sau khi bạn reboot thủ công; cấu hình bootloader quyết định kernel được chọn. Bộ cài không tự thay bootloader. Không tự bật BBR; dùng lệnh riêng bên dưới.

Chuẩn bị config thật từ `release/config/config.yml.example`. Không dùng API key mẫu. Chép các file geoip/geosite, DNS, routing và chứng chỉ mà config tham chiếu vào đúng đường dẫn. Bộ cài từ chối ghi đè bản cũ; với VPS đang chạy, cần backup binary, config, unit và xác định tên service trước khi chuyển đổi.

```sh
sudo bash deploy/debian/install.sh /path/to/XrayR /path/to/config.yml
sudo systemctl enable --now xrayr
sudo journalctl -u xrayr -n 50 --no-pager
```

Service dùng `GOMAXPROCS=1` cho 1 vCPU; không ép GOMEMLIMIT/GOGC và không hạ buffer để tiết kiệm RAM. Kiểm tra RSS và CPU dưới tải; nếu vượt 512 MB thì phải giảm số kết nối hoặc tăng RAM, không có thiết lập nào đảm bảo cả thông lượng và RAM cố định dưới mọi tải. Không tự thêm swap, quota CPU hay giới hạn tốc độ mạng.

## BBR và cập nhật kernel riêng

```sh
sudo bash deploy/debian/network.sh status
sudo bash deploy/debian/network.sh bbr
# Cập nhật kernel riêng sau lần cài mới, nếu cần:
sudo bash deploy/debian/network.sh kernel
```

Debian 12/13 thường đã hỗ trợ BBR, không cần thay kernel. Lệnh `kernel` cài metapackage `linux-image-amd64` từ repository APT đang cấu hình, không cài kernel bên thứ ba, không xóa kernel cũ, không tự reboot. Kiểm tra nguồn APT chính thức, dung lượng /boot, bootloader, console và backup trước khi chạy. Sau reboot, kiểm tra `uname -r`, kết nối SSH và service. Nếu lỗi, chọn kernel cũ từ console.

BBR được ghi vào `/etc/sysctl.d/90-xrayr-bbr.conf`; script từ chối ghi đè file này. Ghi lại các giá trị sysctl cũ trước khi chạy. Để hoàn tác: xóa file này rồi khôi phục các giá trị cũ bằng `sysctl -w`; xóa file không tự hoàn tác trạng thái đang chạy. `fq` mặc định không thay qdisc đã gắn trên interface; kiểm tra bằng `tc qdisc show`. Không tự thay qdisc interface để tránh làm gián đoạn mạng.

## Xác minh tốc độ trước khi triển khai

So sánh main và nhánh này trên cùng VPS, cùng core/config, endpoint và payload. Dùng client thực qua proxy, đo download/upload, CPU, RSS, lỗi và độ trễ ở 1/10/50 kết nối; lặp ít nhất 5 lần. Đo TCP và UDP riêng. `iperf3` trực tiếp chỉ đo đường truyền nền, không thay thế phép đo qua XrayR. Benchmark limiter chỉ đo cấp phát trong Go, không chứng minh thông lượng mạng. Chỉ chuyển service thật sau khi build, test và phép đo qua proxy đạt yêu cầu.

## Tương thích DPanel

Bản `0.9.5-debian-dpanel.1` chọn `custom_config` có dữ liệu dù panel dùng phiên bản dạng `1.0.0` thay vì lịch SSPanel. Hỗ trợ port dạng số/chuỗi, cờ VLESS dạng boolean/số/chuỗi; kiểm tra port và cấu trúc legacy trước khi đọc. `DisableCustomConfig: true` vẫn buộc dùng định dạng legacy. REALITY lấy cấu hình local khi `DisableLocalREALITYConfig: false`; không tự sinh hoặc thay private key của node hiện có.

Nếu endpoint báo cáo trạng thái node trả HTTP 405, backend ghi cảnh báo một lần rồi ngừng gửi loại báo cáo này đến khi tiến trình khởi động lại; các báo cáo user/traffic vẫn giữ nguyên. Đây không phải lỗi kernel.

## Profile thiết bị (0.9.5-debian-devices.1)

Cần triển khai nhánh `feature/device-profiles` của DPanel và chạy migration trước khi bật chế độ này cho account. Nâng cấp node trước; account chưa bật vẫn dùng UUID cũ. Node mới gửi khả năng `device_profiles=1`, nhận UUID riêng + `device_id` cho mỗi profile và tính lưu lượng về `user_id` gốc.

Thu hồi một profile hoặc khóa account được thực thi sau lần đồng bộ danh sách user tiếp theo. Node đóng cả luồng đang chạy, không chỉ từ chối kết nối mới. Với profile thiết bị, quyền cache hết hạn sau `max(120, 3 * UpdatePeriodic)` giây nếu không đồng bộ thành công; các phiên bị cắt trong tối đa khoảng 5 giây tiếp theo. Account legacy không áp dụng timeout quyền này. `304 Not Modified` vẫn gia hạn quyền.

Nên đặt `UpdatePeriodic: 30` để thu hồi trong khoảng 30 giây khi web/node liên lạc bình thường. Không gọi web theo từng gói dữ liệu. Trạng thái online dựa trên các luồng còn mở; profile sao chép sang hai máy vẫn cùng một định danh, không phải xác thực phần cứng. DPanel hiển thị trạng thái nhận trong 180 giây gần đây.
