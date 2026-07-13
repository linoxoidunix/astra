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
| крейты не из Astra (tokio…) | вендор + объединённый реестр (`build-vendor.sh` / `build-registry.sh`) |

**C++ LSP (clangd)** ставится штатным `apt` на самой Astra. Версия зависит от машины
(напр. `clangd-15`) — доступную ищи через `apt-cache search clangd`.

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
- C++ LSP (версия зависит от машины — сперва `apt-cache search clangd`):
  ```bash
  sudo apt install -y clangd-15    # подставь найденную версию
  sudo ln -sf "$(command -v clangd-15 || command -v clangd)" /usr/local/bin/clangd
  ```
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

### 5. Крейты, которых нет в `librust-*-dev` (напр. tokio) — офлайн

Часть крейтов (например `tokio`) в репозиториях Astra отсутствует. Их исходники
вендорятся и раздаются офлайн, а на Astra **сливаются с debian-реестром в один
объединённый** cargo-реестр — проект видит крейты из обоих.

Раскладка **раздельная**:
- **исходники** крейтов → `cargo/vendor/` (в git, ~25 МБ чистого текста);
- бинарные **`windows-*`** крейты → `dist/cargo-vendor-win.tar.gz` (в Release).
  Их нельзя выкинуть — cargo требует их и на Linux (cfg-зависимости), но это
  import-либы `.a`/`.lib`, поэтому едут не в git, а в Release.

**Пересобрать набор** (на машине с интернетом, нужен `cargo`/rustup):
```bash
./build/build-vendor.sh                            # tokio/full
./build/build-vendor.sh tokio/full serde/derive    # свой список <crate>/<features>
```
Обновит `cargo/vendor/` (закоммить) и `dist/cargo-vendor-win.tar.gz` (в Release).
Версии — под MSRV Astra (`RUST_VERSION`, по умолчанию `1.70`).

**Развернуть на Astra:**
```bash
# исходники приезжают с git clone (cargo/vendor/); windows-часть — из Release:
gh release download v0.1.0 --repo <you>/<repo> -p 'cargo-vendor-win.tar.gz' -D dist/
# слить обе части + debian-реестр в объединённый реестр:
sudo bash install/build-registry.sh cargo/vendor dist/cargo-vendor-win.tar.gz
cp /opt/astra-dev/cargo-registry.config.toml ~/.cargo/config.toml
```
После этого в проекте:
```bash
cargo build --offline          # tokio = { version = "1.47", features = ["full"] }
```
`build-registry.sh` принимает несколько наборов (каталоги и/или `.tar.gz`), считает
дубли и конфликты версий.

## Разворачивание на Astra (всё по порядку)

Репозиторий вместе с `dist/` уже перенесён на Astra (см. п.1–2). Дальше — одна
последовательность от начала до рабочего окружения:

```bash
cd astra    # каталог с репозиторием и dist/

# 1) Neovim + LazyVim + плагины + rust-analyzer + парсеры + шрифт
bash install/install.sh                 # для текущего пользователя ($HOME)
#   или на всю машину:  sudo bash install/install-system.sh

# 2) C++ LSP (clangd) — версия своя на каждой машине
apt-cache search clangd                 # посмотреть доступную
sudo apt install -y clangd-15           # подставить найденную версию
sudo ln -sf "$(command -v clangd-15 || command -v clangd)" /usr/local/bin/clangd

# 3) Rust-тулчейн + системные крейты librust-*-dev
bash install/install-rust.sh popular    # all | popular | none

# 4) Внешние крейты (tokio и пр.) → объединённый офлайн-реестр cargo.
#    cargo-vendor-win.tar.gz уже в dist/ (приехал с бандлом), исходники — в cargo/vendor/
sudo bash install/build-registry.sh cargo/vendor dist/cargo-vendor-win.tar.gz
cp /opt/astra-dev/cargo-registry.config.toml ~/.cargo/config.toml

# 5) открыть НОВЫЙ терминал (обновится PATH), выбрать шрифт
#    "JetBrainsMono Nerd Font Mono", запустить:
nvim
```

Что нужно от sudo: п.2 (clangd), п.3 (`apt`), п.4 (`/opt`). Пункты 1 и итоговый
`nvim` — без прав root. При установке `install-system.sh` config+плагины LazyVim
засеются каждому пользователю при первом запуске `nvim`.

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
- Крейты, которых нет в `librust-*-dev` (tokio и т.п.), вендорятся исходниками и
  сливаются с debian-реестром в один directory-source (`install/build-registry.sh`).
  Пруним `windows-*` из vendor **нельзя** — cargo требует их и на Linux (cfg-зависимости).
