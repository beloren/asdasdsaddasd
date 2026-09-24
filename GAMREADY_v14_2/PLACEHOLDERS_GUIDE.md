# Полный гайд по замене плейсхолдеров

Документ описывает актуальные контракты моделей, VFX, скинов, жеод и UI. Источник истины: `src/shared/PlaceholderFactory.lua`, сервисы в `src/server/Services`, клиенты в `src/client`, `src/shared/Config.lua` и билдеры из `tools`.

## Самое важное

1. Все игровые 3D-ассеты лежат прямыми детьми в `ReplicatedStorage/Assets`.
2. Имена регистрозависимы: `Cart_Tier1` и `cart_tier1` — разные имена.
3. Для любой составной физической модели безопасный стандарт — прямой `BasePart` `Root`, назначенный как `PrimaryPart`.
4. Для скинов вместо `Root` используй `SkinRoot`. Их части код приваривает сам.
5. Для кристаллов, тележек, физических жеод и составных VFX декоративные части нужно заранее соединить с корнем через `WeldConstraint`, если в разделе ассета не сказано обратное.
6. Никогда не оставляй движущиеся модели заанкоренными. Особенно это важно для тележек.
7. Почти все старые билдеры удаляют свои объекты с точными именами. Исключение — безопасный preview-билдер `BuildNewAssetWorkspacePack.lua`.
8. `default.project.json` не синхронизирует содержимое `Assets`, `StarterGui` и Studio-постройки. После работы обязательно сохрани или опубликуй place.

В рантайме поддерживается 105 точных верхнеуровневых имён в `Assets`. Из них `Coin` сейчас не используется, поэтому для релиза фактически нужны до 104 ассетов. Не все обязательны: для большинства есть кодовый плейсхолдер, но у скинов его нет.

## Безопасный порядок работы

1. Останови Play Test.
2. Запусти Rojo и дождись `ReplicatedStorage/Shared`, `ReplicatedStorage/Assets`, серверных и клиентских скриптов.
3. Если нужны стартовые заглушки, сначала запусти соответствующие билдеры.
4. Только после последнего запуска билдера заменяй модели и вручную стилизуй UI.
5. Перед повторным запуском любого билдера сделай дубликат его объектов.
6. Сохрани place: Studio-ассеты не находятся в исходниках Rojo.
7. Проверяй через свежий запуск сервера, а не только через Reset Character.

## Общая структура Assets

```text
ReplicatedStorage
└─ Assets
   ├─ Crystal_Tier1 .. Crystal_Tier8
   ├─ Cart_Tier1 .. Cart_Tier8
   ├─ Mine_Tier1 .. Mine_Tier8
   ├─ Pickaxe_Tier1 .. Pickaxe_Tier8
   ├─ PlotTemplate
   ├─ Bank
   ├─ LeaderboardBoards
   ├─ UpgradeShopNPC
   ├─ ShopNPC
   ├─ RebirthNPC
   ├─ RespawnButton
   ├─ swing
   ├─ SprintVFX
   ├─ BankSellVFX
   ├─ PickaxeHitVFX
   ├─ ShieldVfx
   ├─ ShieldVfxVIP
   ├─ Geode_Stone .. Geode_Nebula
   ├─ GeodeBuilding
   ├─ GeodePodium
   ├─ GeodeSafe
   ├─ GeodeCartVFX
   ├─ Boulder_Tier1 .. Boulder_Tier10
   ├─ Goblin_Warrior_1/_2/_3, Goblin_Thief_1/_2/_3, Goblin_Berserker_1/_2/_3, Goblin_King_1/_2/_3, Goblin_Golden_1/_2/_3
   ├─ CollectionOre_<OreId> (40 штук: 30 жеодных + 10 валунных)
   ├─ Skin_Pickaxe_<Name> (17 штук)
   ├─ Skin_Cart_<Name> (11 штук)
   └─ MoneyFxTemplate
```

`workspace.RubbleBoulderSpawnPoints` — отдельная папка НЕ в `Assets`, а прямо в `workspace` (это точки на карте, а не ассеты-шаблоны): 16 `BasePart`, опционально с атрибутом `Tier` (число 1-10) на каждой.

`PlaceholderFactory` ищет только прямого ребёнка `Assets`. Вложенная папка `Assets/Carts/Cart_Tier1` не сработает.

## Тир-модели

### `Crystal_Tier1` ... `Crystal_Tier8`

Для кирки предпочтителен `Tool`; также поддерживается `Model` с `SkinRoot`/`PrimaryPart`.

Рекомендуемая структура модели:

```text
Crystal_Tier1 (Model, PrimaryPart = Root)
├─ Root (BasePart)
├─ Decoration (MeshPart, WeldConstraint к Root)
└─ PriceGui (BillboardGui, необязательно)
   └─ Price (TextLabel, прямой ребёнок PriceGui)
```

Требования:

- `Root` должен быть прямым ребёнком модели или у модели должен быть назначен другой `PrimaryPart`.
- Все дополнительные физические части привариваются к корню.
- `PriceGui` необязателен. В нём нужен прямой дочерний `TextLabel`; его имя не важно.
- Код сам выставляет цену, цвет, атрибуты и случайный масштаб ±8%.
- Размер кристалла с максимальным разбросом должен оставаться меньше ячейки тележки `1.8 × 1.8` studs.
- `ParticleEmitter` внутри кристаллов может автоматически прореживаться в заполненной тележке.

### `Cart_Tier1` ... `Cart_Tier8`

Тип: только `Model`.

Минимальная структура:

```text
Cart_Tier1 (Model, PrimaryPart = Root)
├─ Root (BasePart, пол тележки)
├─ BodyParts... (каждая часть соединена с Root)
├─ AttachPoint (BasePart, необязательно)
├─ FacingPoint (BasePart, необязательно)
├─ Hitbox (BasePart, необязательно)
├─ Bottom (BasePart, необязательно)
├─ SprintVFXPoint (BasePart, необязательно)
├─ LeftHandGrip (BasePart, необязательно)
├─ RightHandGrip (BasePart, необязательно)
├─ ValueGui (BillboardGui, необязательно)
└─ ComboGui (BillboardGui, необязательно)
```

