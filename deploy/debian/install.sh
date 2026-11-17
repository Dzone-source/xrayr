#!/usr/bin/env bash
# Install a prebuilt binary; never compile on the 512 MB VPS.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

preflight() {
  [[ $EUID == 0 ]] || { echo 'Run as root' >&2; return 1; }
  source /etc/os-release
  [[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) && $(uname -m) == x86_64 ]] || { echo 'Requires Debian 12/13 amd64' >&2; return 1; }
  [[ $# == 2 && -f $1 && -f $2 ]] || { echo "Usage: $0 /path/to/XrayR /path/to/config.yml" >&2; return 1; }
  # Preserve existing installation and config before attempting kernel changes.
  [[ ! -e /usr/local/bin/XrayR && ! -e /etc/XrayR && ! -e /etc/systemd/system/xrayr.service ]] || { echo 'Existing installation found; back up and migrate explicitly before installing.' >&2; return 1; }
  [[ -f $script_dir/network.sh && -f $script_dir/xrayr.service ]] || { echo 'Incomplete installation bundle' >&2; return 1; }
}

main() {
  preflight "$@" || return 1
  # Abort on APT/kernel failure before writing any XrayR files.
  bash "$script_dir/network.sh" kernel || return 1
  install -m 0755 "$1" /usr/local/bin/XrayR
  install -d -m 0700 /etc/XrayR
  install -m 0600 "$2" /etc/XrayR/config.yml
  install -m 0644 "$script_dir/xrayr.service" /etc/systemd/system/xrayr.service
  if [[ -d $script_dir/assets ]]; then
    for asset in "$script_dir"/assets/*; do
      install -m 0600 "$asset" "/etc/XrayR/$(basename -- "$asset")"
    done
  fi
  systemctl daemon-reload
  echo 'Installed, not started. Install any referenced geo/routing/TLS files, then run: systemctl enable --now xrayr'
  echo 'Debian kernel package installed/updated. The running kernel changes only after a manual reboot; keep provider console access and check uname -r afterwards.'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
