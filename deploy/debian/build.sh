#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 deploy/debian/test_install.py
python3 deploy/debian/test_oneclick.py
python3 deploy/debian/test_upgrade.py
bash -n deploy/debian/install.sh deploy/debian/network.sh deploy/debian/oneclick.sh
export GOFLAGS=-mod=readonly
: "${GOMAXPROCS:=4}"
export GOMAXPROCS
go mod download
go mod verify
go test -p "$GOMAXPROCS" -race -count=1 -timeout=120s ./common/limiter
go test -p "$GOMAXPROCS" -count=1 -timeout=120s ./common/mylego -run '^(Test_merge|Test_needRenewal)$'
go test -p "$GOMAXPROCS" -count=1 -timeout=120s ./service/controller -run '^(TestBuildV2ray|TestBuildTrojan|TestBuildSS)$'
mkdir -p dist/linux-amd64
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -p "$GOMAXPROCS" -trimpath -ldflags='-s -w' -o dist/linux-amd64/XrayR .
cp deploy/debian/{install.sh,network.sh,xrayr.service,README.vi.md} dist/linux-amd64/
mkdir -p dist/linux-amd64/assets
cp release/config/* dist/linux-amd64/assets/
(cd dist/linux-amd64 && sha256sum XrayR > XrayR.sha256)
tar -czf dist/XrayR-debian-linux-amd64.tar.gz -C dist/linux-amd64 .
(cd dist && sha256sum XrayR-debian-linux-amd64.tar.gz > XrayR-debian-linux-amd64.tar.gz.sha256)