Физика тележки:

- `Root` и вся подвижная сборка должны иметь `Anchored = false`.
- Все части кузова должны быть соединены с `Root` через `WeldConstraint` или корректные constraints.
- Код назначает collision group и физические свойства, но не исправляет `Anchored` и не выключает `CanCollide` у всей кастомной геометрии.
- Невидимые маркеры делай `Transparency = 1`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`, `Massless = true`.
- `Hitbox` настрой отдельно как невидимую область удара. Не рассчитывай, что код нормализует все её свойства.

Назначение маркеров:

| Имя | Назначение |
|---|---|
| `AttachPoint` | Используется локальная высота Y крепления тележки к игроку |
| `FacingPoint` | Показывает, какая сторона модели должна смотреть к держателю |
| `Hitbox` | Объём, по которому кирка попадает в тележку |
| `Bottom` | Нижняя точка для проверки ступеней и подъёма |
| `SprintVFXPoint` | Точное место эффекта движения |
| `LeftHandGrip` + `RightHandGrip` | Точные точки рук; добавляй обе, иначе работает автоматический raycast |

`ValueGui` и `ComboGui` должны содержать `TextLabel`. Для радужного комбо положи `UIGradient` прямо в этот `TextLabel` или в его непосредственного родителя. Неполный GUI код удалит и заменит стандартным.

Части с Boolean-атрибутом `DailyColorable = true` перекрашиваются ежедневной наградой.

Сетка груза: 4 колонки × 3 ряда, шаг `1.8` studs, следующие кристаллы идут слоями вверх. Пол `Root` удобно проектировать примерно под `7.2 × 5.4` studs. Для проверки размеров можно запустить `tools/BuildCartSizeGuides.lua`.

### `Mine_Tier1` ... `Mine_Tier8`

Тип: `Model`.

```text
Mine_Tier1 (Model, PrimaryPart назначен)
├─ BuildingParts...
├─ Zone (BasePart, обязательно)
└─ OreDropPoint (BasePart, необязательно)
```

- Назначь `PrimaryPart`, иначе размещение и подгонка к земле будут непредсказуемыми.
- `Zone` ищется рекурсивно и обязана быть `BasePart`. Это парковочная область добычи.
- `OreDropPoint` задаёт только высоту визуального падения руды.
- Шахта статична: заанкорь её части или собери их как корректную статическую модель.
- Для маркеров используй невидимые неколлизионные части.

### `Pickaxe_Tier1` ... `Pickaxe_Tier8`

Тип: `Tool`.

```text
Pickaxe_Tier1 (Tool)
├─ Handle (BasePart, прямой ребёнок)
└─ VisualParts... (соединены с Handle)
```

- `Handle` обязателен и должен быть прямым ребёнком Tool.
- Все `Script` и `LocalScript` внутри исходного Tool удаляются при клонировании.
- Код переименует Tool в `Pickaxe` и выставит `CanBeDropped = false`.
- Геометрию, grip и ориентацию `Handle` настрой в Studio заранее.

## Мир и участок

### `PlotTemplate`

Тип: `Model`. Безопасная структура:

```text
PlotTemplate (Model, PrimaryPart = PlotPad)
├─ PlotPad
├─ MineMarker
├─ PillarMarker
├─ CartSpawnMarker
├─ PlayerSpawnMarker
├─ RebirthMarker
├─ CartButtonMarker       (необязательно)
├─ ShopMarker             (необязательно)
├─ LeaderboardMarker      (необязательно)
├─ GeodeBuildingMarker    (необязательно)
├─ GeodePodiumMarker      (необязательно)
└─ GeodeSafeMarker        (необязательно)
```

Обязательные `BasePart`: `MineMarker`, `PillarMarker`, `CartSpawnMarker`, `PlayerSpawnMarker`, `RebirthMarker`.

Необязательные маркеры имеют запасные позиции, кроме `ShopMarker`: без него `ShopNPC` на участке не создаётся.

Любому маркеру можно добавить соседний `<MarkerName>Look`, например `MineMarkerLook`. Направление от маркера к `...Look` задаст поворот без использования Rotate. Все декорации внутри `PlotTemplate` клонируются на каждый участок.

Ручная расстановка участков:

```text
Workspace
└─ PlotOrigins (Folder)
   ├─ Plot1 (BasePart)
   ├─ Plot1Look (BasePart, необязательно)
   ├─ Plot2
   └─ Plot2Look
