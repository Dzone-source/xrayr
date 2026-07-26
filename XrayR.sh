#!/usr/bin/env bash
#
# XrayR management script
# Installed to: /usr/bin/XrayR
#

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO="Dzone-source/xrayr"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
INSTALL_SCRIPT_URL="https://github.com/${REPO}/releases/latest/download/install.sh"

[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi:${plain} phải chạy bằng root.\n" && exit 1

detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /etc/issue 2>/dev/null; then
        release="centos"
    elif grep -Eqi "debian" /proc/version 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /proc/version 2>/dev/null; then
        release="centos"
    else
        echo -e "${red}Không nhận diện được hệ điều hành.${plain}\n" && exit 1
    fi
}

detect_os

confirm() {
    if [[ $# -gt 1 ]]; then
        echo && read -rp "$1 [mặc định $2]: " temp
        if [[ -z "${temp}" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0
    fi
    return 1
}

confirm_restart() {
    confirm "Khởi động lại XrayR?" "y"
    if [[ $? -eq 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Nhấn Enter để về menu: ${plain}" && read -r temp
    show_menu
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    local temp
    temp=$(systemctl status XrayR 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ "${temp}" == "running" ]]; then
        return 0
    fi
    return 1
}

check_enabled() {
    local temp
    temp=$(systemctl is-enabled XrayR 2>/dev/null)
    if [[ "${temp}" == "enabled" ]]; then
        return 0
    fi
    return 1
}

check_uninstall() {
    check_status
    if [[ $? -ne 2 ]]; then
        echo ""
        echo -e "${red}XrayR đã được cài, không cài lại.${plain}"
        if [[ $# -eq 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    return 0
}

check_install() {
    check_status
    if [[ $? -eq 2 ]]; then
        echo ""
        echo -e "${red}Hãy cài XrayR trước.${plain}"
        if [[ $# -eq 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    return 0
}

install() {
    bash <(curl -Ls "${INSTALL_SCRIPT_URL}")
    if [[ $? -eq 0 ]]; then
        if [[ $# -eq 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    local version=""
    if [[ $# -eq 0 ]]; then
        echo && echo -n -e "Nhập phiên bản (Enter = mới nhất): " && read -r version
    else
        version=${2:-}
    fi
    bash <(curl -Ls "${INSTALL_SCRIPT_URL}") ${version}
    if [[ $? -eq 0 ]]; then
        echo -e "${green}Cập nhật xong. Xem log bằng: XrayR log${plain}"
        exit 0
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "XrayR sẽ tự khởi động lại sau khi sửa cấu hình (nếu đang chạy)."
    if command -v vim >/dev/null 2>&1; then
        vim /etc/XrayR/config.yml
    elif command -v vi >/dev/null 2>&1; then
        vi /etc/XrayR/config.yml
    elif command -v nano >/dev/null 2>&1; then
        nano /etc/XrayR/config.yml
    else
        echo -e "${red}Không tìm thấy trình soạn thảo (vim/vi/nano).${plain}"
        echo "File: /etc/XrayR/config.yml"
    fi
    sleep 2
    check_status
    case $? in
        0)
            echo -e "Trạng thái XrayR: ${green}đang chạy${plain}"
            ;;
        1)
            echo -e "XrayR chưa chạy hoặc tự khởi động lại thất bại. Xem log? [Y/n]"
            read -e -rp "(mặc định: y): " yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
                show_log
            fi
            ;;
        2)
            echo -e "Trạng thái XrayR: ${red}chưa cài${plain}"
            ;;
    esac
}

uninstall() {
    confirm "Xác nhận gỡ XrayR?" "n"
    if [[ $? -ne 0 ]]; then
        if [[ $# -eq 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop XrayR 2>/dev/null || true
    systemctl disable XrayR 2>/dev/null || true
    rm -f /etc/systemd/system/XrayR.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    rm -rf /etc/XrayR/
    rm -rf /usr/local/XrayR/

    echo ""
    echo -e "Đã gỡ. Để xóa script quản lý: ${green}rm -f /usr/bin/XrayR /usr/bin/xrayr${plain}"
    echo ""

    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${green}XrayR đang chạy rồi.${plain}"
    else
        systemctl start XrayR
        sleep 2
        check_status
        if [[ $? -eq 0 ]]; then
            echo -e "${green}Khởi động thành công. Xem log: XrayR log${plain}"
        else
            echo -e "${red}Có thể khởi động thất bại. Xem: XrayR log${plain}"
        fi
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

stop() {
    systemctl stop XrayR
    sleep 2
    check_status
    if [[ $? -eq 1 ]]; then
        echo -e "${green}Đã dừng XrayR${plain}"
    else
        echo -e "${red}Dừng thất bại, kiểm tra log.${plain}"
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart XrayR
    sleep 2
    check_status
    if [[ $? -eq 0 ]]; then
        echo -e "${green}Khởi động lại thành công. Xem log: XrayR log${plain}"
    else
        echo -e "${red}Có thể khởi động thất bại. Xem: XrayR log${plain}"
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status XrayR --no-pager -l
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable XrayR
    if [[ $? -eq 0 ]]; then
        echo -e "${green}Đã bật khởi động cùng hệ thống${plain}"
    else
        echo -e "${red}Bật khởi động cùng hệ thống thất bại${plain}"
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable XrayR
    if [[ $? -eq 0 ]]; then
        echo -e "${green}Đã tắt khởi động cùng hệ thống${plain}"
    else
        echo -e "${red}Tắt khởi động cùng hệ thống thất bại${plain}"
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u XrayR.service -e --no-pager -f
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh)
}

update_shell() {
    local url="https://github.com/${REPO}/releases/latest/download/XrayR.sh"
    wget -O /usr/bin/XrayR -N --no-check-certificate "${url}" \
        || wget -O /usr/bin/XrayR -N --no-check-certificate "${RAW_BASE}/XrayR.sh"
    if [[ $? -ne 0 ]]; then
        echo ""
        echo -e "${red}Tải script thất bại, kiểm tra kết nối GitHub.${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/XrayR
        ln -sf /usr/bin/XrayR /usr/bin/xrayr
        echo -e "${green}Đã nâng cấp script. Chạy lại XrayR.${plain}" && exit 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Trạng thái XrayR: ${green}đang chạy${plain}"
            show_enable_status
            ;;
        1)
            echo -e "Trạng thái XrayR: ${yellow}đã dừng${plain}"
            show_enable_status
            ;;
        2)
            echo -e "Trạng thái XrayR: ${red}chưa cài${plain}"
            ;;
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? -eq 0 ]]; then
        echo -e "Khởi động cùng hệ thống: ${green}có${plain}"
    else
        echo -e "Khởi động cùng hệ thống: ${red}không${plain}"
    fi
}

show_XrayR_version() {
    echo -n "Phiên bản XrayR: "
    /usr/local/XrayR/XrayR version
    echo ""
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

generate_config_file() {
    echo -e "${yellow}Trình tạo cấu hình XrayR${plain}"
    echo -e "${red}Lưu ý:${plain}"
    echo -e "1. File mới: /etc/XrayR/config.yml"
    echo -e "2. File cũ được lưu: /etc/XrayR/config.yml.bak"
    echo -e "3. Chế độ này chưa cấu hình TLS nâng cao"
    read -rp "Tiếp tục? (y/n): " generate_config_file_continue
    if [[ ! $generate_config_file_continue =~ ^[yY]$ ]]; then
        echo -e "${red}Đã hủy.${plain}"
        before_show_menu
        return
    fi

    echo -e "${yellow}Chọn panel:${plain}"
    echo -e "${green}1.${plain} SSpanel"
    echo -e "${green}2.${plain} NewV2board"
    echo -e "${green}3.${plain} PMpanel"
    echo -e "${green}4.${plain} Proxypanel"
    echo -e "${green}5.${plain} V2RaySocks"
    echo -e "${green}6.${plain} GoV2Panel"
    echo -e "${green}7.${plain} BunPanel"
    read -rp "Panel [1-7, mặc định 2]: " PanelType
    case "$PanelType" in
        1) PanelType="SSpanel" ;;
        3) PanelType="PMpanel" ;;
        4) PanelType="Proxypanel" ;;
        5) PanelType="V2RaySocks" ;;
        6) PanelType="GoV2Panel" ;;
        7) PanelType="BunPanel" ;;
        *) PanelType="NewV2board" ;;
    esac

    read -rp "ApiHost (vd: https://panel.example.com): " ApiHost
    read -rp "ApiKey: " ApiKey
    read -rp "NodeID: " NodeID

    echo -e "${yellow}Chọn NodeType:${plain}"
    echo -e "${green}1.${plain} Shadowsocks"
    echo -e "${green}2.${plain} Shadowsocks-Plugin"
    echo -e "${green}3.${plain} V2ray"
    echo -e "${green}4.${plain} Trojan"
    echo -e "${green}5.${plain} Vless"
    read -rp "NodeType [1-5, mặc định 3]: " NodeType
    case "$NodeType" in
        1) NodeType="Shadowsocks" ;;
        2) NodeType="Shadowsocks-Plugin" ;;
        4) NodeType="Trojan" ;;
        5) NodeType="Vless" ;;
        *) NodeType="V2ray" ;;
    esac

    mkdir -p /etc/XrayR
    if [[ -f /etc/XrayR/config.yml ]]; then
        mv /etc/XrayR/config.yml /etc/XrayR/config.yml.bak
    fi

    cat >/etc/XrayR/config.yml <<EOF
