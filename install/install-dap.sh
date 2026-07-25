#!/usr/bin/env bash
# install-dap.sh — ИНКРЕМЕНТАЛЬНАЯ доустановка codelldb (отладчик C/C++/Rust)
# ПОВЕРХ уже установленного комплекта. Ничего не сносит: кладёт дерево codelldb
# и симлинк на адаптер в PATH.
#
#   bash install/install-dap.sh              # для текущего пользователя (~/.local)
#   sudo bash install/install-dap.sh system  # для всех (/opt/astra-dev + /usr/local/bin)
#
# Нужен ассет codelldb.tar.gz в dist/ — его кладёт build/build-all.sh. Если dist
# собран до появления этого шага, на машине с интернетом:
#   curl -fsSL -o /tmp/codelldb.vsix https://github.com/vadimcn/codelldb/releases/download/v1.12.2/codelldb-linux-x64.vsix
#   rm -rf /tmp/cl && unzip -q /tmp/codelldb.vsix -d /tmp/cl
#   mkdir -p /tmp/codelldb && cp -a /tmp/cl/extension/adapter /tmp/cl/extension/lldb /tmp/codelldb/
#   chmod a+x /tmp/codelldb/adapter/codelldb /tmp/codelldb/lldb/bin/* && find /tmp/codelldb -name '*.so' -exec chmod a+x {} +
#   tar czf dist/codelldb.tar.gz -C /tmp codelldb
#
# ВАЖНО: сам бинарь — это только половина дела. Плагины nvim-dap/dap-ui и спек
# astra-dap.lua приезжают ПЕРЕСБОРКОЙ бандла (lazyvim-config/-data): офлайн
# доклонировать плагины на Astra нельзя.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="${DIST:-$ROOT/dist}"
MODE="${1:-user}"
say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$DIST/codelldb.tar.gz" ] || { echo "Нет $DIST/codelldb.tar.gz — см. шапку скрипта."; exit 1; }

if [ "$MODE" = system ]; then
    [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" system
    PREFIX=/opt/astra-dev; BIN=/usr/local/bin
else
    PREFIX="$HOME/.local"; BIN="$HOME/.local/bin"
fi
mkdir -p "$PREFIX" "$BIN"

say "codelldb → $PREFIX/codelldb"
rm -rf "$PREFIX/codelldb"
tar xzf "$DIST/codelldb.tar.gz" -C "$PREFIX"
ln -sf "$PREFIX/codelldb/adapter/codelldb" "$BIN/codelldb"

say "Проверка"
"$PREFIX/codelldb/lldb/bin/lldb" --version
"$BIN/codelldb" --help >/dev/null && echo "адаптер запускается"

cat <<EOF

Готово. Если codelldb не виден без полного пути — открой новый терминал
(PATH подхватит $BIN) и проверь: command -v codelldb

В nvim: <leader>db поставить точку останова, <leader>dc запустить,
<leader>du панель отладчика. Для Rust — <leader>dr (:RustLsp debuggables).
EOF
