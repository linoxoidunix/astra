#!/usr/bin/env bash
# install_rust_astra.sh — установка Rust-тулчейна и крейтов librust-*-dev
# из репозиториев Astra Linux 1.7.
#
# Запуск на Astra:
#   bash install_rust_astra.sh            # тулчейн + ВСЕ librust-*-dev
#   bash install_rust_astra.sh popular    # тулчейн + типовой набор крейтов
#   bash install_rust_astra.sh none       # только тулчейн, без крейтов
#
# Скрипт сам поднимет права через sudo. Требуется доступ к репозиториям Astra.

set -uo pipefail

MODE="${1:-all}"          # all | popular | none

# --- повышение прав ---------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$MODE"
fi

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

# --- обновление списков пакетов ---------------------------------------------
log "apt update (обновление списков пакетов)"
apt-get update

# --- тулчейн ----------------------------------------------------------------
log "Установка тулчейна Rust (rustc, cargo, rust-src, rust-gdb, rust-doc)"
apt-get install -y rustc cargo rust-src rust-gdb rust-doc

if [ "$MODE" = none ]; then
    log "Режим none — крейты не ставим"
else
    # --- список крейтов -----------------------------------------------------
    if [ "$MODE" = popular ]; then
        log "Режим popular — типовой набор крейтов"
        SEL='^librust-(serde|serde-json|serde-derive|tokio|clap|anyhow|thiserror|rand|regex|log|env-logger|itertools|chrono|once-cell|lazy-static|libc|bitflags|byteorder|num|futures|reqwest)([+-]|-dev$)'
        mapfile -t CRATES < <(apt-cache search '^librust-.*-dev$' \
            | awk '{print $1}' | grep -E "$SEL" | sort -u)
    else
        log "Режим all — все доступные librust-*-dev"
        mapfile -t CRATES < <(apt-cache search '^librust-.*-dev$' \
            | awk '{print $1}' | sort -u)
    fi
    log "Крейтов к установке: ${#CRATES[@]}"

    if [ "${#CRATES[@]}" -gt 0 ]; then
        # Пробуем одной транзакцией; если конфликт версий — доустанавливаем
        # по одному, пропуская проблемные пакеты.
        log "Установка крейтов (одной транзакцией)"
        if apt-get install -y --no-install-recommends "${CRATES[@]}"; then
            log "Крейты установлены пакетной транзакцией"
        else
            log "Пакетная установка не прошла — ставлю по одному, конфликты пропускаю"
            ok=0; fail=0
            for c in "${CRATES[@]}"; do
                if apt-get install -y --no-install-recommends "$c" >/dev/null 2>&1; then
                    ok=$((ok + 1))
                else
                    fail=$((fail + 1)); echo "  пропущен: $c"
                fi
            done
            log "Крейты: установлено $ok, пропущено $fail"
        fi
    fi
fi

# --- итог -------------------------------------------------------------------
log "Готово. Версии:"
rustc --version 2>/dev/null || echo "rustc не найден"
cargo --version 2>/dev/null || echo "cargo не найден"
printf 'Установлено пакетов librust-*-dev: '
dpkg-query -f '${binary:Package}\n' -W 'librust-*-dev' 2>/dev/null | wc -l
