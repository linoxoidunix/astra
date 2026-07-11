-- Печатает "lang<TAB>url<TAB>revision<TAB>location" для языков из аргументов,
-- читая реестр nvim-treesitter (parsers.lua). Запуск:
--   nvim --headless -l _gen-parser-list.lua <parsers.lua> lang1 lang2 ...
local args = _G.arg
local path = args[1]
local P = dofile(path)
for i = 2, #args do
  local lang = args[i]
  local e = P[lang]
  if e and e.install_info then
    io.write(table.concat({
      lang,
      e.install_info.url or '',
      e.install_info.revision or '',
      e.install_info.location or '',
    }, '\t'), '\n')
  else
    io.stderr:write('нет в реестре: ' .. lang .. '\n')
  end
end
