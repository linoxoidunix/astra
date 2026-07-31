#!/usr/bin/env bash
# PATH установки. Подключается точкой из установщиков:
#   . "$HERE/_path-setup.sh";  ensure_user_path;  verify_bin git ~/.local/bin/git
#
# Задача не «чтобы наш каталог был в PATH», а «чтобы он был ПЕРВЫМ». Мы кладём
# туда git 2.55 рядом с системным /usr/bin/git (~2.20 в Astra 1.7), и выигрывает
# тот каталог, который стоит раньше. Дописывание в конец PATH ничего не меняет:
# `command -v git` по-прежнему отдаёт /usr/bin/git, а lazygit по-прежнему падает
# с «Git version must be at least 2.32.0».
#
# Почему «проверить и дописать, если ещё нет» — недостаточно (и откуда в PATH
# брались дубли вида .local/bin:/usr/bin:.local/bin:.cargo/bin:.local/bin):
#   * проверка «стоит ли каталог первым» ничего не гарантирует: она смотрит на
#     PATH В МОМЕНТ выполнения блока, а всё, что препендит PATH ПОСЛЕ него,
#     спокойно уезжает вперёд нас;
#   * ветка «иначе допишем в начало» срабатывала каждый раз, когда кто-то ещё
#     влез вперёд, и каталог добавлялся заново, не убирая прошлые вхождения.
# Поэтому теперь блок не проверяет, а НОРМАЛИЗУЕТ: пересобирает PATH так, что
# наш каталог первый, а каждый остальной встречается ровно один раз. Операция
# идемпотентна — сколько раз её ни выполни (вход в систему, вложенный `bash -l`,
# `su -`), PATH получается один и тот же.
PATH_MARK_BEG='# >>> astra-dev-setup PATH >>>'
PATH_MARK_END='# <<< astra-dev-setup PATH <<<'

# Имя со zz- не косметика: /etc/profile читает /etc/profile.d/*.sh в порядке
# glob, то есть по алфавиту. Файл astra-dev-path.sh шёл одним из первых, и любая
# чужая правка PATH после него (в Astra их хватает) уводила /usr/local/bin вниз.
SYSTEM_PATH_FILE=/etc/profile.d/zz-astra-dev-path.sh
SYSTEM_PATH_FILE_OLD=/etc/profile.d/astra-dev-path.sh

# --- нормализация PATH ------------------------------------------------------
# Ставит каталог первым и заодно схлопывает весь PATH: каждый каталог остаётся
# в одном экземпляре, на первой своей позиции. Поиск программы это не меняет
# (выигрывало и так первое вхождение), зато PATH перестаёт распухать от чужих
# безусловных препендов — тех самых лишних ~/.local/bin и ~/.cargo/bin.
# Реализация на ${var%%:*} без IFS и без sed: файлы входа читает и dash
# (/bin/sh), а трогать IFS в чужом окружении — напрашиваться на сюрпризы.
path_first() {
    local rest="$PATH" out="$1" p
    while [ -n "$rest" ]; do
        p="${rest%%:*}"
        if [ "$rest" = "$p" ]; then rest=""; else rest="${rest#*:}"; fi
        [ -n "$p" ] || continue
        case ":$out:" in *":$p:"*) continue ;; esac   # уже есть — не повторяем
        out="$out:$p"
    done
    PATH="$out"
    export PATH
}

# Тело правки для файла входа. $1 — каталог ЛИТЕРАЛОМ ('$HOME/.local/bin' пишем
# как есть, чтобы он раскрылся у пользователя, а не у того, кто ставил).
_path_block() {
    cat <<EOF
$PATH_MARK_BEG
# $1 должен идти РАНЬШЕ /usr/bin: там наш git (lazygit требует >= 2.32,
# системный в Astra 1.7 — ~2.20), nvim, rust-analyzer, rg, fd, codelldb.
# Не «добавить, если нет», а пересобрать PATH: каталог первым, дубли схлопнуть.
# Иначе каждый чужой безусловный препенд плодит ещё одну копию каталога, и
# PATH разрастается на каждом входе.
_astra_path_first() {
    _rest="\$PATH"; _out="\$1"
    while [ -n "\$_rest" ]; do
        _p="\${_rest%%:*}"
        if [ "\$_rest" = "\$_p" ]; then _rest=""; else _rest="\${_rest#*:}"; fi
        [ -n "\$_p" ] || continue
        case ":\$_out:" in *":\$_p:"*) continue ;; esac
        _out="\$_out:\$_p"
    done
    PATH="\$_out"
    export PATH
    unset _rest _out _p
}
_astra_path_first "$1"
unset -f _astra_path_first
$PATH_MARK_END
EOF
}

