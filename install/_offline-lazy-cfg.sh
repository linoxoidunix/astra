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

# Отпечаток бандла: по нему установщики и обёртка понимают, что комплект сменился
# и плагины в домашке пора переложить. Считаем по самим архивам — их пересборка
# всегда меняет содержимое, а версий/тегов у комплекта нет.
bundle_id() {
    local dist="$1" sum
    sum=$(command -v sha256sum || command -v md5sum || command -v cksum) || return 0
    cat "$dist/lazyvim-config.tar.gz" "$dist/lazyvim-data.tar.gz" 2>/dev/null \
        | "$sum" | tr -dc '0-9a-f' | cut -c1-16
}
