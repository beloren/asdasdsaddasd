# Полный гайд по иконкам и SwordNPC

## Как загрузить картинку

1. Подготовь PNG с прозрачным фоном. Для предметов и жеод удобно использовать квадрат `512x512` или `1024x1024`.
2. В Roblox Studio открой `View -> Asset Manager`.
3. Выбери `Images`, нажми `Import` и загрузи PNG.
4. Дождись обработки Roblox, нажми по изображению правой кнопкой и скопируй Asset ID.
5. В `src/shared/Config.lua` вставляй только число, без `rbxassetid://` и без кавычек.

Пример:

```lua
Stone = 123456789012345,
```

`0` означает, что своей картинки нет. Игра использует цветную заглушку и продолжает работать.

## Иконки восьми жеод

Раздел `Config.Geodes.Images`:

```lua
Stone = 0,
Crystal = 0,
Amber = 0,
Topaz = 0,
Jade = 0,
Onyx = 0,
Aurora = 0,
Nebula = 0,
```

Эти восемь картинок используются в хранилище, магазине жеод и анимации открытия. Они не заменяют физические модели `Geode_Stone` ... `Geode_Nebula` в `ReplicatedStorage/Assets`.

## Иконки наград жеоды

В том же `Config.Geodes.Images`:

```lua
Dust = 0,          -- пустая/пылевая награда
MoneySmall = 0,    -- маленькая денежная награда
MoneyLarge = 0,    -- средняя денежная награда
MoneyJackpot = 0,  -- джекпот
OfflineIncome = 0, -- офлайн-доход
Installed = 0,     -- сейчас не используется: выбранный камень отмечается зелёной рамкой
```

## Фон и свечение

```lua
SlotBackground = 0,
CrackGlow = 0,
```

- `SlotBackground`: квадратный светлый/серый фон карточки. Код перекрашивает его по редкости, поэтому лучше использовать белую или grayscale-текстуру без собственного сильного цвета.
- `CrackGlow`: прозрачная PNG-вспышка или радиальный свет за раскалывающейся жеодой. Центр должен быть ярким, края прозрачными.
- При `CrackGlow = 0` используется встроенный мягкий цветной круг.

## Иконки 24 коллекционных камней

У каждой записи в `Config.Geodes.Ores` замени `ImageId = 0` на ID картинки.

```lua
Quartz = { ..., ImageId = 1234567890, ... },
```

Полный список:

| Жеода | Ключи `Config.Geodes.Ores` |
|---|---|
| Stone | `Quartz`, `Amethyst`, `GreenCrystal` |
| Crystal | `Sapphire`, `Ruby`, `Diamond` |
| Amber | `Citrine`, `Carnelian`, `SunOpal` |
| Topaz | `Aquamarine`, `Turquoise`, `Moonstone` |
| Jade | `Peridot`, `Malachite`, `Tourmaline` |
| Onyx | `Garnet`, `Bloodstone`, `Obsidianite` |
| Aurora | `Starshard`, `Moonlight`, `Prism` |
| Nebula | `Voidshard`, `Stardust`, `Eclipse` |

Одна и та же `ImageId` используется в результате открытия и в `Crystal Collection`. Трёхмерная модель на подиуме задаётся отдельно как `CollectionOre_<OreId>` в `ReplicatedStorage/Assets`.

## Обычная руда шахты

У обычной руды из шахты нет отдельных UI `ImageId`: она показывается в мире настоящими 3D-моделями. Замени:

```text
ReplicatedStorage/Assets/Crystal_Tier1
...
ReplicatedStorage/Assets/Crystal_Tier8
```

Если нужна картинка шахты/тележки/кирки в меню улучшений, используй:

```lua
Config.UpgradeShop.Icons.Mine
Config.UpgradeShop.Icons.Cart
Config.UpgradeShop.Icons.Pickaxe

Config.UpgradeShop.Cards.CoverIcons.Mine
Config.UpgradeShop.Cards.CoverIcons.Cart
Config.UpgradeShop.Cards.CoverIcons.Pickaxe
```

