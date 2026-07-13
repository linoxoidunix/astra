#!/usr/bin/env bash
# build-vendor.sh — собирает офлайн-набор внешних крейтов (которых НЕТ в
# librust-*-dev Astra) в dist/cargo-vendor.tar.gz. На машине с интернетом.
#
#   ./build/build-vendor.sh                         # набор по умолчанию: tokio/full
#   ./build/build-vendor.sh tokio/full serde/derive reqwest
#
# Аргумент: <crate> либо <crate>/<feature,feature>.
# Версии подбираются под MSRV целевой Astra: RUST_VERSION (по умолчанию 1.70) —
# резолвер не возьмёт крейт, требующий более новый rustc.
#
# Результат кладётся рядом с прочими артефактами в dist/ и выкладывается в
# GitHub Release (см. README). На Astra разворачивается install/build-registry.sh.
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

echo "==> Упаковка dist/cargo-vendor.tar.gz"
tar czf "$DIST/cargo-vendor.tar.gz" -C "$WORK" vendor Cargo.toml Cargo.lock
ls -lh "$DIST/cargo-vendor.tar.gz"
echo "крейтов в наборе: $(find "$WORK/vendor" -maxdepth 1 -mindepth 1 | wc -l)"
