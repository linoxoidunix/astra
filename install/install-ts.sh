#!/usr/bin/env bash
# install-ts.sh — ИНКРЕМЕНТАЛЬНАЯ доустановка Node.js + vtsls (TS/JS LSP)
# ПОВЕРХ уже установленного комплекта. Ничего не сносит из nvim/LazyVim —
# ставит только Node и vtsls в PATH.
#
#   bash install/install-ts.sh            # для текущего пользователя (~/.local)
#   sudo bash install/install-ts.sh system  # для всех (/opt/astra-dev + /usr/local)
#
# Нужны ассеты node.tar.gz и ts-lsp.tar.gz в dist/ (скачай из Release).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="${DIST:-$ROOT/dist}"
MODE="${1:-user}"
say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$DIST/node.tar.gz" ]   || { echo "Нет $DIST/node.tar.gz — скачай ассет из Release в dist/."; exit 1; }
[ -f "$DIST/ts-lsp.tar.gz" ] || { echo "Нет $DIST/ts-lsp.tar.gz — скачай ассет из Release в dist/."; exit 1; }

if [ "$MODE" = system ]; then
    [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" system
    PREFIX=/opt/astra-dev; BIN=/usr/local/bin; mkdir -p "$PREFIX" "$BIN"
    say "Node.js → $PREFIX/node"
    rm -rf "$PREFIX/node"; tar xzf "$DIST/node.tar.gz" -C "$PREFIX"
    ln -sf "$PREFIX/node/bin/node" "$BIN/node"; ln -sf "$PREFIX/node/bin/npm" "$BIN/npm"
    say "vtsls → $PREFIX/ts-lsp"
    rm -rf "$PREFIX/ts-lsp"; tar xzf "$DIST/ts-lsp.tar.gz" -C "$PREFIX"
    ln -sf "$PREFIX/ts-lsp/bin/vtsls" "$BIN/vtsls"
else
    mkdir -p ~/.local ~/.local/bin
    say "Node.js → ~/.local/node"
    rm -rf ~/.local/node; tar xzf "$DIST/node.tar.gz" -C ~/.local
    ln -sf ~/.local/node/bin/node ~/.local/bin/node; ln -sf ~/.local/node/bin/npm ~/.local/bin/npm
    say "vtsls → ~/.local/ts-lsp"
    rm -rf ~/.local/ts-lsp; tar xzf "$DIST/ts-lsp.tar.gz" -C ~/.local
    ln -sf ~/.local/ts-lsp/bin/vtsls ~/.local/bin/vtsls
fi

say "Проверка"
node --version 2>/dev/null || echo "node не в PATH (открой новый терминал)"
vtsls --version 2>/dev/null || echo "vtsls не в PATH (открой новый терминал)"

cat <<'EOF'

Node + vtsls доустановлены (бинари). Чтобы TS/JS ЗАРАБОТАЛ В NVIM, нужны ещё
две вещи, которые связаны с LazyVim и НЕ ставятся этим скриптом:
  - typescript-extra в конфиге LazyVim (+ плагин nvim-vtsls в данных);
  - treesitter-парсеры js/ts/tsx.
Их даёт ПЕРЕСБОРКА бандла (build/build-all.sh) с обновлёнными
lazyvim-config.tar.gz / lazyvim-data.tar.gz / parsers.tar.gz — офлайн доклонировать
плагины и скомпилировать парсеры на самой Astra нельзя.
EOF
