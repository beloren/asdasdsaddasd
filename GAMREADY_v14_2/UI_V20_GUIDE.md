# Интерфейс v20: единый стиль и один билдер

Весь интерфейс игры, и экранный, и мировой (надписи над рудой, NPC, мобами), собран в **одном стиле**
(тёмные полупрозрачные панели, тонкая цветная рамка окна, отдельная полоса заголовка с закладкой слева
и красным «X» справа, жирный курсив с обводкой, зелёные градиентные кнопки покупки, карточки с рамкой
цвета редкости, заголовки секций «—— Money ——»).
Все подложки — `ImageLabel`/`ImageButton`, поэтому свои картинки подставляются без правок кода.

## Как это устроено

| Модуль | Что делает |
|---|---|
| `Shared/UiTheme` | Все цвета, шрифты, акценты окон, цвета редкостей, **скины подложек** (`Theme.Skins`) и **иконки** (`Theme.Icons`) |
| `Shared/UiKit` | Кирпичики: `Window`, `Button`, `Card`, `Slot`, `Tabs`, `SectionHeader`, `Bar`, `Text` и т.д. Каждая подложка — ImageLabel с атрибутом `UiSkin` |
| `Shared/UiRegistry` | Список **всех** экранов игры и их билдеров. Клиенты берут экран через `UiRegistry.Get("Имя")` |
| `Shared/UiBuilders/*` + `Shared/*UiBuilder` | Билдеры конкретных экранов |
| `Shared/WorldUi` | Мировой интерфейс (BillboardGui/SurfaceGui) — стили текста и шаблоны из `StarterGui/WorldUiTemplates`. Работает и на сервере, и на клиенте |

## Один билдер на всё

1. Синхронизируй проект через Rojo.
2. Studio → View → Command Bar → вставь содержимое `tools/BuildAllUI.lua` → Enter.
3. В `StarterGui` появятся **все** экраны игры (список ниже). Старые экраны прошлых версий удаляются автоматически.
4. Меняй что угодно прямо в Studio (позиции, размеры, картинки, тексты, цвета) — игра использует **именно твои** экраны из StarterGui.

Пересобрать только часть экранов: в начале `tools/BuildAllUI.lua` впиши их имена в `ONLY`.
`SKIP_EXISTING = true` — не трогать экраны, которые уже есть в StarterGui (сохранит ручные правки).

Если билдер не запускали или экран в StarterGui собран старой версией билдера (без атрибута
`UiKitVersion` ≥ 20), игра соберёт новый вид сама, кодом. Интерфейс есть всегда.

## Свои картинки (подложки, камни, кнопки)

* **Подложки всех окон, карточек, кнопок сразу** — впиши `rbxassetid` в `Theme.Skins.<Скин>.Image`
  (`Panel`, `TitleBar`, `Card`, `Slot`, `Button_Green`, `Button_Yellow`, `Tab`, …; при необходимости поправь `Slice` для 9-slice),
  затем запусти `tools/ApplyUiSkins.lua` — он проставит картинки во всём StarterGui, не трогая твою раскладку.
  Без запуска картинки подхватятся при следующей сборке.
* **Иконки** (крестик, галочка, Robux, деньги, кнопки HUD) — `Theme.Icons`. Пусто = эмодзи/текст.
* **Конкретный элемент** — просто выбери ImageLabel в StarterGui и поставь `Image`. Чтобы `ApplyUiSkins`
  его больше не перезаписывал, поставь атрибут `UiSkinLocked = true`.
* **Камни, предметы, жеоды** — как раньше, `ImageId` в `Config` (карточки показывают картинку, если она задана, иначе эмодзи).

## Мировой интерфейс (надписи в мире)

Все надписи над рудой, тележкой, NPC, островами, печью, сейфами, гоблинами, валунами, числа урона и т.д.
берут шрифт и обводку из `StarterGui/WorldUiTemplates/TextStyles` (`Title`, `Heading`, `Number`, `Money`, `Body`, `Small`, `Glyph`).
Поменяй образец — поменяются все надписи этого стиля в игре, и серверные, и клиентские.
Таблички гоблинов и валунов — `StarterGui/MobBillboardTemplates` (`GoblinTemplate`, `BoulderTemplate`).

## Все экраны (UiRegistry)