# Убирает нашу правку из файла: блок между маркерами плюс голые строки, которые
# дописывали ранние версии установщика (маркеров тогда не было). Их-то и видно в
# PATH лишними копиями ~/.local/bin: чистка по маркерам их не замечала, а сами
# строки препендят каталог безусловно, при каждом входе.
_strip_our_path_edits() {
    local f="$1"
    [ -f "$f" ] || return 0
    # разделитель | — в самих маркерах есть '#'
    sed -i "\\|^${PATH_MARK_BEG}\$|,\\|^${PATH_MARK_END}\$|d" "$f"
    sed -i '\|^[[:space:]]*export PATH="\$HOME/\.local/bin:\$PATH"[[:space:]]*$|d' "$f"
}

# --- пользовательская установка ---------------------------------------------
# Вписывает блок в ~/.bashrc и в ЛОГИН-файл и применяет его к PATH самого
# установщика (чтобы проверки ниже смотрели на итоговое состояние, а не на
# унаследованное). .bashrc — интерактивные шеллы; логин-файл — графическая
# сессия, откуда nvim запускают из меню и .bashrc не читается вовсе.
#
# Логин-файл нельзя жёстко брать как ~/.profile: bash в логин-шелле читает
# ТОЛЬКО ПЕРВЫЙ существующий из ~/.bash_profile, ~/.bash_login, ~/.profile и
# остальные игнорирует. У давно заведённых пользователей ~/.bash_profile обычно
# есть — и правка в ~/.profile у них просто не выполняется.
#
# Блок дописывается в КОНЕЦ файла намеренно: так он выполняется после всех
# правок PATH, которые в этом файле уже есть (в т.ч. после `. ~/.bashrc` и
# после дебиановского «if [ -d "$HOME/.local/bin" ]» в ~/.profile).
ensure_user_path() {
    local f login found=""
    for login in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [ -f "$login" ]; then found=1; break; fi
    done
    [ -n "$found" ] || login="$HOME/.profile"   # нет ни одного — заведём ~/.profile

    touch "$HOME/.bashrc" "$login"
    for f in "$HOME/.bashrc" "$login"; do
        _strip_our_path_edits "$f"
        _path_block '$HOME/.local/bin' >> "$f"
    done

    path_first "$HOME/.local/bin"
    hash -r 2>/dev/null || true
}

# --- системная установка ----------------------------------------------------
# То же для всех пользователей: /usr/local/bin должен быть ПЕРВЫМ, а не просто
# присутствовать. Проверка «есть ли вообще» тут бесполезна — /etc/profile кладёт
# его почти всегда, и при порядке /usr/bin:/usr/local/bin выигрывает системный
# git 2.20. Пишем в /etc/profile.d, чтобы правило действовало для ВСЕХ:
# install-git.sh в режиме system чужие ~/.bashrc не трогает.
ensure_system_path() {
    rm -f "$SYSTEM_PATH_FILE_OLD"       # старое имя читалось слишком рано
    {
        printf '# astra-dev-setup: /usr/local/bin строго первым (там наш git, nvim, rust-analyzer).\n'
        printf '# Имя со zz-: /etc/profile.d/*.sh читается по алфавиту, нам нужно последними.\n'
        _path_block '/usr/local/bin'
    } > "$SYSTEM_PATH_FILE"
    chmod 0644 "$SYSTEM_PATH_FILE"

    path_first /usr/local/bin
    hash -r 2>/dev/null || true
}