```

Без `PlotOrigins` участки расставляются автоматически по кругу.

### `Bank`

Тип: `Model`.

```text
Bank
├─ Building (BasePart, обязательно)
└─ SellZone (BasePart, обязательно)
```

Важно: `Building` должен быть именно `BasePart`, не вложенной `Model`, потому что код читает его `Position` и `Size`. `SellZone` тоже должен быть `BasePart`.

Альтернатива ассету: поставь готовую модель прямо в `Workspace` и добавь ей Boolean-атрибут `IsBank = true`. Тогда код использует её на месте и не клонирует `Assets/Bank`.

### `LeaderboardBoards`

Тип: `Model` с назначенным `PrimaryPart`.

Обязательные рекурсивные `BasePart`:

- `MoneyBoard`
- `RebirthBoard`
- `CartDamageBoard`

Код сам создаёт `SurfaceGui`. Детали и тестовый билдер описаны в `LEADERBOARDS_GUIDE.md`.

### `RespawnButton`

Тип: `BasePart` или `Model`.

У модели назначь `PrimaryPart` или сделай прямой `BasePart` `Root`. Корневая часть получает `ProximityPrompt`, таймер, цвет и анимацию нажатия. Если другие части должны двигаться вместе с кнопкой, соедини их с корнем. Статичный постамент можно оставить отдельным заанкоренным элементом.

## Валуны

### `Boulder_Tier1` ... `Boulder_Tier10`

Тип: `Model` с назначенным `PrimaryPart`, либо часть с именем `Root` внутри модели (код сам найдёт и назначит её как `PrimaryPart`).

Минимальная структура:

```text
Boulder_Tier5 (Model, PrimaryPart = Root)
├─ Root (BasePart)
└─ Decoration... (необязательно, привари к Root через WeldConstraint)
```

Код автоматически:

- анкорит все части (валун статичен);
- отключает коллизию у всех частей (хитбокс идёт по позиции `Root`, не по физической коллизии);
- вешает `BillboardGui` с полоской здоровья на `Root`;
- для элитных ("золотых") валунов добавляет `Highlight`-подсветку поверх модели — отдельную "элитную" модель заводить не нужно, элитность — это ТА ЖЕ модель тира + подсветка.

Если `Boulder_Tier<N>` не найден или у него нет `PrimaryPart`/`Root` — валун этого тира будет цветным шаром-плейсхолдером (цвет берётся из `Config.MineTiers[N].Color`), игра не упадёт, только `warn` в Output.

### `workspace.RubbleBoulderSpawnPoints`

НЕ ассет, а обычная папка прямо в `workspace` (точки на карте, не шаблон для клонирования) — 16 `BasePart`. Каждая часть — точка, где будет стоять один валун.

**Быстрый старт**: запусти `tools/BuildRubbleBoulderSpawnPoints.lua` через Command Bar — расставит 16 подписанных (T1..T10) цветных плейсхолдер-точек кольцом вокруг банка (радиус 70 студов). Это временно — просто подвинь/удали/добавь части внутри папки в Studio, когда решишь, где валуны должны стоять по-настоящему; ровно 16 штук и кольцом оставаться не обязано, код подхватит любой набор `BasePart` внутри папки.

- Атрибут `Tier` (число 1-10) на части — необязателен. Если не проставлен, тир назначится автоматически по кругу (1,2,3...10,1,2...) так, чтобы все 10 тиров были покрыты хотя бы одной точкой при 16 точках.
- Если вручную расставленные `Tier` всё же оставили какой-то тир без единой точки, сервер сам это поправит при старте (заберёт лишнюю точку у тира-дубля) и запишет исправленный `Tier` обратно на точку — с `warn` в Output, что и почему переставил.
- Меньше 16 частей в папке — тоже не критично (`warn`), просто одновременно активных валунов будет меньше, чем `Config.Boulders.MaxActive` (16).

## NPC

Точные имена:

- `UpgradeShopNPC`
- `ShopNPC`
- `RebirthNPC`

Тип: `Model` с назначенным `PrimaryPart`. Имя PrimaryPart может быть любым.

Для СВОЕГО ассета (положил модель под этим именем в `ReplicatedStorage/Assets`) — по прямому запросу код делает МИНИМУМ:

- ставит модель на маркер участка (позиция + поворот, с учётом необязательного `FacingPoint` — см. ниже);
- поправляет высоту по `GetBoundingBox`, чтобы модель не проваливалась под пол и не парила над ним;
- добавляет `ProximityPrompt` для взаимодействия.

И ничего больше: аксессуары/шляпы не трогаются и не сдвигаются, скрипты внутри модели не трогаются, части НЕ анкорятся и коллизии НЕ отключаются (у модели может быть свой скрипт с движением/анимацией, которому нужна рабочая физика), диалоговый BillboardGui НЕ строится и не удаляется — свой билборд (если он там есть) остаётся как есть, чужого научить формату `gui/name/dialog` (см. ниже) код не пытается. Хочешь диалог для своего NPC — либо положи в модель собственный `gui` по формату ниже, либо реализуй сам.

Если своего ассета НЕТ (используется код-генерируемый плейсхолдер — блочный человечек) — код по-прежнему делает всё как раньше:

- анкорит все части;
- отключает коллизии;
- сдвигает шляпы под свою геометрию;
- строит стандартный диалоговый BillboardGui.

Необязательный `FacingPoint` показывает локальный перед NPC — учитывается в обоих случаях (это часть позиционирования на маркере, а не "лишняя" обработка).

Формат диалога (актуален только для код-генерируемого плейсхолдера — см. выше):

```text
NPC Model
└─ gui (BillboardGui)
   ├─ name (TextLabel, обязательно)
   ├─ dialog (TextLabel, обязательно)
   └─ arrow (TextLabel, необязательно)
