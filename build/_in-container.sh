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
RUST_VER="${RUST_VER:-1.70.0}"       # тулчейн для сборки rust-analyzer
RA_TAG="${RA_TAG:-2023-11-27}"       # последний релиз rust-analyzer, реально собирающийся на 1.70 (2024-01-01 врёт про MSRV — E0445)
RA_JOBS="${RA_JOBS:-2}"              # параллельных задач cargo: меньше = меньше пик ОЗУ (LLVM codegen)
RG_VER="${RG_VER:-14.1.1}"          # ripgrep для LazyVim-грепа (<leader>sg/sG); static-musl, без glibc
FD_VER="${FD_VER:-10.2.0}"          # fd для файлового пикера (<leader>ff); static-musl, без glibc
CODELLDB_VER="${CODELLDB_VER:-v1.12.2}"  # отладчик C/C++/Rust (DAP-адаптер + свой lldb)
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
log "rustup + toolchain ${RUST_VER} (для rust-analyzer)"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain "${RUST_VER}"
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup default "${RUST_VER}"
cargo --version; rustc --version

log "Сборка rust-analyzer ${RA_TAG} (cargo ${RUST_VER}, -j${RA_JOBS}) — долго"
# --branch на тег: 2023-11-27 — последний rust-analyzer, реально собирающийся на 1.70.
# (2024-01-01 объявляет MSRV 1.70, но падает E0445 из-за InFileWrapper от 2023-11-28.)
# committed Cargo.lock в этом теге фиксирует версии зависимостей → сборка детерминирована.
git clone --depth 1 --branch "${RA_TAG}" https://github.com/rust-lang/rust-analyzer /ra
# --jobs ограничивает параллелизм codegen — главный источник пикового ОЗУ при сборке.
( cd /ra && cargo build --release --jobs "${RA_JOBS}" --bin rust-analyzer )
cp /ra/target/release/rust-analyzer "$DIST/bin/rust-analyzer"
"$DIST/bin/rust-analyzer" --version

# ---------------------------------------------------------------- CLI-инструменты для пикеров
# ripgrep (<leader>sg/sG греп) и fd (<leader>ff поиск файлов). Готовые static-musl бинарники:
# статически слинкованы, от glibc не зависят вовсе → работают на любой Astra.
log "ripgrep ${RG_VER} + fd ${FD_VER} (static-musl) → dist/bin"
curl -fsSL -o /tmp/rg.tgz \
  "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VER}/ripgrep-${RG_VER}-x86_64-unknown-linux-musl.tar.gz"
tar xzf /tmp/rg.tgz -C /tmp
cp /tmp/ripgrep-${RG_VER}-x86_64-unknown-linux-musl/rg "$DIST/bin/rg"
"$DIST/bin/rg" --version | head -1
curl -fsSL -o /tmp/fd.tgz \
  "https://github.com/sharkdp/fd/releases/download/v${FD_VER}/fd-v${FD_VER}-x86_64-unknown-linux-musl.tar.gz"
tar xzf /tmp/fd.tgz -C /tmp
cp /tmp/fd-v${FD_VER}-x86_64-unknown-linux-musl/fd "$DIST/bin/fd"
"$DIST/bin/fd" --version

# ---------------------------------------------------------------- codelldb (отладчик)
# Готовый vsix, а не сборка из исходников: собирать codelldb — это тянуть в контейнер
# LLVM/LLDB на часы. Проверено objdump'ом и живой сессией в buster: максимум по всем
# ELF пакета — GLIBC_2.18 (у нас 2.28), libstdc++ слинкован статически, Python свой.
# vsix — обычный zip; unzip НЕ сохраняет бит исполнения, отсюда chmod ниже.
log "codelldb ${CODELLDB_VER} (DAP-адаптер + свой lldb) → dist/codelldb"
curl -fsSL -o /tmp/codelldb.vsix \
  "https://github.com/vadimcn/codelldb/releases/download/${CODELLDB_VER}/codelldb-linux-x64.vsix"
rm -rf /tmp/cl "$DIST/codelldb"; mkdir -p /tmp/cl "$DIST/codelldb"
unzip -q /tmp/codelldb.vsix -d /tmp/cl
# нужны только адаптер и lldb; extension/bin (25 МБ) — обвязка VSCode, не нужна
cp -a /tmp/cl/extension/adapter "$DIST/codelldb/adapter"
cp -a /tmp/cl/extension/lldb    "$DIST/codelldb/lldb"
chmod -R a+rX "$DIST/codelldb"
chmod a+x "$DIST/codelldb/adapter/codelldb" "$DIST/codelldb/lldb/bin/"*
find "$DIST/codelldb" -name '*.so' -exec chmod a+x {} +
"$DIST/codelldb/lldb/bin/lldb" --version
"$DIST/codelldb/adapter/codelldb" --help >/dev/null && echo "адаптер codelldb запускается"

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

