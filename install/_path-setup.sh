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

# Вписывает блок в ~/.bashrc и ~/.profile и применяет его к PATH самого
# установщика (чтобы проверки ниже смотрели на итоговое состояние, а не на
# унаследованное). .bashrc — интерактивные и (через дебиановский .profile)
# логин-шеллы; .profile — не-bash логин-шеллы и графическая сессия, откуда
# nvim запускают из меню и .bashrc не читается вовсе.
ensure_user_path() {
    local f
    touch "$HOME/.bashrc"
    for f in "$HOME/.bashrc" "$HOME/.profile"; do
        [ -f "$f" ] || continue          # .profile не создаём, если его нет
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