Log:
  Level: warning
  AccessPath:
  ErrorPath:
DnsConfigPath:
RouteConfigPath:
InboundConfigPath:
OutboundConfigPath:
ConnectionConfig:
  Handshake: 8
  ConnIdle: 300
  UplinkOnly: 5
  DownlinkOnly: 8
  BufferSize: 512
Nodes:
  - PanelType: "${PanelType}"
    ApiConfig:
      ApiHost: "${ApiHost}"
      ApiKey: "${ApiKey}"
      NodeID: ${NodeID}
      NodeType: ${NodeType}
      Timeout: 30
      EnableVless: false
      VlessFlow: "xtls-rprx-vision"
      SpeedLimit: 0
      DeviceLimit: 0
      RuleListPath:
      DisableCustomConfig: false
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 90
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false
      EnableFallback: false
      DisableLocalREALITYConfig: false
      EnableREALITY: false
      CertConfig:
        CertMode: none
        CertDomain: "node1.test.com"
        CertFile: /etc/XrayR/cert/node1.test.com.cert
        KeyFile: /etc/XrayR/cert/node1.test.com.key
EOF

    echo -e "${green}Đã tạo cấu hình, đang khởi động lại XrayR...${plain}"
    restart 0
    before_show_menu
}

open_ports() {
    systemctl stop firewalld.service 2>/dev/null || true
    systemctl disable firewalld.service 2>/dev/null || true
    setenforce 0 2>/dev/null || true
    ufw disable 2>/dev/null || true
    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true
    echo -e "${green}Đã mở firewall (ACCEPT tất cả).${plain}"
}