| ScreenGui | Билдер | Что это |
|---|---|---|
| `Hud` | `UiBuilders.HudUi` | портрет, деньги, престиж |
| `TopbarDock` | `UiBuilders.HudUi`.BuildTopbar | ряд кнопок в топбаре |
| `CartInteractionUi` | `UiBuilders.CartInteractionUi` | экранные подсказки промптов |
| `HotbarUi` | `UiBuilders.InventoryUi`.BuildHotbar | хотбар |
| `SatchelInventory` | `UiBuilders.InventoryUi`.BuildSatchel | рюкзак (клавиша ~) |
| `InventoryDragOverlay` | `UiBuilders.InventoryUi`.BuildDragOverlay | слой перетаскивания предметов |
| `BuffBar` | `UiBuilders.BuffBarUi` | панель баффов |
| `LootFeedUi` | `UiBuilders.LootFeedUi` | лента добычи |
| `Toast` | `ToastUiBuilder` | уведомления |
| `QuestUi` | `UiBuilders.QuestUi` | квесты + трекер |
| `MobileShiftLockButton` | `UiBuilders.ShiftLockUi` | кнопка шифтлока (телефон) |
| `SocialHud` | `UiBuilders.SocialHudUi` | кнопка наград за группу/избранное |
| `QuestMarkerUi` | `UiBuilders.QuestMarkerUi` | стрелка навигации квеста |
| `ShopUi` | `UiBuilders.ShopUi` | магазин за Robux |
| `UpgradeShopUi` | `UiBuilders.UpgradeShopUi` | прокачка (Upgrade Mole) |
| `SettingsMenu` | `UiBuilders.SettingsUi` | настройки и промокоды |
| `DailyRewardUi` | `UiBuilders.DailyRewardUi` | награды за вход / время |
| `ReturnScreenUi` | `UiBuilders.ReturnScreenUi` | экран возвращения |
| `StarterPackOffer` | `UiBuilders.StarterPackUi` | стартовый набор |
| `CollectionMenu` | `UiBuilders.CollectionMenuUi` | книга-меню |
| `SkinUi` | `SkinUiBuilder` | скины |
| `PerkUi` | `PerkUiBuilder` | перки престижа |
| `RebirthDialogButtons` | `PrestigeUiBuilder` | окно престижа у NPC |
| `MerchantUi` | `MerchantUiBuilder` | торговец |
| `MarketTicker` | `MerchantUiBuilder`.BuildMarketTicker | табло курса руды |
| `GeodeUi` | `GeodeUiBuilder` | жеоды |
| `DropPreviewUi` | `UiBuilders.DropPreviewUi` | окно шансов |
| `IslandUi` | `UiBuilders.IslandUi` | острова и путешествия |
| `GearUi` | `GearUiBuilder` | снаряжение, лут сундуков |
| `OfferUi` | `OfferUiBuilder` | предложения |
| `GroupRewardUi` | `SocialRewardCard`.BuildGroup | награда за группу |
| `LikeRewardUi` | `SocialRewardCard`.BuildLike | награда за лайк |
| `CombatUi` | `CombatUiBuilder` | бой |
| `BoulderGameUi` | `BoulderGameUiBuilder` | мини-игра валуна |
| `MineArcUi` | `MineVeinUiBuilder` | мини-игра шахты |
| `MinerDialogUi` | `MinerDialogUiBuilder` | диалог шахтёра |
| `MiningRhythmUi` | `UiBuilders.MiningRhythmUi` | ритм добычи |
| `TutorialUi` | `TutorialUiBuilder` | обучение |
| `RubbleCrystalHotbar` | `UiBuilders.RubbleCrystalUi` | кристалл в руках |
| `OrePreviewHud` | `UiBuilders.OrePreviewUi` | руда в руках |
| `PlacementUi` | `UiBuilders.PlacementUi` | подсказки установки |
| `MoneyGainFx` | `UiBuilders.MoneyFxUi` | «+$X» при начислении денег |
| `RevealCards` | `UiBuilders.RevealCardsUi` | карточки открытия жеод/сундуков |
| `MobBillboardTemplates` | `UiBuilders.MobBillboardsUi` | таблички гоблинов и валунов |
| `WorldUiTemplates` | `UiBuilders.WorldUi` | шаблоны билбордов (мобы, валуны, промпты) |

## Правила для разработчика

* Новый экран: билдер в `src/shared/UiBuilders/<Имя>.lua` (функция `Build()` → ScreenGui) + строка в `UiRegistry.Entries`.
  Клиент получает его через `UiRegistry.Get("<Имя>")` и **ищет детали по именам** (имена — контракт, они описаны в шапке каждого билдера).
* Повторяющиеся элементы (строки списков, карточки) лежат в папке `Templates` экрана и клонируются клиентом.
  Меняешь шаблон в Studio — меняются все строки.
* Кнопки: `UiKit.Button(parent, name, text, "Green"|"Yellow"|"Red"|"Blue"|"Purple"|"Dark"|"Claim"|"Track")`, подпись — `Caption`.
  Сменить состояние кнопки из клиента: `UiKit.SetButtonVariant(button, "Dark")`.
* Мировой текст: `WorldUi.Text(parent, name, "Number")`, готовый TextLabel → `WorldUi.Restyle(label, "Heading")`.
* `CustomCartUI.client.lua` упирается в лимит 200 локальных регистров на верхнем уровне: новые `require`
  клади **внутрь функций**, а не в начало файла.


## Телефон и ПК (v20.18)

* `src/client/ResponsiveUi.client.lua` работает **только на телефоне** (профиль Phone из `src/shared/UiLayout.lua`;
  проверить на ПК: `Config.UiLayout.ForceProfile = "Phone"`). На ПК интерфейс ровно такой, как собран.
* Раскладка телефона: `Config.UiLayout.Overrides.Phone["Экран/Элемент/…"] = { свойства }`; ключ `"@Имя"` ставит атрибут.
* Масштаб «влезает + HUD компактнее» получают только верхние элементы БЕЗ своего UIScale (UIScale `PhoneFitScale`).
  Окна и кнопки со своими UIScale (анимации, наведение, своя подгонка) не трогаются — правила: не вешайте на один
  объект два UIScale (Roblox их не складывает) и не домножайте чужой UIScale.
* Атрибуты: `UiScale_Phone = 0.8` — своя база элемента на телефоне; `NoAutoFit = true` — не трогать.
* Превью: `lune run tools/dev/preview_ui.luau "Hud+HotbarUi+…" 844 390 "" demo Phone`.
