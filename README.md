# astra-dev-setup

Полная **офлайн**-интеграция Neovim (LazyVim) + Rust + C++ для **Astra Linux 1.7** (glibc 2.28).

Готовые бинарники под старый glibc собираются на машине с интернетом в контейнере
**Debian Buster (glibc 2.28)**, затем ставятся на офлайн-Astra одним скриптом.

## Что ставится
| Компонент | Как |
|---|---|
| Neovim (последний) | собирается под glibc 2.28 |
| LazyVim + плагины (rust, clangd, cmake) | клон на этапе сборки |
| rust-analyzer (Rust LSP) | собирается из исходников |
| treesitter-парсеры (rust/cpp/c/…) | компилятся tree-sitter CLI под 2.28 |
| JetBrainsMono Nerd Font | из nerd-fonts |
| офлайн-конфиг cargo | крейты из `librust-*-dev` |

**C++ LSP (clangd)** ставится штатным `apt` на самой Astra (`clangd-19` есть в репозитории).

## Использование

### 1. Сборка бандла — на машине с интернетом (podman или docker)
```bash
./build/build-all.sh            # → dist/
# ENGINE=docker ./build/build-all.sh
```
Долго: собираются Neovim, rust-analyzer, tree-sitter CLI, парсеры. Результат — `dist/`:
`nvim.tar.gz`, `bin/rust-analyzer`, `lazyvim-config.tar.gz`, `lazyvim-data.tar.gz`,
`fonts.tar.gz`.

> Для «скачал с GitHub и поставил» без пересборки — выложи содержимое `dist/`
> в **GitHub Release** и клади рядом с репозиторием перед `install.sh`.

### 2. Перенос на Astra
Скопировать репозиторий вместе с `dist/` на Astra (scp / USB).

### 3. Установка на Astra (офлайн)
```bash
bash install/install.sh
```
Затем руками (см. вывод скрипта):
- `sudo apt install -y clangd-19 && sudo ln -sf "$(command -v clangd-19)" /usr/local/bin/clangd`
- в терминале выбрать шрифт **JetBrainsMono Nerd Font Mono**
- открыть новый терминал → `nvim`

## Проверка
```bash
nvim --version
rust-analyzer --version
cd <rust-проект> && nvim src/main.rs   # rust-analyzer подцепится
nvim file.cpp                          # clangd подцепится
```

## Заметки
- Всё, что требует свежего glibc/интернета, собирается в Buster-контейнере —
  готовые сборки Neovim/rust-analyzer с GitHub требуют glibc ≥ 2.31 и на Astra 2.28 не идут.
- podman: контейнер запускается с `--network=host` (иначе из NAT-контейнера не виден
  прокси), ro-монтирования — с меткой `:z`/`:Z` (SELinux на Fedora).
- Rust-проекты собираются офлайн из `librust-*-dev` через `~/.cargo/config.toml`.
