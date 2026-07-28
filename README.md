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
| codelldb (отладчик C/C++/Rust) + nvim-dap | готовый vsix, целиком со своим lldb |
| lazygit (git-TUI на `<leader>gg`) | статический бинарь, от glibc не зависит |
| git (свой, 2.55) | собирается под glibc 2.28; в Astra ~2.20, а lazygit требует ≥ 2.32 |
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

Раскладка, которую ждут скрипты (архивы — в `dist/`, бинарники — в `dist/bin/`):

```
<репозиторий>/
└── dist/
    ├── nvim.tar.gz
    ├── node.tar.gz            # Node.js 20 (для TS/JS LSP)
    ├── ts-lsp.tar.gz          # vtsls + typescript
    ├── codelldb.tar.gz        # отладчик C/C++/Rust (адаптер + свой lldb)
    ├── git.tar.gz             # свой git 2.55 (lazygit не стартует на < 2.32)
    ├── lazyvim-config.tar.gz
    ├── lazyvim-data.tar.gz
    ├── fonts.tar.gz
    ├── parsers.tar.gz
    └── bin/
        ├── rust-analyzer
        ├── rg                 # ripgrep — греп в пикере (<leader>sg/sG)
        ├── fd                 # поиск файлов в пикере (<leader>ff)
        └── lazygit            # git-TUI на <leader>gg
```

**Вариант A — скачать из Release** (на машине с интернетом):
```bash
# склонировать репозиторий с комплектом и перейти в него
cd <репозиторий>
mkdir -p dist/bin
gh release download v0.2.0 --repo <владелец>/<репозиторий> -p '*.tar.gz'      -D dist/
gh release download v0.2.0 --repo <владелец>/<репозиторий> -p 'rust-analyzer' -D dist/bin/
```
Без `gh` — через `curl`:
```bash
mkdir -p dist/bin
base=<адрес-релиза>          # .../releases/download/v0.2.0
for f in nvim node ts-lsp codelldb git lazyvim-config lazyvim-data fonts parsers; do
  curl -fL -o dist/$f.tar.gz $base/$f.tar.gz
done
for b in rust-analyzer rg fd lazygit; do
  curl -fL -o dist/bin/$b $base/$b && chmod +x dist/bin/$b
done
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
gh release download v0.2.0 --repo <владелец>/<репозиторий> -p 'cargo-vendor-win.tar.gz' -D dist/
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
cd <репозиторий>    # каталог с репозиторием и dist/

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

### Повторная установка новой версии поверх старой

`install-system.sh` можно гонять повторно: разделяемая часть (`/opt/astra-dev`,
`/usr/local/bin`) перезаписывается, а домашки пользователей он не сносит. Плагины
в уже существующих домашках обновляет **обёртка** `/usr/local/bin/nvim` при
следующем запуске `nvim` — она сверяет отпечаток бандла

```
/opt/astra-dev/skel/.local/share/nvim/.astra-bundle-id   # эталон, кладёт установщик
~/.local/share/nvim/.astra-bundle-id                     # копия в домашке
```

и при расхождении заменяет `~/.local/share/nvim/lazy` содержимым из skel, обновляет
`lazy-lock.json` и сносит `~/.cache/nvim` (соберётся заново). В консоли это одна
строка «комплект обновился — перекладываю плагины LazyVim». Каталог `lazy`
принадлежит комплекту целиком: офлайн доставить туда своё всё равно неоткуда,
поэтому он заменяется, а не сливается. Личные спеки в `~/.config/nvim/lua/plugins`
(всё, кроме `astra-*.lua`) не трогаются.

> Раньше этого шага не было, и установка новой версии поверх старой ломала nvim:
> установщик дописывал новые экстры в `lazyvim.json` домашки, а плагинов под них
> в `~/.local/share/nvim/lazy` не появлялось — lazy.nvim шёл за ними на github и
> офлайн сыпал ошибками на каждом старте. Домашку, уже сломанную таким образом,
> чинит либо новый `install-system.sh` (обёртка переложит плагины сама), либо
> сброс руками — `rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim
> ~/.cache/nvim` и запуск `nvim` (обёртка засеет всё заново из skel).

## Обновление уже установленной машины (точечно)

Если комплект уже стоит и надо доставить/обновить только часть (например добавить
JS/TS), НЕ гоняй установку с нуля. `install/install.sh` — деструктивный полный
установщик (стирает и перезаписывает `~/.config/nvim` и данные nvim). Вместо него
качай из Release только изменившиеся ассеты и раскладывай точечно.

**На машине с интернетом** — обновить репозиторий и скачать нужные ассеты в `dist/`:
```bash
cd <репозиторий> && git pull
gh release download v0.2.0 --repo <владелец>/<репозиторий> --clobber -D dist/ \
  -p 'node.tar.gz' -p 'ts-lsp.tar.gz' \
  -p 'lazyvim-config.tar.gz' -p 'lazyvim-data.tar.gz' -p 'parsers.tar.gz'
