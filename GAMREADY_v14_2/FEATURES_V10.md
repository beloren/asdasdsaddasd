# ФИЧИ v10 — монетизация

Всё настраивается в `src/shared/Config.lua`: `Config.GamePasses`, `Config.DevProducts.Micro`,
`Config.RocketPickaxe`, `Config.Offers`, `Config.Shop.Items`.

## Что сделать в Creator Hub (обязательно)
1. Создать новые геймпассы и вписать Id в `Config.GamePasses`: DoubleLuck, OreMagnet, GeodeMaster,
   DemolitionExpert, CartGuard, FastSmelter, RocketPickaxe (сейчас Id = 0 — товар неактивен).
2. Создать Developer Products и вписать Id в `Config.DevProducts.Micro` (13 штук) и ключи сундуков
   (`Config.Chests.Types[*].SkipProductId`).
3. **Поменять цены у уже существующих** пассов/продуктов в Creator Hub — цифры в конфиге только для
   отображения, реальную цену берёт Roblox: 2x Money 99, Mega Backpack 49, 2x Geode Rewards 39,
   погода 19/25/35/49/79, деньги 25/59/119, заполнение тележки 5–25, пропуск ребёрта вдвое дешевле,
   жеоды 9–89, стартовый пак 49, щит 9.
4. Старые пассы (x3/x5/x8 cash, Golden Shield, Speed, Damage, Health, FastMining, Triple/Five geode)
   снять с продажи, **но не удалять их Id из конфига** — по ним владельцы получают замену.
5. В Studio запустить `tools/BuildAllUI.lua` (добавлено окно `OfferUi`).

## Геймпассы
| Пасс | Цена | Эффект |
|---|---|---|
| 💰 2x Money | 99 | ×2 к продаже руды |
| 🍀 2x Luck | 129 | ×2 шанс мутаций + наклон к редкой руде |
| 🧲 Ore Magnet | 69 | подбор руды с 22 стадов |
| 🎒 Mega Backpack | 49 | +12 слотов |
| 🪨 Geode Master | 59 | открытие x3/x5 + жеода вскрывается сама |
| 🧨 Demolition Expert | 79 | откат динамита ×0.5 + 1 бесплатный динамит в сутки (самый большой открытый вид) |
| 🛡 Cart Guard | 59 | щит 60 с вместо 30, откат 90 с вместо 180, золотая обводка |
| ⚡ Fast Smelter | 49 | печь ×2 быстрее, +1 слот |
| 🚀 Rocket Pickaxe | 149 | см. ниже |
| 2x Geode Rewards | 39 | оставлен |

Замена для владельцев старых: x3/x5/x8 cash → 2x Money + 2x Luck; Golden Shield / Speed / Damage /
Health → Cart Guard; FastMining → Ore Magnet; Triple/Five geode → Geode Master.

## 🚀 Rocket Pickaxe
Кнопка 🚀 справа внизу или клавиша **R** — включить/выключить.
- Плюс: удар по игроку сразу рагдоллит на 3.5 с и отбрасывает ~×3 дальше. Откат **18 с** (шторка на кнопке).
- Минусы, пока включена: руды из шахты ×0.5, ударов на валун ×1.8, урон кирки ×0.4, замах ×1.35 медленнее.
- Щит и безопасная зона защищают как обычно.

## Микротранзакции (`Config.DevProducts.Micro`)
🧍 Get Up 5 · 💢 Get back 50% 19 · 🧨 5 Small 9 · 🧨 5 Medium 19 · 💣 3 Mega TNT 29 ·
⛏ Mine Rush (x2 руды, 3 раскопки) 15 · 🎯 Perfect Boulder 9 · 🍀 Luck x2 15 мин 19 ·
🌐 Server Luck x2 15 мин 49 / x3 30 мин 99 (объявление всему серверу) · 💵 Money x2 5 мин 15 ·
🔥 доплавить 5 · 🍖 накормить слайма 5. Ключи сундуков 9/15/25/39.

## Всплывающие предложения (`OfferPrompts.client.lua`, окно `OfferUi`)
Купон с ценой, покупка в одно касание, крестик — скрыть на 45 с:
- 🛡 щит — несёшь тележку, рядом чужой игрок;
- 🧍 встать — лежишь в рагдолле;
- 💢 вернуть 50% — тебя уронили с рудой или увезли твою тележку (90 с);
- ⛏ Mine Rush — стоишь у своей шахты;
- 🎯 Perfect — идёт мини-игра валуна (покупка сразу добивает валун на PERFECT).

Товары с Id = 0 не показываются (`Config.Offers.ShowWithoutId = true` — для проверки в Studio).
«Заполнить тележку» не всплывает — эту кнопку раньше убрали по твоему запросу.

Стартовый пак: кнопка показывает зачёркнутую цену «R$ 199» и реальную 49.
