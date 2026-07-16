#!/usr/bin/env bash
# Build release ZIP packages for GitHub Releases.
# Usage: ./scripts/build-release.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-v0.9.5}"
OUT_DIR="${ROOT}/dist"
CGO_ENABLED=0

mkdir -p "${OUT_DIR}"
rm -rf "${OUT_DIR:?}/"*

build_one() {
    local goos=$1
    local goarch=$2
    local goarm=${3:-}
    local asset=$4

    local stage="${OUT_DIR}/stage-${asset}"
    rm -rf "${stage}"
    mkdir -p "${stage}"

    echo "==> Building ${asset} (GOOS=${goos} GOARCH=${goarch} GOARM=${goarm})"
    (
        cd "${ROOT}"
        export CGO_ENABLED=0
        export GOOS="${goos}"
        export GOARCH="${goarch}"
        if [[ -n "${goarm}" ]]; then
            export GOARM="${goarm}"
        else
            unset GOARM || true
        fi
        go build -o "${stage}/XrayR" -trimpath -ldflags "-s -w -buildid="
    )

    if [[ "${goos}" == "windows" ]]; then
        mv "${stage}/XrayR" "${stage}/XrayR.exe"
    fi

    cp "${ROOT}/README.md" "${stage}/README.md"
    cp "${ROOT}/LICENSE" "${stage}/LICENSE"
    cp "${ROOT}/XrayR.service" "${stage}/XrayR.service"
    cp "${ROOT}/XrayR.sh" "${stage}/XrayR.sh"
    cp "${ROOT}/release/config/dns.json" "${stage}/dns.json"
    cp "${ROOT}/release/config/route.json" "${stage}/route.json"
    cp "${ROOT}/release/config/custom_outbound.json" "${stage}/custom_outbound.json"
    cp "${ROOT}/release/config/custom_inbound.json" "${stage}/custom_inbound.json"
    cp "${ROOT}/release/config/rulelist" "${stage}/rulelist"
    cp "${ROOT}/release/config/config.yml.example" "${stage}/config.yml"

    if [[ -f "${ROOT}/release/config/geoip.dat" ]]; then
        cp "${ROOT}/release/config/geoip.dat" "${stage}/geoip.dat"
        cp "${ROOT}/release/config/geosite.dat" "${stage}/geosite.dat"
    else
        curl -fsSL "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat" -o "${stage}/geoip.dat"
        curl -fsSL "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat" -o "${stage}/geosite.dat"
    fi

    (
        cd "${stage}"
        zip -9qr "${OUT_DIR}/XrayR-${asset}.zip" .
    )
    rm -rf "${stage}"
    echo "    -> ${OUT_DIR}/XrayR-${asset}.zip"
}

# Primary install targets
build_one linux amd64 "" "linux-64"
build_one linux arm64 "" "linux-arm64-v8a"

# Copy installer assets for release upload
cp "${ROOT}/install.sh" "${OUT_DIR}/install.sh"
cp "${ROOT}/XrayR.sh" "${OUT_DIR}/XrayR.sh"
cp "${ROOT}/XrayR.service" "${OUT_DIR}/XrayR.service"

echo ""
echo "Built ${VERSION} artifacts in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"
