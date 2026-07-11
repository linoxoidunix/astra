#!/usr/bin/env bash
# Компилирует treesitter-парсеры под glibc 2.28 напрямую из грамматик
# (по реестру nvim-treesitter, без tree-sitter CLI) → /out/parsers.tar.gz.
# Монтируется: /nvim (nvim), /reg/parsers.lua, /gen.lua. Запуск в debian:buster-slim.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
TS_LANGS="${TS_LANGS:-c cpp rust lua luadoc vim vimdoc query markdown markdown_inline bash json yaml toml regex printf gitcommit diff}"
log(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

log "apt: gcc/g++/git"
sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g' /etc/apt/sources.list
sed -i '/buster-updates/d' /etc/apt/sources.list
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check
apt-get update -qq
apt-get install -y --no-install-recommends build-essential git ca-certificates >/dev/null

OUT=/out/parsers
mkdir -p "$OUT"

log "Список грамматик из реестра"
/nvim/bin/nvim --headless -l /gen.lua /reg/parsers.lua $TS_LANGS > /tmp/list.tsv 2>/tmp/list.err
cat /tmp/list.err || true
cat /tmp/list.tsv

log "Компиляция парсеров"
ok=0; fail=0
while IFS=$'\t' read -r lang url rev loc; do
  [ -n "$lang" ] || continue
  d=$(mktemp -d)
  if ! git clone -q "$url" "$d" 2>/dev/null; then echo "  clone FAIL $lang"; fail=$((fail+1)); rm -rf "$d"; continue; fi
  if [ -n "$rev" ]; then
    git -C "$d" checkout -q "$rev" 2>/dev/null \
      || { git -C "$d" fetch -q --depth 1 origin "$rev" 2>/dev/null && git -C "$d" checkout -q FETCH_HEAD 2>/dev/null; } \
      || echo "  (ревизия $rev не найдена, беру default) $lang"
  fi
  src="$d/${loc:+$loc/}src"
  if [ ! -f "$src/parser.c" ]; then echo "  нет parser.c $lang ($src)"; fail=$((fail+1)); rm -rf "$d"; continue; fi
  files="$src/parser.c"; cc_bin=cc
  [ -f "$src/scanner.c" ]  && files="$files $src/scanner.c"
  [ -f "$src/scanner.cc" ] && { files="$files $src/scanner.cc"; cc_bin=g++; }
  if $cc_bin -O2 -fPIC -shared -I"$src" $files -o "$OUT/$lang.so" 2>/dev/null; then
    ok=$((ok+1))
  else
    echo "  compile FAIL $lang"; fail=$((fail+1))
  fi
  rm -rf "$d"
done < /tmp/list.tsv

log "Итог: $ok собрано, $fail не удалось"
ls -1 "$OUT"
tar czf /out/parsers.tar.gz -C "$OUT" .
echo "требуемый glibc (пример):"
objdump -T "$OUT"/rust.so 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | uniq | tail -2 || true
log "ГОТОВО"
