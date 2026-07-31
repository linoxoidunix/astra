#!/usr/bin/env bash
# fix-dpkg.sh — привести в порядок dpkg, когда apt на Astra падает на ЧУЖОМ
# пакете и из-за этого не даёт поставить ничего.
#
#   bash install/fix-dpkg.sh                # показать, что сломано (без изменений)
#   sudo bash install/fix-dpkg.sh --fix     # чинить, спрашивая на каждый шаг
#   sudo bash install/fix-dpkg.sh --fix --yes   # чинить без вопросов
#
# Комплекта astra-dev-setup скрипт не касается: он чинит состояние системного
# dpkg. Симптом, ради которого он написан:
#
#   ERROR: Module mpm_event is enabled - cannot proceed due to conflicts.
#           It needs to be disabled first!
#   dpkg: ошибка при обработке пакета apache2 (--configure):
#    installed apache2 package post-installation script subprocess returned
#    error exit status 1
#   ls: невозможно получить доступ к '/etc/X11/trusted.d/*': Нет такого файла
#   needrestart is being skipped since dpkg has failed
#   E: Sub-process /usr/bin/dpkg returned an error code (1)
#
# Что здесь происходит: dpkg настраивает пакеты по очереди, и один упавший
# postinst обрывает всю транзакцию. apt возвращает 1, даже если запрошенные
# пакеты уже распакованы и настроены. Дальше хуже: перед КАЖДОЙ следующей
# установкой apt сначала доводит до ума недонастроенное — и снова спотыкается о
# тот же apache2. Пока это не разобрано, apt непригоден к работе целиком.
set -uo pipefail

FIX=0; YES=0
for a in "$@"; do
    case "$a" in
        --fix)     FIX=1 ;;
        --yes|-y)  YES=1 ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "неизвестный аргумент: $a (см. --help)"; exit 2 ;;
    esac
done

# Права нужны только для правок. Без --fix скрипт ничего не меняет и прекрасно
# работает от обычного пользователя — с него и стоит начинать.
if [ "$FIX" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Пакеты, которые dpkg не довёл до конца: half-configured, half-installed,
# unpacked, triggers-awaited/pending. Поля ${Status} — «want flag status»,
# то есть $2 $3 $4. Нормальное состояние установленного — «install ok installed»;
# удалённый с конфигами («deinstall ok config-files») к поломкам не относится.
dpkg_broken() {
    dpkg-query -f '${Package} ${Status}\n' -W 2>/dev/null \
        | awk '$3 != "ok" || ($2 == "install" && $4 != "installed") { print $1 }'
}

# Согласие спрашиваем на каждую правку отдельно: часть из них меняет чужие
# службы, и «починить apt» не равно «разрешить трогать apache2».
confirm() {
    [ "$YES" -eq 1 ] && return 0
    local ans
    printf '    выполнить? [д/N] '
    read -r ans </dev/tty 2>/dev/null || return 1
    case "$ans" in [ДдYy]*) return 0 ;; *) return 1 ;; esac
}

# step "пояснение" команда...   — в режиме показа только печатает команду
step() {
    printf '    %s\n      %s\n' "$1" "${*:2}"
    if [ "$FIX" -eq 0 ]; then
        printf '    (показ; чинить — запусти с --fix)\n'
        return 0
    fi
    if confirm; then
        if "${@:2}"; then printf '    ok\n'; else printf '    НЕ УДАЛОСЬ\n'; fi
    else
        printf '    пропущено\n'
    fi
}

# --- 1. что сломано ---------------------------------------------------------
say "Состояние dpkg"
command -v dpkg-query >/dev/null 2>&1 || {
    echo "  dpkg на этой машине нет — скрипт для Astra/Debian"; exit 2; }
BAD="$(dpkg_broken)"
if [ -z "$BAD" ]; then
    echo "  все пакеты настроены — чинить нечего"
    echo "  (если apt всё равно ругается, покажи его вывод целиком)"
    exit 0
fi
echo "  незавершённые пакеты:"
for pkg in $BAD; do
    printf '    %-28s %s\n' "$pkg" "$(dpkg-query -f '${Status}' -W "$pkg" 2>/dev/null)"
done

# --- 2. известные поломки Astra ---------------------------------------------
say "Известные причины"
KNOWN=0

# Триггер xserver-xorg-core ищет каталог, которого в системе нет:
#   ls: невозможно получить доступ к '/etc/X11/trusted.d/*'
# Сам триггер от этого не падает, но шум мешает читать вывод apt, а каталог
# пустой и ни на что больше не влияет.
if [ ! -d /etc/X11/trusted.d ]; then
    KNOWN=1
    echo
    echo "  * нет /etc/X11/trusted.d — триггер xserver-xorg-core сыплет ошибкой ls"
    step "создать пустой каталог:" mkdir -p /etc/X11/trusted.d
fi

# apache2: его postinst включает MPM, которого требуют модули (обычно
# mpm_prefork для mod_php), а включённый mpm_event этого не даёт. Выключение
# mpm_event МЕНЯЕТ модель обработки запросов apache2 — если веб-сервер боевой,
# решать должен его администратор, поэтому только с явного согласия.
if printf '%s\n' "$BAD" | grep -qx apache2; then
    KNOWN=1
    echo
    echo "  * apache2 не настраивается: конфликт MPM"
    if [ -e /etc/apache2/mods-enabled/mpm_event.load ]; then
        echo "    ВНИМАНИЕ: mpm_event выключится, apache2 сменит модель обработки запросов."
        echo "    Боевой сервер — не соглашайся, позови его администратора."
        step "выключить mpm_event, чтобы postinst смог включить нужный MPM:" \
            a2dismod mpm_event
    else
        echo "    mpm_event не включён — причина другая, смотри вывод dpkg --configure -a"
    fi
fi

[ "$KNOWN" -eq 0 ] && echo "  ни одна из известных причин не подошла — лечим общим способом"

# --- 3. добить очередь ------------------------------------------------------
say "Донастройка отложенных пакетов"
if [ "$FIX" -eq 0 ]; then
    echo "    (показ) sudo dpkg --configure -a"
    echo "    (показ) sudo apt-get -f install"
else
    dpkg --configure -a
    apt-get -f install -y
fi

# --- 4. итог ----------------------------------------------------------------
say "Итог"
if [ "$FIX" -eq 0 ]; then
    echo "  Ничего не менялось. Чинить:  sudo bash install/fix-dpkg.sh --fix"
    exit 1
fi
BAD2="$(dpkg_broken)"
if [ -z "$BAD2" ]; then
    echo "  dpkg в порядке — apt больше не будет возвращать ошибку из-за этого"
    exit 0
fi
echo "  остались незавершёнными:"
printf '%s\n' "$BAD2" | sed 's/^/    /'
cat <<'EOF'

  Конкретный упавший postinst виден в выводе dpkg --configure -a выше — дальше
  разбираться с этим пакетом отдельно, к комплекту он отношения не имеет.
  Крайний случай, когда пакет не нужен и мешает:
      sudo dpkg --remove --force-remove-reinstreq <пакет>
EOF
exit 1
