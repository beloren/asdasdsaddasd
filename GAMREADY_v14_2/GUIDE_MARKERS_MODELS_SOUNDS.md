# Гайд: маркеры, модели, звуки (v20.134)

Коротко: **маркер** — обычная деталь (Part), которую ты ставишь в Studio. Игра берёт её место и поворот, а в игре сама делает её невидимой и без коллизии. Деталь с тем же именем + `Look` (например `GamepassNpcMarkerLook`) — куда объект смотрит лицом. Нет `Look` — смотрит туда же, куда передняя грань (Front) маркера.

**Проверка карты:** вставь `tools/CheckMapMarkers.lua` в Command Bar и нажми Enter — в Output будет список `[OK]` / `[!!]`.

---

## 1. Маркеры на общей карте (Workspace)

| Имя детали | Что делает | Обязательно? |
|---|---|---|
| `CompassCenterMarker` (+`Look`) | Куда TRAVEL → **Ore Merchant** телепортирует (игрок встаёт на верх детали) | нет — без неё встаёт перед торговцем |
| `GamepassNpcMarker` (+`Look`) | НПС магазина геймпассов (встаёт ступнями на низ детали) | да, иначе НПС не появится |
| `IslandKeeperMarker` (+`Look`) | Продавец островов | нет — встанет у банка |
| Папка `RubbleBoulderSpawnPoints` → любые детали | **Дикие валуны**: сколько деталей — столько валунов, тир случайный | да |
| Папка `PlotOrigins` → `Plot1..Plot8` (+`Plot1Look`...) | Где стоят 8 баз | да |
| Модель с атрибутом `IsBank` → деталь `SellZone` | Зона продажи (крот вылезает внутри) | да |
| …внутри банка: `Building` | Куда летит проданная руда | желательно |
| …внутри банка: `MerchantSpot` (+`Look`) | Где стоит Ore Merchant | нет |
| `GoblinCamp` → `Zone`, папка `Spawns`, `Marker` | Лагерь гоблинов, точки появления, табличка | да |
| `LikeGoalBoard` | Табло целей по лайкам | нет |
| `BridgeSpans` | Мосты, поднимающиеся из-под земли | нет |

Точки валунов быстро накидать: `tools/BuildRubbleBoulderSpawnPoints.lua` (Command Bar). Твои точки не трогает, докладывает новые до 36.

## 2. Маркеры внутри базы (ReplicatedStorage/Assets/PlotTemplate)

| Имя детали | Что ставится |
|---|---|
| `MineMarker` (+`Look`), `MineFacingMarker` | Шахта и куда она смотрит лицом |
| `MinerMarker` (+`Look`) | Шахтёр у шахты (можно и внутри модели `Mine_TierN`) |
| `PlayerSpawnMarker` | Где появляется игрок (и TRAVEL → My Raft) |
| `RebirthMarker` | НПС престижа |
| `PrestigeCaseMarker` (+`Look`) | Сундук/кейс престижа (дерево перков) |
| `ShopMarker` | НПС магазина |
| `BoulderMarker1`, `BoulderMarker2`, … | Личные валуны базы (закрывают шахту в начале) |
| `GeodeBuildingMarker`, `GeodePodiumMarker`, `GeodeSafeMarker` | Наковальня, подиум кристалла, сейф |
| `IslandAnvilMarker`, `IslandIncomeMarker`, `IslandSmelterMarker` | Где поднимаются острова |
| `LeaderboardMarker`, `PillarMarker`, `CartSpawnMarker`, `CartButtonMarker` | Лидерборд, колонна, служебные |
| В модели `Mine_TierN`: `CameraMarker1..N` (+`Look`) | Точки камеры при улучшении шахты |

---

## 3. Модели — что заменить (ReplicatedStorage/Assets)

Положи свою модель **с этим именем** в `ReplicatedStorage/Assets` — игра возьмёт её вместо заглушки. У модели должен быть PrimaryPart (или `HumanoidRootPart`). Для НПС с анимацией стойки нужен риг с Humanoid/AnimationController.

**НПС**
- `GamepassNPC` — НПС магазина геймпассов (стойка как у продавца островов)
- `IslandKeeperNPC` — продавец островов
- `MinerNPC` — шахтёр
- `BankMerchant` — Ore Merchant
- `RebirthNPC`, `UpgradeShopNPC`, `ShopNPC`
- `SellMole` — крот-скупщик (нужна деталь `Head` — над ней меню)

