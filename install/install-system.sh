f#!/usr/bin/env bash
# install-system.sh — системная (для ВСЕХ пользователей) установка комплекта
# на Astra (офлайн, glibc 2.28).
#
# Разделяемое ставится один раз в систему (read-only):
#   nvim, rust-analyzer  → /usr/local/bin
#   treesitter-парсеры   → в runtime самого nvim (виден всем)
#   Nerd Font            → /usr/share/fonts
#   PATH/окружение       → /etc/profile.d/astra-dev.sh
# Neovim-часть (config+плагины) и cargo-конфиг у каждого пользователя свои —
# засеваются в его $HOME при первом запуске (wrapper nvim + /etc/profile.d).
#
# Запуск на Astra (сам поднимет права):
#   bash install/install-system.sh [путь-к-dist]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DIST_ARG="${1:-}"

# --- повышение прав ---------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$DIST_ARG"
fi

DIST="${DIST_ARG:-$ROOT/dist}"
PREFIX=/opt/astra-dev          # разделяемые файлы (nvim, seed)
SKEL="$PREFIX/skel"            # заготовка домашки пользователя
say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -f "$DIST/nvim.tar.gz" ] || { echo "Нет собранного dist/ (ожидался $DIST). Сначала ./build/build-all.sh на хосте."; exit 1; }

mkdir -p "$PREFIX" "$SKEL/.config" "$SKEL/.local/share" "$SKEL/.cargo" /usr/local/bin

# --- Neovim → /opt/astra-dev/nvim ------------------------------------------
say "Neovim → $PREFIX/nvim"
rm -rf "$PREFIX/nvim"
tar xzf "$DIST/nvim.tar.gz" -C "$PREFIX"
NVIM_REAL="$PREFIX/nvim/bin/nvim"

# --- treesitter-парсеры → в системный runtime nvim (виден всем) -------------
if [ -f "$DIST/parsers.tar.gz" ]; then
    say "treesitter-парсеры → runtime nvim (общие для всех)"
    PARSER_DIR="$PREFIX/nvim/share/nvim/runtime/parser"
    mkdir -p "$PARSER_DIR"
    tar xzf "$DIST/parsers.tar.gz" -C "$PARSER_DIR"
fi

# --- rust-analyzer → /usr/local/bin ----------------------------------------
say "rust-analyzer → /usr/local/bin"
install -m755 "$DIST/bin/rust-analyzer" /usr/local/bin/rust-analyzer

# --- Node.js + TS/JS LSP (vtsls) → /opt/astra-dev + /usr/local/bin ----------
if [ -f "$DIST/node.tar.gz" ]; then
    say "Node.js → $PREFIX/node (для TS/JS LSP, общий для всех)"
    rm -rf "$PREFIX/node"
    tar xzf "$DIST/node.tar.gz" -C "$PREFIX"
    ln -sf "$PREFIX/node/bin/node" /usr/local/bin/node
    ln -sf "$PREFIX/node/bin/npm"  /usr/local/bin/npm
fi
if [ -f "$DIST/ts-lsp.tar.gz" ]; then
    say "TS/JS LSP (vtsls) → $PREFIX/ts-lsp"
    rm -rf "$PREFIX/ts-lsp"
    tar xzf "$DIST/ts-lsp.tar.gz" -C "$PREFIX"
    ln -sf "$PREFIX/ts-lsp/bin/vtsls" /usr/local/bin/vtsls
fi

# --- nvim: wrapper в /usr/local/bin, засевающий домашку при первом запуске ---
say "nvim wrapper → /usr/local/bin/nvim (засев config+плагинов на пользователя)"
cat > /usr/local/bin/nvim <<EOF
#!/usr/bin/env bash
# Обёртка над общим nvim: при первом запуске пользователя раскладывает
# LazyVim config+плагины в его \$HOME (state/cache nvim создаёт сам).
SKEL="$SKEL"
NVIM_REAL="$NVIM_REAL"
if [ ! -e "\$HOME/.config/nvim" ] && [ -d "\$SKEL/.config/nvim" ]; then
    mkdir -p "\$HOME/.config" "\$HOME/.local/share"
    cp -a "\$SKEL/.config/nvim"       "\$HOME/.config/nvim"
    cp -a "\$SKEL/.local/share/nvim"  "\$HOME/.local/share/nvim"
fi
exec "\$NVIM_REAL" "\$@"
EOF
chmod 0755 /usr/local/bin/nvim

# --- LazyVim config + плагины → seed ---------------------------------------
say "LazyVim config+плагины → $SKEL (заготовка для пользователей)"
rm -rf "$SKEL/.config/nvim" "$SKEL/.local/share/nvim"
tar xzf "$DIST/lazyvim-config.tar.gz" -C "$SKEL/.config"
tar xzf "$DIST/lazyvim-data.tar.gz"   -C "$SKEL/.local/share"

# --- Nerd Font → /usr/share/fonts ------------------------------------------
say "Nerd Font → /usr/share/fonts/astra-nerd"
mkdir -p /usr/share/fonts/astra-nerd
tar xzf "$DIST/fonts.tar.gz" -C /usr/share/fonts/astra-nerd
fc-cache -f /usr/share/fonts >/dev/null 2>&1 || true

# --- cargo офлайн-реестр → seed --------------------------------------------
say "cargo офлайн-конфиг → $SKEL/.cargo/config.toml"
cp "$ROOT/cargo/config.toml" "$SKEL/.cargo/config.toml"

# --- окружение для всех: PATH + засев cargo-конфига при входе ---------------
say "Окружение для всех → /etc/profile.d/astra-dev.sh"
cat > /etc/profile.d/astra-dev.sh <<EOF
# astra-dev-setup: общее окружение
case ":\$PATH:" in *":/usr/local/bin:"*) ;; *) export PATH="/usr/local/bin:\$PATH";; esac
# засев cargo-офлайн-конфига пользователю (один раз)
if [ ! -e "\$HOME/.cargo/config.toml" ] && [ -f "$SKEL/.cargo/config.toml" ]; then
    mkdir -p "\$HOME/.cargo" && cp "$SKEL/.cargo/config.toml" "\$HOME/.cargo/config.toml"
fi
EOF
chmod 0644 /etc/profile.d/astra-dev.sh

# --- итог -------------------------------------------------------------------
cat <<EOF

==> Системная часть установлена (общая для всех пользователей).
    nvim/rust-analyzer в /usr/local/bin, парсеры/шрифты/seed — в системе.
    Каждому пользователю config+плагины LazyVim засеются при первом \`nvim\`,
    cargo-конфиг — при следующем входе в систему.

Осталось руками (sudo, один раз на машину):
  1) C++ LSP (версия clangd зависит от машины — сперва:  apt-cache search clangd):
       sudo apt install -y clangd-15    # подставь найденную версию
       sudo ln -sf "\$(command -v clangd-15 || command -v clangd)" /usr/local/bin/clangd
  2) Rust-тулчейн из репозиториев Astra (для cargo/rustc):
       bash install/install-rust.sh
  3) В терминале выбрать шрифт "JetBrainsMono Nerd Font Mono".

Проверка (от обычного пользователя, в НОВОМ терминале):
  which nvim rust-analyzer         # → /usr/local/bin/...
  nvim --version
  rust-analyzer --version
EOF