```
(набор `-p` — то, что реально поменялось; для JS/TS это эти пять). Перенести каталог репозитория
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

### ripgrep + fd + lazygit (греп, поиск файлов, git-TUI)

Если в пикере греп падает с `Failed to spawn rg` — на машине нет `rg`. Если не работает
`<leader>gg` — нет `lazygit`: LazyVim вешает эту клавишу только когда бинарь есть в `PATH`. Это признак
бандла, собранного до появления шага с ripgrep/fd. Пересобирать весь `dist/` не надо:
это готовые static-musl бинарники, они не зависят от glibc и никак не связаны с
контейнерной сборкой.

**На машине с интернетом** — положить их в `dist/bin/`:
```bash
curl -fsSL https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz \
  | tar xz -O --wildcards '*/rg' > dist/bin/rg
curl -fsSL https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-unknown-linux-musl.tar.gz \
  | tar xz -O --wildcards '*/fd' > dist/bin/fd
curl -fsSL https://github.com/jesseduffield/lazygit/releases/download/v0.63.1/lazygit_0.63.1_Linux_x86_64.tar.gz \
  | tar xz -O lazygit > dist/bin/lazygit
chmod +x dist/bin/rg dist/bin/fd dist/bin/lazygit
```
Перенести каталог репозитория на целевую машину (или просто скопировать туда эти два файла).

**На целевой машине:**
```bash
bash install/install-tools.sh              # или: sudo bash install/install-tools.sh system
```
Скрипт инкрементальный — кладёт `rg`, `fd` и `lazygit` в `~/.local/bin` (или `/usr/local/bin`
в режиме `system`) и больше ничего не трогает. Если каталог уже был в `PATH`
запущенного nvim, греп заработает без перезапуска (он спавнит `rg` заново на каждый
ввод); если `PATH` дописывался в `~/.bashrc` только что — нужен новый терминал.

### Свой git (lazygit требует ≥ 2.32)

Если `<leader>gg` открывается и сразу гаснет с

```
Git version must be at least 2.32.0. Please upgrade your git version.
```

значит на машине git старее 2.32. Это не баг комплекта: минимум прописан в самом
lazygit (`pkg/app/app.go`, `minGitVersionStr = "2.32.0"`), а в репозитории Astra 1.7
лежит buster-овский ~2.20. Проверить: `git --version`, `apt-cache policy git`.

Обновлять git через `apt` из чужого репозитория **не надо** — потянет за собой glibc.
Комплект собирает свой git под ту же glibc 2.28 и кладёт его рядом с остальным.
Пересобирать весь `dist/` ради него не надо — это отдельный ассет (~9 МБ).

**На машине с интернетом:**
```bash
gh release download v0.2.0 --repo <владелец>/<репозиторий> --clobber -D dist/ -p 'git.tar.gz'
```
Перенести каталог репозитория на целевую машину.

**На целевой машине:**
```bash
bash install/install-git.sh              # для себя → ~/.local/git
sudo bash install/install-git.sh system  # для всех → /opt/astra-dev/git
```

Системный `/usr/bin/git` при этом **не трогается**: dpkg-состояние не меняется, наш
git просто стоит раньше в `PATH`. Откат — удалить каталог и симлинки (скрипт
печатает готовую команду).

Особенности сборки (см. `build/_in-container.sh`):

| Флаг | Зачем |
|---|---|
| `NO_RUST=1` | с 2.55 часть git на Rust и тянет `cargo`; в buster rustc 1.41, git хочет ≥ 1.49. До **Git 3.0** отключаемо, дальше шаг сборки git придётся переставить после установки rustup |
| `NO_CURL=1 NO_EXPAT=1` | транспорты http(s) офлайн не нужны; ssh и локальные пути работают |
| `NO_GETTEXT=1 NO_OPENSSL=1` | сообщения на английском, свой SHA — меньше зависимостей: остаются только `libz` и `libc` |
| `RUNTIME_PREFIX=YesPlease` | git ищет `libexec/git-core` и шаблоны рядом с бинарём, поэтому дерево кладётся хоть в `/opt/astra-dev/git`, хоть в `~/.local/git` |

Оборотная сторона `RUNTIME_PREFIX`: общесистемный конфиг ищется не в `/etc/gitconfig`,
а в `<префикс>/etc/gitconfig`. Установщики поэтому ставят туда симлинк на `/etc/gitconfig`
— иначе настройки Astra (прокси, `safe.directory`) молча перестали бы действовать.

Дерево после `strip` — 19 МБ (архив ~9 МБ); без `strip` было бы 106 МБ.

### Отладчик codelldb (C/C++/Rust)

Отладка в nvim — это две независимые части: **бинарь** `codelldb` (адаптер DAP плюс
свой lldb) и **редакторная часть** (плагины `nvim-dap`/`nvim-dap-ui` и спек
`astra-dap.lua`). Бинарь ставится инкрементально, редакторная часть приезжает только
пересборкой бандла — доклонировать плагины офлайн на Astra нельзя.

**На машине с интернетом** — скачать ассет в `dist/`:
```bash
gh release download v0.2.0 --repo <владелец>/<репозиторий> --clobber -D dist/ \
  -p 'codelldb.tar.gz' -p 'lazyvim-config.tar.gz' -p 'lazyvim-data.tar.gz'
