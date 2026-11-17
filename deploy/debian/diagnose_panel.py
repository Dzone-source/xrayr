#!/usr/bin/env python3
"""Read one configured panel locally; print response shape, never API credentials."""
import json
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def config_field(text, name):
    matches = re.findall(r'^\s*' + re.escape(name) + r':\s*([^\r\n]+)', text, re.M)
    if len(matches) != 1:
        raise ValueError('Expected exactly one ' + name + ' entry; multi-node configuration needs manual diagnosis')
    value = matches[0].strip()
    if value.startswith(('"', "'")):
        quote = value[0]
        value = value[1:].split(quote, 1)[0]
    else:
        value = value.split(' #', 1)[0].strip()
    return value


def shape(value):
    if isinstance(value, dict):
        return {key: shape(item) for key, item in value.items() if not re.search(r'key|password|passwd|secret|token|uuid', key, re.I)}
    if isinstance(value, list):
        return {'type': 'array', 'length': len(value), 'first_type': type(value[0]).__name__ if value else None}
    return type(value).__name__


def summarize(data):
    result = {'data_shape': shape(data)}
    if not isinstance(data, dict):
        return result
    version = data.get('version')
    if isinstance(version, str) and re.fullmatch(r'[0-9.\-]{0,32}', version):
        result['version'] = version
    server = data.get('server')
    if isinstance(server, str):
        fields = server.split(';')
        result['server_semicolon_fields'] = len(fields)
        result['server_field_lengths'] = [len(field) for field in fields]
    custom = data.get('custom_config')
    if isinstance(custom, str):
        try:
            custom = json.loads(custom)
        except ValueError:
            custom = None
    result['custom_config_shape'] = shape(custom)
    # Only report known protocol enums and numeric port/sort fields, not arbitrary strings.
    for name in ('port', 'server_port', 'sort'):
        value = data.get(name)
        if type(value) is int:
            result[name] = value
    for name in ('network', 'security', 'type', 'method'):
        value = data.get(name)
        if value in ('tcp', 'ws', 'grpc', 'tls', 'reality', 'vless', 'vmess', 'V2ray', 'Vless', 'aes-128-gcm', 'chacha20-ietf-poly1305'):
            result[name] = value
    return result


def main():
    text = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/etc/XrayR/config.yml').read_text()
    host = config_field(text, 'ApiHost').rstrip('/')
    key = config_field(text, 'ApiKey')
    node = int(config_field(text, 'NodeID'))
    if urllib.parse.urlsplit(host).scheme != 'https':
        raise ValueError('HTTPS ApiHost required for credential protection')
    url = host + '/mod_mu/nodes/' + str(node) + '/info?' + urllib.parse.urlencode({'key': key, 'muKey': key})
    request = urllib.request.Request(url, headers={'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read(2 * 1024 * 1024)
            body = json.loads(raw)
            print(json.dumps({'http_status': response.status, 'response_shape': shape(body), **summarize(body.get('data'))}, indent=2, ensure_ascii=False))
    except urllib.error.HTTPError as error:
        print(json.dumps({'http_status': error.code, 'error': 'Panel rejected GET; response body and credential URL omitted'}))
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, urllib.error.URLError):
        print('Could not inspect panel safely (config/network/JSON issue). Credentials and response body omitted.', file=sys.stderr)
        sys.exit(1)
