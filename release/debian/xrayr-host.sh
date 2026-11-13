#!/usr/bin/env bash
# Inspect the host or prioritize XrayR without restarting it.
set -euo pipefail

valid_weight() {
  [[ $1 == idle || $1 =~ ^([1-9][0-9]{0,3}|10000)$ ]]
}

get_weight() {
  local value
  value=$(systemctl show "$1" -p CPUWeight --value) || return 1
  if valid_weight "$value"; then
    printf '%s\n' "$value"
  else
    # systemd's unset value means the default effective weight of 100.
    printf '100\n'
  fi
}

set_weight() {
  local unit=$1 weight=$2 old
  [[ $unit == XrayR.service || $unit == xrayr.service ]] || { echo 'Use the actual XrayR.service or xrayr.service unit.' >&2; return 1; }
  valid_weight "$weight" || { echo 'CPUWeight must be idle or 1..10000.' >&2; return 1; }
  systemctl is-active --quiet "$unit" || { echo 'XrayR is not active; no changes made.' >&2; return 1; }
  old=$(get_weight "$unit") || return 1
  printf 'Current CPUWeight: %s\nRestore scheduling weight: systemctl set-property %s CPUWeight=%s\n' "$old" "$unit" "$old"
  systemctl set-property "$unit" "CPUWeight=$weight" || return 1
  printf 'Applied CPUWeight=%s to %s without restarting.\n' "$weight" "$unit"
  echo 'This changes relative CPU priority under contention; it sets no CPU or memory cap.'
}

audit() {
  echo '=== OS and kernel ==='
  sed -n '/^PRETTY_NAME=/p; /^VERSION_ID=/p' /etc/os-release
  uname -r
  uname -m
  systemd-detect-virt || true
  echo '=== Boot space ==='
  df -h /boot
  if [[ -d /sys/firmware/efi ]]; then echo UEFI; else echo 'BIOS or no exposed EFI'; fi
  echo '=== Network drivers (no IP addresses) ==='
  for device in /sys/class/net/*; do
    if [[ -L $device/device/driver ]]; then
      printf '%s: %s\n' "${device##*/}" "$(basename "$(readlink -f "$device/device/driver")")"
    fi
  done
  echo '=== Resource summary ==='
  free -h
  ps -eo comm,rss,pcpu --sort=-rss | head -20 || true
  echo '=== Running services (names, no environment or config values) ==='
  systemctl list-units --type=service --state=running --no-pager --plain
  echo '=== Timers ==='
  systemctl list-timers --all --no-pager
  echo '=== Installed kernel packages ==='
  dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package} ${Version}\n' 'linux-image-*' 2>/dev/null || true
  case $(uname -m) in
    x86_64) package=linux-image-amd64 ;;
    aarch64|arm64) package=linux-image-arm64 ;;
    *) echo 'No generic kernel package selected for this architecture.'; return ;;
  esac
  echo '=== Kernel package policy (local package index; not proof of latest upstream) ==='
  apt-cache policy "$package"
  echo '=== Cgroup CPU controller ==='
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then cat /sys/fs/cgroup/cgroup.controllers; else echo 'cgroup v2 not detected'; fi
}

main() {
  case ${1:-audit} in
    audit) audit ;;
    prioritize|restore)
      ((EUID == 0)) || { echo 'Run this mode as root.' >&2; return 1; }
      source /etc/os-release
      [[ $ID == debian && ($VERSION_ID == 12 || $VERSION_ID == 13) ]] || { echo 'Only Debian 12/13 supported.' >&2; return 1; }
      [[ -f /sys/fs/cgroup/cgroup.controllers ]] && grep -qw cpu /sys/fs/cgroup/cgroup.controllers || { echo 'cgroup v2 CPU controller required; no changes made.' >&2; return 1; }
      if [[ $1 == prioritize ]]; then
        set_weight "${2:-XrayR.service}" 1000
      else
        set_weight "${2:-XrayR.service}" "${3:?Supply the previous CPUWeight printed by prioritize}"
      fi
      ;;
    *) echo "Usage: bash $0 audit | prioritize [XrayR.service] | restore XrayR.service OLD_WEIGHT" >&2; return 2 ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
