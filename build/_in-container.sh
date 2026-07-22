#!/usr/bin/env bash
# Собирает ВЕСЬ комплект под glibc 2.28 (Debian Buster) в /out/dist:
#   nvim, rust-analyzer, LazyVim(config+plugins), treesitter-парсеры, Nerd Font.
# Запускается ВНУТРИ контейнера debian:buster-slim (см. build-all.sh).
set -uo pipefail
export HOME=/root
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/opt/cmake/bin:$PATH"

NVIM_TAG="${NVIM_TAG:-v0.12.4}"
CMAKE_VER="${CMAKE_VER:-3.28.3}"
FONT="${FONT:-JetBrainsMono}"
NODE_VER="${NODE_VER:-v20.18.1}"     # LTS, собран под glibc 2.28 (идёт на Astra 1.7)
TS_VER="${TS_VER:-5.7.3}"            # typescript 5.x — стабильный tsserver для vtsls
TS_LANGS="${TS_LANGS:-c cpp cmake rust lua luadoc vim vimdoc query markdown markdown_inline bash json yaml toml regex printf gitcommit diff javascript typescript tsx jsdoc html css}"

DIST=/out
mkdir -p "$DIST/bin" "$DIST/fonts" "$DIST/parsers"
log(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- apt / buster
log "Buster archive + build deps"
sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g' /etc/apt/sources.list
sed -i '/buster-updates/d' /etc/apt/sources.list
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check
apt-get update
apt-get install -y --no-install-recommends \
    build-essential gettext libtool-bin autoconf automake pkg-config \
    git curl wget ca-certificates unzip xz-utils file libssl-dev ninja-build

log "CMake ${CMAKE_VER}"
curl -fsSL -o /tmp/cmake.tgz \
    "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-x86_64.tar.gz"
mkdir -p /opt/cmake && tar xzf /tmp/cmake.tgz -C /opt/cmake --strip-components=1
cmake --version | head -1

# ---------------------------------------------------------------- neovim
log "Сборка Neovim ${NVIM_TAG}"
git clone --depth 1 --branch "${NVIM_TAG}" https://github.com/neovim/neovim /src
make -C /src CMAKE_BUILD_TYPE=Release \
     CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$DIST/nvim" -j"$(nproc)"
make -C /src install
NVIM="$DIST/nvim/bin/nvim"
"$NVIM" --version | head -1

# ---------------------------------------------------------------- rust toolchain
log "rustup + stable (для rust-analyzer и tree-sitter CLI)"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustc --version

log "Сборка rust-analyzer (долго)"
git clone --depth 1 https://github.com/rust-lang/rust-analyzer /ra
( cd /ra && cargo build --release --bin rust-analyzer )
cp /ra/target/release/rust-analyzer "$DIST/bin/rust-analyzer"
"$DIST/bin/rust-analyzer" --version

# ---------------------------------------------------------------- Node + TS LSP
log "Node ${NODE_VER} (для TS/JS LSP) + vtsls + typescript"
curl -fsSL -o /tmp/node.tar.xz \
  "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.xz"
rm -rf "$DIST/node"; mkdir -p "$DIST/node"
tar xf /tmp/node.tar.xz -C "$DIST/node" --strip-components=1
export PATH="$DIST/node/bin:$PATH"
node --version
# vtsls + фиксированный typescript 5.x (стабильный tsserver.js, который ждёт vtsls)
rm -rf "$DIST/ts-lsp"
npm install -g --prefix "$DIST/ts-lsp" @vtsls/language-server "typescript@${TS_VER}"
"$DIST/ts-lsp/bin/vtsls" --version

# ---------------------------------------------------------------- LazyVim
log "LazyVim starter + расширения"
rm -rf "$HOME/.config/nvim" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
git clone --depth 1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
rm -rf "$HOME/.config/nvim/.git"
mkdir -p "$HOME/.config/nvim/lua/plugins"
cat > "$HOME/.config/nvim/lua/plugins/extras.lua" <<'LUA'
return {
  { import = "lazyvim.plugins.extras.lang.rust" },
  { import = "lazyvim.plugins.extras.lang.clangd" },
  { import = "lazyvim.plugins.extras.lang.cmake" },
  { import = "lazyvim.plugins.extras.lang.typescript" },
  -- офлайн: mason ничего не доустанавливает, LSP берём из PATH
  { "mason.nvim", opts = { ensure_installed = {} } },
  { "nvim-lspconfig", opts = { servers = {
    rust_analyzer = { mason = false },  -- собранный бинарь (dist/bin) из PATH
    clangd = { mason = false },
    vtsls  = { mason = false },   -- TS/JS сервер (bundled Node) из PATH
  } } },
}
LUA

log "Lazy! sync (клон плагинов)"
"$NVIM" --headless "+Lazy! sync" +qa 2>&1 | tail -15 || true
echo "плагинов: $(ls "$HOME/.local/share/nvim/lazy" | wc -l)"

log "Treesitter-парсеры: компиляция из грамматик по реестру nvim-treesitter"
cat > /tmp/gen.lua <<'GEN'
local a=_G.arg; local P=dofile(a[1])
for i=2,#a do local e=P[a[i]]; if e and e.install_info then
  io.write(table.concat({a[i],e.install_info.url or '',e.install_info.revision or '',e.install_info.location or ''},'\t'),'\n') end end
GEN
REG="$HOME/.local/share/nvim/lazy/nvim-treesitter/lua/nvim-treesitter/parsers.lua"
"$NVIM" --headless -l /tmp/gen.lua "$REG" $TS_LANGS > /tmp/list.tsv 2>/dev/null || true
tsok=0; tsfail=0
while IFS=$'\t' read -r lang url rev loc; do
  [ -n "$lang" ] || continue
  d=$(mktemp -d)
  git clone -q "$url" "$d" 2>/dev/null || { tsfail=$((tsfail+1)); rm -rf "$d"; continue; }
  [ -n "$rev" ] && { git -C "$d" checkout -q "$rev" 2>/dev/null \
    || { git -C "$d" fetch -q --depth 1 origin "$rev" 2>/dev/null && git -C "$d" checkout -q FETCH_HEAD 2>/dev/null; }; }
  src="$d/${loc:+$loc/}src"
  if [ -f "$src/parser.c" ]; then
    files="$src/parser.c"; ccb=cc
    [ -f "$src/scanner.c" ]  && files="$files $src/scanner.c"
    [ -f "$src/scanner.cc" ] && { files="$files $src/scanner.cc"; ccb=g++; }
    $ccb -O2 -fPIC -shared -I"$src" $files -o "$DIST/parsers/$lang.so" 2>/dev/null \
      && tsok=$((tsok+1)) || tsfail=$((tsfail+1))
  else tsfail=$((tsfail+1)); fi
  rm -rf "$d"
done < /tmp/list.tsv
echo "парсеры: собрано $tsok, не удалось $tsfail"; ls -1 "$DIST/parsers"

# ---------------------------------------------------------------- Nerd Font
log "Nerd Font ${FONT}"
curl -fsSL -o /tmp/font.tar.xz \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.tar.xz"
mkdir -p /tmp/font && tar xf /tmp/font.tar.xz -C /tmp/font
cp /tmp/font/*NerdFontMono-*.ttf "$DIST/fonts/" 2>/dev/null || cp /tmp/font/*.ttf "$DIST/fonts/"
echo "шрифтов: $(ls "$DIST/fonts" | wc -l)"

# ---------------------------------------------------------------- упаковка
log "Упаковка dist"
tar czf "$DIST/nvim.tar.gz"           -C "$DIST" nvim && rm -rf "$DIST/nvim"
tar czf "$DIST/node.tar.gz"           -C "$DIST" node && rm -rf "$DIST/node"
tar czf "$DIST/ts-lsp.tar.gz"         -C "$DIST" ts-lsp && rm -rf "$DIST/ts-lsp"
tar czf "$DIST/lazyvim-config.tar.gz" -C "$HOME/.config" nvim
tar czf "$DIST/lazyvim-data.tar.gz"   -C "$HOME/.local/share" nvim
( cd "$DIST/fonts" && tar czf "$DIST/fonts.tar.gz" ./*.ttf ) && rm -rf "$DIST/fonts"
( cd "$DIST/parsers" && tar czf "$DIST/parsers.tar.gz" ./*.so ) 2>/dev/null && rm -rf "$DIST/parsers"
ls -lh "$DIST"
log "ГОТОВО"