## Иконки скинов

У каждого скина в `Config.Skins.Definitions` есть `ImageId`:

```lua
Frostmorn = {
    Kind = "Pickaxe",
    DisplayName = "Frostmorn",
    AssetName = "Skin_Frostmorn",
    ImageId = 1234567890,
    NpcExclusive = true,
},
```

Картинка отображается в инвентаре скинов. Для всех остальных кирок меняй их собственный `ImageId` по той же схеме. Модель и картинка независимы.

## Общие иконки интерфейса

Раздел `Config.Icons`:

| Ключ | Где используется |
|---|---|
| `Pickaxe` | слот кирки в hotbar |
| `Money` | деньги |
| `Rebirth` | перерождение |
| `Protection` | кнопка защиты |
| `Settings` | настройки |
| `Shop` | магазин |
| `Robux` | значок Robux |
| `Hint` | подсказка `?` |
| `Owned` | отметка купленного |
| `SliderThumb` | ползунок настроек |
| `FlyingCoin` | летящие монеты при получении денег |

Для сложной анимации монет вместо `FlyingCoin` можно создать `ReplicatedStorage/Assets/MoneyFxTemplate` через `tools/BuildMoneyFx.lua`.

Также проверь:

- `Config.UI.CloseButtonImageId` - общая картинка кнопки закрытия;
- `Config.Shop.Items[*].ImageId` - карточки магазина;
- `Config.Shop.HintImageId` - подсказка магазина;
- `Config.QuickBar.Items[*].ImageId` - иконки quick bar;
- `Config.QuickBar.HintImageId` и `OwnedImageId`;
- `Config.Tutorial.TrailTextureId` - повторяющаяся текстура дорожки к цели обучения.

## Проверка иконок

1. Останови Play Test.
2. Вставь числовые ID в `Config.lua`.
3. Дождись синхронизации Rojo.
4. Запусти новый Play Test.
5. Проверь хранилище жеод, открытие, Crystal Collection, инвентарь скинов и получение денег.
6. Если картинка пустая, проверь модерацию ассета, права владельца experience и правильность ID.

## Установка SwordNPC

NPC можно расположить в любом месте и на любой глубине внутри `Workspace`. Сервис ищет имя рекурсивно.

```text
Workspace
├─ SwordNPC (Model, PrimaryPart назначен)
│  ├─ HumanoidRootPart или другой Root
│  ├─ Head
│  └─ ProximityPrompt
└─ Skin_Frostmorn (Tool)
   ├─ Handle (BasePart, прямой ребёнок)
   └─ остальные части, weld-ы и эффекты
```

Требования:

1. Модель NPC должна называться ровно `SwordNPC`.
2. Назначь ей `PrimaryPart`. Если забудешь, код возьмёт `HumanoidRootPart` или первый `BasePart`.
3. Поставь NPC вручную в нужное место Workspace. Код не перемещает и не анкорит его.
4. Tool должен называться ровно `Skin_Frostmorn`.
5. Внутри Tool нужен прямой `BasePart` `Handle`.
6. Все части меча соедини с `Handle`; настрой `Tool.Grip` в Studio.
7. Скрипты внутри исходного Tool не нужны: при создании боевого инструмента они удаляются.

Постоянный BillboardGui не нужен. Во время разговора клиент временно показывает пиксельный текст над головой NPC и удаляет его после диалога. Существующий `ProximityPrompt` переиспользуется, получает имя `Zavtrack` и синий custom-стиль.

При разговоре NPC:

- говорит приветственную реплику над головой;
- навсегда добавляет `Frostmorn` в сохранённые скины кирки игрока;
- показывает его в `Skins -> Pickaxe`;
- не экипирует скин автоматически: игрок выбирает его сам;
- при экипировке сохраняет урон, кулдаун и серверную логику текущей кирки;
- не выдаёт награду повторно.

Если NPC говорит, что скин не готов, проверь имя `Skin_Frostmorn`, класс `Tool` и прямой `Handle`.
