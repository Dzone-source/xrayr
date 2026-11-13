#!/usr/bin/env bash
# Build on a development machine, then copy the artifact to the VPS.
set -euo pipefail

arch=${1:-amd64}
case "$arch" in
  amd64|arm64) ;;
  *) echo "Supported target architectures: amd64, arm64" >&2; exit 2 ;;
esac

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
output_dir=${XRAYR_OUTPUT_DIR:-/tmp/xrayr-dist}
mkdir -p -- "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd)
artifact="XrayR-linux-${arch}"
cd -- "$repo_dir"
go version
CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build \
  -mod=readonly -p "${XRAYR_BUILD_JOBS:-2}" \
  -trimpath -ldflags='-s -w' -o "$output_dir/$artifact" .
cd -- "$output_dir"
sha256sum "$artifact" > "$artifact.sha256"
tar -czf "$artifact.tar.gz" "$artifact"
sha256sum "$artifact.tar.gz" > "$artifact.tar.gz.sha256"
printf 'Built: %s/%s\nChecksum: %s/%s.sha256\n' "$output_dir" "$artifact" "$output_dir" "$artifact"