# Экстры подключаем через lazyvim.json — это штатный механизм :LazyExtras. Его
# импортирует сам модуль lazyvim.plugins, поэтому порядок получается правильный:
# lazyvim.plugins → extras → plugins. Если писать { import = "lazyvim.plugins.extras..." }
# внутри lua/plugins/*.lua, каталог plugins регистрируется РАНЬШЕ экстр, и LazyVim
# ругается на каждом старте (check_order в lazyvim/config/init.lua):
#   The order of your `lazy.nvim` imports is incorrect
#
# "version" обязателен. Файл без него LazyVim считает схемой v0 и гонит миграцию,
# которая дописывает каждому имени префикс "lazyvim.plugins.extras." (util/json.lua):
#   Failed to load `lazyvim.plugins.extras.lazyvim.plugins.extras.coding.neogen`
# После этого экстры не грузятся вовсе, а `Lazy! sync` вычищает их плагины
# (clangd_extensions, cmake-tools, crates.nvim, neogen) как «лишние».
# 8 — текущая версия схемы (lazyvim/config/init.lua: M.json.version).
cat > "$HOME/.config/nvim/lazyvim.json" <<'JSON'
{
  "version": 8,
  "install_version": 8,
  "extras": [
    "lazyvim.plugins.extras.coding.neogen",
    "lazyvim.plugins.extras.dap.core",
    "lazyvim.plugins.extras.editor.aerial",
    "lazyvim.plugins.extras.editor.inc-rename",
    "lazyvim.plugins.extras.editor.refactoring",
    "lazyvim.plugins.extras.lang.clangd",
    "lazyvim.plugins.extras.lang.cmake",
    "lazyvim.plugins.extras.lang.rust",
    "lazyvim.plugins.extras.lang.typescript",
    "lazyvim.plugins.extras.ui.indent-blankline",
    "lazyvim.plugins.extras.ui.treesitter-context",
    "lazyvim.plugins.extras.util.mini-hipatterns"
  ]
}
JSON

# neogen — Doxygen/rustdoc/JSDoc аннотации (<leader>cn); dap.core — nvim-dap + dap-ui
# (адаптер задаётся в astra-dap.lua).
cat > "$HOME/.config/nvim/lua/plugins/astra-lsp-offline.lua" <<'LUA'
return {
  -- офлайн: mason ничего не доустанавливает, LSP берём из PATH.
  -- Именно функцией, а не таблицей: lang.rust дописывает codelldb в ensure_installed
  -- своей opts-функцией, а функции применяются после таблиц — и эта, будучи ПОСЛЕ
  -- экстр, отрабатывает последней и обнуляет список.
  { "mason.nvim", opts = function(_, opts) opts.ensure_installed = {} end },
  { "nvim-lspconfig", opts = { servers = {
    rust_analyzer = { mason = false },  -- собранный бинарь (dist/bin) из PATH
    clangd = { mason = false },
    vtsls  = { mason = false },   -- TS/JS сервер (bundled Node) из PATH
  } } },
}
LUA

# blink.cmp (движок автодополнения LazyVim) по умолчанию тянет с github готовую
# libblink_cmp_fuzzy.so, а при неудаче предлагает собрать её nightly-cargo. Офлайн
# не выходит ни то, ни другое:
#   curl: (6) Could not resolve host: github.com
#   Falling back to Lua implementation due to error while downloading pre-built binary
# Lua-реализация fuzzy встроена в плагин и ничего внешнего не требует — включаем её
# явно, чтобы не было ни попыток скачивания, ни предупреждения на каждом старте.
cat > "$HOME/.config/nvim/lua/plugins/astra-blink-offline.lua" <<'LUA'
return {
  {
    "saghen/blink.cmp",
    opts = {
      fuzzy = {
        implementation = "lua",
        prebuilt_binaries = { download = false },
      },
    },
  },
}
LUA

