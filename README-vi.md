# XrayR

[![](https://img.shields.io/badge/TgChat-@XrayR讨论-blue.svg)](https://t.me/XrayR_project)
[![](https://img.shields.io/badge/Channel-@XrayR通知-blue.svg)](https://t.me/XrayR_channel)
![](https://img.shields.io/github/stars/XrayR-project/XrayR)
![](https://img.shields.io/github/forks/XrayR-project/XrayR)
![](https://github.com/XrayR-project/XrayR/actions/workflows/release.yml/badge.svg)
![](https://github.com/XrayR-project/XrayR/actions/workflows/docker.yml/badge.svg)
[![Github All Releases](https://img.shields.io/github/downloads/XrayR-project/XrayR/total.svg)]()

[Iranian(farsi) README](https://github.com/XrayR-project/XrayR/blob/master/README_Fa.md), [Vietnamese(vi) README](https://github.com/XrayR-project/XrayR/blob/master/README-vi.md), [English(en) README](https://github.com/XrayR-project/XrayR/blob/master/README-en.md)

A Xray backend framework that can easily support many panels.

Khung trở lại dựa trên XRay hỗ trợ các giao thức V2ay, Trojan, Shadowsocks, dễ dàng mở rộng và hỗ trợ kết nối nhiều người.

Nếu bạn thích dự án này, bạn có thể nhấp vào Star+Watch ở góc trên bên phải để tiếp tục chú ý đến tiến trình của dự án này.

## Tài liệu
Sử dụng hướng dẫn: [Hướng dẫn chi tiết](https://xrayr-project.github.io/XrayR-doc/) ( Tiếng Trung )

## Tuyên bố miễn trừ

Dự án này chỉ là học tập và phát triển và bảo trì cá nhân của tôi. Tôi không đảm bảo bất kỳ sự sẵn có nào và không chịu trách nhiệm cho bất kỳ hậu quả nào do việc sử dụng phần mềm này.

## Đặt điểm nổi bật

* Nguồn mở vĩnh viễn và miễn phí.
* Hỗ trợ V2Ray, Trojan, Shadowsocks nhiều giao thức.
* Hỗ trợ các tính năng mới như Vless và XTL.
* Hỗ trợ trường hợp đơn lẻ kết nối Multi -Panel và Multi -Node, không cần phải bắt đầu nhiều lần.
* Hỗ trợ hạn chế IP trực tuyến
* Hỗ trợ cấp cổng nút và giới hạn tốc độ cấp người dùng.
* Cấu hình đơn giản và rõ ràng.
* Sửa đổi phiên bản khởi động lại tự động.
* Dễ dàng biên dịch và nâng cấp, bạn có thể nhanh chóng cập nhật phiên bản cốt lõi và hỗ trợ các tính năng mới của Xray-Core.

## Chức năng

| Chức năng        | v2ray | trojan | shadowsocks |
|-----------|-------|--------|-------------|
| Nhận thông tin Node    | √     | √      | √           |
| Nhận thông tin người dùng    | √     | √      | √           |
| Thống kê lưu lượng người dùng    | √     | √      | √           |
| Báo cáo thông tin máy chủ   | √     | √      | √           |
| Tự động đăng ký chứng chỉ TLS | √     | √      | √           |
| Chứng chỉ TLS gia hạn tự động | √     | √      | √           |
| Số người trực tuyến    | √     | √      | √           |
| Hạn chế người dùng trực tuyến    | √     | √      | √           |
| Quy tắc kiểm toán      | √     | √      | √           |
| Giới hạn tốc độ cổng nút    | √     | √      | √           |
| Theo giới hạn tốc độ người dùng    | √     | √      | √           |
| DNS tùy chỉnh    | √     | √      | √           |

## Hỗ trợ Panel 

| Panel                                                     | v2ray | trojan | shadowsocks             |
|--------------------------------------------------------|-------|--------|-------------------------|
| sspanel-uim                                            | √     | √      | √ (Nhiều người dùng cuối và v2ray-plugin) |
| v2board                                                | √     | √      | √                       |
| [PMPanel](https://github.com/ByteInternetHK/PMPanel)   | √     | √      | √                       |
| [ProxyPanel](https://github.com/ProxyPanel/ProxyPanel) | √     | √      | √                       |
| [WHMCS (V2RaySocks)](https://v2raysocks.doxtex.com/)   | √     | √      | √                       |
| [BunPanel](https://github.com/pennyMorant/bunpanel-release)   | √     | √      | √                       |

## Cài đặt phần mềm

### Cài đặt một lệnh

```bash
bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/latest/download/install.sh)
```

Hoặc:

```bash
wget -N https://github.com/Dzone-source/xrayr/releases/latest/download/install.sh && bash install.sh
```

Sau khi cài xong:
- Sửa cấu hình: `/etc/XrayR/config.yml`
- Quản lý dịch vụ: gõ `XrayR` (menu) hoặc `XrayR start|stop|restart|log|status`
- **Tối ưu mượt mà (BBR + buffer):** `XrayR optimize`

Cài phiên bản cụ thể:

```bash
bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/latest/download/install.sh) v0.9.5
```

### Triển khai bằng Docker

```bash
docker build -t xrayr .
docker run -d --name xrayr --network host -v /etc/XrayR:/etc/XrayR xrayr
```

### Cài đặt thủ công

1. Cài Go (>= 1.24)
2. `git clone https://github.com/Dzone-source/xrayr.git && cd xrayr`
3. `CGO_ENABLED=0 go build -o XrayR -trimpath -ldflags "-s -w -buildid="`
4. Copy binary và file trong `release/config/` lên server, chạy với `--config /etc/XrayR/config.yml`

## Tệp cấu hình và hướng dẫn sử dụng chi tiết

[Hướng dẫn chi tiết](https://xrayr-project.github.io/XrayR-doc/)

## Thanks

* [Project X](https://github.com/XTLS/)
* [V2Fly](https://github.com/v2fly)
* [VNet-V2ray](https://github.com/ProxyPanel/VNet-V2ray)
* [Air-Universe](https://github.com/crossfw/Air-Universe)

## Licence

[Mozilla Public License Version 2.0](https://github.com/XrayR-project/XrayR/blob/master/LICENSE)

## Telgram

[Xrayr Back-end Thảo luận](https://t.me/XrayR_project)

[Thông báo Xrayr](https://t.me/XrayR_channel)

## Stargazers over time

[![Stargazers over time](https://starchart.cc/XrayR-project/XrayR.svg)](https://starchart.cc/XrayR-project/XrayR)
