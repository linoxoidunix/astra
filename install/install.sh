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

for tool in rg fd; do   # ripgrep (<leader>sg/sG греп) и fd (<leader>ff поиск файлов)
    [ -f "$DIST/bin/$tool" ] && { install -m755 "$DIST/bin/$tool" ~/.local/bin/$tool; say "$tool → ~/.local/bin"; }
done

if [ -f "$DIST/node.tar.gz" ]; then
    say "Node.js → ~/.local/node (для TS/JS LSP)"
    rm -rf ~/.local/node
    tar xzf "$DIST/node.tar.gz" -C ~/.local
    ln -sf ~/.local/node/bin/node ~/.local/bin/node
    ln -sf ~/.local/node/bin/npm  ~/.local/bin/npm
fi
if [ -f "$DIST/ts-lsp.tar.gz" ]; then
    say "TS/JS LSP (vtsls) → ~/.local/ts-lsp"
    rm -rf ~/.local/ts-lsp
    tar xzf "$DIST/ts-lsp.tar.gz" -C ~/.local
    ln -sf ~/.local/ts-lsp/bin/vtsls ~/.local/bin/vtsls
fi

if [ -f "$DIST/parsers.tar.gz" ]; then
    say "treesitter-парсеры → ~/.config/nvim/parser"
    mkdir -p ~/.config/nvim/parser
    tar xzf "$DIST/parsers.tar.gz" -C ~/.config/nvim/parser
fi

say "Nerd Font → ~/.local/share/fonts"
tar xzf "$DIST/fonts.tar.gz" -C ~/.local/share/fonts
fc-cache -f ~/.local/share/fonts >/dev/null 2>&1 || true

say "cargo офлайн-реестр → ~/.cargo/config.toml"
cp "$ROOT/cargo/config.toml" ~/.cargo/config.toml

say "PATH → ~/.bashrc"
grep -q '.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

cat <<'EOF'

==> Пользовательская часть установлена. Осталось руками:
  1) C++ LSP (нужен sudo). Версия clangd в репозитории зависит от машины —
     сперва найди доступную:  apt-cache search clangd
       sudo apt install -y clangd-15    # подставь найденную версию
       sudo ln -sf "$(command -v clangd-15 || command -v clangd)" /usr/local/bin/clangd
  2) Шрифт терминала: выбрать "JetBrainsMono Nerd Font Mono"
     (иначе иконки LazyVim показываются как "?").
  3) Открыть НОВЫЙ терминал (обновится PATH) и запустить:  nvim

Проверка:
  ~/.local/bin/nvim --version
  ~/.local/bin/rust-analyzer --version
EOF
