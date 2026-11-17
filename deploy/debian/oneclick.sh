#!/usr/bin/env bash
# This bootstrap pins the bundle to an immutable Git commit.
set -euo pipefail
BUNDLE_REF=216c3e351bd2b3f30133ab2104f708c03d4fbd33
BASE_URL="https://raw.githubusercontent.com/Dzone-source/xrayr/$BUNDLE_REF/dist"

preflight_oneclick() {
  [[ $EUID == 0 ]] || { echo 'Run as root (sudo bash oneclick.sh).' >&2; return 1; }
  source /etc/os-release
  [[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) && $(uname -m) == x86_64 ]] || { echo 'Requires Debian 12/13 amd64' >&2; return 1; }
  [[ $(systemd-detect-virt || true) == kvm ]] || { echo 'Requires KVM' >&2; return 1; }
  [[ ! -e /usr/local/bin/XrayR && ! -e /etc/XrayR && ! -e /etc/systemd/system/xrayr.service ]] || { echo 'Existing XrayR found; configuration preserved. Fresh installs only.' >&2; return 1; }
  [[ $# -le 1 ]] || { echo 'Usage: oneclick.sh [/path/to/config.yml]' >&2; return 1; }
  if [[ $# == 1 ]]; then [[ -f $1 ]] || { echo 'Config file not found' >&2; return 1; }; fi
  for command in curl tar sha256sum systemctl; do
    command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; return 1; }
  done
}

install_bundle() {
  local work=$1 supplied_config=${2:-}
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' "$BASE_URL/XrayR-debian-linux-amd64.tar.gz" -o "$work/bundle.tar.gz"
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' "$BASE_URL/XrayR-debian-linux-amd64.tar.gz.sha256" -o "$work/bundle.sha256"
  # Require exactly one checksum for the expected filename; never accept arbitrary paths.
  local expected filename extra
  read -r expected filename extra < "$work/bundle.sha256"
  [[ $expected =~ ^[[:xdigit:]]{64}$ && $filename == XrayR-debian-linux-amd64.tar.gz && -z $extra ]] || { echo 'Invalid checksum manifest' >&2; return 1; }
  printf '%s  %s\n' "$expected" "$work/bundle.tar.gz" | sha256sum -c - || return 1
  mkdir "$work/package"
  tar --extract --gzip --file "$work/bundle.tar.gz" --directory "$work/package" --no-same-owner
  (cd "$work/package" && sha256sum -c XrayR.sha256) || return 1
  local config=$supplied_config
  if [[ -z $config ]]; then
    config=$work/config.yml
    printf 'Log:\n  Level: warning\nNodes: []\n' > "$config"
  fi
  bash "$work/package/install.sh" "$work/package/XrayR" "$config" || return 1
  systemctl enable --now xrayr
  systemctl is-active --quiet xrayr
  echo 'XrayR installed and started. Kernel package updated; reboot manually to load it.'
  if [[ -z $supplied_config ]]; then
    echo 'No panel node configured. Edit /etc/XrayR/config.yml using /etc/XrayR/config.yml.example, then systemctl restart xrayr.'
  fi
}

main() {
  preflight_oneclick "$@" || return 1
  umask 077
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  install_bundle "$work" "${1:-}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