```

`name` и `dialog` обязательны, `arrow` необязателен. Неполный GUI у код-генерируемого плейсхолдера будет удалён и заменён стандартным — это правило применяется, только когда используется плейсхолдер, а не твой ассет.

Для декоративной анимации NPC есть пример `tools/ExampleNpcStretchScript.lua`. Сервисы выставляют атрибут `Talking`, который можно читать из своего скрипта.

## Гоблины

### `Goblin_Warrior_1/_2/_3`, `Goblin_Thief_1/_2/_3`, `Goblin_Berserker_1/_2/_3`, `Goblin_King_1/_2/_3`, `Goblin_Golden_1/_2/_3`

**По 3 скина на тип** — при каждом спавне случайно выбирается один из трёх (визуальное разнообразие среди одинаковых по статам гоблинов одного типа). Не обязательно делать все три сразу: если найден только один номер — используется он; если не найдено ни одного пронумерованного варианта, код на всякий случай попробует старое имя без номера (`Goblin_Warrior`, для обратной совместимости), и только потом — процедурный плейсхолдер.

Тип: `Model`. В отличие от NPC выше — это не просто модель с `PrimaryPart`, а полноценный R6-риг, потому что гоблины ходят/атакуют/умирают через `Humanoid`.

Обязательные части, ИМЕНА ТОЧНО такие (регистр и пробелы важны):

```text
Goblin_Warrior_1 (Model)
├─ HumanoidRootPart (BasePart)
├─ Torso (BasePart)
├─ Head (BasePart)
├─ Left Arm (BasePart)
├─ Right Arm (BasePart)
├─ Left Leg (BasePart)
└─ Right Leg (BasePart)
```

Если хотя бы одной из этих семи частей нет или она не `BasePart` — этот КОНКРЕТНЫЙ скин отклоняется (`warn` в Output с указанием, какой именно части не хватает), код пробует следующий из трёх номеров, и только если ни один не подошёл — текущий зелёный кубический плейсхолдер.

Необязательно, но желательно — Motor6D-суставы (`RootJoint`, `Neck`, `Left Shoulder`, `Right Shoulder`, `Left Hip`, `Right Hip`), стоящие в `Part0` соответствующего сустава (см. таблицу ниже). Если каких-то из них нет — код сам достроит недостающие с теми же C0/C1, что и у плейсхолдера, поэтому гоблин в любом случае будет нормально ходить/атаковать; без правильных суставов только КОНЕЧНОСТИ не будут гнуться при ходьбе (визуально "скользят" вместо шага).

| Сустав | Part0 | Part1 |
|---|---|---|
| `RootJoint` | `HumanoidRootPart` | `Torso` |
| `Neck` | `Torso` | `Head` |
| `Left Shoulder` | `Torso` | `Left Arm` |
| `Right Shoulder` | `Torso` | `Right Arm` |
| `Left Hip` | `Torso` | `Left Leg` |
| `Right Hip` | `Torso` | `Right Leg` |

`HumanoidRootPart` код сам сделает невидимым (`Transparency = 1`) и без коллизии — своё оформление на нём можно не делать, всё равно не будет видно.

**`Goblin_Golden_1/_2/_3`** — модель для элитного гоблина, который спавнится при разрушении "золотого" валуна. **Это отдельная запись в энциклопедии** (`Config.Goblins.Types.Golden`, копия статов короля с другим именем/цветом) — раньше он записывался туда же, куда и обычный King, и убить его было неотличимо для коллекции; теперь у него свой собственный прогресс открытия. `MinMineTier`/`MaxMineTier` = 11 у этой записи — так обычные волны гоблинов никогда его не выбирают (валидных тиров шахты только 1-10), появляется исключительно через золотой валун. Если модель не найдена — код по-старому берёт `Goblin_King` (с той же логикой 3 скинов) и перекрашивает в оранжевый; если модель найдена — перекраска НЕ применяется, чтобы не портить готовый золотой ассет.

## VFX

### `BookVFX`

Тип: `ParticleEmitter`, `BasePart` или `Model` с эмиттером внутри.

- Положи ассет прямым ребёнком `ReplicatedStorage/Assets`.
- Клиент клонирует его в `CurrentCamera` за `CollectionMenu/BookButton`.
- Для `Model` все части должны быть собраны вокруг центра; коллизии отключаются кодом.
- Необязательный атрибут `ScreenOffset` типа `Vector2` сдвигает эффект в пикселях относительно центра книги.
- Необязательный числовой атрибут `Depth` задаёт расстояние до камеры при эталонной высоте экрана; по умолчанию `12`.
- Необязательный числовой атрибут `ReferenceViewportHeight` задаёт эталонную высоту в пикселях; по умолчанию `1080`. Дистанция нормализуется по высоте, поэтому размер VFX относительно книги сохраняется на телефоне.
- Если ассета нет, используется UI-fallback без настоящих частиц.

### `swing`

Тип: строго `ParticleEmitter`.

- Настрой `Texture`, `Lifetime`, `Speed`, `Size`, `Color` и остальные свойства.
- Необязательный numeric-атрибут `EmitCount`, по умолчанию 10.
- Эффект испускается один раз около `HumanoidRootPart`.
- Без ассета удар работает, но без swing-VFX.

### `SprintVFX`

Тип: `BasePart` или `Model` с `PrimaryPart`/прямым `Root`.

- Все `ParticleEmitter` могут лежать рекурсивно, в том числе внутри `Attachment`.
- Корень приваривается к тележке.
- В составной модели заранее соедини остальные части с корнем и отключи у них коллизии.
- Позиция берётся из `SprintVFXPoint`, затем `FacingPoint`, затем рассчитывается автоматически.

### `ShieldVfx` и `ShieldVfxVIP`

Тип: `BasePart` или `Model` с `PrimaryPart`/прямым `Root`.

- Корень приваривается над головой игрока.
- Все вложенные `ParticleEmitter` включаются и выключаются кодом.
- Остальные части составной модели заранее соедини с корнем и сделай неколлизионными.

### `BankSellVFX` и `PickaxeHitVFX`

Тип: `BasePart` или `Model` с `PrimaryPart`/прямым `Root`.

- Это одноразовые эффекты, которые удаляются после таймера.
- Для `Model` код почти не исправляет физику. Все части должны быть собраны, безопасно заанкорены/соединены и иметь выключенные коллизии.
- `ParticleEmitter` может находиться в любом потомке, но сервис не вызывает для кастомного ассета `Emit()`. Для готового эффекта оставь `Enabled = true` и настрой `Rate`, чтобы он работал всё короткое время жизни. Контракт `EmitCount` здесь не поддерживается.

### `GeodeCartVFX`

Тип: `BasePart` или `Model` с `PrimaryPart`/прямым `Root`.

- Код сам делает все части неколлизионными и приваривает каждую часть к физической жеоде.
- `ParticleEmitter` получает burst; необязательный `EmitCount`, по умолчанию 24.

`Coin` существует только как старый fallback фабрики и сейчас не вызывается игровым кодом.

### `LootBox`

Тип: `Model` (желательно с `PrimaryPart` или прямым `Root`) либо одиночный `BasePart`.

Коробка, которая **визуально выпадает** из валуна или сундука, когда саму награду показать предметом нельзя — скины и всё в этом духе (они существуют только в инвентаре). Сценарий такой: коробка вылетает из камня по дуге, кувыркаясь, падает на землю, подпрыгивает и через секунду влетает в игрока.

- Принимаются имена `LootBox`, `Box` и `box` — последние два оставлены для совместимости со старыми сборками.
- Размер подгонять не нужно: код сам масштабирует коробку так, чтобы её наибольшая сторона была 2 стада (`LOOT_BOX_TARGET_STUDS` в `GoblinService.lua`). Если модель уже примерно такого размера (в пределах 5%), она не трогается вовсе.
- Декоративные части приваривай к корню через `WeldConstraint`, как и у остальных составных моделей.
- Без своего ассета используется кодовый плейсхолдер: деревянный ящик с крышкой и двумя перекрещенными жёлтыми лентами. Именно его и нужно заменить.

Раньше на этом месте искался только `ReplicatedStorage.Assets.box`, которого не создаёт ни один билдер, поэтому по умолчанию вместо коробки летел неоновый шарик.

## Жеоды

### Физические жеоды: 8 ассетов

```text
Geode_Stone
Geode_Crystal
Geode_Amber
Geode_Topaz
Geode_Jade
Geode_Onyx
Geode_Aurora
Geode_Nebula
```

Тип: `BasePart` или `Model`.

Для модели используй прямой `Root`, назначенный `PrimaryPart`. Все дополнительные части обязательно соедини с ним: при перевозке код приваривает к тележке только корень.

`GeodeVFX_<Type>` не является отдельным верхнеуровневым ассетом. Билдер создаёт такой `Attachment` внутри соответствующей физической жеоды.

`GeodeResultTemplates` создаётся `BuildGeodeAssets.lua`, но текущий runtime его не читает. Не трать время на его оформление: результат открытия строится из `GeodeUi` и значений `ImageId`.

### Постройки жеод

| Ассет | Тип | Контракт |
|---|---|---|
| `GeodeBuilding` | `Model` | `PrimaryPart`/`Root` и рекурсивный `BasePart` `Crusher` |
| `GeodePodium` | `BasePart` или `Model` с `PrimaryPart`/`Root` | Поверхность установленной коллекционной руды |
| `GeodeSafe` | `BasePart` или `Model` с `PrimaryPart`/`Root` | Точка сбора пассивного дохода |
| `GeodeCartVFX` | `BasePart` или `Model` | Контракт описан в разделе VFX |

`GeodeBuilding`, `GeodePodium` и `GeodeSafe` анкорятся кодом. На `Crusher`, подиум и сейф добавляется или переиспользуется `ProximityPrompt`. Для моделей назначь `PrimaryPart` или создай часть `Root`.

У `GeodePodium` расположи `Root` в центре платформы: именно он совмещается с маркером участка. Необязательный невидимый `BasePart` `OrePlacement` задаёт точную нижнюю центральную точку, куда ставится коллекционный камень; без него код использует центр `Root` и верхнюю границу модели.

### Коллекционная руда: 34 ассета (24 жеодных + 10 валунных)

Тип каждого: `BasePart` или `Model` с `PrimaryPart`/`Root`. Они показываются статично на подиуме (и теперь ещё физически в руках при переноске с валуна — см. раздел про валуны выше), поэтому код анкорит все части; внутренние сварки для этого отображения не обязательны.

| Жеода | Точные имена ассетов |
|---|---|
| Stone | `CollectionOre_Quartz`, `CollectionOre_Amethyst`, `CollectionOre_GreenCrystal` |
| Crystal | `CollectionOre_Sapphire`, `CollectionOre_Ruby`, `CollectionOre_Diamond` |
| Amber | `CollectionOre_Citrine`, `CollectionOre_Carnelian`, `CollectionOre_SunOpal` |
| Topaz | `CollectionOre_Aquamarine`, `CollectionOre_Turquoise`, `CollectionOre_Moonstone` |
| Jade | `CollectionOre_Peridot`, `CollectionOre_Malachite`, `CollectionOre_Tourmaline` |
| Onyx | `CollectionOre_Garnet`, `CollectionOre_Bloodstone`, `CollectionOre_Obsidianite` |
| Aurora | `CollectionOre_Starshard`, `CollectionOre_Moonlight`, `CollectionOre_Prism` |
| Nebula | `CollectionOre_Voidshard`, `CollectionOre_Stardust`, `CollectionOre_Eclipse` |

| Тир валуна | Точное имя ассета |
|---|---|
| 1 | `CollectionOre_Rubblegem` |
| 2 | `CollectionOre_Ironflake` |
| 3 | `CollectionOre_Coalheart` |
| 4 | `CollectionOre_Duskstone` |
| 5 | `CollectionOre_VerdantCore` |
| 6 | `CollectionOre_Emberite` |
| 7 | `CollectionOre_Frostvein` |
| 8 | `CollectionOre_Wyrmglass` |
| 9 | `CollectionOre_UmbralShard` |
| 10 | `CollectionOre_Titanheart` |

Не меняй ID после релиза: `GreenCrystal`, `SunOpal`, `Obsidianite` и остальные ключи хранятся в данных игроков. Видимое `DisplayName` менять безопасно.

## Скины

Скины не получают автоматический визуальный плейсхолдер. Если ассета нет или он невалиден, скин исключается из выдачи, инвентаря и экипировки.

### Контракт модели скина

Тип: `BasePart` или `Model`.

Рекомендуемая структура:

```text
Skin_Pickaxe_BigWooden (Tool)
├─ Handle (BasePart, прямой ребёнок)
├─ VisualPart1
├─ VisualPart2
└─ ParticleEmitter / Trail / Beam / Light
```

Корень выбирается по приоритету:

1. рекурсивный `BasePart` `SkinRoot`;
2. назначенный `PrimaryPart`;
3. первый найденный `BasePart`.

Для `Tool` используй прямой `Handle`; для `Model` — прямой `SkinRoot`, назначенный как `PrimaryPart`. Соедини дополнительные физические части с корнем через `WeldConstraint` и расположи визуал относительно него так, как он должен сидеть на кирке.

Важное отличие от обычных моделей: внутренние `WeldConstraint` не обязательны. `SkinService` сам делает каждую часть незаанкоренной, неколлизионной, невесомой и приваривает напрямую к игровому корню. `Script` и `LocalScript` из клона удаляются.

### Точные имена

Кирки, 17:

```text
Skin_Pickaxe_BigWooden
Skin_Pickaxe_Crystal
Skin_Pickaxe_Love
Skin_Pickaxe_Radioactive
Skin_Pickaxe_VoidFixed
Skin_Pickaxe_Amethyst
Skin_Pickaxe_CactusSword
Skin_Pickaxe_Fish
Skin_Pickaxe_TungTungStick
Skin_Pickaxe_BigMole
Skin_Pickaxe_DevSword
Skin_Pickaxe_GoldSword
Skin_Pickaxe_GoldKunai (Gold Shuriken)
Skin_Frostmorn
Skin_GOLD
```

Тележки, 11:

```text
Skin_Cart_Miner
Skin_Cart_Royal
Skin_Cart_Industrial
Skin_Cart_Frost
Skin_Cart_Obsidian
Skin_Cart_Amber
Skin_Cart_Topaz
Skin_Cart_Jade
Skin_Cart_Onyx
Skin_Cart_Aurora
Skin_Cart_Nebula
```

Соответствие постоянных ID из сохранений и моделей:

| ID в `Config.Skins.Definitions` | `Kind` | Точный `AssetName` |
|---|---|---|
| `BigWoodenPickaxe` | Pickaxe | `Skin_Pickaxe_BigWooden` |
| `CrystalPickaxe` | Pickaxe | `Skin_Pickaxe_Crystal` |
| `LovePickaxe` | Pickaxe | `Skin_Pickaxe_Love` |
| `RadioactivePickaxe` | Pickaxe | `Skin_Pickaxe_Radioactive` |
| `VoidPickaxe` | Pickaxe | `Skin_Pickaxe_VoidFixed` |
| `MinerCart` | Cart | `Skin_Cart_Miner` |
| `RoyalCart` | Cart | `Skin_Cart_Royal` |
| `IndustrialCart` | Cart | `Skin_Cart_Industrial` |
| `FrostCart` | Cart | `Skin_Cart_Frost` |
| `ObsidianCart` | Cart | `Skin_Cart_Obsidian` |
| `AmethystPickaxe` | Pickaxe | `Skin_Pickaxe_Amethyst` |
| `AmberCart` | Cart | `Skin_Cart_Amber` |
| `CactusSword` | Pickaxe | `Skin_Pickaxe_CactusSword` |
| `TopazCart` | Cart | `Skin_Cart_Topaz` |
| `FishSkin` | Pickaxe | `Skin_Pickaxe_Fish` |
| `JadeCart` | Cart | `Skin_Cart_Jade` |
| `TungTungStick` | Pickaxe | `Skin_Pickaxe_TungTungStick` |
| `OnyxCart` | Cart | `Skin_Cart_Onyx` |
| `BigMole` | Pickaxe | `Skin_Pickaxe_BigMole` |
| `AuroraCart` | Cart | `Skin_Cart_Aurora` |
| `DevSword` | Pickaxe | `Skin_Pickaxe_DevSword` |
| `GoldSword` | Pickaxe | `Skin_Pickaxe_GoldSword` |
| `GoldKunai` | Pickaxe | `Skin_Pickaxe_GoldKunai` |
| `Frostmorn` | Pickaxe | `Skin_Frostmorn` |
| `Gold` | Pickaxe | `Skin_GOLD` |
| `NebulaCart` | Cart | `Skin_Cart_Nebula` |

В текущем конфиге нет `Skin_Cart_Ember`, `Skin_Cart_Crystal`, `Skin_Cart_Toxic` и `Skin_Cart_Void`. Добавление таких имён в `Assets` само по себе ничего не даст: для нового скина нужна отдельная запись в `Config.Skins.Definitions`.

Категории `Cart` и `Ore` в Skin UI сейчас помечены `COMING SOON` и отключены через `Config.Skins.EnabledKinds`. Игрокам доступны только скины `Pickaxe`; определения и модели тележек сохранены для будущего включения.

### Как переименовывать скин

Каждый скин имеет три разных имени:

- ключ определения, например `EmberPickaxe` — постоянный ID в сохранениях;
- `AssetName`, например `Skin_Pickaxe_Ember` — точное имя модели;
- `DisplayName` — видимый текст.

Безопасно меняй только строку `DisplayName`:

```lua
-- Было
EmberPickaxe = { Kind = "Pickaxe", DisplayName = "Ember Pickaxe", AssetName = "Skin_Pickaxe_Ember", ... },

