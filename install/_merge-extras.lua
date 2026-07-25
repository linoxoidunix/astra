-- Дописывает экстры комплекта в lazyvim.json пользователя, не трогая остального
-- содержимого файла (news-хэши, version, свои экстры из :LazyExtras).
--
-- Нужно тем, у кого комплект уже стоял: раньше экстры подключались импортами из
-- lua/plugins/extras.lua, теперь — через lazyvim.json (штатный :LazyExtras), иначе
-- LazyVim ругается «The order of your `lazy.nvim` imports is incorrect».
--
-- Запуск:  nvim --headless -l _merge-extras.lua <lazyvim.json> <экстра>...
local path = table.remove(arg, 1)
local want = arg

local data = {}
local f = io.open(path, "r")
if f then
    local ok, decoded = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(decoded) == "table" then data = decoded end
end

local extras = type(data.extras) == "table" and data.extras or {}
local have_before = vim.list_slice(extras)
local have = {}
for _, e in ipairs(extras) do have[e] = true end
for _, e in ipairs(want) do
    if not have[e] then
        extras[#extras + 1] = e
        have[e] = true
    end
end
-- Файл без "version" LazyVim принимает за схему v0 и мигрирует: дописывает каждому
-- имени префикс "lazyvim.plugins.extras.", получая двойной, после чего экстры молча
-- не грузятся, а Lazy! sync вычищает их плагины. Проставляем версию только когда
-- файла (или экстр) не было вовсе: у файла со своими экстрами версия уже есть, и
-- если она старая — пусть LazyVim мигрирует его сам, штатно.
table.sort(extras)
if data.version == nil and #have_before == 0 then
    data.version = 8          -- lazyvim/config/init.lua: M.json.version
    data.install_version = 8
end
data.extras = extras

local out = assert(io.open(path, "w"))
out:write(vim.json.encode(data))
out:close()
