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
| treesitter-парсеры (rust/cpp/c/cmake/…) | компилятся из грамматик под 2.28 |
| JetBrainsMono Nerd Font | из nerd-fonts |
| офлайн-конфиг cargo | крейты из `librust-*-dev` |

**C++ LSP (clangd)** ставится штатным `apt` на самой Astra (`clangd-19` есть в репозитории).

## Использование

### 1. Получить бандл `dist/`

Установщики читают собранный бандл из каталога `dist/`. Его либо **скачиваешь из
GitHub Release** (готовое, ничего собирать не надо), либо **собираешь сам**.

Раскладка, которую ждут скрипты (5 архивов — в `dist/`, `rust-analyzer` — в `dist/bin/`):

```
astra/
└── dist/
    ├── nvim.tar.gz
    ├── lazyvim-config.tar.gz
    ├── lazyvim-data.tar.gz
    ├── fonts.tar.gz
    ├── parsers.tar.gz
    └── bin/
        └── rust-analyzer
```

**Вариант A — скачать из Release** (на машине с интернетом):
```bash
git clone https://github.com/linoxoidunix/astra.git
cd astra
mkdir -p dist/bin
gh release download v0.1.0 --repo linoxoidunix/astra -p '*.tar.gz'      -D dist/
gh release download v0.1.0 --repo linoxoidunix/astra -p 'rust-analyzer' -D dist/bin/
```
Без `gh` — через `curl`:
```bash
mkdir -p dist/bin
base=https://github.com/linoxoidunix/astra/releases/download/v0.1.0
for f in nvim lazyvim-config lazyvim-data fonts parsers; do
  curl -fL -o dist/$f.tar.gz $base/$f.tar.gz
done
curl -fL -o dist/bin/rust-analyzer $base/rust-analyzer && chmod +x dist/bin/rust-analyzer
```

**Вариант B — собрать самому** (нужны podman или docker + интернет):
```bash
./build/build-all.sh            # → dist/
# ENGINE=docker ./build/build-all.sh
```
Долго: собираются Neovim, rust-analyzer, парсеры. Результат — тот же `dist/`.

### 2. Перенос на Astra
Скопировать репозиторий **вместе с `dist/`** на Astra (scp / USB).

### 3. Установка на Astra (офлайн)

Для текущего пользователя (без sudo, ставит в `$HOME`):
```bash
bash install/install.sh
```
Либо на всю машину, для всех пользователей (sudo; разделяемое — в `/usr/local`
и `/opt/astra-dev`, config+плагины засеваются каждому при первом запуске `nvim`):
```bash
sudo bash install/install-system.sh
```

Затем руками (см. вывод скрипта):
- `sudo apt install -y clangd-19 && sudo ln -sf "$(command -v clangd-19)" /usr/local/bin/clangd`
- в терминале выбрать шрифт **JetBrainsMono Nerd Font Mono**
- открыть новый терминал → `nvim`

### 4. Rust-тулчейн из репозиториев Astra (онлайн, sudo)
Отдельный скрипт ставит `rustc`/`cargo` и крейты `librust-*-dev` штатным `apt`
(права поднимает сам через `sudo`):
```bash
bash install/install-rust.sh            # тулчейн + ВСЕ librust-*-dev
bash install/install-rust.sh popular    # типовой набор крейтов
bash install/install-rust.sh none       # только тулчейн, без крейтов
```

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
