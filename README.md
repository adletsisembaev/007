# Kitchen Cabinet Designer for SketchUp

Расширение SketchUp 2024+ для параметрического проектирования кухонных
шкафов: нижних и верхних, с дверями, ящиками, цоколем, ножками и монтажной
шиной. Строит настоящую редактируемую 3D-геометрию: каждая деталь —
отдельная группа, каждый шкаф — компонент. Параметры хранятся в модели и
изменяются в любой момент.

- **Установка:** [docs/INSTALL.md](docs/INSTALL.md)
- **Руководство пользователя:** [docs/USER_GUIDE.md](docs/USER_GUIDE.md)
- **Возможности, ограничения, статус проверки:** [docs/FEATURES.md](docs/FEATURES.md)
- **Архитектура и формулы:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Сборка и тесты

```bash
python3 tools/make_icons.py      # PNG-иконки 24/32 из рисунка (нужен Pillow)
ruby tools/build_rbz.rb          # dist/kitchen_cabinet_designer_<версия>.rbz
ruby tests/run_all.rb            # тесты геометрии и валидации (без SketchUp)
ruby tests/smoke/sketchup_stub_smoke.rb
node tests/ui/dialog_test.js /tmp   # тест диалога (Playwright + Chromium)
```

## Структура

```
kitchen_cabinet_designer.rb        загрузчик (регистрация расширения)
kitchen_cabinet_designer/
  main.rb                          меню, тулбар, контекстное меню
  constants.rb, l10n.rb            константы, локализация (locales/*.json)
  settings.rb, validation.rb       схема параметров и проверки
  geometry/                        расчёт деталей на чистом Ruby (без SketchUp API)
  sketchup/                        построение в SketchUp, материалы, размещение
  ui/dialog_controller.rb          HtmlDialog и обмен JS <-> Ruby
  dialogs/                         main.html, styles.css, app.js
  icons/                           cabinet.svg, cabinet_24.png, cabinet_32.png
tools/                             сборка .rbz, генерация иконок
tests/                             unit-, smoke- и UI-тесты
```