**Мир и база**
- `PlotTemplate` — вся база
- `Mine_Tier1..N` — шахты по тирам
- `Boulder_Tier1..9` — валуны
- `Bank` — банк
- `GeodeBuilding`, `GeodePodium`, `GeodeSafe`
- `Island_Anvil`, `Island_Income`, `Island_Smelter`
- `Smelter`, `Smelter_LevelN`
- `LeaderboardBoards`
- `PrestigeCase` — кейс престижа

**Предметы**
- `OreBox` — коробка руды (рисунок руды на PrimaryPart)
- `OreRandomBox` — рандом-бокс (без неё — перекрашенная `OreBox` со знаком «?»)
- `Crystal_<Ключ>` / `Crystal_<Ключ>_V2..4` — руда и её вариации
- `Ingot` / `Ingot_<Ключ>` — слитки
- `Geode_<Тип>` — жеоды
- `Chest_Common`, `Chest_Rare`, `Chest_Epic`, `Chest_Legendary`
- `Pickaxe_Tier1..N` — кирки; скины — `Skin_Pickaxe_...`, `Skin_Cart_...` (имена в `Config.Skins`)
- `Potion_<Ключ>`, `Dynamite...`, `Charm`, `Essence`, `LootBox`, `CartPackage_TierN`
- `GeodeHammer` — молот раскола жеоды (вставляется в руку как есть, по Handle/Grip)
- `QuestMarker` — значок над целью квеста

**VFX** (Attachment с ParticleEmitter, можно в Part/Model)
- `PickaxeHitVFX`, `Swing`, `BoulderBreakVFX` / `BoulderBreakVFX_<вариант>`
- `MutationVfx_<Мутация>`, `GeodeCartVFX`, `SprintVFX`, `PrestigeVFX`, `ThunderVFX`, `DailyRewardVFX`
- `MineRarityCards` — карточки редкости в ленте шахты

---

## 4. Звуки — что заменить (`Config.Sounds` в `src/shared/Config.lua`)

Меняешь только `Id = "rbxassetid://..."` у нужной строки. `Pitch` — высота тона, `PitchJitter` — случайный разброс, `Volume` — громкость.

**Пустые, нужно вставить ID:**
- `DynamiteBoom`, `DynamiteBigBoom` — взрыв динамита (обычный и большой)

**Временные — один звук стоит сразу на многих действиях** (лучше дать каждому свой):

| Сейчас один ID на… | Что это |
|---|---|
| `UiMenuOpen`, `UiMenuClose`, `LikePrompt`, `GroupPrompt`, `Teleport`, `LoadingWhoosh` | открыть/закрыть окно, телепорт, перелёт камеры загрузки |
| `UiTabSwitch`, `UiConfirm`, `UiCancel`, `UiButtonClick`, `DialogueChoice`, `ReelTick` | клики по кнопкам, выбор в диалоге, щелчки ленты |
| `UiError`, `GoblinDeath`, `CartDestroyed`, `BoulderBreak`, `CrystalKnockout`, `Upgrade` | ошибка, смерть гоблина, **разлом валуна**, **покупка улучшения** |
| `UiSuccess`, `QuestComplete`, `ReelWin`, `OreRevealRare`, `PerkUnlock`, `Rebirth`, `GeodeDrop`, `RewardSkin`… (16 штук) | все «успехи» — самый важный кандидат на разные звуки |
| `GoblinSpawn`, `ChestSpawn`, `LootPop`, `CrystalSpawn`, `OreRevealCommon`, `OreEject`, `MoleRise` | появление чего-то |
| `ChestShake`, `ChestOpen`, `ChestCreak`, `OreBoxShake` | сундук/коробка трясётся и открывается |
| `ChestBurst`, `GeodeReveal`, `OreBoxOpen` | раскрытие |
| `LootPickup`, `CrystalPickup`, `ItemPickup`, `UpgradeFail` | подбор |
| `RewardMoney`, `Sell`, `Purchase`, `CoinCollect`, `SafeCollect`, `DailyRewardClaim`, `CartBanked`, `CartSoldOut` | деньги |
| `RewardCrystal`, `CrystalInstall`, `CrystalDeposit`, `QuestProgress`, `DailyRewardReady` | кристаллы, прогресс квеста |
| `BadgeEarned`, `OreRevealEpic`, `LuckModifier` | эпик-моменты |
| `PickaxeHit`, `MineHitGood`, `MiningRhythmHit`, `OreLand`, `CartDamaged`, `PickaxeHitCart` | удары киркой, руда падает |
| `CartTake`, `CartDrop`, `ItemPlace`, `CrystalRemove`, `MoleBurrow` | взять/поставить |
| `GoblinAttackHit`, `GoblinHit` | удары гоблинов |
| `CartRoll`, `IslandRise` | грохот (подъём острова) |
| `DynamiteThrow`, `MineHitMiss`, `OreThrow` | стандартный «свист» Roblox |

