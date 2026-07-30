#!/usr/bin/env bash
# PATH пользовательской установки. Подключается точкой из установщиков:
#   . "$HERE/_path-setup.sh";  ensure_user_path;  verify_bin git ~/.local/bin/git
#
# Задача не «чтобы ~/.local/bin был в PATH», а «чтобы он был ПЕРВЫМ». Мы кладём
# туда git 2.55 рядом с системным /usr/bin/git (~2.20 в Astra 1.7), и выигрывает
# тот каталог, который стоит раньше. Дописывание в конец PATH ничего не меняет:
# `command -v git` по-прежнему отдаёт /usr/bin/git, а lazygit по-прежнему падает
# с «Git version must be at least 2.32.0».
#
# Правка помечена маркерами и перед записью удаляется целиком — повторный запуск
# установщика не плодит копии и подтягивает новую версию блока.

PATH_MARK_BEG='# >>> astra-dev-setup PATH >>>'
PATH_MARK_END='# <<< astra-dev-setup PATH <<<'

# Вписывает блок в ~/.bashrc и в ЛОГИН-файл и применяет его к PATH самого
# установщика (чтобы проверки ниже смотрели на итоговое состояние, а не на
# унаследованное). .bashrc — интерактивные шеллы; логин-файл — графическая
# сессия, откуда nvim запускают из меню и .bashrc не читается вовсе.
#
# Логин-файл нельзя жёстко брать как ~/.profile: bash в логин-шелле читает
# ТОЛЬКО ПЕРВЫЙ существующий из ~/.bash_profile, ~/.bash_login, ~/.profile и
# остальные игнорирует. У давно заведённых пользователей ~/.bash_profile обычно
# есть — и правка в ~/.profile у них просто не выполняется.
ensure_user_path() {
    local f login
    for login in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [ -f "$login" ] && break
    done                                  # если нет ни одного — создадим ~/.profile

    touch "$HOME/.bashrc" "$login"
    for f in "$HOME/.bashrc" "$login"; do
        if grep -qF "$PATH_MARK_BEG" "$f"; then
            # разделитель | — в самих маркерах есть '#'
            sed -i "\|^${PATH_MARK_BEG}\$|,\|^${PATH_MARK_END}\$|d" "$f"
        fi
        cat >> "$f" <<'EOF'
# >>> astra-dev-setup PATH >>>
# ~/.local/bin должен идти РАНЬШЕ /usr/bin: там наш git (lazygit требует >= 2.32,
# системный в Astra 1.7 — ~2.20), nvim, rust-analyzer, rg, fd, codelldb.
# Именно в начало: "$PATH:$HOME/.local/bin" задачу не решает.
case ":$PATH:" in
    ":$HOME/.local/bin:"*) ;;                   # уже первый — не трогаем
    *) PATH="$HOME/.local/bin:$PATH" ;;         # иначе в начало (дубль безвреден)
esac
export PATH
# <<< astra-dev-setup PATH <<<
EOF
    done

    case ":$PATH:" in
        ":$HOME/.local/bin:"*) ;;
        *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
    esac
    hash -r 2>/dev/null || true
}

# То же для системной установки: /usr/local/bin должен быть ПЕРВЫМ в PATH, а не
# просто присутствовать. Проверка «есть ли вообще» тут бесполезна — /etc/profile
# кладёт его почти всегда, и при порядке /usr/bin:/usr/local/bin выигрывает
# системный git 2.20. Пишем в /etc/profile.d, чтобы правило действовало для ВСЕХ
# пользователей: install-git.sh в режиме system чужие ~/.bashrc не трогает.
ensure_system_path() {
    cat > /etc/profile.d/astra-dev-path.sh <<'EOF'
# astra-dev-setup: /usr/local/bin строго первым (там наш git, nvim, rust-analyzer)
case ":$PATH:" in
    ":/usr/local/bin:"*) ;;
    *) PATH="/usr/local/bin:$PATH"; export PATH ;;
esac
EOF
    chmod 0644 /etc/profile.d/astra-dev-path.sh
    case ":$PATH:" in
        ":/usr/local/bin:"*) ;;
        *) PATH="/usr/local/bin:$PATH"; export PATH ;;
    esac
    hash -r 2>/dev/null || true
}
