#!/usr/bin/env bash
#
# XrayR one-click installer
# Usage (khuyến nghị, dùng Release):
#   bash <(curl -Ls https://github.com/Dzone-source/xrayr/releases/latest/download/install.sh)
#
# Hoặc từ nhánh main (sau khi merge):
#   bash <(curl -Ls https://raw.githubusercontent.com/Dzone-source/xrayr/main/install.sh)
#

set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO="Dzone-source/xrayr"
GITHUB_BASE="https://github.com/${REPO}"
RAW_MAIN="https://raw.githubusercontent.com/${REPO}/main"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
GO_VERSION="1.24.1"
TMP_DIR=""

cur_dir=$(pwd)

cleanup() {
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

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

detect_arch() {
    local machine
    machine=$(uname -m)
    case "${machine}" in
        x86_64|x64|amd64)
            arch="64"
            go_arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64-v8a"
            go_arch="arm64"
            ;;
        s390x)
            arch="s390x"
            go_arch="s390x"
            ;;
        *)
            arch="64"
            go_arch="amd64"
            echo -e "${yellow}Không nhận diện được kiến trúc (${machine}), dùng mặc định: ${arch}${plain}"
            ;;
    esac

    if [ "$(getconf LONG_BIT)" != '64' ]; then
        echo -e "${red}Chỉ hỗ trợ hệ thống 64-bit.${plain}"
        exit 2
    fi
    echo -e "Kiến trúc: ${green}${arch}${plain}"
}

check_os_version() {
    local os_version=""
    if [[ -f /etc/os-release ]]; then
        os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
    fi
    if [[ -z "${os_version}" && -f /etc/lsb-release ]]; then
        os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
    fi

    if [[ "${release}" == "centos" && -n "${os_version}" && ${os_version} -le 6 ]]; then
        echo -e "${red}Cần CentOS 7 trở lên.${plain}\n" && exit 1
    elif [[ "${release}" == "ubuntu" && -n "${os_version}" && ${os_version} -lt 16 ]]; then
        echo -e "${red}Cần Ubuntu 16 trở lên.${plain}\n" && exit 1
    elif [[ "${release}" == "debian" && -n "${os_version}" && ${os_version} -lt 8 ]]; then
        echo -e "${red}Cần Debian 8 trở lên.${plain}\n" && exit 1
    fi
}

