#!/usr/bin/env bash
# build-registry.sh — собирает ОБЪЕДИНЁННЫЙ офлайн-реестр cargo из нескольких
# наборов крейтов симлинками в один directory-source. Проект видит крейты из
# всех наборов через одну подмену crates.io.
#
# Наборы: debian-реестр (librust-*-dev, /usr/share/cargo/registry, если есть)
#         + любые vendor-каталоги ИЛИ cargo-vendor.tar.gz, переданные аргументами.
#
# Запуск (для /opt нужен root — поднимет сам):
#   bash install/build-registry.sh <vendor-dir | cargo-vendor.tar.gz> [...]
# Примеры:
#   bash install/build-registry.sh dist/cargo-vendor.tar.gz      # из Release-ассета
#   bash install/build-registry.sh ~/crate-vendor/vendor         # из каталога
#
# Результат:
#   каталог  $REGISTRY                (по умолчанию /opt/astra-dev/cargo-registry)
#   конфиг   $REGISTRY.config.toml    (готовый [source]-блок для ~/.cargo/config.toml)
set -uo pipefail

REGISTRY="${REGISTRY:-/opt/astra-dev/cargo-registry}"
DEBIAN_REG="${DEBIAN_REG:-/usr/share/cargo/registry}"

# --- повышение прав, если каталог назначения не писабелен ------------------
mkdir -p "$(dirname "$REGISTRY")" 2>/dev/null || true
if [ ! -w "$(dirname "$REGISTRY")" ]; then
    exec sudo -E bash "$0" "$@"
fi

log(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }
abs(){ (cd "$1" 2>/dev/null && pwd); }

# --- собрать список наборов (в абсолютных путях) ---------------------------
# .tar.gz-ассеты распаковываются сюда:
EXTRACT_ROOT="${EXTRACT_ROOT:-$(dirname "$REGISTRY")/vendor}"

SOURCES=()
[ -d "$DEBIAN_REG" ] && SOURCES+=("$(abs "$DEBIAN_REG")")
for v in "$@"; do
    case "$v" in
        *.tar.gz|*.tgz)
            if [ -f "$v" ]; then
                d="$EXTRACT_ROOT/$(basename "$v" | sed 's/\.\(tar\.gz\|tgz\)$//')"
                rm -rf "$d"; mkdir -p "$d"
                tar xzf "$v" -C "$d"
                if [ -d "$d/vendor" ]; then SOURCES+=("$(abs "$d/vendor")"); else SOURCES+=("$(abs "$d")"); fi
            else echo "!! пропуск (нет архива): $v"; fi
            ;;
        *)
            a="$(abs "$v")"
            if [ -n "$a" ]; then SOURCES+=("$a"); else echo "!! пропуск (нет каталога): $v"; fi
            ;;
    esac
done

if [ "${#SOURCES[@]}" -eq 0 ]; then
    echo "Нет ни одного набора крейтов. Укажи vendor-каталог(и) аргументом"
    echo "(и/или должен существовать debian-реестр $DEBIAN_REG)."
    exit 1
fi

log "Объединённый реестр: $REGISTRY"
echo "Наборы:"; printf '  - %s\n' "${SOURCES[@]}"

# --- пересборка симлинков (идемпотентно) -----------------------------------
rm -rf "$REGISTRY"; mkdir -p "$REGISTRY"
linked=0; dup=0; conflict=0
for src in "${SOURCES[@]}"; do
    for dir in "$src"/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        dst="$REGISTRY/$name"
        if [ -e "$dst" ]; then
            if [ -f "$dir/.cargo-checksum.json" ] && [ -f "$dst/.cargo-checksum.json" ] \
               && ! cmp -s "$dir/.cargo-checksum.json" "$dst/.cargo-checksum.json"; then
                echo "  !! КОНФЛИКТ (разные checksum, оставлен первый): $name"
                conflict=$((conflict+1))
            else
                dup=$((dup+1))
            fi
            continue
        fi
        ln -s "${dir%/}" "$dst" && linked=$((linked+1))
    done
done
log "Слинковано: $linked, дублей пропущено: $dup, конфликтов: $conflict"

# --- готовый конфиг --------------------------------------------------------
CFG="$REGISTRY.config.toml"
cat > "$CFG" <<EOF
# Объединённый офлайн-реестр cargo (debian librust-*-dev + vendor-наборы).
# Подменяет crates.io на объединённый каталог симлинков.
[source.crates-io]
replace-with = "combined"

[source.combined]
directory = "$REGISTRY"
EOF

log "Готово. Крейтов в реестре: $(find "$REGISTRY" -maxdepth 1 -mindepth 1 | wc -l)"
cat <<EOF

Применить для текущего пользователя:
  cp "$CFG" ~/.cargo/config.toml
Для всех (если ставился install-system.sh):
  cp "$CFG" /opt/astra-dev/skel/.cargo/config.toml   # засев новым пользователям
Затем в проекте:
  cargo build --offline
EOF