patch_config_performance() {
    local f="/etc/XrayR/config.yml"
    if [[ ! -f "${f}" ]]; then
        echo -e "${yellow}Không tìm thấy ${f}, bỏ qua tinh chỉnh config.${plain}"
        return 0
    fi
    cp -a "${f}" "${f}.bak.performance.$(date +%s)"

    sed -i \
        -e 's/^  Handshake:.*/  Handshake: 8/' \
        -e 's/^  ConnIdle:.*/  ConnIdle: 300/' \
        -e 's/^  UplinkOnly:.*/  UplinkOnly: 5/' \
        -e 's/^  DownlinkOnly:.*/  DownlinkOnly: 8/' \
        -e 's/^  BufferSize:.*/  BufferSize: 512/' \
        -e 's/^  Level:.*/  Level: warning/' \
        -e 's/^      UpdatePeriodic:.*/      UpdatePeriodic: 90/' \
        "${f}"

    echo -e "${green}Đã áp dụng thông số ConnectionConfig / UpdatePeriodic / Log.${plain}"
}

run_network_tune() {
    local tune_script="/usr/local/XrayR/scripts/tune-network.sh"
    if [[ -x "${tune_script}" ]]; then
        bash "${tune_script}"
        return $?
    fi
    local url="https://github.com/${REPO}/releases/latest/download/tune-network.sh"
    if curl -fsSL -o /tmp/tune-network.sh "${url}" 2>/dev/null; then
        chmod +x /tmp/tune-network.sh
        bash /tmp/tune-network.sh
        return $?
    fi
    echo -e "${yellow}Không tải được tune-network.sh, dùng BBR cơ bản...${plain}"
    cat >/etc/sysctl.d/99-xrayr-tune.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
    sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-xrayr-tune.conf 2>/dev/null || true
}