# rust-analyzer (его поднимает rustaceanvim из экстры lang.rust) гоняет `cargo check`
# в том же target/, что и ручной `cargo build`. Прерванная проверка (выход из nvim,
# OOM на слабой машине) оставляет недописанный .rmeta, дальше сыпется
#   corrupt metadata encountered in target/debug/deps/libtokio-*.rmeta   (E0786)
# а следом не раскрывается #[tokio::main]:
#   `main` function is not allowed to be `async`                          (E0752)
# extraArgs уводит проверки в отдельный target/rust-analyzer: сборка редактора и
# сборка из терминала больше не пересекаются. Лечение уже случившегося — `cargo clean`.
# Опцию cargo.targetDir не используем: в rust-analyzer 2023-11-27 её ещё нет.
cat > "$HOME/.config/nvim/lua/plugins/astra-rust.lua" <<'LUA'
return {
  {
    "mrcjkb/rustaceanvim",
    opts = { server = { default_settings = { ["rust-analyzer"] = {
      check = { extraArgs = { "--target-dir", "target/rust-analyzer" } },
    } } } },
  },
}
LUA

# Греп от папки под курсором в explorer'е: встал на каталог → <leader>sG ищет в нём.
# picker_grep берёт cwd из выделенного элемента (для файла — его каталог).
# Штатный <leader>/ делает то же самое; здесь дублируем на привычную грепу клавишу.
# Префикс astra- = спек комплекта: install-system.sh обновляет такие файлы
# у всех пользователей при каждом запуске nvim (см. wrapper). Личные спеки
# пользователя называются как угодно иначе и не трогаются.
cat > "$HOME/.config/nvim/lua/plugins/astra-explorer-grep.lua" <<'LUA'
return {
  {
    "folke/snacks.nvim",
    opts = { picker = { sources = { explorer = { win = { list = { keys = {
      ["<leader>sG"] = "picker_grep",
    } } } } } } },
  },
}
LUA

# Отладка C/C++/Rust через codelldb из комплекта. Адаптер ищется в PATH, liblldb —
# рядом с ним (<корень>/adapter/codelldb → <корень>/lldb/lib/liblldb.so), поэтому
# спек одинаково работает и при системной установке, и при установке в $HOME.
cat > "$HOME/.config/nvim/lua/plugins/astra-dap.lua" <<'LUA'
-- Путь к адаптеру и его liblldb. exepath даёт симлинк из /usr/local/bin —
-- разыменовываем, иначе не найти lldb/lib рядом с настоящим бинарём.
local function codelldb()
  local exe = vim.fn.exepath("codelldb")
  if exe == "" then return nil end
  local real = vim.uv.fs_realpath(exe) or exe
  local lib = vim.fs.dirname(vim.fs.dirname(real)) .. "/lldb/lib/liblldb.so"
  if not vim.uv.fs_stat(lib) then return real, nil end
  return real, lib
end

local function adapter(exe, lib)
  return {
    type = "server",
    host = "127.0.0.1",
    port = "${port}",
    executable = {
      command = exe,
      args = lib and { "--liblldb", lib, "--port", "${port}" } or { "--port", "${port}" },
    },
  }
end