```

**На целевой машине:**
```bash
bash install/install-dap.sh              # или: sudo bash install/install-dap.sh system
```
Кладёт дерево в `~/.local/codelldb` (или `/opt/astra-dev/codelldb`) и симлинк
`codelldb` в `PATH`; больше ничего не трогает. Если бандл старый и плагинов
`nvim-dap` в нём нет — нужен ещё шаг 2 из раздела выше (распаковка
`lazyvim-config`/`lazyvim-data`).

Клавиши: `<leader>db` точка останова, `<leader>dc` запуск/продолжить, `<leader>du`
панель отладчика, `<leader>de` вычислить выражение. Для Rust — `<leader>dr`
(`:RustLsp debuggables`, цели берутся из Cargo). Для C/C++ спрашивается путь к
исполняемому файлу; собирать нужно с `-g`.

Спек `astra-dap.lua` ищет адаптер через `PATH` и разыменовывает симлинк, чтобы найти
`liblldb.so` рядом с настоящим бинарём — поэтому он одинаково работает и при
установке в `$HOME`, и при системной.

#### Qt5 в панели переменных

LLDB из коробки знает контейнеры STL, но про Qt не знает ничего: `QString` и `QMap`
показываются сырым указателем `d:0x...`. Комплект возит форматтеры
[lldb/qt5_lldb.py](lldb/qt5_lldb.py) — установщики кладут их рядом с адаптером
(`.../codelldb/qt5_lldb.py`), а спек подключает через `initCommands`. Отдельных
действий не требуется; если файла нет, отладчик работает как обычно.

Что становится читаемым: `QString`, `QByteArray`, `QList`, `QVector`, `QStringList`,
`QMap`, `QMultiMap`, `QHash`, `QSet`, `QSharedPointer` (разыменовывается), `QVariant`
(распространённые типы), `QDateTime`, а также вложенные комбинации — `QMap` с
`QPair` в значении, `QMap<int, QVector<QString>>`, `QList<QMap<...>>` и свои
структуры с Qt-полями внутри. Ключ ассоциативного контейнера идёт в имя элемента:
`["host"] = 8080`.

Проверено на Qt 5.11 (Buster, glibc 2.28) и Qt 5.15.

Ограничения: только Qt5 — в Qt6 `QString`/`QList`/`QMap` переписаны, форматтеры
туда не поедут без правок. `QVariant` знает распространённые типы, для остальных
пишет номер типа. Для `QList` со **своей** movable-структурой имя типа нужно дописать
в список `_MOVABLE` в скрипте: определить это по отладочной информации нельзя (в
DWARF нет `QTypeInfo`), а от ответа зависит, лежит элемент в слоте или по указателю.
Та же оговорка есть и у готовых наборов вроде `qt5printers`.

### Что чинить, если бандл старый (blink.cmp, порядок импортов, битый `target/`)

Симптомы, которые видно на машинах с бандлом до этих правок, и что с ними делать.
Если непонятно, какой из случаев твой — сперва снять картину скриптом
`install/collect-diag.sh` (см. «Диагностика одной командой» ниже).

**1. `blink.cmp` лезет на github за бинарём fuzzy.**
```
blink.cmp Downloading pre-built binary
blink.cmp Failed to download libblink_cmp_fuzzy.so.tmp
curl: (6) Could not resolve host: github.com
blink.cmp Falling back to Lua implementation ...
```
Автодополнение при этом работает (падает в Lua-реализацию), но ругань висит на каждом
старте. Лечится спеком `astra-blink-offline.lua` — он включает Lua-реализацию явно и
запрещает скачивание. Спек управляемый, разъедется по всем при следующем `nvim`:
```bash
sudo tee /opt/astra-dev/skel/.config/nvim/lua/plugins/astra-blink-offline.lua >/dev/null <<'LUA'
return {
  {
    "saghen/blink.cmp",
    opts = { fuzzy = { implementation = "lua", prebuilt_binaries = { download = false } } },
  },
}
LUA
```

**2. `The order of your lazy.nvim imports is incorrect`.** Экстры подключались
импортами из `lua/plugins/extras.lua`, а каталог `plugins` регистрируется раньше их —
LazyVim это и ловит. Теперь экстры едут в `lazyvim.json` (штатный `:LazyExtras`),
который импортирует сам `lazyvim.plugins`. `install-system.sh` мигрирует все домашки
сам; точечно, от имени пользователя, это те же два шага:
```bash
rm -f ~/.config/nvim/lua/plugins/extras.lua
nvim --headless -l install/_merge-extras.lua ~/.config/nvim/lazyvim.json \
  lazyvim.plugins.extras.coding.neogen lazyvim.plugins.extras.dap.core \
  lazyvim.plugins.extras.lang.clangd  lazyvim.plugins.extras.lang.cmake \
  lazyvim.plugins.extras.lang.rust    lazyvim.plugins.extras.lang.typescript
