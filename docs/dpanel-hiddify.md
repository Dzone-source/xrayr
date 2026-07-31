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
bash <(curl -Ls https://raw.githubusercontent.com/Dzone-source/xrayr/cursor/hiddify-stable-node-7233/install.sh)
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

Deploy node (config tại **`/etc/xrayr`**):

```bash
systemctl cat XrayR | grep -E 'ExecStart|WorkingDirectory'

cd /tmp
rm -rf xrayr && git clone -b cursor/hiddify-stable-node-7233 https://github.com/Dzone-source/xrayr.git
cd xrayr

# Đổi đường dẫn binary cho khớp ExecStart trên máy bạn (ví dụ):
go build -o /usr/local/XrayR/XrayR -ldflags "-s -w" -trimpath .
# hoặc: go build -o /etc/xrayr/XrayR -ldflags "-s -w" -trimpath .

sed -i \
  -e 's/^  ConnIdle:.*/  ConnIdle: 600/' \
  -e 's/^  UplinkOnly:.*/  UplinkOnly: 3600/' \
  -e 's/^  DownlinkOnly:.*/  DownlinkOnly: 3600/' \
  -e 's/^  BufferSize:.*/  BufferSize: 1024/' \
  /etc/xrayr/config.yml

grep -nE 'SpeedLimit|DeviceLimit|NodeType' /etc/xrayr/config.yml
systemctl restart XrayR
journalctl -u XrayR -f | egrep -i 'GetUserList|user deleted|not a valid user'
```

Phải thấy `GetUserList: N users` (N>0), không còn hàng loạt `not a valid user`. Giữ `SpeedLimit: 0`, `DeviceLimit: 0`.