return {
  -- Офлайн: докачивать адаптеры нечем и незачем, codelldb уже лежит в PATH.
  -- Выключать плагин целиком (enabled = false) НЕЛЬЗЯ: config самой dap.core зовёт
  -- его setup() под проверкой LazyVim.has(), а та видит и отключённые спеки, — и
  -- nvim-dap падает на старте "attempt to call field 'setup' (a nil value)".
  -- Поэтому оставляем, но глушим: ничего не ставит и в сеть не ходит.
  {
    "jay-babu/mason-nvim-dap.nvim",
    opts = { automatic_installation = false, ensure_installed = {} },
  },

  -- Русские подписи в which-key. Только описания: rhs не задаём, поэтому сами
  -- клавиши остаются теми же, что ставит dap.core. opts-функцией и list_extend,
  -- а не таблицей: иначе спек LazyVim со всеми остальными группами затрётся.
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      vim.list_extend(opts.spec, {
        { "<leader>d", group = "отладка" },
        { "<leader>dp", group = "профайлер Neovim (Lua, не ваш код)" },
        { "<leader>db", desc = "Точка останова: поставить/снять" },
        { "<leader>dB", desc = "Точка останова с условием" },
        { "<leader>dc", desc = "Запустить / продолжить" },
        { "<leader>da", desc = "Запустить с аргументами" },
        { "<leader>dC", desc = "Выполнять до курсора" },
        { "<leader>dg", desc = "Перейти к строке (не выполняя)" },
        { "<leader>di", desc = "Шаг внутрь вызова" },
        { "<leader>dO", desc = "Шаг через строку" },
        { "<leader>do", desc = "Шаг наружу из функции" },
        { "<leader>dj", desc = "Ниже по стеку вызовов" },
        { "<leader>dk", desc = "Выше по стеку вызовов" },
        { "<leader>dl", desc = "Повторить последний запуск" },
        { "<leader>dP", desc = "Пауза" },
        { "<leader>dr", desc = "REPL отладчика (в Rust — цели Cargo)" },
        { "<leader>ds", desc = "Текущая сессия" },
        { "<leader>dt", desc = "Завершить сессию" },
        { "<leader>dw", desc = "Значение под курсором" },
        { "<leader>du", desc = "Панели отладчика" },
        { "<leader>de", desc = "Вычислить выражение" },
      })
    end,
  },

  {
    "mfussenegger/nvim-dap",
    -- stylua: ignore
    keys = {
      { "<leader>dq", function() require("dap").list_breakpoints(true) end, desc = "Точки останова → quickfix" },
      { "<leader>dx", function() require("dap").clear_breakpoints() end,    desc = "Снять все точки останова" },
    },
    opts = function()
      local exe, lib = codelldb()
      if not exe then return end
      local dap = require("dap")
      dap.adapters.codelldb = adapter(exe, lib)
      -- Форматтеры Qt5: LLDB из коробки знает STL, но не знает Qt — QString и QMap
      -- показываются сырым указателем d. Файл кладут установщики рядом с адаптером;
      -- если его нет, initCommands пустой и всё работает как раньше.
      local qt = vim.fs.dirname(vim.fs.dirname(exe)) .. "/qt5_lldb.py"
      local init_cmds = vim.uv.fs_stat(qt) and { "command script import " .. qt } or {}
      for _, ft in ipairs({ "c", "cpp" }) do
        dap.configurations[ft] = {
          {
            name = "Запустить бинарь (спросить путь)",
            type = "codelldb",
            request = "launch",
            program = function()
              return vim.fn.input("Путь к исполняемому файлу: ", vim.fn.getcwd() .. "/", "file")
            end,
            cwd = "${workspaceFolder}",
            args = {},
            stopOnEntry = false,
            initCommands = init_cmds,
          },
          {
            name = "Подключиться к процессу",
            type = "codelldb",
            request = "attach",
            pid = require("dap.utils").pick_process,
            cwd = "${workspaceFolder}",
          },
        }
      end
    end,
  },

  {
    -- lang.rust прописывает адаптеру mason-путь ($MASON/opt/lldb/...), которого у нас
    -- нет. Его config сливает opts в vim.g.rustaceanvim режимом "keep" — уже заданное
    -- побеждает, поэтому выставляем свой адаптер здесь, в init (до загрузки плагина).
    "mrcjkb/rustaceanvim",
    optional = true,
    init = function()
      local exe, lib = codelldb()
      if not exe then return end
      vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, {
        dap = { adapter = adapter(exe, lib) },
      })
    end,
  },
}
LUA

log "Lazy! sync (клон плагинов)"
"$NVIM" --headless "+Lazy! sync" +qa 2>&1 | tail -15 || true
echo "плагинов: $(ls "$HOME/.local/share/nvim/lazy" | wc -l)"

# Каждый каталог плагина обязан быть git-репозиторием. Без .git у lazy.nvim пустеет
# Git.info, и на целевой машине любой Lazy! sync/clean падает:
#   lazy/manage/lock.lua:26: bad argument #1 to 'assert' (value expected)
# Обычный старт при этом чистый, поэтому такой бандл легко уехать незамеченным
# (так в комплект попал neogen без .git). Ловим здесь, а не у пользователя.
nogit=""
for d in "$HOME/.local/share/nvim/lazy"/*/; do
    [ -d "$d" ] || continue
    [ -e "$d/.git" ] || nogit="$nogit ${d%/}"
done
if [ -n "$nogit" ]; then
    echo "ОШИБКА: каталоги плагинов без .git —$nogit" >&2
    echo "Бандл с таким плагином ломает Lazy! sync на Astra. Сборка прервана." >&2
    exit 1
fi
echo "все каталоги плагинов — git-репозитории"

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
tar czf "$DIST/codelldb.tar.gz"       -C "$DIST" codelldb && rm -rf "$DIST/codelldb"
tar czf "$DIST/lazyvim-config.tar.gz" -C "$HOME/.config" nvim
tar czf "$DIST/lazyvim-data.tar.gz"   -C "$HOME/.local/share" nvim
( cd "$DIST/fonts" && tar czf "$DIST/fonts.tar.gz" ./*.ttf ) && rm -rf "$DIST/fonts"
( cd "$DIST/parsers" && tar czf "$DIST/parsers.tar.gz" ./*.so ) 2>/dev/null && rm -rf "$DIST/parsers"
ls -lh "$DIST"
log "ГОТОВО"
