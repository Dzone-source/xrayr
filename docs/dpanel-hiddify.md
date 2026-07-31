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
bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/download/v0.9.12/install.sh) v0.9.12
# hoặc nếu đã có script quản lý:
# XrayR update v0.9.12

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
# 1) Cập nhật binary từ release (giữ /etc/XrayR/config.yml)
XrayR update v0.9.12
# nếu chưa có lệnh XrayR:
# bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/download/v0.9.12/install.sh) v0.9.12

# 2) Timeout / limit trong config hiện có
sed -i \
  -e 's/^  ConnIdle:.*/  ConnIdle: 600/' \
  -e 's/^  UplinkOnly:.*/  UplinkOnly: 3600/' \
  -e 's/^  DownlinkOnly:.*/  DownlinkOnly: 3600/' \
  -e 's/^  BufferSize:.*/  BufferSize: 1024/' \
  /etc/XrayR/config.yml

grep -nE 'SpeedLimit|DeviceLimit|NodeType|ApiHost' /etc/XrayR/config.yml
systemctl restart XrayR
/usr/local/XrayR/XrayR version
journalctl -u XrayR -f | egrep -i 'GetUserList|user deleted|not a valid user|Added'
```

Phải thấy `GetUserList: N users` (N>0). Giữ `SpeedLimit: 0`, `DeviceLimit: 0`.
