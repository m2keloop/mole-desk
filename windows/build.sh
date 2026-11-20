#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p dist
for arch in amd64 arm64; do
  CGO_ENABLED=0 GOOS=windows GOARCH="$arch" go build -trimpath -buildvcs=false -ldflags '-s -w -H=windowsgui' -o "dist/MoleDesk-windows-$arch.exe" ./cmd/mandesk
done
