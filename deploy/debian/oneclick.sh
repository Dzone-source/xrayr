#!/usr/bin/env bash
# This bootstrap pins the bundle to an immutable Git commit.
set -euo pipefail
BUNDLE_REF=1e982a5c29ce997f6167e8ee20916c0bb064bbd0
MODE=install
BACKUP_ROOT=/var/backups/XrayR
CONFIG_ROOT=/etc/XrayR
BASE_URL="https://raw.githubusercontent.com/Dzone-source/xrayr/$BUNDLE_REF/dist"

preflight_oneclick() {
  [[ $EUID == 0 ]] || { echo 'Run as root (sudo bash oneclick.sh).' >&2; return 1; }
  source /etc/os-release
  [[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) && $(uname -m) == x86_64 ]] || { echo 'Requires Debian 12/13 amd64' >&2; return 1; }
  [[ $(systemd-detect-virt || true) == kvm ]] || { echo 'Requires KVM' >&2; return 1; }
  if [[ $MODE == upgrade ]]; then
    [[ $# == 0 ]] || { echo 'Upgrade preserves the current config; do not supply a new config.' >&2; return 1; }
    discover_upgrade || return 1
  else
    [[ ! -e /usr/local/bin/XrayR && ! -e /usr/local/XrayR/XrayR && ! -e /etc/XrayR && ! -e /etc/systemd/system/xrayr.service ]] || { echo 'Existing XrayR found. Run: sudo bash xrayr-oneclick.sh --upgrade' >&2; return 1; }
  fi
  [[ $# -le 1 ]] || { echo 'Usage: oneclick.sh [/path/to/config.yml]' >&2; return 1; }
  if [[ $# == 1 ]]; then [[ -f $1 ]] || { echo 'Config file not found' >&2; return 1; }; fi
  for command in curl tar sha256sum systemctl; do
    command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; return 1; }
  done
}


discover_upgrade() {
  local candidate id exec_start
  upgrade_service=
  for candidate in xrayr.service XrayR.service; do
    [[ $(systemctl show -p LoadState --value "$candidate" 2>/dev/null) == loaded ]] || continue
    id=$(systemctl show -p Id --value "$candidate")
    [[ -n $id ]] || return 1
    if [[ -n $upgrade_service && $upgrade_service != "$id" ]]; then
      echo 'Multiple XrayR services found; manual migration required.' >&2; return 1
    fi
    upgrade_service=$id
  done
  [[ -n $upgrade_service ]] || { echo 'No supported systemd XrayR service found; files preserved.' >&2; return 1; }
  exec_start=$(systemctl show -p ExecStart --value "$upgrade_service")
  [[ $exec_start =~ path=([^\;[:space:]]+) ]] || { echo 'Cannot identify service binary' >&2; return 1; }
  upgrade_binary=${BASH_REMATCH[1]}
  case $upgrade_binary in
    /usr/local/bin/XrayR|/usr/local/XrayR/XrayR|/usr/bin/XrayR) ;;
    *) echo 'Unsupported service binary path; manual migration required.' >&2; return 1 ;;
  esac
  [[ -f $upgrade_binary && ! -L $upgrade_binary && -d /etc/XrayR && ! -L /etc/XrayR ]] || { echo 'Missing files or symlink installation; manual migration required.' >&2; return 1; }
  # Back up standard config tree only; reject explicit config locations outside it.
  if [[ $exec_start =~ (--config|-config|-c)(=|[[:space:]]+)([^[:space:]\;]+) ]]; then
    [[ ${BASH_REMATCH[3]} == /etc/XrayR/* ]] || { echo 'Custom config outside /etc/XrayR; manual migration required.' >&2; return 1; }
  else
    [[ $(systemctl show -p WorkingDirectory --value "$upgrade_service") == /etc/XrayR ]] || { echo 'Custom working directory without explicit config; manual migration required.' >&2; return 1; }
  fi
  upgrade_unit=$(systemctl show -p FragmentPath --value "$upgrade_service")
  [[ -f $upgrade_unit ]] || { echo 'Service unit not found' >&2; return 1; }
}

run_kernel_update() { bash "$1/network.sh" kernel; }

upgrade_bundle() {
  local package=$1 was_active=0 backup replacement
  systemctl is-active --quiet "$upgrade_service" && was_active=1
  install -d -m 0700 "$BACKUP_ROOT"
  backup=$(mktemp -d "$BACKUP_ROOT/upgrade-XXXXXXXX")
  cp -a -- "$upgrade_binary" "$backup/XrayR"
  cp -a -- "$CONFIG_ROOT" "$backup/config"
  cp -a -- "$upgrade_unit" "$backup/service.unit"
  systemctl cat "$upgrade_service" > "$backup/effective-unit.txt"
  printf '%s\n' "$upgrade_binary" > "$backup/binary-path.txt"
  (cd "$backup" && sha256sum XrayR > XrayR.sha256 && sha256sum -c XrayR.sha256) || return 1
  echo "Backup: $backup"
  run_kernel_update "$package" || return 1
  replacement=$(mktemp "${upgrade_binary}.new.XXXXXXXX")
  if ! install -m 0755 "$package/XrayR" "$replacement"; then
    rm -f -- "$replacement"; return 1
  fi
  if ! mv -f -- "$replacement" "$upgrade_binary"; then
    rm -f -- "$replacement"; return 1
  fi
  # Preserve config, geo assets, service unit, overrides and enable/disable state.
  if [[ $was_active == 1 ]]; then
    if ! systemctl restart "$upgrade_service" || ! { sleep 3; systemctl is-active --quiet "$upgrade_service"; }; then
      echo 'Restart failed; restoring previous binary.' >&2
      replacement=$(mktemp "${upgrade_binary}.rollback.XXXXXXXX")
      cp -p -- "$backup/XrayR" "$replacement"
      mv -f -- "$replacement" "$upgrade_binary"
      if ! systemctl restart "$upgrade_service"; then
        echo "Rollback restart failed. Inspect journalctl -u $upgrade_service; backup: $backup" >&2
      fi
      return 1
    fi
  fi
  echo "XrayR upgraded; configuration and unit preserved. Backup: $backup"
  [[ $was_active == 1 ]] || echo 'Service was inactive and remains inactive.'
  echo 'Kernel package updated. Reboot manually to load it; old kernels retained.'
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
  if [[ $MODE == upgrade ]]; then
    upgrade_bundle "$work/package"
    return $?
  fi
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
  if [[ ${1:-} == --upgrade ]]; then MODE=upgrade; shift; fi
  preflight_oneclick "$@" || return 1
  umask 077
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  install_bundle "$work" "${1:-}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
