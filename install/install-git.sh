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
. "$HERE/_path-setup.sh"   # ensure_user_path
. "$HERE/_verify.sh"       # verify_bin, verify_git_transport

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

# Симлинков мало: если $BIN не стоит в PATH раньше /usr/bin, `git` останется
# системным и lazygit так же откажется стартовать. В user-режиме правим PATH
# сами; в system-режиме /usr/local/bin уже раньше /usr/bin в /etc/profile
# (и install-system.sh кладёт /etc/profile.d/astra-dev.sh на случай, когда нет).
if [ "$MODE" != system ]; then
    say "PATH → ~/.bashrc, ~/.profile"
    ensure_user_path
fi

say "Проверка"
"$PREFIX/git/bin/git" --version
"$PREFIX/git/bin/git" --exec-path
verify_bin git "$PREFIX/git/bin/git" || true
verify_git_transport "$PREFIX/git" || true

cat <<EOF

Готово. Системный /usr/bin/git не тронут — наш просто стоит раньше в PATH.
В ТЕКУЩЕМ терминале PATH ещё старый; проверь в новом (или \`exec bash -l\`):
  command -v git && git --version      # → $BIN/git, $("$PREFIX/git/bin/git" --version | awk '{print $3}')

Откат: rm -rf $PREFIX/git && rm -f $BIN/git $BIN/git-* $BIN/scalar
EOF