```
`_merge-extras.lua` только дописывает экстры, остальное в `lazyvim.json` (news-хэши,
свои экстры) не трогает, и его можно гонять повторно.

**3. `corrupt metadata encountered in target/debug/deps/libtokio-*.rmeta` (E0786), а
следом `main function is not allowed to be async` (E0752).** Это одна поломка, а не
две: в `target/` лежит недописанный `.rmeta` (прерванная сборка — выход из nvim, OOM,
кончилось место), из-за него не грузится `tokio-macros`, поэтому `#[tokio::main]` не
раскрывается и `async fn main` остаётся голым. Ни к версии rustc, ни к вендору крейтов
отношения не имеет: тот же проект с `tokio 1.47` собирается на rustc 1.70 начисто.
```bash
cargo clean && cargo build --offline
```
Чтобы не повторялось, спек `astra-rust.lua` уводит проверки rust-analyzer в отдельный
`target/rust-analyzer` — сборка из редактора и сборка из терминала больше не пишут
в одни и те же файлы.

**4. `rust-analyzer: -32603: request handler panicked: projecting associated item
ProjectionTy { def_id: TypeAliasId("Output") } from future, which is not Output`, а
`gd` отвечает `no result found for lsp_definition`.** rust-analyzer не смог вывести
`Future::Output` и уронил inference всего файла — отсюда и отказ goto. Ловится там же,
где п.3 (сломанное раскрытие `#[tokio::main]`), поэтому сперва `cargo clean` и заново
открыть проект. Если осталось — снять версии, они должны быть от комплекта:
```bash
which -a rust-analyzer && rust-analyzer --version   # ожидается 0.3.1748 (тег 2023-11-27)
rustc --version                                     # 1.70.0 из репозиториев Astra
```
Обновлять rust-analyzer в надежде вылечить **не надо**: на чистом проекте
(`tokio 1.47` + rustc 1.70) сборки 2023-11-27, 2024-06-03 и 2025-06-30 отрабатывают без
паники, а свежая 2026-07-20 на том же проекте падает ровно этим сообщением — с
устаревшим sysroot новые сборки хуже, а не лучше.

### Диагностика одной командой

На офлайн-машине неудобно главное — вынести с неё вывод. `install/collect-diag.sh`
печатает состояние комплекта и Rust-проекта так, чтобы отчёт можно было **перенести
фотографией**: одна проверка — одна ASCII-строка не длиннее 72 символов, строки
пронумерованы, в конце `END lines=N` (сразу видно, если снимок обрезал хвост).

```bash
bash install/collect-diag.sh ~/dev/hello_world            # только читает
bash install/collect-diag.sh ~/dev/hello_world --clean    # + cargo clean перед сборкой
```

Без `--clean` скрипт ничего не меняет. Первый прогон лучше делать именно без него:
тогда в отчёте видно сломанное состояние `target/` как есть. Гонять на маленьком
проекте — на большом `analysis-stats` думает минутами, а строка отчёта от этого
полезнее не станет. Вывод дублируется в `/tmp/astra-diag.txt`.