Приоритет замены: `BoulderBreak`, `Upgrade`, `QuestComplete`, `PerkUnlock`, `Purchase`/`Sell`, `OreRevealRare`/`OreRevealEpic`, `DynamiteBoom`.

---

## 5. Картинки, которые ещё 0 (`Config`)

- `Config.Compass.ButtonImageId`, `Config.Compass.PlaceImages` — иконка TRAVEL и карточки мест (0 — эмодзи)
- `Config.MineRework.OreBoxImages` — рисунок на коробке руды по каждой руде
- `Config.Prestige.NodeImageId` — форма узла дерева престижа
- `Config.StudTexture.Id` — текстура стадов на всех заглушках
- `Config.Tutorial.CharacterImageId`, `BoardImageId` — персонаж и табличка в диалоге обучения
- `Config.Badges.*` — ID бейджей (0 — бейдж выключен)

---

## 6. Деревья прокачки — где менять форму узлов (v20.143)

Оба дерева теперь **на весь экран**, как дерево престижа: в центре NPC, ветки расходятся во все стороны, поле таскается мышкой/пальцем, колесо и щипок - масштаб, карточка узла всплывает рядом, внизу CLOSE. Собираются `tools/BuildAllUI.lua` (он трогает только окна прокачки и престижа).

**Experienced Miner** - `StarterGui/UpgradeTreeUi`, **Island Keeper** - `StarterGui/IslandTreeUi`, **престиж** - `StarterGui/PrestigeTreeUi` (у всех трёх одинаковое устройство; у престижа ещё `Tabs` → `PerksTab`, `ShrinesTab`, а `Money` показывает очки престижа):
- `Templates/RootNode` - центральный узел (NPC)
- `Templates/TierNode` - тир / остров / уровень печи (`Shape`, `Caption` - номер или значок, `Price`, `Name` над узлом)
- `Templates/StarNode` - звезда-улучшение (`Shape` повёрнут на 45 = ромб, `Icon`, `Level`, `Name`)
- `Templates/FinalNode` - финальный узел острова
- `Templates/Link` - линия между узлами (толщина = высота шаблона)
- `Card` - карточка узла (`Title`, `Level`, `Text`, кнопки `Buy`, `More` = DETAILS, `Close`)
- `BigClose`, `Title`, `Hint`, `Backdrop` (затемнение)

Кнопка DETAILS у тира открывает прежнее окно ветки (`StarterGui/UpgradeShopUi`) поверх дерева.

**Как поставить свою форму (пятиугольник и т.п.):** в шаблоне выбери `Shape` → `Image = rbxassetid://...`, удали `SkinCorner` (скругление) и, если обводка на картинке, `Stroke`. У звезды поставь `Shape.Rotation = 0`. Картинку рисуй **белой** - игра красит её сама (куплен / следующий / закрыт). Размер шаблона = размер узла на экране.

**Расположение веток:** `Config.UpgradeTree` (`Dir` у каждой строки, `FirstDistance`, `Step`, `StarOffset`, `StarSide`) и `Config.IslandPerks.Dirs`.

**Промокоды** - `StarterGui/SettingsMenu` → `RedeemRow` (`CodeInput`, `RedeemButton`, `ResultText`). Пункт CODES в меню: если в твоём `CollectionMenu` его нет, игра скопирует соседнюю строку (стиль твой), само меню не пересобирается. Иконка пункта - `Config.UI.CodesMenuIconId`.
