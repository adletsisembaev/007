# Установка Kitchen Cabinet Designer

Требования: SketchUp 2024 или новее, Windows или macOS. Интернет не нужен.

## 1. Установка готового пакета `.rbz`

1. Откройте SketchUp.
2. Меню **Extensions → Extension Manager**.
3. Нажмите **Install Extension** и выберите файл
   `kitchen_cabinet_designer_1.0.0.rbz`.
4. Подтвердите установку. Если SketchUp предложит, перезапустите его.
5. Проверьте, что всё на месте:
   - появилось меню **Extensions → Kitchen Cabinet Designer**;
   - появился тулбар с иконкой шкафа. Если его не видно, включите
     **View → Toolbars → Kitchen Cabinet Designer**.

**Обновление.** Установите новый `.rbz` так же, поверх старого, затем
перезапустите SketchUp.

**Удаление.** В Extension Manager выберите расширение и нажмите **Uninstall**.

## 2. Сборка `.rbz` из исходников

Файл `.rbz` — это обычный ZIP-архив, у которого в корне лежат загрузчик и
папка расширения:

```
kitchen_cabinet_designer.rb
kitchen_cabinet_designer/
    main.rb, constants.rb, ...
    dialogs/, geometry/, icons/, locales/, sketchup/, ui/
```

### Вариант А: скрипт на Ruby (рекомендуется)

Нужен только Ruby 2.7+, без гемов:

```bash
ruby tools/build_rbz.rb
```

Результат: `dist/kitchen_cabinet_designer_<версия>.rbz`. Скрипт сам проверяет,
что все обязательные файлы на месте, включая PNG-иконки.

### Вариант Б: вручную в Windows Explorer

1. Выделите **вместе** файл `kitchen_cabinet_designer.rb` и папку
   `kitchen_cabinet_designer`. Не саму родительскую папку!
2. Правый клик → **Отправить → Сжатая ZIP-папка**.
3. Переименуйте получившийся `.zip` в `.rbz`.

### Вариант В: 7-Zip

1. Выделите тот же файл и ту же папку.
2. Правый клик → **7-Zip → Добавить к архиву…**
3. Формат **zip**, имя архива `kitchen_cabinet_designer.rbz`.

**Частая ошибка.** Если упаковать родительскую папку, в архиве будет лишний
уровень вложенности. SketchUp установит такой пакет, но расширение не
загрузится.

## 3. Иконки тулбара

Исходник иконки — `kitchen_cabinet_designer/icons/cabinet.svg`. PNG-файлы
24×24 и 32×32 уже лежат в репозитории. Пересоздать их можно двумя способами:

- **скриптом** (нужен Pillow, `pip install pillow`):

  ```bash
  python3 tools/make_icons.py
  ```

- **вручную в Inkscape:** откройте `cabinet.svg` → **File → Export PNG Image** →
  размер 24×24, затем 32×32. Сохраните как `icons/cabinet_24.png` и
  `icons/cabinet_32.png`.

Если PNG-файлов нет, на Windows используется SVG. На macOS тулбар в этом
случае останется без иконки, но пункт меню работает.

## 4. Установка для разработки (без `.rbz`)

Скопируйте `kitchen_cabinet_designer.rb` и папку `kitchen_cabinet_designer` в
папку Plugins и перезапустите SketchUp. Папка Plugins находится здесь:

- Windows: `%APPDATA%\SketchUp\SketchUp 2024\SketchUp\Plugins`
- macOS: `~/Library/Application Support/SketchUp 2024/SketchUp/Plugins`

## 5. Если что-то не работает

- Откройте **Window → Ruby Console**: все ошибки плагина выводятся туда с
  префиксом `Kitchen Cabinet Designer:`.
- Убедитесь, что расширение включено в Extension Manager.
- Плагин не использует наблюдатели и фоновые процессы. Конфликты с другими
  расширениями исключены: всё лежит в модуле `KitchenCabinetDesigner`.
