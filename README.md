# astra-dev-setup

Полная **офлайн**-интеграция Neovim (LazyVim) + Rust + C++ для **Astra Linux 1.7** (glibc 2.28).

Готовые бинарники под старый glibc собираются на машине с интернетом в контейнере
**Debian Buster (glibc 2.28)**, затем ставятся на офлайн-Astra одним скриптом.

## Что ставится
| Компонент | Как |
|---|---|
| Neovim (последний) | собирается под glibc 2.28 |
| LazyVim + плагины (rust, clangd, cmake, typescript) | клон на этапе сборки |
| rust-analyzer (Rust LSP) | собирается из исходников |
| Node.js 20 + vtsls (TS/JS LSP) | Node LTS под glibc 2.28 + `npm i` vtsls/typescript |
| treesitter-парсеры (rust/cpp/c/cmake/js/ts/tsx/…) | компилятся из грамматик под 2.28 |
| JetBrainsMono Nerd Font | из nerd-fonts |
| офлайн-конфиг cargo | крейты из `librust-*-dev` |
| крейты не из Astra (tokio…) | вендор + объединённый реестр (`build-vendor.sh` / `build-registry.sh`) |

**C++ LSP (clangd)** ставится штатным `apt` на самой Astra. Версия зависит от машины
(напр. `clangd-15`) — доступную ищи через `apt-cache search clangd`.

## Использование

### 1. Получить бандл `dist/`

Установщики читают собранный бандл из каталога `dist/`. Его либо **скачиваешь из
GitHub Release** (готовое, ничего собирать не надо), либо **собираешь сам**.

Раскладка, которую ждут скрипты (5 архивов — в `dist/`, бинарники — в `dist/bin/`):

```
astra/
└── dist/
    ├── nvim.tar.gz
    ├── node.tar.gz            # Node.js 20 (для TS/JS LSP)
    ├── ts-lsp.tar.gz          # vtsls + typescript
    ├── lazyvim-config.tar.gz
    ├── lazyvim-data.tar.gz
    ├── fonts.tar.gz
    ├── parsers.tar.gz
    └── bin/
        ├── rust-analyzer
        ├── rg                 # ripgrep — греп в пикере (<leader>sg/sG)
        └── fd                 # поиск файлов в пикере (<leader>ff)
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

## Обновление уже установленной машины (точечно)

Если комплект уже стоит и надо доставить/обновить только часть (например добавить
JS/TS), НЕ гоняй установку с нуля. `install/install.sh` — деструктивный полный
установщик (стирает и перезаписывает `~/.config/nvim` и данные nvim). Вместо него
качай из Release только изменившиеся ассеты и раскладывай точечно.

**На машине с интернетом** — обновить репозиторий и скачать нужные ассеты в `dist/`:
```bash
cd astra && git pull
gh release download v0.1.0 --repo linoxoidunix/astra --clobber -D dist/ \
  -p 'node.tar.gz' -p 'ts-lsp.tar.gz' \
  -p 'lazyvim-config.tar.gz' -p 'lazyvim-data.tar.gz' -p 'parsers.tar.gz'
```
(набор `-p` — то, что реально поменялось; для JS/TS это эти пять). Перенести `astra/`
на целевую машину.

**На целевой машине** — два шага:
```bash
cd ~/astra

# 1) бинарники Node + vtsls (инкрементально, ничего не сносит)
bash install/install-ts.sh              # или: sudo bash install/install-ts.sh system

# 2) редакторная часть LazyVim: config + плагины + парсеры.
#    ВНИМАНИЕ: перезаписывает ~/.config/nvim (правил руками — сделай бэкап).
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
tar xzf dist/lazyvim-config.tar.gz -C ~/.config
tar xzf dist/lazyvim-data.tar.gz   -C ~/.local/share
mkdir -p ~/.config/nvim/parser && tar xzf dist/parsers.tar.gz -C ~/.config/nvim/parser
```
`install-ts.sh` сам по себе ставит **только** Node + vtsls; редакторная интеграция
(typescript-extra в конфиге, плагины, парсеры js/ts) — это шаг 2. Не трогаются
`nvim`-бинарь, `rust-analyzer`, шрифты, clangd, Rust-тулчейн и cargo-реестр —
их повторять не нужно.

### ripgrep + fd (греп и поиск файлов в пикере)

Если в пикере греп падает с `Failed to spawn rg` — на машине нет `rg`. Это признак
бандла, собранного до появления шага с ripgrep/fd. Пересобирать весь `dist/` не надо:
это готовые static-musl бинарники, они не зависят от glibc и никак не связаны с
контейнерной сборкой.

**На машине с интернетом** — положить их в `dist/bin/`:
```bash
curl -fsSL https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz \
  | tar xz -O --wildcards '*/rg' > dist/bin/rg
