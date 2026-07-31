#!/usr/bin/env bash
# diag-git.sh — почему `git --version` показывает старую версию.
# Запускать ОТ ТОГО ЖЕ пользователя и в ТОМ ЖЕ терминале, где версия старая:
#   bash install/diag-git.sh
# Ничего не меняет, только печатает. Вывод можно целиком приложить к вопросу.
p(){ printf '%-22s %s\n' "$1" "$2"; }

echo "=== 1. что запускается сейчас ==="
p USER "$(id -un)"
p SHELL "$SHELL  (логин-шелл: $(getent passwd "$(id -un)" | awk -F: '{print $7}'))"
p "git (command -v)" "$(command -v git 2>/dev/null || echo NONE)"
p "git --version" "$(git --version 2>/dev/null || echo NONE)"
echo
echo "все git в PATH, по порядку (выигрывает верхний):"
which -a git 2>/dev/null | while read -r g; do
    printf '  %-34s %s\n' "$g" "$("$g" --version 2>/dev/null || echo '(не запускается)')"
done

echo
echo "=== 2. что установлено ==="
for d in "$HOME/.local/git" /opt/astra-dev/git; do
    if [ -x "$d/bin/git" ]; then
        p "$d" "$("$d/bin/git" --version)"
        p "  git-remote-https" "$([ -x "$d/libexec/git-core/git-remote-https" ] \
            && echo 'есть (https работает)' || echo 'НЕТ — https-удалёнка не заработает')"
    else
        p "$d" "не установлен"
    fi
done
for l in "$HOME/.local/bin/git" /usr/local/bin/git; do
    [ -e "$l" ] || [ -L "$l" ] || continue
    p "$l" "→ $(readlink -f "$l" 2>/dev/null || echo '(битая ссылка)')"
done

echo
echo "=== 3. PATH этого терминала ==="
printf '%s\n' "$PATH" | tr ':' '\n' | nl -ba | sed 's/^/  /'
# Дубли — верный признак, что какой-то файл входа препендит каталог безусловно
# (например голая строка export PATH="$HOME/.local/bin:$PATH" от старой версии
# установщика). Сам по себе дубль безвреден, но показывает, где искать виновника.
dups="$(printf '%s\n' "$PATH" | tr ':' '\n' | sort | uniq -d)"
[ -n "$dups" ] && { echo; echo "  ! каталоги встречаются в PATH больше одного раза:"; \
    printf '%s\n' "$dups" | sed 's/^/      /'; }
# Каталог с нашим git обязан стоять раньше /usr/bin, иначе выигрывает системный.
echo
for d in "$HOME/.local/bin" /usr/local/bin; do
    [ -x "$d/git" ] || continue
    n_ours="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -nxF "$d"    | head -1 | cut -d: -f1)"
    n_usr="$( printf '%s\n' "$PATH" | tr ':' '\n' | grep -nxF /usr/bin | head -1 | cut -d: -f1)"
    if [ -z "$n_ours" ]; then
        echo "  ! $d вообще нет в PATH"
    elif [ -n "$n_usr" ] && [ "$n_ours" -gt "$n_usr" ]; then
        echo "  ! $d (#$n_ours) стоит ПОЗЖЕ /usr/bin (#$n_usr) — выигрывает системный git"
    else
        echo "  $d (#$n_ours) раньше /usr/bin (#${n_usr:-нет}) — ок"
    fi
done

echo
echo "=== 4. правки PATH в файлах входа ==="
# Порядок в списке — примерно порядок чтения. Ищем тех, кто препендит PATH ПОСЛЕ
# нашей правки: именно так /usr/bin оказывается впереди /usr/local/bin.
for f in /etc/environment /etc/profile /etc/bash.bashrc /etc/profile.d/*.sh \
         "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" "$HOME/.bashrc"; do
    [ -f "$f" ] || { p "$f" "нет файла"; continue; }
    p "$f" "$(grep -c 'astra-dev-setup PATH\|astra-dev-setup:' "$f" 2>/dev/null) наших строк-маркеров"
    grep -n 'PATH' "$f" 2>/dev/null | sed 's/^/    /'
done

echo
echo "=== 5. вывод ==="
# ~/.bash_profile перекрывает ~/.profile: bash читает только ПЕРВЫЙ найденный из
# .bash_profile / .bash_login / .profile. У давно заведённых пользователей он часто
# есть — тогда наш блок в ~/.profile не читается вовсе.
if [ -f "$HOME/.bash_profile" ] || [ -f "$HOME/.bash_login" ]; then
    echo "  ! Есть ~/.bash_profile (или ~/.bash_login) — bash в логин-шелле читает"
    echo "    ТОЛЬКО его, а ~/.profile игнорирует. Если он не подключает ~/.bashrc,"
    echo "    наш блок не выполняется. Проверь, что внутри есть:  . ~/.bashrc"
fi
real="$(command -v git 2>/dev/null)"
want=""
[ -x "$HOME/.local/git/bin/git" ] && want="$HOME/.local/git/bin/git"
[ -x /opt/astra-dev/git/bin/git ] && want=/opt/astra-dev/git/bin/git
if [ -n "$want" ] && [ -n "$real" ] && [ "$(readlink -f "$real")" != "$(readlink -f "$want")" ]; then
    echo "  ! Наш git установлен ($want), но выигрывает $real."
    echo "    Значит его каталог стоит в PATH позже. Проверь раздел 3 и 4 выше."
    echo "    Быстрая проверка, что дело именно в PATH:"
    echo "      $want --version"
elif [ -z "$want" ]; then
    echo "  ! Наш git не установлен у этого пользователя — запусти install-git.sh"
else
    echo "  Всё сходится: из PATH идёт наш git."
fi
