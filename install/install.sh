#!/usr/bin/env bash
# Ставит комплект в $HOME на Astra (офлайн, glibc 2.28).
# Использование (на Astra):  bash install/install.sh [путь-к-dist]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST="${1:-$ROOT/dist}"
say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$DIST/nvim.tar.gz" ] || { echo "Нет собранного dist/ (ожидался $DIST). Сначала ./build/build-all.sh на хосте."; exit 1; }

mkdir -p ~/.local ~/.local/bin ~/.local/share ~/.config ~/.local/share/fonts ~/.cargo

say "Neovim → ~/.local/nvim"
rm -rf ~/.local/nvim
tar xzf "$DIST/nvim.tar.gz" -C ~/.local
ln -sf ~/.local/nvim/bin/nvim ~/.local/bin/nvim

say "LazyVim: конфиг + плагины (перезапись)"
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
tar xzf "$DIST/lazyvim-config.tar.gz" -C ~/.config
tar xzf "$DIST/lazyvim-data.tar.gz"   -C ~/.local/share

say "rust-analyzer → ~/.local/bin"
install -m755 "$DIST/bin/rust-analyzer" ~/.local/bin/rust-analyzer

say "Nerd Font → ~/.local/share/fonts"
tar xzf "$DIST/fonts.tar.gz" -C ~/.local/share/fonts
fc-cache -f ~/.local/share/fonts >/dev/null 2>&1 || true

say "cargo офлайн-реестр → ~/.cargo/config.toml"
cp "$ROOT/cargo/config.toml" ~/.cargo/config.toml

say "PATH → ~/.bashrc"
grep -q '.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

cat <<'EOF'

==> Пользовательская часть установлена. Осталось руками:
  1) C++ LSP (нужен sudo):
       sudo apt install -y clangd-19 && sudo ln -sf "$(command -v clangd-19)" /usr/local/bin/clangd
  2) Шрифт терминала: выбрать "JetBrainsMono Nerd Font Mono"
     (иначе иконки LazyVim показываются как "?").
  3) Открыть НОВЫЙ терминал (обновится PATH) и запустить:  nvim

Проверка:
  ~/.local/bin/nvim --version
  ~/.local/bin/rust-analyzer --version
EOF