curl -fsSL https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-unknown-linux-musl.tar.gz \
  | tar xz -O --wildcards '*/fd' > dist/bin/fd
chmod +x dist/bin/rg dist/bin/fd
```
Перенести `astra/` на целевую машину (или просто скопировать туда эти два файла).

**На целевой машине:**
```bash
bash install/install-tools.sh              # или: sudo bash install/install-tools.sh system
```
Скрипт инкрементальный — кладёт `rg` и `fd` в `~/.local/bin` (или `/usr/local/bin`
в режиме `system`) и больше ничего не трогает. Если каталог уже был в `PATH`
запущенного nvim, греп заработает без перезапуска (он спавнит `rg` заново на каждый
ввод); если `PATH` дописывался в `~/.bashrc` только что — нужен новый терминал.

### Правка конфига LazyVim для всех пользователей

Конфиг у каждого пользователя **свой** (`~/.config/nvim`): `install-system.sh` держит
эталон в `/opt/astra-dev/skel`, а wrapper `/usr/local/bin/nvim` копирует его в `$HOME`
при **первом** запуске nvim. Отсюда три разных случая для любой правки конфига.

**1. Машина ставится с нуля** — ничего делать не надо, правка должна быть в
`build/_in-container.sh` (там генерится `lua/plugins/*.lua`) и приедет в
`lazyvim-config.tar.gz`.

**2. Система уже стоит, но пользователи ещё не запускали nvim** — дописать в seed:
```bash
sudo tee /opt/astra-dev/skel/.config/nvim/lua/plugins/explorer-grep.lua >/dev/null <<'LUA'
return {
  {
    "folke/snacks.nvim",
    opts = { picker = { sources = { explorer = { win = { list = { keys = {
      ["<leader>sG"] = "picker_grep",
    } } } } } } },
  },
}
LUA
```

**3. У пользователей `~/.config/nvim` уже создан** — полный seed им больше не
копируется (wrapper проверяет `[ ! -e "$HOME/.config/nvim" ]`, и это правильно:
иначе затирались бы их собственные правки). Но спеки комплекта доезжают:

> Файлы `lua/plugins/astra-*.lua` — **управляемые**. Wrapper при каждом запуске
> сверяет их с эталоном в skel по содержимому и обновляет, если разошлись.
> Всё остальное в `lua/plugins` — личное пользователя, не трогается никогда.

То есть достаточно положить новый спек в skel — он разъедется по всем при следующем
запуске nvim:
```bash
sudo cp dist-распакованный/lua/plugins/astra-explorer-grep.lua \
        /opt/astra-dev/skel/.config/nvim/lua/plugins/
```
Обратная сторона: если пользователь отредактирует `astra-*.lua`, правку откатит.
Свои настройки он должен класть в файл с любым другим именем — там его никто не
тронет, а лишний спек в `lua/plugins` LazyVim просто домержит.

Сравнение идёт по содержимому, а не по времени: `tar` восстанавливает в skel mtime
из архива, поэтому свежий спек запросто оказывается «старее» копии в домашке, и
проверка по mtime (`cp -u`) молча ничего бы не делала.

Правку конфига **нельзя** протолкнуть через общий runtimepath или `/etc/xdg/nvim`:
lazy.nvim сбрасывает runtimepath на старте, системных каталогов там нет. Поэтому
единственный путь — эталон в skel плюс синхронизация в домашки.

## Проверка
```bash
nvim --version
rust-analyzer --version
cd <rust-проект> && nvim src/main.rs   # rust-analyzer подцепится
nvim file.cpp                          # clangd подцепится
node --version                         # bundled Node 20
nvim file.ts                           # vtsls подцепится (:LspInfo → vtsls)
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
