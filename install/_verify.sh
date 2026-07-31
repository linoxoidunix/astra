#!/usr/bin/env bash
# Проверки после установки. Подключается точкой из установщиков:
#   . "$HERE/_verify.sh";  verify_bin git ~/.local/git/bin/git;  verify_git_transport

# Проверяет, что из PATH запускается именно наш бинарь, а не системный. Молча
# при успехе; при расхождении показывает, кто перекрывает и чем это лечится —
# иначе установка «проходит успешно», а версия остаётся старой.
# Третий аргумент noexec — не запускать бинарь ради версии. Нужен для обёртки
# /usr/local/bin/nvim: она при ЛЮБОМ запуске засевает LazyVim в $HOME, а от root
# это разложило бы конфиг и плагины в /root.
verify_bin() {
    local name="$1" want="$2" mode="${3:-}" got ver
    got="$(command -v "$name" 2>/dev/null || true)"

    if [ -z "$got" ]; then
        printf '  ! %s не найден в PATH (ожидался %s)\n' "$name" "$want"
        return 1
    fi
    [ "$mode" = noexec ] && ver='' || ver="$("$got" --version 2>/dev/null | head -1)"

    # сравниваем по разыменованному пути: got — обычно симлинк на want
    if [ "$got" -ef "$want" ] || [ "$(readlink -f "$got")" = "$(readlink -f "$want")" ]; then
        printf '  %s → %s  %s\n' "$name" "$got" "${ver:+[$ver]}"
        return 0
    fi

    printf '\n  ! %s из PATH — это %s, а не наш %s\n' "$name" "$got" "$want"
    [ -n "$ver" ] && printf '    версия: %s\n' "$ver"
    printf '    перекрывают (which -a):\n'
    which -a "$name" 2>/dev/null | sed 's/^/      /'
    printf '    порядок PATH (выигрывает верхний):\n'
    printf '%s\n' "$PATH" | tr ':' '\n' | nl -ba | sed 's/^/      /'
    printf '    Значит наш каталог в PATH позже — кто-то препендит PATH после нашей правки.\n'
    printf '    Найти виновника:  bash install/diag-git.sh   (разделы 3 и 4)\n\n'
    return 1
}

# Проверяет, что наш git умеет ходить по https. Симптом при поломке:
#   fatal: Unable to find remote helper for 'https'
# — git собран без libcurl (NO_CURL) и не получил git-remote-https; либо helper
# есть, но на машине нет libcurl.so.4. Ни fetch, ни push по https не работают,
# при этом ssh- и локальные удалёнки работают, поэтому проблему легко не заметить.
verify_git_transport() {
    local gitdir="$1" helper="$1/libexec/git-core/git-remote-https" miss

    if [ ! -x "$helper" ]; then
        printf '\n  ! git собран без git-remote-https — https-удалёнки работать не будут:\n'
        printf '      fatal: Unable to find remote helper for %s\n' "'https'"
        printf '    Пересобери комплект: в контейнере нужен libcurl4-openssl-dev.\n'
        printf '    Пока не пересобран — используй ssh-удалёнку:\n'
        printf '      git remote set-url origin git@<хост>:<группа>/<репо>.git\n\n'
        return 1
    fi

    miss="$(ldd "$helper" 2>/dev/null | awk '/not found/{print $1}')"
    if [ -n "$miss" ]; then
        printf '\n  ! git-remote-https не запускается — нет библиотек:\n'
        printf '%s\n' "$miss" | sed 's/^/      /'
        printf '    Поставь их из репозитория Astra, например:  sudo apt install -y libcurl4\n\n'
        return 1
    fi

    printf '  https-транспорт: ok (%s)\n' \
        "$(ldd "$helper" 2>/dev/null | grep -o 'libcurl[^ ]*' | head -1)"
    return 0
}