-- Стало
EmberPickaxe = { Kind = "Pickaxe", DisplayName = "Клинок Пламени", AssetName = "Skin_Pickaxe_Ember", ... },
```

Это не ломает сохранения и не требует повторного запуска билдера. Достаточно синхронизации Rojo и нового запуска игры.

Правила для `DisplayName`:

- оставляй строкой;
- не используй RichText-теги вида `<...>`;
- одинаковые видимые названия технически допустимы, но путают игрока;
- не переименовывай ключ `EmberPickaxe` после релиза без миграции данных.

`AssetName` можно поменять только одновременно с точным переименованием модели в `Assets`. Сохранения останутся, но до появления нового ассета скин будет недоступен.

## Интерфейс и билдеры

UI хранится в `StarterGui`, но не синхронизируется текущим `default.project.json`. Билдеры выполняются из Studio Command Bar в Edit Mode. Весь интерфейс (v20) собирает один `tools/BuildAllUI.lua` — подробности в `UI_V20_GUIDE.md`.

### Все билдеры

| Билдер | Что создаёт/заменяет |
|---|---|
| `BuildNewAssetWorkspacePack.lua` | Безопасно создаёт в `Workspace` пакет из 22 скинов и 36 ассетов жеод; ничего не удаляет из `Assets` |
| `BuildAllUI.lua` | **v20: ВЕСЬ интерфейс** — все экраны игры в `StarterGui` в едином стиле (список — `UI_V20_GUIDE.md`) |
| `ApplyUiSkins.lua` | Проставляет картинки из `UiTheme.Skins`/`UiTheme.Icons` во всём StarterGui, не трогая раскладку |
| `BuildSkinAssets.lua` | 22 заглушки скинов в `Assets` |
| `BuildGeodeAssets.lua` | Все модели жеод/руды; `StarterGui/GeodeUi` — через общий билдер (UiRegistry) |
| `BuildLeaderboardBoards.lua` | Удаляет старые доски и создаёт preview в `Workspace` |
| `BuildCartSizeGuides.lua` | Только временные размеры в `Workspace/CartSizeGuides` |
| `BuildRubbleBoulderSpawnPoints.lua` | `workspace/RubbleBoulderSpawnPoints` — 16 плейсхолдер-точек кольцом вокруг банка, временно (см. раздел "Валуны") |

Каждый билдер разрушителен для указанных объектов. Особенно опасны:

- `BuildSkinAssets.lua`: удаляет все 22 готовых скина с точными именами;
- `BuildGeodeAssets.lua`: удаляет готовые жеоды, коллекционную руду, постройки и Geode UI;
- `BuildLeaderboardBoards.lua`: удаляет и финальный ассет, и старый preview, затем создаёт только новый preview в `Workspace`;
- `BuildAllUI.lua`: пересоздаёт экраны (кроме `SKIP_EXISTING = true` или не входящих в `ONLY`) — ручные правки этих экранов пропадут.

Исключение — `BuildNewAssetWorkspacePack.lua`: он не трогает `ReplicatedStorage/Assets` и отказывается запускаться, если в `Workspace` уже есть `NEW_ASSETS_MOVE_CHILDREN_TO_ASSETS`. После редактирования открой эту папку, выдели все 58 дочерних ассетов и перенеси их прямо в `ReplicatedStorage/Assets`. Саму папку переносить нельзя: runtime не ищет ассеты во вложенных папках.

Как собрать новый 3D-набор:

1. Останови Play Test и дождись синхронизации Rojo.
2. Открой `tools/BuildNewAssetWorkspacePack.lua` и скопируй весь файл.
3. В Studio открой `View → Command Bar`, вставь код и нажми Enter.
4. В `Workspace` появится и автоматически выделится папка `NEW_ASSETS_MOVE_CHILDREN_TO_ASSETS`.
5. Замени геометрию внутри созданных шаблонов, сохраняя верхнеуровневые имена, `SkinRoot`, `Root` и `Crusher`.
6. Раскрой папку, выдели все её 58 дочерних объектов и перетащи прямо в `ReplicatedStorage/Assets`.
7. Не переноси саму папку-обёртку и не запускай старые `BuildSkinAssets.lua`/`BuildGeodeAssets.lua` после переноса: они заменят готовые модели заглушками.

### Минимальные контракты UI

| ScreenGui | Главные обязательные объекты |
|---|---|
| `CartInteractionUi` | `CartPromptGui/Text`, `CartDropHintGui/Text`, `TalkPromptGui/Text`; отсутствие может остановить значительную часть `CustomCartUI` |
| `Hud` | `MoneyPill/Value`, `RebirthPill/Value` |
| `PickaxeHotbar` | `Slot/Icon`; fallback доступен |
| `ActionButtons` | `ProtectionButton/Icon`; fallback доступен |
| `SettingsMenu` | `GearButton`, `Panel`, `SoundToggle`, `CodeInput`, `RedeemButton`, `ResultText`; fallback доступен |
| `DialogResponses` | `Responses/Template/Text`; нужен, если нет полноценного `UpgradeShopCards` |
| `UpgradeShopCards` | `Panel`, `CardRow`, `Card_Mine`, `Card_Cart`, `Card_Pickaxe`, в карточках `StatusLine`, `PriceButton/Caption` |
| `ShopEntry` | `ShopButton`; без него пропадает угловая кнопка магазина |
| `GamepassQuickBar` | `Bar` и кнопки `<ConfigKey>Button`; отдельные кнопки можно не добавлять |
| `ShopUi` | `Dimmer`, `Panel`, `Body`, `Cards_<Tab>`, `CardSlotN`, `Pager`, `Tab_<Tab>` |
| `SkinEntry` | `SkinsButton` |
| `SkinUi` | `Panel`, `Dimmer`, `CloseButton`, `Body`, `Tabs`, `BackButton`, `Inventory`, `SkinCardTemplate`, `Preview`, `Viewport`, `EquipButton` |
| `QuestUi` | `QuestToggleButton` (+ `Icon`, `Badge`), `QuestModal` (`Background`, `Title`, `CloseButton`, `List/QuestRowTemplate`), `Dimmer`, `PinnedTracker` — каждая строка квеста (`QuestRowTemplate`/клон в `List`/`PinnedTracker`) содержит `Background`, `Icon`, `PinButton`, `Body/Title`, `Body/Description`, `ProgressBarBackground/ProgressBarFill`, `Body/Progress`, `Body/Reward` |
| `DailyRewardUi` | `Dimmer`, `Panel`, `CloseButton`, `ClaimButton`, `Day1` ... `Day7` как `GuiButton` |
| `GeodeUi` | Лучше строить `BuildGeodeAssets.lua`; клиент строго проверяет полную структуру открытия и коллекции |
| `Toast` | `Panel/Text`, необязательный `ActionButton/Caption` |

У всех созданных ScreenGui должно быть `ResetOnSpawn = false`.

Fallback у UI неодинаковый:

- `CartInteractionUi`, `Hud`, `SkinEntry` и `SkinUi` лучше считать обязательными;
- без `ShopUi`, `ShopEntry`, `GamepassQuickBar` или `Toast` соответствующая функция просто исчезает;
- `QuestUi`, `GeodeUi`, `DailyRewardUi` умеют построить fallback только при полном отсутствии; существующий неполный UI может привести к предупреждению и отключению клиента;
- `SettingsMenu`, `PickaxeHotbar`, `ActionButtons`, `RebirthDialogButtons` имеют рабочие fallback.

### `MoneyFxTemplate`

Прямой ребёнок `Assets`, тип любой `GuiObject`. Обычно это `ImageLabel`. Клиент клонирует его для летящих монет и перезаписывает позицию, размер и anchor. Без него используется `Config.Icons.FlyingCoin`, затем цветной `Frame`.

### Loading screen

Старый `StarterGui/PreloadScreen` больше не поддерживается и удаляется. Экран загрузки создаёт `src/LoadingScreen.client.lua` в `ReplicatedFirst`. Текущая картинка задана константой `IMAGE_ID` в этом файле.

## Изображения, анимации и звук

### Числовые ImageId

Для следующих полей указывай только число без `rbxassetid://`; `0` означает визуальную заглушку:

