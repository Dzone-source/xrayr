#!/usr/bin/env bash
# Install a prebuilt binary; never compile on the 512 MB VPS.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root' >&2; exit 1; }
source /etc/os-release
[[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) && $(uname -m) == x86_64 ]] || { echo 'Requires Debian 12/13 amd64' >&2; exit 1; }
[[ $# == 2 && -f $1 && -f $2 ]] || { echo "Usage: $0 /path/to/XrayR /path/to/config.yml" >&2; exit 1; }
# Preserve existing installation and config for explicit operator migration.
[[ ! -e /usr/local/bin/XrayR && ! -e /etc/XrayR && ! -e /etc/systemd/system/xrayr.service ]] || { echo 'Existing installation found; back up and migrate explicitly before installing.' >&2; exit 1; }
install -m 0755 "$1" /usr/local/bin/XrayR
install -d -m 0700 /etc/XrayR
install -m 0600 "$2" /etc/XrayR/config.yml
install -m 0644 "$(dirname "$0")/xrayr.service" /etc/systemd/system/xrayr.service
systemctl daemon-reload
echo 'Installed, not started. Install any referenced geo/routing/TLS files, then run: systemctl enable --now xrayr'