Как выглядит (rustc 1.70 + rust-analyzer из комплекта):
```
01 DATE      2026-07-25 23:10
03 RA        rust-analyzer 0.3.1748-standalone
04 RA-PATH   /usr/local/bin/rust-analyzer [x1]
05 RUSTC     rustc 1.70.0 (90c541806 2023-05-31)
09 RUST-SRC  OK
12 TOKIO     1.47.5
13 PM2       1.0.86
14 RMETA     total=12 tiny=0
17 BUILD     OK
19 RA-STATS  exprs: 47, ??ty: 0 (0%)
20 RA-PANIC  0 hits
22 RA-NOPM   0 hits (proc-macros off)
24 EXTRAS-L  absent-ok
26 BLINK-SP  implementation = "lua"
32 END       lines=32 file=/tmp/astra-diag.txt
```

Что читать в первую очередь:

| строка | о чём говорит |
|---|---|
| `RA` / `RA-PATH` | тот ли rust-analyzer подхватился; `[x2]` — в `PATH` их два, это уже причина |
| `RUST-SRC` | `MISSING` объясняет панику про `Future::Output` без всякого `target/`: серверу нечем разрешать `Future` |
| `TOKIO` / `PM2` | версии из лока; `proc-macro2 ≥ 1.0.107` при rustc 1.70 значит, что лок собран не MSRV-aware резолвером и проект не соберётся в принципе |
| `RMETA tiny=N` | прямой детектор обрезанных метаданных (E0786); `> 0` — лечится `cargo clean` |
| `BUILD` | воспроизводится ли поломка из терминала; `msrv-errors` отделяет MSRV-беду от битого `target/` |
| `RA-PANIC` / `RA-NOPM` | паника есть с proc-макросами и нет без них → валит раскрытие `#[tokio::main]`; есть в обоих → дело в sysroot/типах, смотри `??ty` в `RA-STATS` |
| `EXTRAS-L` / `BLINK-SP` / `RUST-SP` | доехали ли до домашки спеки комплекта; пока `present-OLD`/`no-spec` — ошибки с blink и порядком импортов будут повторяться |
| `LSPLOG` / `LSP-MSG` | паника из живой LSP-сессии: бывает, что CLI чист, а под nvim падает из-за настроек rustaceanvim |

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

### Офлайн-настройки самой lazy.nvim

Стартовый конфиг LazyVim (`lua/config/lazy.lua`) рассчитан на машину с интернетом,
поэтому в комплекте он правится — сборкой (`build/_in-container.sh`) и, для бандлов
постарше, установщиками (`install/_offline-lazy-cfg.sh`, правка идемпотентная):

| Настройка | Зачем |
|---|---|
| `checker = { enabled = false }` | иначе lazy.nvim на старте и раз в час делает `git fetch` по каждому из полусотни плагинов: офлайн это висящие процессы `git` и ошибки в уведомлениях на каждом запуске |
| `rocks = { enabled = false }` | luarocks/hererocks lazy.nvim при случае качает из сети, а плагины с `.rockspec` в комплекте есть (nvim-dap, plenary, gitsigns…) |

Установщики применяют эти правки и к уже существующим домашкам, так что
«лезет на github» лечится повторным `install-system.sh` без пересборки бандла.

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
codelldb --help >/dev/null && echo ok  # адаптер отладчика запускается
```

## Заметки
- Всё, что требует свежего glibc/интернета, собирается в Buster-контейнере —
  готовые сборки Neovim/rust-analyzer с GitHub требуют glibc ≥ 2.31 и на Astra 2.28 не идут.
- codelldb берётся готовым vsix, а не собирается: сборка тянет LLVM/LLDB на часы,
  а релизные бинарники и так требуют максимум `GLIBC_2.18` (проверено `objdump -T`
  по всем ELF пакета) и не зависят от `libstdc++` — на 2.28 идут как есть. Проверено
  живой DAP-сессией в buster: точка останова, стек, STL-переменные, `evaluate`.
  `unzip` не сохраняет бит исполнения — после распаковки vsix нужен `chmod +x`.
- podman: контейнер запускается с `--network=host` (иначе из NAT-контейнера не виден
  прокси), ro-монтирования — с меткой `:z`/`:Z` (SELinux на Fedora).
- Rust-проекты собираются офлайн из `librust-*-dev` через `~/.cargo/config.toml`.
- Крейты, которых нет в `librust-*-dev` (tokio и т.п.), вендорятся исходниками и
  сливаются с debian-реестром в один directory-source (`install/build-registry.sh`).
  Пруним `windows-*` из vendor **нельзя** — cargo требует их и на Linux (cfg-зависимости).
