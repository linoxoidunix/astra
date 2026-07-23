#!/usr/bin/env bash
# install-tools.sh — ИНКРЕМЕНТАЛЬНАЯ доустановка ripgrep + fd ПОВЕРХ уже
# установленного комплекта. Ничего не сносит: кладёт два бинарника в PATH.
#
#   bash install/install-tools.sh              # для текущего пользователя (~/.local/bin)
#   sudo bash install/install-tools.sh system  # для всех (/usr/local/bin)
#
# Зачем: snacks-пикер LazyVim запускает rg внешним процессом для грепа
# (<leader>sg/sG) и fd для поиска файлов (<leader>ff). Без rg греп падает
# с "Failed to spawn rg"; без fd файловый пикер молча работает медленнее.
#
# Нужны бинарники в dist/bin/ — их кладёт build/build-all.sh (static-musl,
# от glibc не зависят). Если dist собран до появления этого шага — скачай
# на машине с интернетом:
#   curl -fsSL https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz | tar xz -O --wildcards '*/rg' > dist/bin/rg
#   curl -fsSL https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-unknown-linux-musl.tar.gz | tar xz -O --wildcards '*/fd' > dist/bin/fd
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="${DIST:-$ROOT/dist}"
MODE="${1:-user}"
say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

missing=""
for tool in rg fd; do
    [ -f "$DIST/bin/$tool" ] || missing="$missing $tool"
done
[ -z "$missing" ] || { echo "Нет в $DIST/bin:$missing — см. шапку скрипта, как их туда положить."; exit 1; }

if [ "$MODE" = system ]; then
    [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" system
    BIN=/usr/local/bin; mkdir -p "$BIN"
else
    BIN="$HOME/.local/bin"; mkdir -p "$BIN"
fi

for tool in rg fd; do
    say "$tool → $BIN"
    install -m755 "$DIST/bin/$tool" "$BIN/$tool"
done

say "Проверка"
"$BIN/rg" --version | head -1
"$BIN/fd" --version

cat <<EOF

Готово. Если rg/fd не видны без полного пути — открой новый терминал
(PATH подхватит $BIN) и проверь: command -v rg
EOF
