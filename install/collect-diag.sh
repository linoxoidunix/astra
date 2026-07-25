#!/usr/bin/env bash
# collect-diag.sh — компактный отчёт о состоянии комплекта и Rust-проекта.
#
# Вывод рассчитан на перенос ГЛАЗАМИ (фото/распечатка): одна проверка — одна
# строка, только ASCII, не длиннее 72 символов, строки пронумерованы, в конце
# маркер END с их количеством — сразу видно, если снимок обрезал хвост.
#
#   bash install/collect-diag.sh [путь-к-rust-проекту]
#   bash install/collect-diag.sh ~/dev/hello_world --clean   # + cargo clean перед сборкой
#
# Без --clean ничего не меняет: только читает, собирает проект и гоняет анализ.
# Запускать на маленьком проекте (том самом hello_world): на большом
# analysis-stats думает минутами, а строка отчёта от этого не станет полезнее.
set -uo pipefail

OUT=/tmp/astra-diag.txt
PROJ=""
CLEAN=0
for a in "$@"; do
    case "$a" in
        --clean) CLEAN=1 ;;
        *) [ -z "$PROJ" ] && PROJ="$a" ;;
    esac
done
[ -n "$PROJ" ] || PROJ="$PWD"
[ -f "$PROJ/Cargo.toml" ] || PROJ="$HOME/dev/hello_world"

n=0
p(){ n=$((n+1)); printf '%02d %-9s %s\n' "$n" "$1" "$2" | cut -c1-72; }
have(){ command -v "$1" >/dev/null 2>&1; }
run(){ if have timeout; then timeout "$1" "${@:2}"; else "${@:2}"; fi; }
ver(){ "$1" --version 2>&1 | head -1 | tr -d '\r'; }
# длинные пути режем с головы: хвост информативнее начала
short(){ printf '%s' "${1/#$HOME/\~}" | awk '{ print (length > 50) ? "..." substr($0, length-46) : $0 }'; }