- `Config.Icons`: `Pickaxe`, `Money`, `Rebirth`, `Protection`, `Settings`, `Shop`, `Robux`, `Hint`, `Owned`, `SliderThumb`, `FlyingCoin`;
- `Config.Geodes.Images`: изображения 8 жеод и служебные `Dust`, `MoneySmall`, `MoneyLarge`, `MoneyJackpot`, `OfflineIncome`, `Installed`, `SlotBackground`, `CrackGlow`;
- `Config.Geodes.Ores.<OreId>.ImageId`: 24 изображения коллекционной руды;
- `Config.Boulders.CustomOres.<OreId>.ImageId`: 10 изображений валунной руды (`Rubblegem`, `Ironflake`, `Coalheart`, `Duskstone`, `VerdantCore`, `Emberite`, `Frostvein`, `Wyrmglass`, `UmbralShard`, `Titanheart`) — используются и в подиуме, и в карточке переноски (`RubbleCrystalHotbar`);
- `Config.Goblins.IconImage`: одна общая иконка для ВСЕХ гоблинов (билборд здоровья + новая вкладка "Mobs" в книге коллекций) — поля нет в `Config.lua` по умолчанию, нужно добавить самому: `Config.Goblins.IconImage = 0,`;
- `CRYSTAL_SLOT_BACKGROUND_IMAGE_ID` в `tools/BuildRubbleCrystalUI.lua` (не в `Config.lua`, локальная константа файла) — фон карточки переноски кристалла;
- `Config.Skins.Definitions.<SkinId>.ImageId`: 22 иконки скинов;
- `Config.UpgradeShop.Icons` и `Config.UpgradeShop.Cards.CoverIcons`;
- `Config.Shop.Items.<Item>.ImageId`;
- `Config.QuickBar.Passes`, `Config.QuickBar.DevProductAd`, `HintImageId`, `OwnedImageId`;
- `Config.UI.CloseButtonImageId`;
- `Config.Tutorial.TrailTextureId`.

