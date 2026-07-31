#!/usr/bin/env bash
# Правки lua/config/lazy.lua под офлайн. Подключается точкой из установщиков:
#   . "$HERE/_offline-lazy-cfg.sh";  offline_lazy_cfg <путь-к-lazy.lua>
#
# Стартовый конфиг LazyVim рассчитан на машину с интернетом:
#   checker.enabled = true — раз в час (и сразу на старте) lazy.nvim делает
#     git fetch по КАЖДОМУ плагину. Офлайн это 49 висящих процессов git и
#     ошибки в уведомлениях на каждом запуске.
#   rocks — luarocks/hererocks lazy.nvim при необходимости качает из сети;
#     плагины с .rockspec в комплекте есть (nvim-dap, plenary, gitsigns…),
#     так что при любом Lazy! sync это всплывёт.
# Обе правки идемпотентны: повторный запуск установщика ничего не меняет.
offline_lazy_cfg() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's|enabled = true, -- check for plugin updates periodically|enabled = false, -- офлайн: не ходим за обновлениями (иначе git fetch на github)|' "$f"
    grep -q 'rocks = {' "$f" || sed -i \
        's|^  install = { colorscheme = .*|&\n  rocks = { enabled = false }, -- офлайн: luarocks/hererocks скачать неоткуда|' "$f"
}

# Спек nvim-treesitter под офлайн:  offline_ts_cfg <каталог-конфига-nvim>
#
# LazyVim держит nvim-treesitter на ветке `main`, а там всё устроено иначе, чем
# на master, и обе особенности бьют по офлайн-комплекту.
#
# 1) Парсеры ищутся ТОЛЬКО в install_dir (по умолчанию ~/.local/share/nvim/site),
#    см. nvim-treesitter/lua/nvim-treesitter/config.lua: get_installed() читает
#    ровно install_dir/parser. Раскладывать .so в ~/.config/nvim/parser, как
#    делалось раньше, недостаточно: сам Neovim их подхватит (каталог в rtp), но
#    LazyVim спрашивает про парсеры именно у nvim-treesitter. Ответ «ничего не
#    установлено» означает, что LazyVim.treesitter.have(ft) ложно ВСЕГДА, и его
#    автокоманда FileType не включает ни подсветку, ни отступы, ни свёртки.
#    Поэтому установщики кладут парсеры в install_dir, а системная установка ещё
#    и переносит сам install_dir в общий /opt/astra-dev/ts (один каталог на всех).
#
# 2) Недостающие парсеры LazyVim доустанавливает сам, а на ветке main для этого
#    нужен tree-sitter CLI. Его нет и взяться офлайн неоткуда, поэтому попытка
#    заканчивается на каждом старте:
#        Unmet requirements for nvim-treesitter `main`: ... x tree-sitter (CLI)
#        Failed to install `tree-sitter-cli` with `mason.nvim`.
#    Пустой ensure_installed убирает саму попытку: доустанавливать нечего, всё
#    нужное уже лежит в install_dir.
#
# Пишем opts ФУНКЦИЕЙ, а не таблицей: у спека LazyVim opts_extend = ensure_installed,
# то есть таблицы сливаются СПИСКОМ и обнулить его таблицей нельзя. Функции же
# применяются после таблиц — тот же приём, что в astra-lsp-offline.lua для mason.
TS_SHARED_DIR=/opt/astra-dev/ts     # общий install_dir системной установки

offline_ts_cfg() {
    # двумя строками, а не «local cfg=... dir="$cfg/..."»: bash раскрывает все
    # аргументы local ДО присваивания, и $cfg внутри той же строки ещё пуст
    local cfg="$1"
    local dir="$cfg/lua/plugins"
    [ -d "$dir" ] || return 0
    cat > "$dir/astra-treesitter.lua" <<EOF
-- спек комплекта astra-dev-setup (обновляется установщиком, править не нужно)
local shared = "$TS_SHARED_DIR"   -- общий каталог парсеров системной установки
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- офлайн: доустанавливать неоткуда и нечем (нужен tree-sitter CLI)
      opts.ensure_installed = {}
      -- при системной установке парсеры общие; при пользовательской остаётся
      -- умолчание nvim-treesitter — ~/.local/share/nvim/site
      if vim.fn.isdirectory(shared .. "/parser") == 1 then
        opts.install_dir = shared
      end
    end,
  },
}
EOF
}

# Отпечаток бандла: по нему установщики и обёртка понимают, что комплект сменился
# и плагины в домашке пора переложить. Считаем по самим архивам — их пересборка
# всегда меняет содержимое, а версий/тегов у комплекта нет.
bundle_id() {
    local dist="$1" sum
    sum=$(command -v sha256sum || command -v md5sum || command -v cksum) || return 0
    cat "$dist/lazyvim-config.tar.gz" "$dist/lazyvim-data.tar.gz" 2>/dev/null \
        | "$sum" | tr -dc '0-9a-f' | cut -c1-16
}
