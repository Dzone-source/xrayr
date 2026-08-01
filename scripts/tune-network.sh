#!/usr/bin/env bash
# Kernel/network tuning for XrayR proxy nodes (BBR + buffers).
set -euo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-xrayr-tune.conf"

cat >"${SYSCTL_FILE}" <<'EOF'
# XrayR network tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
net.core.netdev_max_backlog=250000
net.core.somaxconn=4096
net.ipv4.ip_local_port_range=1024 65535
fs.file-max=1048576
EOF

sysctl --system >/dev/null 2>&1 || sysctl -p "${SYSCTL_FILE}" 2>/dev/null || true

# Raise open files for current session (systemd unit also sets limits)
if [[ -f /etc/security/limits.d/99-xrayr.conf ]]; then
  :
else
  cat >/etc/security/limits.d/99-xrayr.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi

echo "Applied ${SYSCTL_FILE}"