Старых полей `Config.Tutorial.Steps[*].ImageId` и `Config.Tutorial.SkipImageId` в текущем Config нет.

### Анимации

Полные строки `rbxassetid://...`:

- `Config.Animations.PickaxeSwingLeft`
- `Config.Animations.PickaxeSwingRight`
- `Config.Animations.CartIdle`
- `Config.Animations.CartWalk`

Анимации должны принадлежать владельцу experience/группе и соответствовать используемому ригу.

### Звуки

Каждая запись `Config.Sounds` имеет вид:

```lua
SoundName = { Id = "rbxassetid://123", Volume = 0.5 }
```

Поддерживаются:

```text
PickaxeSwing, PickaxeHit, PickaxeHitCart,
CrystalSpawn, CrystalDrop, CrystalKnockout, CrystalPickup,
Sell, CartSoldOut, CartTake, CartDrop, CartRoll,
Upgrade, UpgradeFail, Rebirth, ComboActivate,
UiButtonClick, DialogueChoice, DialogueTypewriter,
GeodeSpawn, GeodeOpen, GeodeReveal, SafeCollect,
QuestProgress, QuestComplete,
DailyRewardReady, DailyRewardClaim,
TutorialStepComplete
```

`CartRoll` должен нормально зацикливаться. `CoinCollect` сейчас не используется. Музыка задаётся в `Config.Music.Tracks` полными `rbxassetid://...` строками.

