# IntelliJ Custom Plugin Repository

Персональный независимый репозиторий плагинов для IDE на базе IntelliJ Platform, работающий через GitHub Pages.

## URL репозитория для IntelliJ IDEA

```text
https://alezhu.github.io/intellij-plugins-repo/updatePlugins.xml
```

### Как подключить в IDE:
1. Откройте **Settings** (`Ctrl + Alt + S` / `Cmd + ,`) → **Plugins**.
2. Нажмите на иконку шестерёнки ⚙️ в верхней панели → **Manage Plugin Repositories...**.
3. Нажмите `+` и вставьте URL выше.
4. Теперь плагины доступны во вкладке **Marketplace** (внутренний поиск IDE), а обновления приходят автоматически.

---

## Текущие плагины в репозитории

1. **Alezhu ClassicUI** (`ru.alezhu.idea.classic.ui`)
   - Версия: `1.0.1`
   - Совместимость: `since-build="232" until-build="299.*"`
2. **GitExtensions** (`com.dmitryzhelnin.intellij.plugin.gitextensions`)
   - Версия: `0.4.8-az`
   - Совместимость: `since-build="233"`

---

## Структура репозитория

- `plugins/` — директория с архивами плагинов (`.zip`), собранными через Gradle (`./gradlew buildPlugin`).
- `generate_repo.py` — скрипт генерации `updatePlugins.xml` (используется в GitHub Actions).
- `generate_repo.ps1` — скрипт генерации `updatePlugins.xml` для локального запуска в PowerShell.
- `.github/workflows/pages.yml` — GitHub Action, автоматически публикующий репозиторий на GitHub Pages при каждом коммите в `main`.

---

## Автоматическая доставка плагинов из их репозиториев (CI/CD)

В каждом проекте плагина (например, в `classic-ui` или `git-extensions-intellij`):

1. Создайте в профиле GitHub **Personal Access Token (Fine-grained)**:
   - Доступ к репозиторию: только `intellij-plugins-repo`.
   - Права: **Contents: Read and write**.
2. В репозитории плагина добавьте секрет:
   - **Settings** → **Secrets and variables** → **Actions** → `CENTRAL_REPO_PAT`.
3. Добавьте шаг публикации в workflow сборки плагина при создании тега `v*` (см. документацию).
