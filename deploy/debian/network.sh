#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root' >&2; exit 1; }
source /etc/os-release
[[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) && $(uname -m) == x86_64 ]] || { echo 'Requires Debian 12/13 amd64' >&2; exit 1; }
virt=$(systemd-detect-virt || true)
[[ $virt == kvm ]] || { echo "Expected KVM, detected: $virt; inspect manually" >&2; exit 1; }
case ${1:-status} in
  status)
    uname -r
    sysctl net.ipv4.tcp_available_congestion_control net.ipv4.tcp_congestion_control net.core.default_qdisc
    ;;
  bbr)
    [[ ! -e /etc/sysctl.d/90-xrayr-bbr.conf ]] || { echo 'Existing BBR config; inspect manually' >&2; exit 1; }
    modprobe tcp_bbr
    [[ " $(sysctl -n net.ipv4.tcp_available_congestion_control) " == *' bbr '* ]] || { echo 'BBR unavailable' >&2; exit 1; }
    printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > /etc/sysctl.d/90-xrayr-bbr.conf
    sysctl -p /etc/sysctl.d/90-xrayr-bbr.conf
    echo 'Applies to new sockets; verify active interface qdisc with tc qdisc show. Existing qdiscs are not replaced.'
    ;;
  kernel)
    echo 'Installing official Debian kernel metapackage; keeping old kernels. No automatic reboot.'
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove linux-image-amd64
    echo 'Review bootloader, free /boot space, and provider console before a manual reboot.'
    ;;
  *) echo "Usage: $0 {status|bbr|kernel}" >&2; exit 1 ;;
esac
