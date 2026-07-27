#!/usr/bin/env bash
# install-git.sh — ИНКРЕМЕНТАЛЬНАЯ доустановка своего git ПОВЕРХ уже
# установленного комплекта. Ничего не сносит и системный git не трогает.
#
#   bash install/install-git.sh              # для текущего пользователя (~/.local)
#   sudo bash install/install-git.sh system  # для всех (/opt/astra-dev + /usr/local/bin)
#
# Зачем: в Astra 1.7 git из репозитория buster-овский (~2.20), а lazygit
# (<leader>gg) с версии 0.4x требует >= 2.32 и отказывается стартовать:
#   "Git version must be at least 2.32.0. Please upgrade your git version."
#
# Что делает: раскладывает дерево из dist/git.tar.gz и ставит симлинки в PATH
# ПЕРЕД системным git. /usr/bin/git остаётся на месте, dpkg-состояние не
# меняется — откат сводится к удалению каталога и симлинков.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="${DIST:-$ROOT/dist}"
MODE="${1:-user}"
say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$DIST/git.tar.gz" ] || {
    echo "Нет $DIST/git.tar.gz — собери ./build/build-all.sh или скачай ассет из Release."; exit 1; }

if [ "$MODE" = system ]; then
    [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" system
    PREFIX=/opt/astra-dev; BIN=/usr/local/bin
else
    PREFIX="$HOME/.local"; BIN="$HOME/.local/bin"
fi
mkdir -p "$PREFIX" "$BIN"

say "git → $PREFIX/git"
rm -rf "$PREFIX/git"
tar xzf "$DIST/git.tar.gz" -C "$PREFIX"

# Симлинки на всё из bin/: git плюс серверные команды (upload-pack и пр. — их
# зовёт удалённая сторона по ssh) и scalar. Остальные ~200 подкоманд git ищет
# сам в libexec рядом с бинарём (собран с RUNTIME_PREFIX).
for exe in "$PREFIX"/git/bin/*; do
    [ -x "$exe" ] || continue
    ln -sf "$exe" "$BIN/${exe##*/}"
done

# Системный конфиг. С RUNTIME_PREFIX git читает <префикс>/etc/gitconfig, а не
# /etc/gitconfig — без этой ссылки общесистемные настройки Astra (прокси,
# safe.directory и пр.) молча перестали бы действовать.
if [ -f /etc/gitconfig ]; then
    mkdir -p "$PREFIX/git/etc"
    ln -sf /etc/gitconfig "$PREFIX/git/etc/gitconfig"
    say "системный /etc/gitconfig подключён"
fi

say "Проверка"
"$BIN/git" --version
"$BIN/git" --exec-path

cat <<EOF

Готово. Системный $(command -v git 2>/dev/null || echo /usr/bin/git) не тронут —
наш стоит раньше в PATH. Проверь в НОВОМ терминале:
  command -v git && git --version      # → $BIN/git, $("$BIN/git" --version | awk '{print $3}')

Откат: rm -rf $PREFIX/git && rm -f $BIN/git $BIN/git-* $BIN/scalar
EOF
