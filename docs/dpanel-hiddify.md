# DPanel + Hiddify (XrayR)

Reference: [Xboard](https://github.com/cedar2025/Xboard) / [Xboard-Node](https://github.com/cedar2025/Xboard-Node) panel-driven protocol config.

## Pair with DPanel

| XrayR | DPanel |
|-------|--------|
| `PanelType: SSpanel` | WebAPI `/mod_mu` |
| `ApiHost` | `webAPIUrl` (HTTPS + matching Host) |
| `ApiKey` | `muKey` |
| `NodeID` | node id in admin |
| `DisableLocalREALITYConfig: true` | REALITY keys in node `custom_config` |

Do **not** use `PanelType: NewV2board` against DPanel (that is UniProxy for Xboard).

## Recommended `config.yml` snippet

See `release/config/config.yml.example`.

```bash
# Install
bash <(curl -Ls https://raw.githubusercontent.com/Dzone-source/xrayr/main/install.sh)
# Generate REALITY keypair for panel custom_config
XrayR x25519
```

## Stability notes for Hiddify

1. Panel subscription must advertise **vless** + **reality public_key** (DPanel ≥ this PR).
2. Node `custom_config.security: reality` alone is enough to enable REALITY (also accepts `enable_reality: 1`).
3. Empty `flow` on VLESS TCP defaults to `xtls-rprx-vision`.
4. Numeric `offset_port_node` / bool `allow_insecure` from DPanel JSON no longer crash the node.
