# DPanel Trojan + Hiddify (XrayR)

Node protocol: **Trojan** (`NodeType: Trojan`).

| XrayR | DPanel |
|-------|--------|
| `PanelType: SSpanel` | WebAPI `/mod_mu` |
| `ApiHost` | `webAPIUrl` |
| `ApiKey` | `muKey` |
| `NodeID` | id node sort=14 |
| `CertMode: file/http/dns` | TLS bắt buộc cho Trojan |

```bash
# Cài / cập nhật kiểu XrayR cũ (tải zip release — không cần Go)
bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/download/v0.9.13/install.sh) v0.9.13
# hoặc nếu đã có script quản lý:
# XrayR update v0.9.13

nano /etc/XrayR/config.yml   # NodeType: Trojan + CertConfig
systemctl restart XrayR
journalctl -u XrayR -n 80 --no-pager
```

Nếu log có `not a valid user` khi sync user → deploy panel branch có fix alive_ip (không hard-kick Trojan khi IP limit).

## Speed test bị rớt giữa chừng (upload)

**Không liên quan hết data.** Nguyên nhân phổ biến trên XrayR:

1. **Sync user remove+add** — `compareUserList` cũ so sánh cả `SpeedLimit`/`DeviceLimit`. Mỗi chu kỳ sync (~60–90s) giá trị limit đổi nhẹ → XrayR xóa Trojan user rồi add lại → session upload đứt giữa chừng (log: `N user deleted, M user added`).
2. **`alive_ip` omit** — user bị bỏ khỏi list → cũng remove.
3. **`UplinkOnly` quá nhỏ** — half-close downlink rồi cắt uplink sớm.

Bản fix: so sánh user theo UID/credential; chỉ update limiter khi đổi speed/IP limit; không omit user vì alive_ip; `UplinkOnly/DownlinkOnly: 3600`.

```yaml
ConnectionConfig:
  Handshake: 8
  ConnIdle: 600
  UplinkOnly: 3600
  DownlinkOnly: 3600
  BufferSize: 1024
```

Deploy node (config **`/etc/XrayR`**, **không cần Go**):

```bash
# v0.9.13+: update zip + tự patch UplinkOnly/DownlinkOnly nếu config cũ còn 2~5
XrayR update v0.9.13
# hoặc:
# bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/download/v0.9.13/install.sh) v0.9.13

# Kiểm tra config (bắt buộc UplinkOnly/DownlinkOnly >= 300; binary cũng clamp)
grep -nE 'UplinkOnly|DownlinkOnly|ConnIdle|SpeedLimit|DeviceLimit|NodeType' /etc/XrayR/config.yml
# Kỳ vọng: UplinkOnly: 3600, DownlinkOnly: 3600, SpeedLimit: 0, DeviceLimit: 0

systemctl restart XrayR
journalctl -u XrayR -n 50 --no-pager | egrep -i 'UplinkOnly|clamping|GetUserList|rebuild|user deleted|not a valid user'
```

Upload speedtest vẫn đứt nếu `/etc/XrayR/config.yml` còn `UplinkOnly: 5` (update binary không sửa YAML trên bản < 0.9.13). Phải thấy `GetUserList: N users` (N>0), **không** thấy `rebuilding inbound` mỗi chu kỳ sync.