report(){

p DATE "$(date '+%Y-%m-%d %H:%M')"

# --- 1. что и откуда запускается -------------------------------------------
p NVIM "$(have nvim && ver nvim || echo NONE)"
if have rust-analyzer; then
    p RA "$(ver rust-analyzer)"
    p RA-PATH "$(short "$(command -v rust-analyzer)") [x$(which -a rust-analyzer 2>/dev/null | wc -l)]"
else
    p RA "NONE in PATH"
fi
p RUSTC "$(have rustc && ver rustc || echo NONE)"
p CARGO "$(have cargo && ver cargo || echo NONE)"
p CLANGD "$(have clangd && ver clangd || echo NONE)"

# --- 2. sysroot: без исходников std rust-analyzer не выведет Future::Output --
SYSROOT="$(rustc --print sysroot 2>/dev/null)"
FUT="$SYSROOT/lib/rustlib/src/rust/library/core/src/future/future.rs"
p SYSROOT "$(short "${SYSROOT:-NONE}")"
p RUST-SRC "$([ -f "$FUT" ] && echo OK || { [ -d /usr/lib/rustlib/src/rust/library ] && echo 'only /usr/lib/rustlib/src' || echo MISSING; })"

# --- 3. проект --------------------------------------------------------------
p PROJ "$(short "$PROJ")"
if [ -f "$PROJ/Cargo.toml" ]; then
    p LOCK "$([ -f "$PROJ/Cargo.lock" ] && echo present || echo MISSING)"
    p TOKIO "$(grep -A1 '^name = "tokio"' "$PROJ/Cargo.lock" 2>/dev/null | grep version | tr -dc '0-9.' || echo none)"
    p PM2 "$(grep -A1 '^name = "proc-macro2"' "$PROJ/Cargo.lock" 2>/dev/null | grep version | tr -dc '0-9.' || echo none)"
    # обрезанный .rmeta — главный подозреваемый по E0786
    p RMETA "total=$(find "$PROJ/target" -name '*.rmeta' 2>/dev/null | wc -l) tiny=$(find "$PROJ/target" -name '*.rmeta' -size -1k 2>/dev/null | wc -l)"
    p TARGET "$(du -sh "$PROJ/target" 2>/dev/null | cut -f1 || echo none)"
else
    p PROJ-ERR "no Cargo.toml, pass project path as argument"
fi

# --- 4. сборка из терминала -------------------------------------------------
if [ -f "$PROJ/Cargo.toml" ] && have cargo; then
    [ "$CLEAN" = 1 ] && { ( cd "$PROJ" && cargo clean >/dev/null 2>&1 ); p CLEAN "cargo clean done"; }
    B=$( cd "$PROJ" && run 900 cargo build --offline 2>&1 )
    if printf '%s' "$B" | grep -q '^error'; then
        CODES=$(printf '%s' "$B" | grep -oE 'E0[0-9]{3}' | sort -u | tr '\n' ',')
        MSRV=$(printf '%s' "$B" | grep -c 'requires rustc')
        p BUILD "FAIL codes=${CODES:-none} msrv-errors=$MSRV"
        p BUILD-1 "$(printf '%s' "$B" | grep -m1 '^error')"
    else
        p BUILD "OK"
    fi
fi

# --- 5. rust-analyzer без nvim в цепочке ------------------------------------
# analysis-stats считает типы по всему крейту и печатает панику явно;
# второй прогон без proc-макросов показывает, виновато ли раскрытие #[tokio::main].
if [ -f "$PROJ/Cargo.toml" ] && have rust-analyzer; then
    A=$( cd "$PROJ" && run 900 rust-analyzer analysis-stats . 2>&1 )
    p RA-STATS "$(printf '%s' "$A" | grep -oE 'exprs: [0-9]+, \?\?ty: [0-9]+ \([0-9]+%\)' | head -1)"
    p RA-PANIC "$(printf '%s' "$A" | grep -c 'panicked') hits"
    p RA-MSG "$(printf '%s' "$A" | grep -m1 -oE 'which is not [A-Za-z]+.*|panicked at [^ ]+')"
    N=$( cd "$PROJ" && run 900 rust-analyzer analysis-stats --disable-proc-macros . 2>&1 )
    p RA-NOPM "$(printf '%s' "$N" | grep -c 'panicked') hits (proc-macros off)"
fi

# --- 6. сторона nvim: доехали ли спеки комплекта ----------------------------
CFG="$HOME/.config/nvim"
p SPECS "$(ls "$CFG/lua/plugins" 2>/dev/null | sed 's/^astra-//; s/\.lua$//' | tr '\n' ' ')"
p EXTRAS-L "$([ -f "$CFG/lua/plugins/extras.lua" ] && echo present-OLD || echo absent-ok)"
p LZJSON "$(grep -c 'lazyvim.plugins.extras' "$CFG/lazyvim.json" 2>/dev/null || echo 0) extras, ver=$(grep -oE '"version":[ ]*[0-9]+' "$CFG/lazyvim.json" 2>/dev/null | tr -dc '0-9')"
p BLINK-SP "$([ -f "$CFG/lua/plugins/astra-blink-offline.lua" ] && grep -o 'implementation = "[a-z_]*"' "$CFG/lua/plugins/astra-blink-offline.lua" || echo no-spec)"
p RUST-SP "$([ -f "$CFG/lua/plugins/astra-rust.lua" ] && echo present || echo no-spec)"
LOG="$HOME/.local/state/nvim/lsp.log"
p LSPLOG "$([ -f "$LOG" ] && echo "$(grep -ci 'panicked' "$LOG") panics, $(du -h "$LOG" | cut -f1)" || echo none)"
p LSP-MSG "$(grep -i 'panicked' "$LOG" 2>/dev/null | tail -1 | grep -oE 'panicked.{0,45}')"

# --- 7. офлайн-реестр крейтов -----------------------------------------------
p REGISTRY "$(ls /usr/share/cargo/registry 2>/dev/null | wc -l) crates, tokio=$(ls -d /usr/share/cargo/registry/tokio* 2>/dev/null | wc -l)"
p CARGOCFG "$(grep -m1 'replace-with' "$HOME/.cargo/config.toml" 2>/dev/null | tr -d ' ' || echo none)"

n=$((n+1)); printf '%02d %-9s %s\n' "$n" END "lines=$n file=$OUT"

}

report | tee "$OUT"
