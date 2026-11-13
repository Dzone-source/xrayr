#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/xrayr-host.sh"
mock_weight=100
active=true
fail_write=false
calls=0
systemctl() {
  case "$1" in
    show) printf '%s\n' "$mock_weight" ;;
    is-active) [[ $active == true ]] ;;
    set-property)
      calls=$((calls + 1))
      [[ $fail_write == false ]] || return 1
      mock_weight=${3#CPUWeight=}
      ;;
    *) echo "Unexpected command: $*" >&2; return 1 ;;
  esac
}
set_weight XrayR.service 1000 >/dev/null
[[ $mock_weight == 1000 && $calls == 1 ]]
set_weight XrayR.service 100 >/dev/null
[[ $mock_weight == 100 && $calls == 2 ]]
active=false
if set_weight XrayR.service 1000 >/dev/null 2>&1; then exit 1; fi
[[ $calls == 2 ]]
active=true
for invalid in 0 10001 -1 99999999999999999999999999 garbage; do
  if set_weight XrayR.service "$invalid" >/dev/null 2>&1; then exit 1; fi
done
if set_weight ssh.service 1000 >/dev/null 2>&1; then exit 1; fi
[[ $calls == 2 ]]
fail_write=true
if set_weight XrayR.service 1000 >/dev/null 2>&1; then exit 1; fi
[[ $mock_weight == 100 ]]
mock_weight=18446744073709551615
[[ $(get_weight XrayR.service) == 100 ]]
mock_weight=idle
[[ $(get_weight XrayR.service) == idle ]]
echo 'PASS: priority, restoration, inactive service, invalid values, protected service and failed write'
