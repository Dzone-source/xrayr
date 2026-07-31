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

Nguyên nhân thường gặp: `ConnectionConfig.UplinkOnly: 5` — sau khi phía server half-close downlink, Xray chỉ giữ uplink ~5 giây rồi cắt (upload speed-test hay bị).

```yaml
ConnectionConfig:
  Handshake: 8
  ConnIdle: 300
  UplinkOnly: 300    # không để 5
  DownlinkOnly: 300  # không để 8
  BufferSize: 512
```

Áp dụng nhanh trên node:

```bash
sed -i \
  -e 's/^  UplinkOnly:.*/  UplinkOnly: 300/' \
  -e 's/^  DownlinkOnly:.*/  DownlinkOnly: 300/' \
  /etc/XrayR/config.yml
systemctl restart XrayR
```

Cũng kiểm tra: `SpeedLimit: 0`, `DeviceLimit: 0`, user còn đủ traffic, node không chạm `node_bandwidth_limit`.
