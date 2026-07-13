#!/usr/bin/env bash
# build-vendor.sh — вендорит внешние крейты (которых НЕТ в librust-*-dev Astra)
# и раскладывает их РАЗДЕЛЬНО:
#   - исходники        → cargo/vendor/            (коммитятся в git)
#   - бинарные windows-* → dist/cargo-vendor-win.tar.gz (в GitHub Release)
# cargo требует windows-крейты в vendor даже на Linux (cfg-зависимости), но они
# бинарные (import-либы .a/.lib) — в git им не место, поэтому едут в Release.
# На Astra обе части сливаются install/build-registry.sh в объединённый реестр.
#
#   ./build/build-vendor.sh                       # набор по умолчанию: tokio/full
#   ./build/build-vendor.sh tokio/full serde/derive
#
# Версии подбираются под MSRV Astra: RUST_VERSION (по умолчанию 1.70).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="$ROOT/dist"; mkdir -p "$DIST"
RUST_VERSION="${RUST_VERSION:-1.70}"

command -v cargo >/dev/null || { echo "Нужен cargo (rustup) на этой машине с интернетом."; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"; printf 'fn main() {}\n' > "$WORK/src/main.rs"

CRATES=("$@"); [ "${#CRATES[@]}" -eq 0 ] && CRATES=("tokio/full")

{
  echo '[package]'
  echo 'name = "vendor-set"'
  echo 'version = "0.0.0"'
  echo 'edition = "2021"'
  echo "rust-version = \"$RUST_VERSION\""
  echo 'resolver = "3"'
  echo
  echo '[dependencies]'
  for c in "${CRATES[@]}"; do
    name="${c%%/*}"
    if [ "$name" = "$c" ]; then
      echo "$name = \"*\""
    else
      feats="${c#*/}"; arr=""
      for f in ${feats//,/ }; do arr="$arr\"$f\","; done
      echo "$name = { version = \"*\", features = [${arr%,}] }"
    fi
  done
} > "$WORK/Cargo.toml"

echo "==> Набор крейтов (Cargo.toml):"; cat "$WORK/Cargo.toml"
echo "==> Подбор версий под rustc $RUST_VERSION и загрузка исходников"
( cd "$WORK"
  cargo generate-lockfile
  cargo vendor vendor >/dev/null )

echo "==> Раскладка: исходники → cargo/vendor/, windows-* → dist/cargo-vendor-win.tar.gz"
rm -rf "$ROOT/cargo/vendor"; mkdir -p "$ROOT/cargo/vendor"
WINSTAGE="$WORK/win/vendor"; mkdir -p "$WINSTAGE"
for d in "$WORK/vendor"/*/; do
  n="$(basename "$d")"
  case "$n" in
    windows*|winapi*) mv "$d" "$WINSTAGE/$n" ;;
    *)                mv "$d" "$ROOT/cargo/vendor/$n" ;;
  esac
done
cp "$WORK/Cargo.lock" "$ROOT/cargo/vendor.lock"
tar czf "$DIST/cargo-vendor-win.tar.gz" -C "$WORK/win" vendor

echo
echo "Исходники (в git):   cargo/vendor/  — $(find "$ROOT/cargo/vendor" -maxdepth 1 -mindepth 1|wc -l) крейтов, $(du -sh "$ROOT/cargo/vendor"|cut -f1)"
echo "Windows (в Release): dist/cargo-vendor-win.tar.gz — $(du -h "$DIST/cargo-vendor-win.tar.gz"|cut -f1)"
echo
echo "Дальше: закоммить cargo/vendor + cargo/vendor.lock; залей dist/cargo-vendor-win.tar.gz в Release."