optimize_all() {
    echo -e "${green}=== Tối ưu XrayR ===${plain}"
    run_network_tune
    patch_config_performance

    if [[ -f /etc/systemd/system/XrayR.service ]]; then
        if ! grep -q 'LimitNOFILE=1048576' /etc/systemd/system/XrayR.service 2>/dev/null; then
            sed -i 's/^LimitNOFILE=.*/LimitNOFILE=1048576/' /etc/systemd/system/XrayR.service 2>/dev/null || true
            sed -i 's/^RestartSec=.*/RestartSec=5/' /etc/systemd/system/XrayR.service 2>/dev/null || true
            systemctl daemon-reload
        fi
    fi

    if check_status 2>/dev/null; then
        systemctl restart XrayR
        sleep 2
        echo -e "${green}Đã khởi động lại XrayR với cấu hình tối ưu.${plain}"
    else
        echo -e "${yellow}XrayR chưa chạy — config/sysctl đã lưu, chạy: XrayR start${plain}"
    fi

    echo -e "${green}Hoàn tất. Gợi ý: giữ Log Level = warning, tránh debug trên production.${plain}"
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

show_usage() {
    echo "Cách dùng XrayR:"
    echo "------------------------------------------"
    echo "XrayR              - Menu quản lý"
    echo "XrayR start        - Khởi động"
    echo "XrayR stop         - Dừng"
    echo "XrayR restart      - Khởi động lại"
    echo "XrayR status       - Trạng thái"
    echo "XrayR enable       - Bật autostart"
    echo "XrayR disable      - Tắt autostart"
    echo "XrayR log          - Xem log"
    echo "XrayR generate     - Tạo config.yml"
    echo "XrayR update       - Cập nhật"
    echo "XrayR update x.x.x - Cài phiên bản chỉ định"
    echo "XrayR install      - Cài đặt"
    echo "XrayR uninstall    - Gỡ cài đặt"
    echo "XrayR version      - Phiên bản"
    echo "XrayR optimize     - Tối ưu mạng + config (BBR, buffer)"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}XrayR quản lý backend${plain} ${red}(không dùng cho Docker)${plain}
  --- https://github.com/${REPO} ---
  ${green}0.${plain}  Sửa cấu hình
————————————————
  ${green}1.${plain}  Cài đặt XrayR
  ${green}2.${plain}  Cập nhật XrayR
  ${green}3.${plain}  Gỡ XrayR
————————————————
  ${green}4.${plain}  Khởi động
  ${green}5.${plain}  Dừng
  ${green}6.${plain}  Khởi động lại
  ${green}7.${plain}  Trạng thái
  ${green}8.${plain}  Log
————————————————
  ${green}9.${plain}  Bật autostart
  ${green}10.${plain} Tắt autostart
————————————————
  ${green}11.${plain} Cài BBR
  ${green}12.${plain} Xem phiên bản
  ${green}13.${plain} Nâng cấp script quản lý
  ${green}14.${plain} Tạo file cấu hình
  ${green}15.${plain} Mở toàn bộ cổng firewall
  ${green}16.${plain} Tối ưu hiệu năng (BBR + buffer)
 "
    show_status
    echo && read -rp "Chọn [0-16]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_XrayR_version ;;
        13) update_shell ;;
        14) generate_config_file ;;
        15) open_ports ;;
        16) optimize_all ;;
        *) echo -e "${red}Nhập số trong khoảng 0-16${plain}" ;;
    esac
}

if [[ $# -gt 0 ]]; then
    case $1 in
        start) check_install 0 && start 0 ;;
        stop) check_install 0 && stop 0 ;;
        restart) check_install 0 && restart 0 ;;
        status) check_install 0 && status 0 ;;
        enable) check_install 0 && enable 0 ;;
        disable) check_install 0 && disable 0 ;;
        log) check_install 0 && show_log 0 ;;
        update) check_install 0 && update 0 "$2" ;;
        config) config ;;
        generate) generate_config_file ;;
        install) check_uninstall 0 && install 0 ;;
        uninstall) check_install 0 && uninstall 0 ;;
        version) check_install 0 && show_XrayR_version 0 ;;
        optimize) optimize_all 0 ;;
        update_shell) update_shell ;;
        *) show_usage ;;
    esac
else
    show_menu
fi
