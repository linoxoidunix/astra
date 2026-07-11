#!/usr/bin/env bash
# Собирает весь комплект на ХОСТЕ (нужны podman или docker + интернет) → ../dist
# Использование:  ./build/build-all.sh
#   ENGINE=docker ./build/build-all.sh     # если вместо podman docker
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="$ROOT/dist"
ENGINE="${ENGINE:-podman}"
mkdir -p "$DIST"

# podman: --network=host нужен, чтобы из NAT-контейнера был виден прокси хоста;
# метки :z/:Z — для SELinux (Fedora). docker их игнорирует.
NET=""
[ "$ENGINE" = podman ] && NET="--network=host"

echo "==> Сборка через $ENGINE (Debian Buster, glibc 2.28). Это долго."
exec "$ENGINE" run --rm $NET \
    -v "$HERE/_in-container.sh":/build.sh:ro,z \
    -v "$DIST":/out:Z \
    -e NVIM_TAG="${NVIM_TAG:-v0.12.4}" \
    debian:buster-slim bash /build.sh
