#!/usr/bin/env bash
# Isolated tests: no root, network calls or real systemd commands.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/install.sh"
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
sleep() { :; }
systemctl() {
  case "$1" in
    reset-failed) resets=$((resets + 1)); return 0 ;;
    restart)
      restarts=$((restarts + 1))
      if [[ $scenario == restart-fails && $restarts == 1 || $scenario == rollback-fails ]]; then
        return 1
      fi
      return 0 ;;
    is-active)
      [[ $scenario != inactive || $restarts != 1 ]] ;;
    show) echo 'Result=exit-code'; echo 'ExecMainStatus=2' ;;
    *) echo "Unexpected systemctl command: $*" >&2; return 1 ;;
  esac
}
journalctl() { echo 'panic: synthetic SSpanel failure'; }

for scenario in success restart-fails inactive rollback-fails; do
  dir="$root/$scenario"
  mkdir "$dir"
  printf old > "$dir/backup"
  printf new > "$dir/binary"
  resets=0
  restarts=0
  if restart_with_rollback XrayR.service "$dir/binary" "$dir/backup" > "$dir/output" 2>&1; then
    [[ $scenario == success && $(cat "$dir/binary") == new && $restarts == 1 ]]
  else
    [[ $scenario != success && $(cat "$dir/binary") == old && $restarts == 2 && $resets == 2 ]]
    [[ $(stat -c %a "$dir/backup.startup.log") == 600 ]]
    grep -q 'synthetic SSpanel failure' "$dir/backup.startup.log"
    if [[ $scenario == rollback-fails ]]; then
      grep -q 'is not active' "$dir/output"
    else
      grep -q 'Old binary restored; service is active' "$dir/output"
    fi
  fi
  printf 'PASS: %s\n' "$scenario"
done
