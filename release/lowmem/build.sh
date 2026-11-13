#!/usr/bin/env bash
# Build on a development machine, then copy the artifact to the VPS.
set -euo pipefail

mode=${1:-full}
arch=${2:-amd64}
case "$mode" in
  full) tags=() ;;
  lowmem) tags=(-tags lowmem) ;;
  *) echo "Usage: $0 [full|lowmem] [amd64|arm64]" >&2; exit 2 ;;
esac
case "$arch" in
  amd64|arm64) ;;
  *) echo "Supported target architectures: amd64, arm64" >&2; exit 2 ;;
esac

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
output_dir=${XRAYR_OUTPUT_DIR:-/tmp/xrayr-dist}
mkdir -p -- "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd)
artifact="XrayR-linux-${arch}-${mode}"
cd -- "$repo_dir"
go version
CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build \
  -mod=readonly -p "${XRAYR_BUILD_JOBS:-2}" "${tags[@]}" \
  -trimpath -ldflags='-s -w' -o "$output_dir/$artifact" .
cd -- "$output_dir"
sha256sum "$artifact" > "$artifact.sha256"
printf 'Built: %s/%s\nChecksum: %s/%s.sha256\n' "$output_dir" "$artifact" "$output_dir" "$artifact"