## Финальный порядок установки

1. Запусти Rojo и дождись полной синхронизации.
2. При необходимости запусти билдеры заглушек до начала ручной работы, включая `BuildRubbleCrystalUI.lua`.
3. Положи финальные модели прямыми детьми `ReplicatedStorage/Assets` — включая `Boulder_Tier1..10` и `Goblin_<Тип>_1/_2/_3` (Warrior/Thief/Berserker/King/Golden, по 3 скина на тип).
4. Создай в `workspace` папку `RubbleBoulderSpawnPoints` с 16 `BasePart` (если ещё нет) — без неё валуны не заспавнятся вообще; для быстрого старта запусти `tools/BuildRubbleBoulderSpawnPoints.lua` (расставит временные плейсхолдеры кольцом вокруг банка).
5. Проверь точные имена, `PrimaryPart`, `Root`, `SkinRoot`, зоны и маркеры.
6. Для движущихся моделей проверь сварки, `Anchored = false`, коллизии и массу.
7. Запусти нужные UI-билдеры и только затем меняй картинки, размеры и оформление.
8. Заполни изображения, анимации и звук в `Config.lua` — включая `Config.Boulders.CustomOres.*.ImageId` и добавленный вручную `Config.Goblins.IconImage`.
9. Сохрани или опубликуй place, потому что Studio-ассеты не входят в Rojo build.
10. Проверь Output на `warn` и ошибки.
11. Протестируй свежий сервер минимум с двумя игроками, смерть/respawn, кражу тележки, магазин, жеоды, подиум, safe, скины, квесты, daily reward, и отдельно — разрушение валуна каждого тира и спавн элитного/золотого гоблина.
12. Отдельно проверь мобильный эмулятор и разные разрешения.

## Чек-лист модели

1. Ассет является прямым ребёнком `ReplicatedStorage/Assets`.
2. Имя совпадает побуквенно, включая регистр.
3. Тип объекта совпадает с контрактом.
4. У `Model` назначен правильный `PrimaryPart`.
5. Физический `Root` или `SkinRoot` является `BasePart`.
6. Движущиеся составные модели правильно сварены и не заанкорены.
7. Статичные модели заанкорены или будут заанкорены соответствующим сервисом.
8. Невидимые маркеры не имеют коллизии, touch и query.
9. Обязательные GUI-дети названы точно.
10. Билдер больше не будет запускаться поверх готового ассета.
11. В Play Test нет предупреждений о malformed asset.
12. Place сохранён после добавления Studio-ассетов.
