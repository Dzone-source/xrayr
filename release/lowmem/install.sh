#!/usr/bin/env bash
# Upgrade an existing XrayR service without changing config or network settings.
set -euo pipefail

restart_with_rollback() {
  local service=$1 executable=$2 saved=$3
  local started_at diagnostic="${3}.startup.log"
  started_at=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
  # Clear a previous systemd start-rate limit for this service only.
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
  if systemctl restart "$service" && sleep 2 && systemctl is-active --quiet "$service"; then
    echo "Service active with optimized XrayR. Test your client connection and panel traffic."
    echo "Rollback: cp -a '$saved' '${executable}.rollback' && mv -fT '${executable}.rollback' '$executable' && systemctl restart '$service'"
    return 0
  fi

  echo 'Startup failed. Capturing the failure before restoring the old binary.' >&2
  if (umask 077; {
    systemctl show "$service" -p Result -p ExecMainCode -p ExecMainStatus || true
    journalctl -u "$service" --since "$started_at" -n 200 --no-pager -o cat | sed '/ accepted /d' || true
  } > "$diagnostic"); then
    cat "$diagnostic" >&2
    echo "Failure log: $diagnostic (redact keys/tokens before sharing)" >&2
  else
    echo 'Could not save diagnostics; continuing rollback.' >&2
  fi
  staged=$(mktemp "${executable}.rollback.XXXXXX") || return 1
  cp -a -- "$saved" "$staged" || return 1
  mv -fT -- "$staged" "$executable" || return 1
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
  if systemctl restart "$service" && sleep 2 && systemctl is-active --quiet "$service"; then
    echo 'Old binary restored; service is active.' >&2
  else
    echo "Old binary restored, but $service is not active. Inspect systemctl status and the saved log." >&2
  fi
  return 1
}

main() {
unit=""
binary=""
download_only=""
while (($#)); do
  case "$1" in
    --service) unit=${2:?Missing service name}; shift 2 ;;
    --bin) binary=${2:?Missing binary path}; shift 2 ;;
    --download-only) download_only=${2:?Missing output directory}; shift 2 ;;
    *) echo "Usage: bash $0 [--service XrayR.service] [--bin /absolute/path/XrayR] [--download-only DIR]" >&2; exit 2 ;;
  esac
done
for tool in curl tar sha256sum mktemp; do
  command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 1; }
done
[[ $(uname -s) == Linux ]] || { echo 'Linux is required' >&2; exit 1; }
case $(uname -m) in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo 'Only Linux amd64 and arm64 are supported' >&2; exit 1 ;;
esac

if [[ -z $download_only ]]; then
  ((EUID == 0)) || { echo 'Run with sudo, or use --download-only DIR' >&2; exit 1; }
  command -v systemctl >/dev/null
  if [[ -z $unit ]]; then
    for candidate in XrayR.service xrayr.service; do
      if systemctl cat "$candidate" >/dev/null 2>&1; then
        [[ -z $unit ]] || { echo 'Multiple units found; specify --service' >&2; exit 1; }
        unit=$candidate
      fi
    done
  fi
  [[ -n $unit ]] || { echo 'No XrayR service found. This installer upgrades an existing installation.' >&2; exit 1; }
  exec_start=$(systemctl show "$unit" -p ExecStart --value)
  if [[ -z $binary ]]; then
    for candidate in /usr/local/XrayR/XrayR /usr/local/bin/XrayR /usr/bin/XrayR; do
      if [[ $exec_start == *"path=$candidate ;"* && -f $candidate ]]; then
        binary=$candidate
        break
      fi
    done
  fi
  [[ $binary == /* && -f $binary && ! -L $binary ]] || { echo 'Specify --bin with the absolute path of the actual binary (not a symlink).' >&2; exit 1; }
  [[ $exec_start == *"path=$binary ;"* ]] || { echo 'ExecStart does not directly reference this binary. Inspect the unit before upgrading.' >&2; exit 1; }
fi

work=$(mktemp -d)
staged=""
trap 'rm -rf -- "$work"; if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
artifact="XrayR-linux-$arch"
expected_version=0.9.5-lowmem.2
base=https://raw.githubusercontent.com/Dzone-source/xrayr/perf/low-memory-debian/release/lowmem/dist
for file in "$artifact.tar.gz" "$artifact.tar.gz.sha256"; do
  curl --proto '=https' --tlsv1.2 -fSL --retry 2 "$base/$file?v=$expected_version" -o "$work/$file"
done
# Require exactly the expected checksum record before passing it to sha256sum.
checksum_line=$(cat "$work/$artifact.tar.gz.sha256")
[[ $checksum_line =~ ^[0-9a-f]{64}\ \ XrayR-linux-$arch\.tar\.gz$ ]] || { echo 'Invalid checksum file' >&2; exit 1; }
(cd "$work" && sha256sum -c "$artifact.tar.gz.sha256")
[[ $(tar -tzf "$work/$artifact.tar.gz") == "$artifact" ]] || { echo 'Unexpected archive contents' >&2; exit 1; }
tar -xzf "$work/$artifact.tar.gz" -C "$work" --no-same-owner
chmod 0755 "$work/$artifact"
version_output=$("$work/$artifact" version)
printf '%s\n' "$version_output"
[[ $version_output == *"XrayR $expected_version "* ]] || { echo "Expected $expected_version; download may be stale. No service changes were made." >&2; exit 1; }
if [[ -n $download_only ]]; then
  mkdir -p -- "$download_only"
  install -m 0755 "$work/$artifact" "$download_only/XrayR"
  echo "Ready: $download_only/XrayR (optimized; no Go needed)"
  exit 0
fi

backup="${binary}.backup-$(date -u +%Y%m%dT%H%M%S)-$$"
cp -a -- "$binary" "$backup"
staged=$(mktemp "${binary}.new.XXXXXX")
install -m 0755 -- "$work/$artifact" "$staged"
# Keep existing owner, permissions and xattrs (including file capabilities).
cp --attributes-only --preserve=all -- "$binary" "$staged"
mv -fT -- "$staged" "$binary"
echo "Backup: $backup"
restart_with_rollback "$unit" "$binary" "$backup"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
