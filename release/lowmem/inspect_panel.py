#!/usr/bin/env python3
"""Read one SSpanel node and print an allowlisted, redacted schema report.

Uses only Python's standard library. Does not change files or services.
"""
import argparse
import json
import re
import shlex
import sys
import urllib.error
import urllib.parse
import urllib.request


class DiagnosticError(Exception):
    pass


def read_settings(path, node_id=None):
    # Read only simple ApiConfig blocks. Never interpret arbitrary YAML tags.
    blocks = []
    current = None
    indent = 0
    with open(path, encoding="utf-8") as config:
        for line in config:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            level = len(line) - len(line.lstrip())
            if current is not None and level <= indent:
                blocks.append(current)
                current = None
            if stripped == "ApiConfig:":
                current, indent = {}, level
            elif current is not None:
                match = re.match(r"(ApiHost|ApiKey|NodeID):\s*(.*)$", stripped)
                if match:
                    try:
                        tokens = shlex.split(match[2], comments=True)
                    except ValueError:
                        raise DiagnosticError("Cannot read ApiConfig scalar; no values were printed.") from None
                    if len(tokens) != 1:
                        raise DiagnosticError("Only simple scalar ApiConfig values are supported.")
                    current[match[1]] = tokens[0]
    if current is not None:
        blocks.append(current)
    if node_id is not None:
        blocks = [b for b in blocks if b.get("NodeID") == str(node_id)]
    if len(blocks) != 1 or not all(blocks[0].get(k) for k in ("ApiHost", "ApiKey", "NodeID")):
        raise DiagnosticError("Select exactly one complete ApiConfig with --node-id NUMBER.")
    if not blocks[0]["NodeID"].isdecimal():
        raise DiagnosticError("NodeID must be an integer.")
    return blocks[0]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch_node(settings):
    base = urllib.parse.urlsplit(settings["ApiHost"])
    local = base.hostname in ("127.0.0.1", "::1", "localhost")
    if (base.scheme != "https" and not (base.scheme == "http" and local)) or base.username or base.password or base.query or base.fragment:
        raise DiagnosticError("ApiHost must be an HTTPS URL without embedded credentials/query.")
    query = urllib.parse.urlencode({"key": settings["ApiKey"], "muKey": settings["ApiKey"]})
    url = settings["ApiHost"].rstrip("/") + "/mod_mu/nodes/" + settings["NodeID"] + "/info?" + query
    opener = urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(url, timeout=30) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise DiagnosticError("Response exceeds the diagnostic size limit.")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        raise DiagnosticError("Panel returned HTTP status " + str(error.code) + "; URL/body were not printed.") from None
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        raise DiagnosticError("Could not read panel JSON; URL, keys and response body were not printed.") from None


PROTOCOLS = {"tcp", "raw", "ws", "websocket", "grpc", "h2", "http", "kcp", "quic", "xhttp", "splithttp", "none", "tls", "xtls", "reality", "vless", "vmess", "V2ray", "Vless", "Vmess", "Trojan", "Shadowsocks", "xtls-rprx-vision"}
VALUE_FIELDS = {"network", "transport", "transport_protocol", "protocol", "type", "security", "flow", "tls"}
FLAG_FIELDS = {"enable_vless", "enable_reality", "enable_xtls", "DisableCustomConfig"}
PORT_FIELDS = {"port", "server_port", "node_port", "offset_port_node"}


def safe_schema(value, key="", depth=0):
    if depth > 8:
        return "<depth-limit>"
    if isinstance(value, dict):
        return {(k if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]{0,63}", k) else "<non-field-key>"): safe_schema(v, k, depth + 1) for k, v in list(value.items())[:150]}
    if isinstance(value, list):
        return {"type": "array", "length": len(value), "first_item_schema": safe_schema(value[0], "", depth + 1) if value else None}
    if value is None:
        return None
    if key in VALUE_FIELDS and isinstance(value, str) and value in PROTOCOLS:
        return value
    if key in FLAG_FIELDS and str(value).lower() in ("true", "false", "0", "1"):
        return value
    if key in PORT_FIELDS and str(value).isdecimal() and 0 < int(value) <= 65535:
        return value
    if key == "version" and isinstance(value, str) and re.fullmatch(r"[0-9]{1,4}(\.[0-9]{1,4}){0,4}", value):
        return value
    if isinstance(value, str):
        if key in ("custom_config", "server", "config"):
            try:
                decoded = json.loads(value)
                if isinstance(decoded, (dict, list)):
                    return {"type": "encoded_json", "schema": safe_schema(decoded, "", depth + 1)}
            except ValueError:
                pass
        if key == "server":
            return {"type": "string", "semicolon_fields": len(value.split(";")), "empty": not value}
        return "<string:redacted>" if value else "<empty-string>"
    return "<" + type(value).__name__ + ":redacted>"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="/etc/XrayR/config.yml")
    parser.add_argument("--node-id", type=int)
    args = parser.parse_args()
    try:
        data = fetch_node(read_settings(args.config, args.node_id))
        print(json.dumps({"diagnostic": "schema-only; credentials and arbitrary values redacted", "response_schema": safe_schema(data)}, indent=2, ensure_ascii=True))
    except (DiagnosticError, OSError) as error:
        # OSError filenames and request details can be sensitive; hide them.
        print(str(error) if isinstance(error, DiagnosticError) else "Cannot read local configuration.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