install_base() {
    echo -e "${green}Cài đặt phụ thuộc cơ bản...${plain}"
    if [[ "${release}" == "centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar ca-certificates socat cronie -y
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y wget curl unzip tar ca-certificates socat cron
    fi
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

download_file() {
    local url=$1
    local dest=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 -o "${dest}" "${url}"
    else
        wget -q -N --no-check-certificate -O "${dest}" "${url}"
    fi
}

is_probably_zip() {
    local f=$1
    [[ -s "${f}" ]] || return 1
    # ZIP magic: PK
    local magic
    magic=$(head -c 2 "${f}" | tr -d '\0' || true)
    [[ "${magic}" == "PK" ]]
}

get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | head -n 1
}

download_release() {
    local version=$1
    local zip_name="XrayR-linux-${arch}.zip"
    local url="${GITHUB_BASE}/releases/download/${version}/${zip_name}"

    echo -e "Tải release ${green}${version}${plain}: ${url}"
    if ! download_file "${url}" "${INSTALL_DIR}/XrayR-linux.zip"; then
        return 1
    fi
    if ! is_probably_zip "${INSTALL_DIR}/XrayR-linux.zip"; then
        rm -f "${INSTALL_DIR}/XrayR-linux.zip"
        return 1
    fi
    return 0
}

install_service_unit() {
    if [[ -f "${INSTALL_DIR}/XrayR.service" ]]; then
        cp -f "${INSTALL_DIR}/XrayR.service" /etc/systemd/system/XrayR.service
        return 0
    fi

    local version=${1:-}
    if [[ -n "${version}" ]]; then
        if download_file "${GITHUB_BASE}/releases/download/${version}/XrayR.service" /etc/systemd/system/XrayR.service; then
            return 0
        fi
    fi

    if download_file "${RAW_MAIN}/XrayR.service" /etc/systemd/system/XrayR.service; then
        return 0
    fi

    cat >/etc/systemd/system/XrayR.service <<'EOF'
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=1048576
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

install_manage_script() {
    local version=${1:-}
    if [[ -f "${INSTALL_DIR}/XrayR.sh" ]]; then
        cp -f "${INSTALL_DIR}/XrayR.sh" /usr/bin/XrayR
        chmod +x /usr/bin/XrayR
        ln -sf /usr/bin/XrayR /usr/bin/xrayr
        return 0
    fi

    if [[ -n "${version}" ]]; then
        if download_file "${GITHUB_BASE}/releases/download/${version}/XrayR.sh" /usr/bin/XrayR; then
            chmod +x /usr/bin/XrayR
            ln -sf /usr/bin/XrayR /usr/bin/xrayr
            return 0
        fi
    fi

    if download_file "${RAW_MAIN}/XrayR.sh" /usr/bin/XrayR; then
        chmod +x /usr/bin/XrayR
        ln -sf /usr/bin/XrayR /usr/bin/xrayr
        return 0
    fi

    echo -e "${yellow}Không tải được script quản lý XrayR.sh (có thể cài binary vẫn OK).${plain}"
}

# Keep legacy /etc/XrayR/config.yml timeouts from killing upload speed tests.
# Binary update alone used to leave UplinkOnly: 2~5 in place.
patch_connection_config() {
    local f="${CONFIG_DIR}/config.yml"
    [[ -f "${f}" ]] || return 0
    if grep -qE '^[[:space:]]*UplinkOnly:[[:space:]]*([0-9]{1,2}|[12][0-9]{2})[[:space:]]*$' "${f}" \
        || grep -qE '^[[:space:]]*DownlinkOnly:[[:space:]]*([0-9]{1,2}|[12][0-9]{2})[[:space:]]*$' "${f}" \
        || grep -qE '^[[:space:]]*ConnIdle:[[:space:]]*([0-9]|[1-5][0-9])[[:space:]]*$' "${f}"; then
        cp -a "${f}" "${f}.bak.conn.$(date +%s)"
        sed -i \
            -e 's/^[[:space:]]*ConnIdle:.*/  ConnIdle: 600/' \
            -e 's/^[[:space:]]*UplinkOnly:.*/  UplinkOnly: 3600/' \
            -e 's/^[[:space:]]*DownlinkOnly:.*/  DownlinkOnly: 3600/' \
            -e 's/^[[:space:]]*BufferSize:.*/  BufferSize: 1024/' \
            "${f}"
        echo -e "${green}Đã nâng ConnectionConfig (UplinkOnly/DownlinkOnly/ConnIdle) trong ${f}${plain}"
    fi
}

install_service_and_tools() {
    local version=${1:-}
    mkdir -p "${CONFIG_DIR}"
    rm -f /etc/systemd/system/XrayR.service
    install_service_unit "${version}"

    systemctl daemon-reload
    systemctl stop XrayR 2>/dev/null || true
    systemctl enable XrayR

    for f in geoip.dat geosite.dat; do
        if [[ -f "${INSTALL_DIR}/${f}" ]]; then
            cp -f "${INSTALL_DIR}/${f}" "${CONFIG_DIR}/"
        fi
    done

    if [[ ! -f "${CONFIG_DIR}/config.yml" ]]; then
        if [[ -f "${INSTALL_DIR}/config.yml" ]]; then
            cp -f "${INSTALL_DIR}/config.yml" "${CONFIG_DIR}/config.yml"
        elif [[ -f "${INSTALL_DIR}/config.yml.example" ]]; then
            cp -f "${INSTALL_DIR}/config.yml.example" "${CONFIG_DIR}/config.yml"
        fi
        echo -e ""
        echo -e "${yellow}Cài đặt mới: hãy sửa ${CONFIG_DIR}/config.yml trước khi khởi động.${plain}"
        echo -e "Tài liệu: ${GITHUB_BASE}"
    else
        patch_connection_config
        systemctl start XrayR
        sleep 2
        if check_status; then
            echo -e "${green}XrayR khởi động lại thành công${plain}"
        else
            echo -e "${red}XrayR có thể chưa chạy được. Kiểm tra: XrayR log${plain}"
        fi
    fi

    for f in dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [[ ! -f "${CONFIG_DIR}/${f}" && -f "${INSTALL_DIR}/${f}" ]]; then
            cp -f "${INSTALL_DIR}/${f}" "${CONFIG_DIR}/"
        fi
    done

    install_manage_script "${version}"
}

show_usage() {
    echo -e ""
    echo "Cách dùng script quản lý XrayR (cũng dùng được: xrayr):"
    echo "------------------------------------------"
    echo "XrayR              - Hiện menu quản lý"
    echo "XrayR start        - Khởi động"
    echo "XrayR stop         - Dừng"
    echo "XrayR restart      - Khởi động lại"
    echo "XrayR status       - Xem trạng thái"
    echo "XrayR enable       - Bật khởi động cùng hệ thống"
    echo "XrayR disable      - Tắt khởi động cùng hệ thống"
    echo "XrayR log          - Xem log"
    echo "XrayR update       - Cập nhật XrayR"
    echo "XrayR update x.x.x - Cài phiên bản chỉ định"
    echo "XrayR uninstall    - Gỡ cài đặt"
    echo "XrayR version      - Xem phiên bản"
    echo "------------------------------------------"
    echo -e "File cấu hình: ${green}${CONFIG_DIR}/config.yml${plain}"
}

install_XrayR() {
    if [[ -e "${INSTALL_DIR}/" ]]; then
        rm -rf "${INSTALL_DIR}/"
    fi
    mkdir -p "${INSTALL_DIR}"
    cd "${INSTALL_DIR}"

    local version=""
    local used_release=0

    if [[ $# -eq 0 ]]; then
        version=$(get_latest_version || true)
        if [[ -z "${version}" ]]; then
            echo -e "${red}Không tìm thấy GitHub Release.${plain}"
            echo -e "Hãy tạo Release tại: ${GITHUB_BASE}/releases"
            echo -e "Hoặc cài phiên bản chỉ định: bash install.sh v0.9.5"
            exit 1
        fi
        echo -e "Phát hiện bản mới nhất: ${green}${version}${plain}"
    else
        if [[ $1 == v* ]]; then
            version=$1
        else
            version="v$1"
        fi
        echo -e "Cài đặt phiên bản chỉ định: ${green}${version}${plain}"
    fi

    if download_release "${version}"; then
        used_release=1
    else
        echo -e "${red}Tải binary release thất bại: XrayR-linux-${arch}.zip${plain}"
        echo -e "Kiểm tra Release có asset đúng kiến trúc tại: ${GITHUB_BASE}/releases/tag/${version}"
        exit 1
    fi

    unzip -o XrayR-linux.zip
    rm -f XrayR-linux.zip
    if [[ ! -f "${INSTALL_DIR}/config.yml" && -f "${INSTALL_DIR}/config.yml.example" ]]; then
        cp -f "${INSTALL_DIR}/config.yml.example" "${INSTALL_DIR}/config.yml"
    fi

    if [[ ! -f "${INSTALL_DIR}/XrayR" ]]; then
        echo -e "${red}ZIP release thiếu file binary XrayR.${plain}"
        exit 1
    fi

    chmod +x "${INSTALL_DIR}/XrayR"
    echo -e "${green}XrayR ${version}${plain} đã cài vào ${INSTALL_DIR}"
    install_service_and_tools "${version}"
    cd "${cur_dir}"
    show_usage
}

detect_os
detect_arch
check_os_version

echo -e "${green}Bắt đầu cài đặt XrayR...${plain}"
install_base
install_XrayR "$@"
