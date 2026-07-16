#!/usr/bin/env bash
#
# XrayR one-click installer
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/Dzone-source/xrayr/main/install.sh)
#   bash <(curl -Ls https://raw.githubusercontent.com/Dzone-source/xrayr/main/install.sh) v0.9.5
#

set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO="Dzone-source/xrayr"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
GITHUB_BASE="https://github.com/${REPO}"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
GO_MIN_VERSION="1.24"
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
        yum install wget curl unzip tar git ca-certificates socat cronie -y
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y wget curl unzip tar git ca-certificates socat cron
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

version_ge() {
    # return 0 if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

ensure_go() {
    if command -v go >/dev/null 2>&1; then
        local current
        current=$(go version | awk '{print $3}' | sed 's/go//')
        if version_ge "${current}" "${GO_MIN_VERSION}"; then
            echo -e "Go đã có sẵn: ${green}${current}${plain}"
            return 0
        fi
        echo -e "${yellow}Go ${current} quá cũ, cần >= ${GO_MIN_VERSION}${plain}"
    fi

    echo -e "${green}Cài đặt Go ${GO_MIN_VERSION}...${plain}"
    local go_tarball="go${GO_MIN_VERSION}.linux-${go_arch}.tar.gz"
    local go_url="https://go.dev/dl/${go_tarball}"
    wget -q -O "/tmp/${go_tarball}" "${go_url}" || {
        echo -e "${red}Không tải được Go từ ${go_url}${plain}"
        exit 1
    }
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/${go_tarball}"
    rm -f "/tmp/${go_tarball}"
    export PATH="/usr/local/go/bin:${PATH}"
    echo -e "Go đã cài: ${green}$(go version)${plain}"
}

get_latest_version() {
    curl -Ls "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | head -n 1
}

download_release() {
    local version=$1
    local zip_name="XrayR-linux-${arch}.zip"
    local url="${GITHUB_BASE}/releases/download/${version}/${zip_name}"

    echo -e "Tải release ${green}${version}${plain}: ${url}"
    if ! wget -q -N --no-check-certificate -O "${INSTALL_DIR}/XrayR-linux.zip" "${url}"; then
        return 1
    fi
    if [[ ! -s "${INSTALL_DIR}/XrayR-linux.zip" ]]; then
        return 1
    fi
    # GitHub returns JSON error body when asset is missing
    if head -c 1 "${INSTALL_DIR}/XrayR-linux.zip" | grep -q '{'; then
        return 1
    fi
    return 0
}

build_from_source() {
    local ref=${1:-main}
    echo -e "${yellow}Không có binary release phù hợp, biên dịch từ source (${ref})...${plain}"
    ensure_go

    TMP_DIR=$(mktemp -d)
    echo -e "Clone ${GITHUB_BASE}.git ..."
    if [[ "${ref}" == "main" || "${ref}" == "master" ]]; then
        git clone --depth 1 --branch main "${GITHUB_BASE}.git" "${TMP_DIR}/src" \
            || git clone --depth 1 "${GITHUB_BASE}.git" "${TMP_DIR}/src"
    else
        if ! git clone --depth 1 --branch "${ref}" "${GITHUB_BASE}.git" "${TMP_DIR}/src"; then
            git clone "${GITHUB_BASE}.git" "${TMP_DIR}/src"
            git -C "${TMP_DIR}/src" checkout "${ref}"
        fi
    fi

    (
        cd "${TMP_DIR}/src"
        export CGO_ENABLED=0
        export GOOS=linux
        export GOARCH="${go_arch}"
        go mod download
        go build -v -o "${INSTALL_DIR}/XrayR" -trimpath -ldflags "-s -w -buildid="
    )

    cp -f "${TMP_DIR}/src/release/config/"* "${INSTALL_DIR}/" 2>/dev/null || true
    if [[ -f "${INSTALL_DIR}/config.yml.example" && ! -f "${INSTALL_DIR}/config.yml" ]]; then
        cp -f "${INSTALL_DIR}/config.yml.example" "${INSTALL_DIR}/config.yml"
    fi

    # Ensure geoip/geosite exist
    if [[ ! -f "${INSTALL_DIR}/geoip.dat" || ! -f "${INSTALL_DIR}/geosite.dat" ]]; then
        echo -e "${green}Tải geoip.dat / geosite.dat...${plain}"
        for i in geoip geosite; do
            curl -L "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/${i}.dat" \
                -o "${INSTALL_DIR}/${i}.dat"
        done
    fi
}

install_service_and_tools() {
    mkdir -p "${CONFIG_DIR}"
    rm -f /etc/systemd/system/XrayR.service
    wget -q -N --no-check-certificate -O /etc/systemd/system/XrayR.service \
        "${RAW_BASE}/XrayR.service" || {
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
LimitNOFILE=999999
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR -config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    }

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
        else
            wget -q -N --no-check-certificate -O "${CONFIG_DIR}/config.yml" \
                "${RAW_BASE}/release/config/config.yml.example"
        fi
        echo -e ""
        echo -e "${yellow}Cài đặt mới: hãy sửa ${CONFIG_DIR}/config.yml trước khi khởi động.${plain}"
        echo -e "Tài liệu: ${GITHUB_BASE}"
    else
        systemctl start XrayR
        sleep 2
        if check_status; then
            echo -e "${green}XrayR khởi động lại thành công${plain}"
        else
            echo -e "${red}XrayR có thể chưa chạy được. Kiểm tra: XrayR log${plain}"
        fi
    fi

    for f in dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
            if [[ -f "${INSTALL_DIR}/${f}" ]]; then
                cp -f "${INSTALL_DIR}/${f}" "${CONFIG_DIR}/"
            else
                wget -q -N --no-check-certificate -O "${CONFIG_DIR}/${f}" \
                    "${RAW_BASE}/release/config/${f}" 2>/dev/null || true
            fi
        fi
    done

    curl -fsSL -o /usr/bin/XrayR "${RAW_BASE}/XrayR.sh"
    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
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
        if [[ -n "${version}" ]]; then
            echo -e "Phát hiện bản mới nhất: ${green}${version}${plain}"
            if download_release "${version}"; then
                used_release=1
            else
                echo -e "${yellow}Tải release thất bại, chuyển sang biên dịch từ source.${plain}"
            fi
        else
            echo -e "${yellow}Chưa có GitHub Release, sẽ biên dịch từ source.${plain}"
        fi
    else
        if [[ $1 == v* ]]; then
            version=$1
        else
            version="v$1"
        fi
        echo -e "Cài đặt phiên bản chỉ định: ${green}${version}${plain}"
        if download_release "${version}"; then
            used_release=1
        else
            echo -e "${yellow}Không tải được ${version}, thử biên dịch từ tag/branch đó.${plain}"
        fi
    fi

    if [[ ${used_release} -eq 1 ]]; then
        unzip -o XrayR-linux.zip
        rm -f XrayR-linux.zip
        if [[ ! -f "${INSTALL_DIR}/config.yml" && -f "${INSTALL_DIR}/config.yml.example" ]]; then
            cp -f "${INSTALL_DIR}/config.yml.example" "${INSTALL_DIR}/config.yml"
        fi
    else
        if [[ $# -eq 0 ]]; then
            build_from_source "main"
            version="source-main"
        else
            build_from_source "${version}"
        fi
    fi

    chmod +x "${INSTALL_DIR}/XrayR"
    echo -e "${green}XrayR ${version}${plain} đã cài vào ${INSTALL_DIR}"
    install_service_and_tools
    cd "${cur_dir}"
    show_usage
}

detect_os
detect_arch
check_os_version

echo -e "${green}Bắt đầu cài đặt XrayR...${plain}"
install_base
install_XrayR "$@"
