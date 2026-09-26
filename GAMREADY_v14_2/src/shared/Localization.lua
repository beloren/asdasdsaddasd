local Localization = {}

local translations = {
	en = {
		["rebirth.intro"] = "Prestige:",
		["rebirth.needBranches"] = "Upgrade Mine, Cart and Pickaxe to MAX.",
		["rebirth.reset"] = "It resets all money.",
		["rebirth.cost"] = "Cost: <font color=\"#{color}\">${cost}</font>.",
		["rebirth.currentBonus"] = "Now: {money}, {speed}.",
		["rebirth.nextBonus"] = "After prestige: {money}, {speed}.",
		["rebirth.missing"] = "You still need <font color=\"#{color}\">${amount}</font>.",
		["rebirth.stolen"] = "Get your stolen cart back first!",
		["rebirth.success"] = "Prestiged! Ore multiplier: x{multiplier}",
		["upgrade.max"] = "{number}) {branch} - MAX (tier {tier})", ["upgrade.needRebirth"] = "{number}) {branch} - Need PRESTIGE (cap tier {tier})", ["upgrade.blocked"] = "{number}) {branch} - catch up other branches (tier {tier}, {cost})", ["upgrade.buy"] = "{number}) {branch} - tier {tier}, {cost}", ["upgrade.wait"] = "{number}) {branch} - ...", ["WAIT {seconds}s"] = "WAIT {seconds}s",
		["Need REBIRTH (cap tier {tier})"] = "Need PRESTIGE (cap tier {tier})", ["User {id}"] = "User {id}",
		["MINE UPGRADED!"] = "MINE UPGRADED!", ["Now fill the cart to 85% for a x4 sell multiplier!"] = "Now fill the cart to 85% for a x4 sell multiplier!",
		["FIND A GEODE"] = "FIND A GEODE", ["Return the cart to your mine and wait for a geode."] = "Return the cart to your mine and wait for a geode.", ["Take your cart back to the mine. Geodes can appear instead of ore."] = "Take your cart back to the mine. Geodes can appear instead of ore.",
		["STORE THE GEODE"] = "STORE THE GEODE", ["Take the cart to the bank. The geode will be sent to your vault."] = "Take the cart to the bank. The geode will be sent to your vault.", ["Take the cart containing the geode."] = "Take the cart containing the geode.",
		["OPEN THE GEODE"] = "OPEN THE GEODE", ["Click the available geode card and watch it open."] = "Click the available geode card and watch it open.", ["Use the Geode Vault at your base."] = "Use the Geode Vault at your base.", ["GEODE OPENED!"] = "GEODE OPENED!", ["Rare crystals can be installed on the podium for passive income."] = "Rare crystals can be installed on the podium for passive income.",
		["WAIT FOR {target} DROPS"] = "WAIT FOR {target} DROPS", ["UPGRADE YOUR MINE"] = "UPGRADE YOUR MINE", ["Talk to the Upgrade Mole, then choose the highlighted MINE card."] = "Talk to the Upgrade Mole, then choose the highlighted MINE card.",
		["Keep the cart in the mine: {count}/{target}. One of these drops is guaranteed to be a geode."] = "Keep the cart in the mine: {count}/{target}. One of these drops is guaranteed to be a geode.",
		["INSTALL THE CRYSTAL"] = "INSTALL THE CRYSTAL", ["Click your new crystal to install it."] = "Click your new crystal to install it.", ["Use the highlighted podium at your base."] = "Use the highlighted podium at your base.", ["MONEY SAFE"] = "MONEY SAFE", ["Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it."] = "Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it.", ["TUTORIAL COMPLETE!"] = "TUTORIAL COMPLETE!", ["Now keep mining ore, sell full carts at the bank, and upgrade your Mine, Cart, and Pickaxe to earn more."] = "Now keep mining ore, sell full carts at the bank, and upgrade your Mine, Cart, and Pickaxe to earn more.", ["WATCH YOUR BACK"] = "WATCH YOUR BACK", ["Other players can attack you and steal your ore! Use your shield if things get dangerous."] = "Other players can attack you and steal your ore! Use your shield if things get dangerous.", ["GOT IT"] = "GOT IT", ["CLOSE"] = "CLOSE", ["CLICK"] = "CLICK", ["SAFE ZONE"] = "SAFE ZONE",
		["Shield {seconds}s"] = "Shield {seconds}s",
		["Other players can knock ore out of your loaded cart - press Shield to protect it!"] = "Other players can knock ore out of your loaded cart - press Shield to protect it!",
		["The shield protects your cargo. Attacking someone will disable it."] = "The shield protects your cargo. Attacking someone will disable it.",
		["Pick up dropped ore and sell it at the bank!"] = "Pick up dropped ore and sell it at the bank!",
		["This branch is maxed! Max all 3 to unlock Prestige for a permanent ore price boost."] = "This branch is maxed! Max all 3 to unlock Prestige for a permanent ore price boost.",
		["Badge earned: First Steps!"] = "Badge earned: First Steps!",
		["Faster ore spawns and higher-value ore tiers."] = "Faster ore spawns and higher-value ore tiers.",
		["More cargo space and more health to survive fights."] = "More cargo space and more health to survive fights.",
		["More damage per swing and knocks more ore loose on a hit."] = "More damage per swing and knocks more ore loose on a hit.",
		["MAX (tier {tier})"] = "MAX (tier {tier})", ["Tier {tier} → {next}"] = "Tier {tier} → {next}", ["MAX"] = "MAX",
		["HOLD!"] = "HOLD!",
	},
	ru = {
		-- ПОДПИСИ ПРОМПТОВ (WorldPrompts приводит их к виду "Взять тележку")
		["UPGRADE"] = "улучшить",
		["DIG"] = "копать",
		["SHOP"] = "магазин",
		["VIEW PERKS"] = "перки",
		["TRAVEL"] = "путешествие",
		["RELEASE CART"] = "отпустить тележку",
		["PICK UP"] = "подобрать",
		["RELEASE"] = "отпустить",
		["OPEN"] = "открыть",
		["COLLECT"] = "забрать",
		["COLLECT MONEY"] = "забрать деньги",
		["CHOOSE ORE"] = "выбрать руду",
		["OPEN GEODES"] = "открыть жеоды",
		["SMELT ORE"] = "переплавить руду",
		["GIFT CRYSTAL"] = "подарить кристалл",
		-- ТОРГОВЕЦ И БИРЖА (Config.Merchant, MerchantUI.client.lua)
		["x2 Speed Potion"] = "Зелье скорости x2",
		["x2 Damage Potion"] = "Зелье урона x2",
		["x2 Money Potion"] = "Зелье денег x2",
		["x2 Luck Potion"] = "Зелье удачи x2",
		["x2 Mutation Potion"] = "Зелье мутаций x2",
		["x3 Money Potion"] = "Зелье денег x3",
		["FULL"] = "ПОЛНО",
		["2X DAMAGE"] = "2X УРОН",
		["Doubles your pickaxe damage."] = "Удваивает урон кирки.",
		["X{count} Stock"] = "В наличии: {count}",
		["NO STOCK"] = "НЕТ В НАЛИЧИИ",
		["BUY"] = "КУПИТЬ",
		["SOON"] = "СКОРО",
		["RESTOCK"] = "ОБНОВИТЬ",
		["New stock in {time}"] = "Новый товар через {time}",
		["ORE PRICE"] = "ЦЕНА РУДЫ",
		["ORE"] = "РУДА",
		["at the bank"] = "у банка",
		["Great time to sell!"] = "Самое время продавать!",
		["Prices are low - wait?"] = "Цены низкие - может, подождать?",
		["Normal prices"] = "Обычные цены",
		["Sell your ore now or wait?"] = "Продать сейчас или подождать?",
		["OWNED"] = "КУПЛЕНО",
		["Purchase failed"] = "Покупка не удалась",
		["Try again"] = "Попробуй ещё раз",
		["Bag full"] = "Сумка полна",
		["Busy"] = "Подожди…",
		["Common"] = "Обычный",
		["Uncommon"] = "Необычный",
		["Rare"] = "Редкий",
		["Epic"] = "Эпический",
		["Legendary"] = "Легендарный",
		["Mythic"] = "Мифический",
		["CRASH"] = "ОБВАЛ",
		["LOW"] = "НИЗКИЙ",
		["NORMAL"] = "ОБЫЧНЫЙ",
		["HIGH"] = "ВЫСОКИЙ",
		["BOOM"] = "БУМ",
		["JACKPOT"] = "ДЖЕКПОТ",
		["Ore Merchant"] = "Торговец рудой",
		["ORE MERCHANT"] = "ТОРГОВЕЦ РУДОЙ",
		["Shop"] = "Лавка",
		["Speed Potion"] = "Зелье скорости",
		["Money Potion"] = "Зелье денег",
		["Luck Potion"] = "Зелье удачи",
		["Mutation Potion"] = "Зелье мутаций",
		["Small Dynamite"] = "Малый динамит",
		["Dynamite Bundle"] = "Связка динамита",
		["Mega TNT"] = "Мега-TNT",
		["Radioactive Pickaxe"] = "Радиоактивная кирка",
		["Love Pickaxe"] = "Любовная кирка",
		["Big Wooden Pickaxe"] = "Большая деревянная кирка",
		["Crystal Pickaxe"] = "Кристальная кирка",
		["Void Pickaxe"] = "Кирка Пустоты",
		["🔄 The merchant restocked just for you!"] = "🔄 Торговец обновил товар специально для тебя!",
		["CART FULL"] = "ТЕЛЕЖКА ПОЛНА",
		["FIND YOUR CART"] = "НАЙДИТЕ ТЕЛЕЖКУ", ["Follow the red arrow."] = "Следуйте за красной стрелкой.", ["GO TO YOUR MINE"] = "ИДИТЕ К СВОЕЙ ШАХТЕ", ["Place the cart inside the highlighted zone."] = "Поставьте тележку в выделенную зону.", ["THE MINE IS WORKING"] = "ШАХТА РАБОТАЕТ", ["Wait for 3 ore pieces: {count}/3"] = "Дождитесь 3 кусков руды: {count}/3", ["TAKE THE LOADED CART"] = "ВОЗЬМИТЕ ТЕЛЕЖКУ С РУДОЙ", ["Hold the interaction button near it."] = "Удерживайте кнопку взаимодействия рядом.", ["SELL YOUR ORE"] = "ПРОДАЙТЕ РУДУ", ["Follow the arrow to the central bank."] = "Следуйте к центральному банку.", ["BUY YOUR FIRST UPGRADE"] = "КУПИТЕ ПЕРВОЕ УЛУЧШЕНИЕ", ["Talk to the highlighted Upgrade Mole."] = "Поговорите с выделенным кротом улучшений.", ["Upgrade your MINE to tier 2."] = "Улучшите ШАХТУ до тира 2.", ["SKIP TUTORIAL"] = "ПРОПУСТИТЬ ОБУЧЕНИЕ", ["TAP AGAIN TO SKIP"] = "НАЖМИТЕ ЕЩЁ РАЗ, ЧТОБЫ ПРОПУСТИТЬ",
		["GRAB CART"] = "ВЗЯТЬ ТЕЛЕЖКУ", ["TALK"] = "ГОВОРИТЬ", ["UPGRADE YOUR MINE"] = "УЛУЧШИТЕ СВОЮ ШАХТУ", ["Upgrade your MINE to the next tier."] = "Улучшите ШАХТУ до следующего тира.", ["TUTORIAL COMPLETE!"] = "ОБУЧЕНИЕ ЗАВЕРШЕНО!", ["Mine, sell, fight and upgrade!"] = "Добывайте, продавайте, сражайтесь и улучшайтесь!",
		["MINE UPGRADED!"] = "ШАХТА УЛУЧШЕНА!", ["Now fill the cart to 85% for a x4 sell multiplier!"] = "Теперь заполни тележку до 85%, чтобы получить множитель продажи x4!",
		["FIND A GEODE"] = "НАЙДИТЕ ЖЕОДУ", ["Return the cart to your mine and wait for a geode."] = "Верните тележку в шахту и дождитесь жеоды.", ["Take your cart back to the mine. Geodes can appear instead of ore."] = "Верните тележку в шахту. Жеода может появиться вместо руды.",
		["STORE THE GEODE"] = "СОХРАНИТЕ ЖЕОДУ", ["Take the cart to the bank. The geode will be sent to your vault."] = "Отвезите тележку в банк. Жеода отправится в ваше хранилище.", ["Take the cart containing the geode."] = "Возьмите тележку с жеодой.",
		["OPEN THE GEODE"] = "ОТКРОЙТЕ ЖЕОДУ", ["Click the available geode card and watch it open."] = "Нажмите на доступную карточку жеоды и откройте её.", ["Use the Geode Vault at your base."] = "Используйте хранилище жеод на своей базе.", ["GEODE OPENED!"] = "ЖЕОДА ОТКРЫТА!", ["Rare crystals can be installed on the podium for passive income."] = "Редкие кристаллы можно установить на подиум для пассивного дохода.",
		["WAIT FOR {target} DROPS"] = "ДОЖДИТЕСЬ {target} ПРЕДМЕТОВ", ["Talk to the Experienced Miner, then choose the highlighted MINE card."] = "Поговорите с опытным шахтёром и выберите выделенную карточку MINE.",
		["Keep the cart in the mine: {count}/{target}. One of these drops is guaranteed to be a geode."] = "Оставьте тележку в шахте: {count}/{target}. Среди этих предметов гарантированно будет одна жеода.",
		["INSTALL THE CRYSTAL"] = "УСТАНОВИТЕ КРИСТАЛЛ", ["Click your new crystal to install it."] = "Нажмите на новый кристалл, чтобы установить его.", ["Use the highlighted podium at your base."] = "Используйте выделенный подиум на своей базе.", ["MONEY SAFE"] = "ДЕНЕЖНЫЙ СЕЙФ", ["Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it."] = "Ваш кристалл со временем зарабатывает деньги и копит их здесь. Удерживайте кнопку взаимодействия у сейфа, чтобы забрать их.", ["TUTORIAL COMPLETE!"] = "ОБУЧЕНИЕ ЗАВЕРШЕНО!", ["Now keep mining ore, sell full carts at the bank, and upgrade your Mine, Cart, and Pickaxe to earn more."] = "Теперь продолжайте добывать руду, продавайте гружёные тележки в банке и прокачивайте Шахту, Тележку и Кирку, чтобы зарабатывать больше.", ["WATCH YOUR BACK"] = "БЕРЕГИСЬ ДРУГИХ ИГРОКОВ", ["Other players can attack you and steal your ore! Use your shield if things get dangerous."] = "Другие игроки могут напасть на вас и украсть вашу руду! Используйте щит, если станет опасно.", ["GOT IT"] = "ПОНЯТНО", ["CLOSE"] = "ЗАКРЫТЬ", ["SAFE ZONE"] = "БЕЗОПАСНАЯ ЗОНА",
		["Shield {seconds}s"] = "Щит: {seconds}с",
		["Other players can knock ore out of your loaded cart - press Shield to protect it!"] = "Другие игроки могут выбить руду из твоей тележки - нажми Щит, чтобы защитить груз!",
		["The shield protects your cargo. Attacking someone will disable it."] = "Щит защищает твой груз. Атака на другого игрока отключит защиту.",
		["Pick up dropped ore and sell it at the bank!"] = "Подбери выпавшую руду и продай в банке!",
		["This branch is maxed! Max all 3 to unlock Prestige for a permanent ore price boost."] = "Эта ветка прокачана до предела! Прокачай все 3 до максимума, чтобы открыть Престиж - постоянный бонус к цене руды.",
		["Badge earned: First Steps!"] = "Получен бейдж: Первые шаги!",
		["Faster ore spawns and higher-value ore tiers."] = "Быстрее появляется руда, доступны более дорогие тиры.",
		["More cargo space and more health to survive fights."] = "Больше места для груза и больше здоровья в бою.",
		["More damage per swing and knocks more ore loose on a hit."] = "Больше урона за удар и больше выбитой руды с одного попадания.",
		["MAX (tier {tier})"] = "МАКС. (тир {tier})", ["Tier {tier} → {next}"] = "Тир {tier} → {next}", ["MAX"] = "МАКС.",
		["YOUR BASE"] = "ВАША БАЗА", ["SKIP"] = "ПРОПУСТИТЬ", ["NEXT"] = "ДАЛЕЕ", ["START"] = "НАЧАТЬ",
		["TAKE YOUR CART"] = "ВОЗЬМИТЕ ТЕЛЕЖКУ", ["Hold the interaction button near your cart."] = "Удерживайте кнопку взаимодействия рядом со своей тележкой.",
		["START THE MINE"] = "ЗАПУСТИТЕ ШАХТУ", ["Leave the cart anywhere inside the glowing mine zone."] = "Оставьте тележку внутри светящейся зоны шахты.",
		["SELL THE ORE"] = "ПРОДАЙТЕ РУДУ", ["Take the loaded cart to the center bank."] = "Отвезите загруженную тележку в центральный банк.",
		["SURVIVE"] = "ВЫЖИВАЙТЕ", ["Use the shield while carrying. Without a cart, equip the pickaxe and attack other players."] = "Используйте щит с тележкой. Без тележки возьмите кирку и атакуйте игроков.",
		["Settings"] = "Настройки", ["On"] = "Вкл.", ["Off"] = "Выкл.", ["Audio"] = "Звук", ["Toggle your audio"] = "Включить или выключить звук",
		["Redeem Codes"] = "Промокоды", ["Look for codes on developer's socials!"] = "Ищите коды в соцсетях разработчика!", ["Type code here.."] = "Введите код...", ["Claim"] = "Получить",
		["WORLD SOUNDS"] = "ЗВУКИ МИРА", ["MUSIC"] = "МУЗЫКА", ["UI SOUNDS"] = "ЗВУКИ ИНТЕРФЕЙСА", ["VISUAL EFFECTS"] = "ВИЗУАЛЬНЫЕ ЭФФЕКТЫ",
		["Already redeemed."] = "Уже использован.", ["This code has expired."] = "Срок действия кода истёк.", ["Invalid code."] = "Неверный код.",
		["HOLD!"] = "ЗАЖМИ!",
		["Take Cart"] = "Взять тележку", ["Cart"] = "Тележка", ["Spawn New"] = "Создать новую", ["Drop Cart"] = "Бросить тележку", ["TAP"] = "НАЖАТЬ", ["HOLD"] = "ДЕРЖАТЬ", ["CLICK"] = "КЛИК",
		["Mole Merchant"] = "Опытный шахтёр", ["Rebirth Mole"] = "Мэр престижа", ["MOLE REBIRTH"] = "МЭР ПРЕСТИЖА", ["REBIRTH MOLE"] = "МЭР ПРЕСТИЖА", ["Mole Rebirth"] = "Мэр престижа", ["PRESTIGE MAYOR"] = "МЭР ПРЕСТИЖА", ["EXPERIENCED MINER"] = "ОПЫТНЫЙ ШАХТЁР", ["Talk"] = "Говорить", ["Upgrade Shop"] = "Магазин улучшений", ["Item Shop"] = "Магазин предметов",
		["MINE"] = "ШАХТА", ["CART"] = "ТЕЛЕЖКА", ["PICKAXE"] = "КИРКА", ["Welcome! What would you like to upgrade?"] = "Добро пожаловать! Что вы хотите улучшить?",
		["Passes"] = "Пропуски", ["Deals"] = "Предложения", ["Store!"] = "Магазин!", ["Golden Shield"] = "Золотой щит", ["Speed Boost"] = "Ускорение", ["Extra Pouch"] = "Большая сумка", ["+50% Mining Speed"] = "+50% к скорости шахты",
		["Welcome! Take a look at today's deals."] = "Добро пожаловать! Посмотрите сегодняшние предложения.", ["FILL INSTANTLY"] = "ЗАПОЛНИТЬ СРАЗУ",
		["REBIRTH"] = "ПЕРЕРОДИТЬСЯ", ["PRESTIGE"] = "ПРЕСТИЖ", ["CANCEL"] = "ОТМЕНА", ["Open Shop"] = "Открыть магазин",
		["Not ready yet!"] = "Ещё не готово!", ["NOT READY YET"] = "ЕЩЁ НЕ ГОТОВО", ["New cart isn't ready yet - wait for the countdown!"] = "Новая тележка ещё не готова - дождитесь окончания таймера!",
		["Not enough money! Buy a Money Pack or a cash-boost pass to speed things up."] = "Недостаточно денег! Купите набор денег или денежный пропуск.",
		["TOP MONEY"] = "ТОП ПО ДЕНЬГАМ", ["TOP REBIRTHS"] = "ТОП ПЕРЕРОЖДЕНИЙ", ["TOP PRESTIGE"] = "ТОП ПО ПРЕСТИЖУ", ["TOP CART DAMAGE"] = "ТОП УРОНА ТЕЛЕЖКАМ", ["TOP PLAYTIME"] = "ТОП ПО ВРЕМЕНИ", ["NO PLAYERS YET"] = "ПОКА НЕТ ИГРОКОВ", ["DATASTORE UNAVAILABLE"] = "ХРАНИЛИЩЕ НЕДОСТУПНО",
		["COMBO {value}"] = "КОМБО {value}", ["Shield +{seconds}s"] = "Щит +{seconds}с", ["Success! +${amount}"] = "Успешно! +${amount}",
		["rebirth.intro"] = "Перерождение:", ["rebirth.needBranches"] = "Прокачай шахту, тележку и кирку до МАКС.", ["rebirth.reset"] = "Все деньги сбросятся.", ["rebirth.cost"] = "Цена: <font color=\"#{color}\">${cost}</font>.", ["rebirth.currentBonus"] = "Сейчас: {money}, {speed}.", ["rebirth.nextBonus"] = "После: {money}, {speed}.", ["rebirth.missing"] = "Вам не хватает <font color=\"#{color}\">${amount}</font>.", ["rebirth.stolen"] = "Сначала верните украденную тележку!", ["rebirth.success"] = "Перерождение выполнено! Множитель руды: x{multiplier}",
		["upgrade.max"] = "{number}) {branch} - МАКС. (тир {tier})", ["upgrade.needRebirth"] = "{number}) {branch} - нужен ПРЕСТИЖ (предел {tier})", ["upgrade.blocked"] = "{number}) {branch} - улучшите другие ветки (тир {tier}, {cost})", ["upgrade.buy"] = "{number}) {branch} - тир {tier}, {cost}", ["upgrade.wait"] = "{number}) {branch} - ...", ["WAIT {seconds}s"] = "ЖДИТЕ {seconds} сек",
		["Already at max tier"] = "Уже максимальный тир", ["Something went wrong"] = "Что-то пошло не так", ["Not enough money"] = "Недостаточно денег", ["Catch up other branches first"] = "Сначала улучшите другие ветки", ["Your cart is stolen!"] = "Ваша тележка украдена!",
		["Need REBIRTH (cap tier {tier})"] = "Нужен ПРЕСТИЖ (предел {tier})", ["User {id}"] = "Пользователь {id}", ["Rejoin to fully restore graphics after lowering effects."] = "Перезайдите, чтобы полностью восстановить графику после снижения эффектов.",
		["2x Cash"] = "Деньги x2", ["4x Cash"] = "Деньги x4", ["6x Cash"] = "Деньги x6", ["8x Cash"] = "Деньги x8", ["$3,000 Cash"] = "$3 000", ["$10,000 Cash"] = "$10 000", ["$120,000 Cash"] = "$120 000",
		["ENABLE API SERVICES TO LOAD GLOBAL DATA"] = "ВКЛЮЧИТЕ API-СЕРВИСЫ ДЛЯ ЗАГРУЗКИ ГЛОБАЛЬНЫХ ДАННЫХ", ["< Prev"] = "< Назад", ["Next >"] = "Далее >",
		["Your data is already loaded on another server. Please try again shortly."] = "Ваши данные уже загружены на другом сервере. Повторите попытку чуть позже.", ["Your data could not be loaded safely. Please rejoin."] = "Не удалось безопасно загрузить ваши данные. Перезайдите в игру.",
		["Player setup failed safely. Please rejoin."] = "Не удалось настроить игрока. Ваши данные в безопасности; перезайдите в игру.", ["Your data session was opened elsewhere. Please rejoin."] = "Сессия ваших данных была открыта в другом месте. Перезайдите в игру.", ["Data saving is temporarily unavailable. Please rejoin safely."] = "Сохранение данных временно недоступно. Безопасно перезайдите в игру.",
		["SELL YOUR FIRST ORE"] = "ПРОДАЙТЕ ПЕРВУЮ РУДУ", ["Take the cart to the bank and sell the mined ore."] = "Отвезите тележку в банк и продайте добытую руду.", ["Take the loaded cart to the bank."] = "Отвезите гружёную тележку в банк.", ["Now talk to the Upgrade Mole, then choose the highlighted MINE card."] = "Поговорите с кротом улучшений и выберите выделенную карточку ШАХТЫ.", ["OPEN YOUR GEODE VAULT"] = "ОТКРОЙТЕ ХРАНИЛИЩЕ ЖЕОД", ["HEY! GOBLINS ATTACKED!"] = "ЭЙ! ГОБЛИНЫ АТАКУЮТ!", ["HEY! GOBLINS ATTACKED YOU! DEAL WITH THEM!"] = "ЭЙ! НА ВАС НАПАЛИ ГОБЛИНЫ! РАЗБЕРИТЕСЬ С НИМИ!", ["DEFEAT THE GOBLIN"] = "ПОБЕДИТЕ ГОБЛИНА", ["Fight back and defeat the goblin attacking your base."] = "Дайте отпор и победите гоблина, напавшего на вашу базу.",

		-- ОБУЧЕНИЕ v7 (см. Config.Tutorial). Реплики наставника, задания
		-- шагов и контекстные подсказки. Ключ — английский оригинал из
		-- Config, как и везде в этом файле.
		["Finally... a living soul."] = "Ох... Наконец-то живой человек.",
		["The mine caved in. Those boulders are holding the entrance shut. Break them and I'll take you inside."] = "Шахту завалило - вход держат вон те камни. Разбей их, и я отведу тебя внутрь.",
		["Good swing! There's always ore inside those rocks. Take it, it's yours."] = "Вот это удар! Внутри камней всегда есть немного руды - забирай, она твоя.",
		["They buy ore in the center. You've got legs, you'll manage without a cart."] = "Руду покупают в центре. Ноги есть - донесёшь и так.",
		["You've got money. Now we can fix the mine."] = "Деньги есть. Теперь можно и шахту чинить.",
		["Go see the trader. He'll sell you a working cave."] = "Иди к торговцу - он продаст тебе рабочую пещеру.",
		["Hear that? She's humming again. Let's get to work."] = "Слышишь? Загудела. Пошли работать.",
		["Stay close. Inside, swing at the vein when the arrow hits the green."] = "Держись рядом. Внутри бей киркой по жиле, когда стрелка встанет в зелёное.",
		["The ore is all outside. You won't carry that by hand - you need a cart."] = "Вся руда снаружи. В руках столько не утащишь - нужна тележка.",
		["The trader gives the first cart away. Take it and set it down wherever you like."] = "Первую тележку торговец отдаёт даром. Забери и поставь её где удобно.",
		["Now collect ore with the cart itself - just drive over it."] = "Теперь собирай руду прямо тележкой - просто проедь по ней.",
		["That's how it works. The fuller the cart, the bigger the multiplier on the run."] = "Вот так это и работает. Чем полнее тележка - тем выше множитель за рейс.",
		["You're on your own now. Your to-do list is in the journal up top."] = "Дальше сам. Список дел - в журнале слева сверху.",
		["GET READY"] = "ПРИГОТОВЬСЯ",
		["Talk to the miner"] = "Поговори с шахтёром",
		["CLEAR THE RUBBLE"] = "РАСЧИСТИ ЗАВАЛ",
		["Break the boulders blocking your mine"] = "Разбей валуны, закрывающие шахту",
		["SELL THE ORE"] = "ПРОДАЙ РУДУ",
		["Carry the ore to the bank in the center and sell it"] = "Отнеси руду в банк в центре и продай",
		["FIX THE MINE"] = "ПОЧИНИ ШАХТУ",
		["Buy the MINE upgrade from the trader"] = "Купи улучшение ШАХТЫ у торговца",
		["GO MINING"] = "В ШАХТУ",
		["Talk to the miner and finish the dig"] = "Поговори с шахтёром и закончи добычу",
		["GET A CART"] = "ВОЗЬМИ ТЕЛЕЖКУ",
		["Take the free cart from the trader and place it"] = "Забери бесплатную тележку у торговца и поставь её",
		["DELIVER THE CART"] = "ОТВЕЗИ ТЕЛЕЖКУ",
		["Load the cart and sell it at the bank"] = "Загрузи тележку и продай её в банке",
		["A geode! Those don't sell - you crack them open in the vault on your base."] = "Жеода! Такие не продаются - их вскрывают в хранилище на базе.",
		["A chest. It opens on its own after a while - or open it now if you can't wait."] = "Сундук. Он откроется сам через время - или открой сразу, если не терпится.",
		["Goblins are raiding their camp! Beat them with your pickaxe - every kill pays out."] = "Гоблины напали на свой лагерь! Бей их киркой - за каждого платят.",
		["Dynamite breaks rocks your pickaxe can't. Place it right on the boulder."] = "Динамит ломает камни, которые киркой не взять. Ставь его прямо на валун.",
		["Mutated ore is worth far more than plain ore. Try not to lose it."] = "Мутировавшая руда стоит заметно дороже обычной. Такие лучше не терять.",
		["You just got hit. The shield buys you a breather - but it drops if you strike back."] = "По тебе ударили. Щит на панели даёт передышку - но снимется, если ударишь в ответ.",
		["Island unlocked. It brings mechanics your base doesn't have."] = "Остров открыт. На нём появляются механики, которых нет на базе.",
		["MINER"] = "ШАХТЁР",
		["THE MINE IS BLOCKED - CLEAR THE RUBBLE FIRST"] = "ШАХТА ЗАВАЛЕНА - СНАЧАЛА РАСЧИСТИ КАМНИ",
		["MAIN QUESTS"] = "ОСНОВНЫЕ КВЕСТЫ",

		-- ОБУЧЕНИЕ v7 — реплики и задания (Config.Tutorial.Steps). Ключ —
		-- английский оригинал ДОСЛОВНО: правишь текст в Config — правь и
		-- ключ здесь, иначе в русский интерфейс просочится английский.
		["Welcome! Here we dig ore, sell it and upgrade our gear."] = "Добро пожаловать! Здесь мы копаем руду, продаём её и улучшаем снаряжение.",
		["But first - the mine entrance is blocked. Break those boulders."] = "Но сперва - вход в шахту завален. Разбей эти камни.",
		["CLEAR THE WAY"] = "РАСЧИСТИ ПУТЬ",
		["Break the boulders"] = "Разбей валуны",
		["The way is clear, but the mine has no power. The trader next to it will fix it - I've already paid."] = "Путь свободен, но шахта обесточена. Торговец рядом с ней всё починит - я уже заплатил.",
		["The ore you picked up is in your bag. You can sell it at the bank any time."] = "Руда, что ты подобрал, лежит в рюкзаке. Её можно продать в банке в любой момент.",
		["Talk to the trader and repair the mine (free)"] = "Поговори с торговцем и почини шахту (бесплатно)",
		["The mine is working again. Let's go down!"] = "Шахта снова работает. Спускаемся!",
		["Talk to me and we'll go down together."] = "Поговори со мной - спустимся вместе.",
		["Inside, tap when the marker is on the green part of the vein."] = "Внутри жми, когда метка окажется на зелёной части жилы.",
		["Nice haul! The ore is waiting outside - you'll need a cart to carry it."] = "Отличная добыча! Руда лежит у входа - чтобы увезти её, нужна тележка.",
		["Your first cart is free - get it from the trader."] = "Первая тележка - бесплатно. Забери её у торговца.",
		["Get the free cart from the trader"] = "Забери бесплатную тележку у торговца",
		["The cart comes in a box. Take the box from your hotbar and tap where the cart should stand."] = "Тележка приходит в коробке. Возьми коробку из панели предметов и нажми туда, где тележка должна стоять.",
		["PLACE THE CART"] = "ПОСТАВЬ ТЕЛЕЖКУ",
		["Take the box from your hotbar and place the cart"] = "Возьми коробку из панели предметов и поставь тележку",
		["Push the cart over the ore - it collects it by itself."] = "Прокати тележку по руде - она соберёт её сама.",
		["Fill the cart and take it to the bank"] = "Наполни тележку и отвези её в банк",
		["Fuller cart, bigger payout. Now let's spend it."] = "Полнее тележка - больше выплата. А теперь потратим заработанное.",
		["Here's a bonus from me. Spend it at the trader - a better pickaxe breaks rocks faster."] = "Держи бонус от меня. Потрать его у торговца - хорошая кирка ломает камни быстрее.",
		["FIRST UPGRADE"] = "ПЕРВОЕ УЛУЧШЕНИЕ",
		["Buy any upgrade from the trader"] = "Купи любое улучшение у торговца",
		["That's the whole loop: dig, sell, upgrade. Your next goals are in the quests panel - good luck!"] = "Вот и весь цикл: копай, продавай, улучшайся. Следующие цели - в панели квестов. Удачи!",

		-- Починка шахты (нулевой шаг ветки шахты, см. Config.Mine.Broken).
		["REPAIR"] = "ПОЧИНИТЬ",
		["REPAIR THE MINE"] = "ПОЧИНИТЬ ШАХТУ",
		["Reopen the mine and start digging"] = "Откроет шахту - можно копать",
		["THE MINE IS OPEN"] = "ШАХТА ОТКРЫТА",
		["FREE REPAIR"] = "ПОЧИНКА БЕСПЛАТНО",
	},
	es = {
		["FIND YOUR CART"] = "ENCUENTRA TU CARRO", ["Follow the red arrow."] = "Sigue la flecha roja.", ["GO TO YOUR MINE"] = "VE A TU MINA", ["Place the cart inside the highlighted zone."] = "Coloca el carro en la zona marcada.", ["THE MINE IS WORKING"] = "LA MINA FUNCIONA", ["Wait for 3 ore pieces: {count}/3"] = "Espera 3 minerales: {count}/3", ["TAKE THE LOADED CART"] = "TOMA EL CARRO CARGADO", ["Hold the interaction button near it."] = "Mantén pulsado el botón de interacción.", ["SELL YOUR ORE"] = "VENDE EL MINERAL", ["Follow the arrow to the central bank."] = "Sigue la flecha al banco central.", ["BUY YOUR FIRST UPGRADE"] = "COMPRA TU PRIMERA MEJORA", ["Talk to the highlighted Upgrade Mole."] = "Habla con el topo de mejoras marcado.", ["Upgrade your MINE to tier 2."] = "Mejora tu MINA al nivel 2.", ["SKIP TUTORIAL"] = "OMITIR TUTORIAL", ["TAP AGAIN TO SKIP"] = "TOCA DE NUEVO PARA OMITIR",
		["GRAB CART"] = "TOMAR CARRO", ["TALK"] = "HABLAR", ["UPGRADE YOUR MINE"] = "MEJORA TU MINA", ["Upgrade your MINE to the next tier."] = "Mejora tu MINA al siguiente nivel.", ["TUTORIAL COMPLETE!"] = "¡TUTORIAL COMPLETADO!", ["Mine, sell, fight and upgrade!"] = "¡Extrae, vende, lucha y mejora!",
		["YOUR BASE"] = "TU BASE", ["SKIP"] = "OMITIR", ["NEXT"] = "SIGUIENTE", ["START"] = "EMPEZAR",
		["TAKE YOUR CART"] = "TOMA TU CARRO", ["Hold the interaction button near your cart."] = "Mantén pulsado el botón de interacción junto a tu carro.", ["START THE MINE"] = "INICIA LA MINA", ["Leave the cart anywhere inside the glowing mine zone."] = "Deja el carro dentro de la zona brillante de la mina.", ["SELL THE ORE"] = "VENDE EL MINERAL", ["Take the loaded cart to the center bank."] = "Lleva el carro cargado al banco central.", ["SURVIVE"] = "SOBREVIVE", ["Use the shield while carrying. Without a cart, equip the pickaxe and attack other players."] = "Usa el escudo con el carro. Sin carro, equipa el pico y ataca a otros jugadores.",
		["Settings"] = "Ajustes", ["On"] = "Sí", ["Off"] = "No", ["Audio"] = "Audio", ["Toggle your audio"] = "Activa o desactiva el audio", ["Redeem Codes"] = "Canjear códigos", ["Look for codes on developer's socials!"] = "¡Busca códigos en las redes del desarrollador!", ["Type code here.."] = "Escribe el código...", ["Claim"] = "Canjear", ["WORLD SOUNDS"] = "SONIDOS DEL MUNDO", ["MUSIC"] = "MÚSICA", ["UI SOUNDS"] = "SONIDOS DE IU", ["VISUAL EFFECTS"] = "EFECTOS VISUALES",
		["Already redeemed."] = "Ya canjeado.", ["This code has expired."] = "Este código ha caducado.", ["Invalid code."] = "Código inválido.", ["Take Cart"] = "Tomar carro", ["Cart"] = "Carro", ["Spawn New"] = "Crear nuevo", ["Drop Cart"] = "Soltar carro", ["TAP"] = "TOCAR", ["HOLD"] = "MANTENER", ["CLICK"] = "CLIC", ["Mole Merchant"] = "Topo mercader", ["Rebirth Mole"] = "Topo de renacimiento", ["MOLE REBIRTH"] = "TOPO DE RENACIMIENTO", ["REBIRTH MOLE"] = "TOPO DE RENACIMIENTO", ["Mole Rebirth"] = "Topo de renacimiento", ["Talk"] = "Hablar", ["Upgrade Shop"] = "Tienda de mejoras", ["Item Shop"] = "Tienda de objetos",
		["MINE"] = "MINA", ["CART"] = "CARRO", ["PICKAXE"] = "PICO", ["Welcome! What would you like to upgrade?"] = "¡Bienvenido! ¿Qué quieres mejorar?", ["Passes"] = "Pases", ["Deals"] = "Ofertas", ["Store!"] = "¡Tienda!", ["Golden Shield"] = "Escudo dorado", ["Speed Boost"] = "Aumento de velocidad", ["Extra Pouch"] = "Bolsa extra", ["+50% Mining Speed"] = "+50% velocidad minera", ["Welcome! Take a look at today's deals."] = "¡Bienvenido! Mira las ofertas de hoy.", ["FILL INSTANTLY"] = "LLENAR AL INSTANTE", ["REBIRTH"] = "RENACER", ["CANCEL"] = "CANCELAR", ["Open Shop"] = "Abrir tienda",
		["Not ready yet!"] = "¡Aún no está listo!", ["NOT READY YET"] = "AÚN NO ESTÁ LISTO", ["New cart isn't ready yet - wait for the countdown!"] = "El carro nuevo aún no está listo. ¡Espera la cuenta atrás!", ["Not enough money! Buy a Money Pack or a cash-boost pass to speed things up."] = "¡No tienes suficiente dinero! Compra dinero o un pase de bonificación.", ["TOP MONEY"] = "MÁS DINERO", ["TOP REBIRTHS"] = "MÁS RENACIMIENTOS", ["TOP CART DAMAGE"] = "MÁS DAÑO A CARROS", ["TOP PLAYTIME"] = "MÁS TIEMPO JUGADO", ["NO PLAYERS YET"] = "AÚN NO HAY JUGADORES", ["DATASTORE UNAVAILABLE"] = "DATOS NO DISPONIBLES", ["COMBO {value}"] = "COMBO {value}", ["Shield +{seconds}s"] = "Escudo +{seconds}s", ["Success! +${amount}"] = "¡Éxito! +${amount}",
		["HOLD!"] = "¡MANTÉN!",
		["rebirth.intro"] = "Soy el Topo del Renacimiento.", ["rebirth.needBranches"] = "Mejora las 3 ramas al nivel {tier} primero.", ["rebirth.reset"] = "Renacer reinicia Mina/Carro/Pico al nivel 1 y aumenta permanentemente el precio del mineral.", ["rebirth.cost"] = "Cuesta <font color=\"#{color}\">${cost}</font>.", ["rebirth.missing"] = "Aún necesitas <font color=\"#{color}\">${amount}</font>.", ["rebirth.stolen"] = "¡Recupera primero tu carro robado!", ["rebirth.success"] = "¡Renacimiento completado! Multiplicador: x{multiplier}",
		["upgrade.max"] = "{number}) {branch} - MÁX. (nivel {tier})", ["upgrade.needRebirth"] = "{number}) {branch} - requiere RENACER (límite {tier})", ["upgrade.blocked"] = "{number}) {branch} - mejora otras ramas (nivel {tier}, {cost})", ["upgrade.buy"] = "{number}) {branch} - nivel {tier}, {cost}", ["upgrade.wait"] = "{number}) {branch} - ...", ["WAIT {seconds}s"] = "ESPERA {seconds}s",
		["Already at max tier"] = "Ya está al nivel máximo", ["Something went wrong"] = "Algo salió mal", ["Not enough money"] = "Dinero insuficiente", ["Catch up other branches first"] = "Mejora primero las otras ramas", ["Your cart is stolen!"] = "¡Tu carro fue robado!",
		["Need REBIRTH (cap tier {tier})"] = "Necesitas RENACER (límite {tier})", ["User {id}"] = "Usuario {id}", ["Rejoin to fully restore graphics after lowering effects."] = "Vuelve a entrar para restaurar por completo los gráficos tras reducir los efectos.",
		["2x Cash"] = "Dinero x2", ["4x Cash"] = "Dinero x4", ["6x Cash"] = "Dinero x6", ["8x Cash"] = "Dinero x8", ["$3,000 Cash"] = "$3.000", ["$10,000 Cash"] = "$10.000", ["$120,000 Cash"] = "$120.000",
		["ENABLE API SERVICES TO LOAD GLOBAL DATA"] = "ACTIVA LOS SERVICIOS API PARA CARGAR DATOS GLOBALES", ["< Prev"] = "< Anterior", ["Next >"] = "Siguiente >",
		["Your data is already loaded on another server. Please try again shortly."] = "Tus datos ya están cargados en otro servidor. Inténtalo de nuevo en unos instantes.", ["Your data could not be loaded safely. Please rejoin."] = "No se pudieron cargar tus datos de forma segura. Vuelve a entrar.",
		["Player setup failed safely. Please rejoin."] = "No se pudo configurar al jugador. Tus datos están seguros; vuelve a entrar.", ["Your data session was opened elsewhere. Please rejoin."] = "Tu sesión de datos se abrió en otro lugar. Vuelve a entrar.", ["Data saving is temporarily unavailable. Please rejoin safely."] = "El guardado de datos no está disponible temporalmente. Vuelve a entrar de forma segura.",
		["SELL YOUR FIRST ORE"] = "VENDE TU PRIMER MINERAL", ["Take the cart to the bank and sell the mined ore."] = "Lleva el carro al banco y vende el mineral extraído.", ["Take the loaded cart to the bank."] = "Lleva el carro cargado al banco.", ["Now talk to the Upgrade Mole, then choose the highlighted MINE card."] = "Habla con el topo de mejoras y elige la tarjeta MINA resaltada.", ["OPEN YOUR GEODE VAULT"] = "ABRE TU BÓVEDA DE GEODAS", ["HEY! GOBLINS ATTACKED!"] = "¡OYE! ¡LOS DUENDES ATACARON!", ["HEY! GOBLINS ATTACKED YOU! DEAL WITH THEM!"] = "¡TE ATACARON LOS DUENDES! ¡ENFRÉNTALOS!", ["DEFEAT THE GOBLIN"] = "DERROTA AL DUENDE", ["Fight back and defeat the goblin attacking your base."] = "Defiéndete y derrota al duende que ataca tu base.", ["MONEY SAFE"] = "CAJA FUERTE DE DINERO", ["Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it."] = "Tu cristal genera dinero con el tiempo y lo guarda aquí. Mantén pulsado el botón de interacción en esta caja para recogerlo.",
	},
	["pt-br"] = {
		["FIND YOUR CART"] = "ENCONTRE SEU CARRINHO", ["Follow the red arrow."] = "Siga a seta vermelha.", ["GO TO YOUR MINE"] = "VÁ ATÉ SUA MINA", ["Place the cart inside the highlighted zone."] = "Coloque o carrinho na área destacada.", ["THE MINE IS WORKING"] = "A MINA ESTÁ FUNCIONANDO", ["Wait for 3 ore pieces: {count}/3"] = "Espere 3 minérios: {count}/3", ["TAKE THE LOADED CART"] = "PEGUE O CARRINHO CHEIO", ["Hold the interaction button near it."] = "Segure o botão de interação perto dele.", ["SELL YOUR ORE"] = "VENDA O MINÉRIO", ["Follow the arrow to the central bank."] = "Siga a seta até o banco central.", ["BUY YOUR FIRST UPGRADE"] = "COMPRE SUA PRIMEIRA MELHORIA", ["Talk to the highlighted Upgrade Mole."] = "Fale com a toupeira destacada.", ["Upgrade your MINE to tier 2."] = "Melhore sua MINA para o nível 2.", ["SKIP TUTORIAL"] = "PULAR TUTORIAL", ["TAP AGAIN TO SKIP"] = "TOQUE NOVAMENTE PARA PULAR",
		["GRAB CART"] = "PEGAR CARRINHO", ["TALK"] = "FALAR", ["UPGRADE YOUR MINE"] = "MELHORE SUA MINA", ["Upgrade your MINE to the next tier."] = "Melhore sua MINA para o próximo nível.", ["TUTORIAL COMPLETE!"] = "TUTORIAL CONCLUÍDO!", ["Mine, sell, fight and upgrade!"] = "Minere, venda, lute e melhore!",
		["YOUR BASE"] = "SUA BASE", ["SKIP"] = "PULAR", ["NEXT"] = "PRÓXIMO", ["START"] = "COMEÇAR", ["TAKE YOUR CART"] = "PEGUE SEU CARRINHO", ["Hold the interaction button near your cart."] = "Segure o botão de interação perto do seu carrinho.", ["START THE MINE"] = "INICIE A MINA", ["Leave the cart anywhere inside the glowing mine zone."] = "Deixe o carrinho dentro da área brilhante da mina.", ["SELL THE ORE"] = "VENDA O MINÉRIO", ["Take the loaded cart to the center bank."] = "Leve o carrinho carregado ao banco central.", ["SURVIVE"] = "SOBREVIVA", ["Use the shield while carrying. Without a cart, equip the pickaxe and attack other players."] = "Use o escudo com o carrinho. Sem ele, equipe a picareta e ataque outros jogadores.",
		["Settings"] = "Configurações", ["On"] = "Ligado", ["Off"] = "Desligado", ["Audio"] = "Áudio", ["Toggle your audio"] = "Ative ou desative o áudio", ["Redeem Codes"] = "Resgatar códigos", ["Look for codes on developer's socials!"] = "Procure códigos nas redes do desenvolvedor!", ["Type code here.."] = "Digite o código...", ["Claim"] = "Resgatar", ["WORLD SOUNDS"] = "SONS DO MUNDO", ["MUSIC"] = "MÚSICA", ["UI SOUNDS"] = "SONS DA INTERFACE", ["VISUAL EFFECTS"] = "EFEITOS VISUAIS", ["Already redeemed."] = "Já resgatado.", ["This code has expired."] = "Este código expirou.", ["Invalid code."] = "Código inválido.",
		["Take Cart"] = "Pegar carrinho", ["Cart"] = "Carrinho", ["Spawn New"] = "Criar novo", ["Drop Cart"] = "Soltar carrinho", ["TAP"] = "TOCAR", ["HOLD"] = "SEGURAR", ["CLICK"] = "CLIQUE", ["Mole Merchant"] = "Toupeira mercadora", ["Rebirth Mole"] = "Toupeira do renascimento", ["MOLE REBIRTH"] = "TOUPEIRA DO RENASCIMENTO", ["REBIRTH MOLE"] = "TOUPEIRA DO RENASCIMENTO", ["Mole Rebirth"] = "Toupeira do renascimento", ["Talk"] = "Falar", ["Upgrade Shop"] = "Loja de melhorias", ["Item Shop"] = "Loja de itens", ["MINE"] = "MINA", ["CART"] = "CARRINHO", ["PICKAXE"] = "PICARETA", ["Welcome! What would you like to upgrade?"] = "Bem-vindo! O que deseja melhorar?", ["Passes"] = "Passes", ["Deals"] = "Ofertas", ["Store!"] = "Loja!", ["Golden Shield"] = "Escudo dourado", ["Speed Boost"] = "Aumento de velocidade", ["Extra Pouch"] = "Bolsa extra", ["+50% Mining Speed"] = "+50% velocidade de mineração", ["Welcome! Take a look at today's deals."] = "Bem-vindo! Veja as ofertas de hoje.", ["FILL INSTANTLY"] = "ENCHER AGORA", ["REBIRTH"] = "RENASCER", ["CANCEL"] = "CANCELAR", ["Open Shop"] = "Abrir loja",
		["Not ready yet!"] = "Ainda não está pronto!", ["NOT READY YET"] = "AINDA NÃO ESTÁ PRONTO", ["New cart isn't ready yet - wait for the countdown!"] = "O novo carrinho ainda não está pronto. Aguarde a contagem!", ["Not enough money! Buy a Money Pack or a cash-boost pass to speed things up."] = "Dinheiro insuficiente! Compre dinheiro ou um passe de bônus.", ["TOP MONEY"] = "MAIS DINHEIRO", ["TOP REBIRTHS"] = "MAIS RENASCIMENTOS", ["TOP CART DAMAGE"] = "MAIS DANO EM CARRINHOS", ["TOP PLAYTIME"] = "MAIS TEMPO JOGADO", ["NO PLAYERS YET"] = "AINDA SEM JOGADORES", ["DATASTORE UNAVAILABLE"] = "DADOS INDISPONÍVEIS", ["COMBO {value}"] = "COMBO {value}", ["Shield +{seconds}s"] = "Escudo +{seconds}s", ["Success! +${amount}"] = "Sucesso! +${amount}",
		["rebirth.intro"] = "Sou a Toupeira do Renascimento.", ["rebirth.needBranches"] = "Melhore os 3 ramos até o nível {tier} primeiro.", ["rebirth.reset"] = "Renascer redefine Mina/Carrinho/Picareta para o nível 1 e aumenta permanentemente o preço do minério.", ["rebirth.cost"] = "Custa <font color=\"#{color}\">${cost}</font>.", ["rebirth.missing"] = "Ainda faltam <font color=\"#{color}\">${amount}</font>.", ["rebirth.stolen"] = "Recupere primeiro seu carrinho roubado!", ["rebirth.success"] = "Renascimento concluído! Multiplicador: x{multiplier}",
		["upgrade.max"] = "{number}) {branch} - MÁX. (nível {tier})", ["upgrade.needRebirth"] = "{number}) {branch} - precisa RENASCER (limite {tier})", ["upgrade.blocked"] = "{number}) {branch} - melhore outros ramos (nível {tier}, {cost})", ["upgrade.buy"] = "{number}) {branch} - nível {tier}, {cost}", ["upgrade.wait"] = "{number}) {branch} - ...", ["WAIT {seconds}s"] = "AGUARDE {seconds}s",
		["Already at max tier"] = "Já está no nível máximo", ["Something went wrong"] = "Algo deu errado", ["Not enough money"] = "Dinheiro insuficiente", ["Catch up other branches first"] = "Melhore os outros ramos primeiro", ["Your cart is stolen!"] = "Seu carrinho foi roubado!",
		["Need REBIRTH (cap tier {tier})"] = "Precisa RENASCER (limite {tier})", ["User {id}"] = "Usuário {id}", ["Rejoin to fully restore graphics after lowering effects."] = "Entre novamente para restaurar totalmente os gráficos após reduzir os efeitos.",
		["2x Cash"] = "Dinheiro x2", ["4x Cash"] = "Dinheiro x4", ["6x Cash"] = "Dinheiro x6", ["8x Cash"] = "Dinheiro x8", ["$3,000 Cash"] = "$3.000", ["$10,000 Cash"] = "$10.000", ["$120,000 Cash"] = "$120.000",
		["ENABLE API SERVICES TO LOAD GLOBAL DATA"] = "ATIVE OS SERVIÇOS DE API PARA CARREGAR DADOS GLOBAIS", ["< Prev"] = "< Anterior", ["Next >"] = "Próxima >",
		["Your data is already loaded on another server. Please try again shortly."] = "Seus dados já estão carregados em outro servidor. Tente novamente em instantes.", ["Your data could not be loaded safely. Please rejoin."] = "Não foi possível carregar seus dados com segurança. Entre novamente.",
		["Player setup failed safely. Please rejoin."] = "A configuração do jogador falhou. Seus dados estão seguros; entre novamente.", ["Your data session was opened elsewhere. Please rejoin."] = "Sua sessão de dados foi aberta em outro lugar. Entre novamente.", ["Data saving is temporarily unavailable. Please rejoin safely."] = "O salvamento de dados está temporariamente indisponível. Entre novamente com segurança.",
		["SELL YOUR FIRST ORE"] = "VENDA SEU PRIMEIRO MINÉRIO", ["Take the cart to the bank and sell the mined ore."] = "Leve o carrinho até o banco e venda o minério extraído.", ["Take the loaded cart to the bank."] = "Leve o carrinho carregado até o banco.", ["Now talk to the Upgrade Mole, then choose the highlighted MINE card."] = "Fale com a toupeira de melhorias e escolha o cartão MINA destacado.", ["OPEN YOUR GEODE VAULT"] = "ABRA SEU COFRE DE GEODOS", ["HEY! GOBLINS ATTACKED!"] = "EI! OS GOBLINS ATACARAM!", ["HEY! GOBLINS ATTACKED YOU! DEAL WITH THEM!"] = "GOBLINS ATACARAM VOCÊ! CUIDE DELES!", ["DEFEAT THE GOBLIN"] = "DERROTE O GOBLIN", ["Fight back and defeat the goblin attacking your base."] = "Revide e derrote o goblin que está atacando sua base.", ["MONEY SAFE"] = "COFRE DE DINHEIRO", ["Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it."] = "Seu cristal gera dinheiro com o tempo e guarda aqui. Segure o botão de interação neste cofre para coletar.",
	},
	ar = {
		["FIND YOUR CART"] = "اعثر على عربتك", ["Follow the red arrow."] = "اتبع السهم الأحمر.", ["GO TO YOUR MINE"] = "اذهب إلى منجمك", ["Place the cart inside the highlighted zone."] = "ضع العربة داخل المنطقة المحددة.", ["THE MINE IS WORKING"] = "المنجم يعمل", ["Wait for 3 ore pieces: {count}/3"] = "انتظر 3 قطع خام: {count}/3", ["TAKE THE LOADED CART"] = "خذ العربة المحملة", ["Hold the interaction button near it."] = "اضغط مطولاً على زر التفاعل قربها.", ["SELL YOUR ORE"] = "بِع الخام", ["Follow the arrow to the central bank."] = "اتبع السهم إلى البنك المركزي.", ["BUY YOUR FIRST UPGRADE"] = "اشترِ أول تطوير", ["Talk to the highlighted Upgrade Mole."] = "تحدث مع خلد التطوير المحدد.", ["Upgrade your MINE to tier 2."] = "طوّر المنجم إلى المستوى 2.", ["SKIP TUTORIAL"] = "تخطي التعليم", ["TAP AGAIN TO SKIP"] = "اضغط مرة أخرى للتخطي",
		["GRAB CART"] = "خذ العربة", ["TALK"] = "تحدث", ["UPGRADE YOUR MINE"] = "طوّر منجمك", ["Upgrade your MINE to the next tier."] = "طوّر المنجم إلى المستوى التالي.", ["TUTORIAL COMPLETE!"] = "اكتمل التعليم!", ["Mine, sell, fight and upgrade!"] = "استخرج وبع وقاتل وطوّر!",
		["YOUR BASE"] = "قاعدتك", ["SKIP"] = "تخطي", ["NEXT"] = "التالي", ["START"] = "ابدأ", ["TAKE YOUR CART"] = "خذ عربتك", ["Hold the interaction button near your cart."] = "اضغط مطولاً على زر التفاعل قرب عربتك.", ["START THE MINE"] = "شغّل المنجم", ["Leave the cart anywhere inside the glowing mine zone."] = "اترك العربة داخل منطقة المنجم المضيئة.", ["SELL THE ORE"] = "بِع الخام", ["Take the loaded cart to the center bank."] = "خذ العربة المحملة إلى البنك المركزي.", ["SURVIVE"] = "ابقَ حياً", ["Use the shield while carrying. Without a cart, equip the pickaxe and attack other players."] = "استخدم الدرع مع العربة. بدونها جهّز المعول وهاجم اللاعبين.",
		["Settings"] = "الإعدادات", ["On"] = "تشغيل", ["Off"] = "إيقاف", ["Audio"] = "الصوت", ["Toggle your audio"] = "تشغيل أو إيقاف الصوت", ["Redeem Codes"] = "استبدال الرموز", ["Look for codes on developer's socials!"] = "ابحث عن الرموز في حسابات المطور!", ["Type code here.."] = "اكتب الرمز...", ["Claim"] = "استبدال", ["WORLD SOUNDS"] = "أصوات العالم", ["MUSIC"] = "الموسيقى", ["UI SOUNDS"] = "أصوات الواجهة", ["VISUAL EFFECTS"] = "المؤثرات البصرية", ["Already redeemed."] = "تم استخدامه مسبقاً.", ["This code has expired."] = "انتهت صلاحية الرمز.", ["Invalid code."] = "رمز غير صالح.",
		["Take Cart"] = "خذ العربة", ["Cart"] = "العربة", ["Spawn New"] = "أنشئ جديدة", ["Drop Cart"] = "اترك العربة", ["TAP"] = "اضغط", ["HOLD"] = "اضغط مطولاً", ["CLICK"] = "انقر", ["Mole Merchant"] = "تاجر الخلد", ["Rebirth Mole"] = "خلد الولادة", ["MOLE REBIRTH"] = "خلد الولادة", ["REBIRTH MOLE"] = "خلد الولادة", ["Mole Rebirth"] = "خلد الولادة", ["Talk"] = "تحدث", ["Upgrade Shop"] = "متجر التطوير", ["Item Shop"] = "متجر الأدوات", ["MINE"] = "المنجم", ["CART"] = "العربة", ["PICKAXE"] = "المعول", ["Welcome! What would you like to upgrade?"] = "مرحباً! ماذا تريد أن تطور؟", ["Passes"] = "التصاريح", ["Deals"] = "العروض", ["Store!"] = "المتجر!", ["Golden Shield"] = "الدرع الذهبي", ["Speed Boost"] = "زيادة السرعة", ["Extra Pouch"] = "حقيبة إضافية", ["+50% Mining Speed"] = "+50% سرعة التعدين", ["Welcome! Take a look at today's deals."] = "مرحباً! شاهد عروض اليوم.", ["FILL INSTANTLY"] = "املأ فوراً", ["REBIRTH"] = "ولادة جديدة", ["CANCEL"] = "إلغاء", ["Open Shop"] = "افتح المتجر",
		["Not ready yet!"] = "ليس جاهزاً بعد!", ["NOT READY YET"] = "ليس جاهزاً بعد", ["New cart isn't ready yet - wait for the countdown!"] = "العربة الجديدة ليست جاهزة. انتظر العد التنازلي!", ["Not enough money! Buy a Money Pack or a cash-boost pass to speed things up."] = "المال غير كافٍ! اشترِ حزمة أموال أو تصريح زيادة.", ["TOP MONEY"] = "الأعلى مالاً", ["TOP REBIRTHS"] = "الأعلى ولادة", ["TOP CART DAMAGE"] = "الأعلى ضرراً للعربات", ["TOP PLAYTIME"] = "الأعلى وقتاً في اللعب", ["NO PLAYERS YET"] = "لا يوجد لاعبون بعد", ["DATASTORE UNAVAILABLE"] = "البيانات غير متاحة", ["COMBO {value}"] = "سلسلة {value}", ["Shield +{seconds}s"] = "درع +{seconds}ث", ["Success! +${amount}"] = "تم! +${amount}",
		["rebirth.intro"] = "أنا خلد الولادة.", ["rebirth.needBranches"] = "طوّر الفروع الثلاثة إلى المستوى {tier} أولاً.", ["rebirth.reset"] = "الولادة تعيد المنجم والعربة والمعول إلى المستوى 1 وتزيد سعر الخام دائماً.", ["rebirth.cost"] = "التكلفة <font color=\"#{color}\">${cost}</font>.", ["rebirth.missing"] = "ما زلت تحتاج <font color=\"#{color}\">${amount}</font>.", ["rebirth.stolen"] = "استعد عربتك المسروقة أولاً!", ["rebirth.success"] = "تمت الولادة! المضاعف: x{multiplier}",
		["upgrade.max"] = "{number}) {branch} - الحد الأقصى (المستوى {tier})", ["upgrade.needRebirth"] = "{number}) {branch} - تتطلب ولادة (الحد {tier})", ["upgrade.blocked"] = "{number}) {branch} - طوّر الفروع الأخرى (المستوى {tier}، {cost})", ["upgrade.buy"] = "{number}) {branch} - المستوى {tier}، {cost}", ["upgrade.wait"] = "{number}) {branch} - ...", ["WAIT {seconds}s"] = "انتظر {seconds} ثانية",
		["Already at max tier"] = "وصلت إلى الحد الأقصى", ["Something went wrong"] = "حدث خطأ", ["Not enough money"] = "المال غير كافٍ", ["Catch up other branches first"] = "طوّر الفروع الأخرى أولاً", ["Your cart is stolen!"] = "عربتك مسروقة!",
		["Need REBIRTH (cap tier {tier})"] = "تحتاج إلى ولادة (الحد {tier})", ["User {id}"] = "المستخدم {id}", ["Rejoin to fully restore graphics after lowering effects."] = "أعد الدخول لاستعادة الرسومات بالكامل بعد تقليل المؤثرات.",
		["2x Cash"] = "المال x2", ["4x Cash"] = "المال x4", ["6x Cash"] = "المال x6", ["8x Cash"] = "المال x8", ["$3,000 Cash"] = "$3,000", ["$10,000 Cash"] = "$10,000", ["$120,000 Cash"] = "$120,000",
		["ENABLE API SERVICES TO LOAD GLOBAL DATA"] = "فعّل خدمات API لتحميل البيانات العالمية", ["< Prev"] = "< السابق", ["Next >"] = "التالي >",
		["Your data is already loaded on another server. Please try again shortly."] = "بياناتك محمّلة بالفعل على خادم آخر. حاول مجددًا بعد قليل.", ["Your data could not be loaded safely. Please rejoin."] = "تعذر تحميل بياناتك بأمان. يُرجى الانضمام مجددًا.",
		["Player setup failed safely. Please rejoin."] = "تعذر إعداد اللاعب. بياناتك آمنة؛ يُرجى الانضمام مجددًا.", ["Your data session was opened elsewhere. Please rejoin."] = "فُتحت جلسة بياناتك في مكان آخر. يُرجى الانضمام مجددًا.", ["Data saving is temporarily unavailable. Please rejoin safely."] = "حفظ البيانات غير متاح مؤقتًا. يُرجى الانضمام مجددًا بأمان.",
		["HOLD!"] = "اضغط مطولاً!",
		["SELL YOUR FIRST ORE"] = "بِع أول خام لك", ["Take the cart to the bank and sell the mined ore."] = "خذ العربة إلى البنك وبِع الخام المستخرج.", ["Take the loaded cart to the bank."] = "خذ العربة المحمّلة إلى البنك.", ["Now talk to the Upgrade Mole, then choose the highlighted MINE card."] = "تحدث مع خلد التطوير، ثم اختر بطاقة المنجم المميزة.", ["OPEN YOUR GEODE VAULT"] = "افتح خزنة الجيود الخاصة بك", ["HEY! GOBLINS ATTACKED!"] = "انتبه! هاجمك الغيلان!", ["HEY! GOBLINS ATTACKED YOU! DEAL WITH THEM!"] = "هاجمك الغيلان! تعامل معهم!", ["DEFEAT THE GOBLIN"] = "اهزم الغول", ["Fight back and defeat the goblin attacking your base."] = "دافع عن نفسك واهزم الغول الذي يهاجم قاعدتك.", ["MONEY SAFE"] = "خزنة المال", ["Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it."] = "بلورتك تكسب مالاً مع الوقت وتخزنه هنا. اضغط مطولاً على زر التفاعل عند هذه الخزنة لجمعه.",
	},
	ja = {
		["FIND YOUR CART"] = "カートを見つけよう", ["Follow the red arrow."] = "赤い矢印を追ってください。", ["GO TO YOUR MINE"] = "自分の鉱山へ行こう", ["Place the cart inside the highlighted zone."] = "強調されたエリアにカートを置きます。", ["THE MINE IS WORKING"] = "鉱山が稼働中", ["Wait for 3 ore pieces: {count}/3"] = "鉱石を3個待ちます: {count}/3", ["TAKE THE LOADED CART"] = "鉱石入りカートを取ろう", ["Hold the interaction button near it."] = "近くで操作ボタンを長押しします。", ["SELL YOUR ORE"] = "鉱石を売ろう", ["Follow the arrow to the central bank."] = "矢印に従って中央銀行へ行きます。", ["BUY YOUR FIRST UPGRADE"] = "最初の強化を買おう", ["Talk to the highlighted Upgrade Mole."] = "強調された強化モグラと話します。", ["Upgrade your MINE to tier 2."] = "鉱山をティア2に強化します。", ["SKIP TUTORIAL"] = "チュートリアルをスキップ", ["TAP AGAIN TO SKIP"] = "もう一度タップしてスキップ",
		["GRAB CART"] = "カートを取る", ["TALK"] = "話す", ["UPGRADE YOUR MINE"] = "鉱山を強化しよう", ["Upgrade your MINE to the next tier."] = "鉱山を次のティアに強化します。", ["TUTORIAL COMPLETE!"] = "チュートリアル完了！", ["Mine, sell, fight and upgrade!"] = "採掘、販売、戦闘、強化を楽しもう！",
		["YOUR BASE"] = "あなたの基地", ["SKIP"] = "スキップ", ["NEXT"] = "次へ", ["START"] = "スタート", ["TAKE YOUR CART"] = "カートを取ろう", ["Hold the interaction button near your cart."] = "カートの近くで操作ボタンを長押しします。", ["START THE MINE"] = "鉱山を動かそう", ["Leave the cart anywhere inside the glowing mine zone."] = "光る鉱山エリア内にカートを置きます。", ["SELL THE ORE"] = "鉱石を売ろう", ["Take the loaded cart to the center bank."] = "鉱石を積んだカートを中央銀行へ運びます。", ["SURVIVE"] = "生き残ろう", ["Use the shield while carrying. Without a cart, equip the pickaxe and attack other players."] = "カート運搬中はシールドを使い、カートがない時はツルハシで戦います。",
		["Settings"] = "設定", ["On"] = "オン", ["Off"] = "オフ", ["Audio"] = "オーディオ", ["Toggle your audio"] = "音声のオン・オフ", ["Redeem Codes"] = "コード入力", ["Look for codes on developer's socials!"] = "開発者のSNSでコードを探そう！", ["Type code here.."] = "コードを入力...", ["Claim"] = "受け取る", ["WORLD SOUNDS"] = "ワールド音", ["MUSIC"] = "音楽", ["UI SOUNDS"] = "UIサウンド", ["VISUAL EFFECTS"] = "視覚効果", ["Already redeemed."] = "使用済みです。", ["This code has expired."] = "このコードは期限切れです。", ["Invalid code."] = "無効なコードです。",
		["Take Cart"] = "カートを取る", ["Cart"] = "カート", ["Spawn New"] = "新しく作る", ["Drop Cart"] = "カートを離す", ["TAP"] = "タップ", ["HOLD"] = "長押し", ["CLICK"] = "クリック", ["Mole Merchant"] = "モグラ商人", ["Rebirth Mole"] = "転生モグラ", ["MOLE REBIRTH"] = "転生モグラ", ["REBIRTH MOLE"] = "転生モグラ", ["Mole Rebirth"] = "転生モグラ", ["Talk"] = "話す", ["Upgrade Shop"] = "アップグレード店", ["Item Shop"] = "アイテム店", ["MINE"] = "鉱山", ["CART"] = "カート", ["PICKAXE"] = "ツルハシ", ["Welcome! What would you like to upgrade?"] = "ようこそ！何をアップグレードしますか？", ["Passes"] = "パス", ["Deals"] = "セール", ["Store!"] = "ストア！", ["Golden Shield"] = "ゴールデンシールド", ["Speed Boost"] = "スピードブースト", ["Extra Pouch"] = "追加ポーチ", ["+50% Mining Speed"] = "採掘速度 +50%", ["Welcome! Take a look at today's deals."] = "ようこそ！本日のセールをご覧ください。", ["FILL INSTANTLY"] = "すぐ満タン", ["REBIRTH"] = "転生", ["CANCEL"] = "キャンセル", ["Open Shop"] = "ショップを開く",
		["Not ready yet!"] = "まだ準備中です！", ["NOT READY YET"] = "まだ準備中", ["New cart isn't ready yet - wait for the countdown!"] = "新しいカートはまだ準備中です。カウントダウンを待ってください！", ["Not enough money! Buy a Money Pack or a cash-boost pass to speed things up."] = "お金が足りません！マネーパックかキャッシュブーストを購入してください。", ["TOP MONEY"] = "所持金ランキング", ["TOP REBIRTHS"] = "転生ランキング", ["TOP CART DAMAGE"] = "カートダメージランキング", ["TOP PLAYTIME"] = "プレイ時間ランキング", ["NO PLAYERS YET"] = "まだプレイヤーがいません", ["DATASTORE UNAVAILABLE"] = "データを利用できません", ["COMBO {value}"] = "コンボ {value}", ["Shield +{seconds}s"] = "シールド +{seconds}秒", ["Success! +${amount}"] = "成功！ +${amount}",
		["rebirth.intro"] = "転生モグラです。", ["rebirth.needBranches"] = "3つの部門をすべてティア{tier}まで強化してください。", ["rebirth.reset"] = "転生すると鉱山/カート/ツルハシがティア1に戻り、鉱石価格が永久に上がります。", ["rebirth.cost"] = "費用は<font color=\"#{color}\">${cost}</font>です。", ["rebirth.missing"] = "あと<font color=\"#{color}\">${amount}</font>必要です。", ["rebirth.stolen"] = "まず盗まれたカートを取り戻してください！", ["rebirth.success"] = "転生完了！倍率: x{multiplier}",
		["upgrade.max"] = "{number}) {branch} - 最大 (ティア{tier})", ["upgrade.needRebirth"] = "{number}) {branch} - 転生が必要 (上限{tier})", ["upgrade.blocked"] = "{number}) {branch} - 他を強化 (ティア{tier}、{cost})", ["upgrade.buy"] = "{number}) {branch} - ティア{tier}、{cost}", ["upgrade.wait"] = "{number}) {branch} - ...", ["WAIT {seconds}s"] = "待機 {seconds}秒",
		["Already at max tier"] = "すでに最大ティアです", ["Something went wrong"] = "エラーが発生しました", ["Not enough money"] = "お金が足りません", ["Catch up other branches first"] = "先に他の部門を強化してください", ["Your cart is stolen!"] = "カートが盗まれています！",
		["Need REBIRTH (cap tier {tier})"] = "転生が必要です (上限{tier})", ["User {id}"] = "ユーザー {id}", ["Rejoin to fully restore graphics after lowering effects."] = "エフェクトを下げた後、グラフィックを完全に戻すには再参加してください。",
		["2x Cash"] = "お金2倍", ["4x Cash"] = "お金4倍", ["6x Cash"] = "お金6倍", ["8x Cash"] = "お金8倍", ["$3,000 Cash"] = "$3,000", ["$10,000 Cash"] = "$10,000", ["$120,000 Cash"] = "$120,000",
		["ENABLE API SERVICES TO LOAD GLOBAL DATA"] = "グローバルデータを読み込むにはAPIサービスを有効にしてください", ["< Prev"] = "< 前へ", ["Next >"] = "次へ >",
		["Your data is already loaded on another server. Please try again shortly."] = "あなたのデータは別のサーバーですでに読み込まれています。しばらくしてからもう一度お試しください。", ["Your data could not be loaded safely. Please rejoin."] = "データを安全に読み込めませんでした。もう一度参加してください。",
		["Player setup failed safely. Please rejoin."] = "プレイヤーの設定に失敗しました。データは安全です。もう一度参加してください。", ["Your data session was opened elsewhere. Please rejoin."] = "データセッションが別の場所で開かれました。もう一度参加してください。", ["Data saving is temporarily unavailable. Please rejoin safely."] = "データの保存は一時的に利用できません。安全にもう一度参加してください。",
		["HOLD!"] = "長押し！",
		["SELL YOUR FIRST ORE"] = "初めての鉱石を売ろう", ["Take the cart to the bank and sell the mined ore."] = "カートを銀行に運んで採掘した鉱石を売却しよう。", ["Take the loaded cart to the bank."] = "積んだカートを銀行に運ぼう。", ["Now talk to the Upgrade Mole, then choose the highlighted MINE card."] = "強化モグラと話して、強調された鉱山カードを選ぼう。", ["OPEN YOUR GEODE VAULT"] = "ジオードの保管庫を開こう", ["HEY! GOBLINS ATTACKED!"] = "おっと！ゴブリンが襲ってきた！", ["HEY! GOBLINS ATTACKED YOU! DEAL WITH THEM!"] = "ゴブリンに襲われた！対処しよう！", ["DEFEAT THE GOBLIN"] = "ゴブリンを倒そう", ["Fight back and defeat the goblin attacking your base."] = "反撃して、拠点を襲うゴブリンを倒そう。", ["MONEY SAFE"] = "お金の金庫", ["Your crystal makes money over time and stores it here. Hold the interaction button at this safe to collect it."] = "クリスタルは時間とともにお金を生み、ここに貯まります。この金庫で操作ボタンを長押しして回収しよう。",
	},
}

-- ИСПРАВЛЕНИЕ ПОТЕРИ ПЕРЕВОДОВ: ниже раньше шли ВТОРЫЕ по счёту ключи
-- `ar = { ... }` и `ja = { ... }` прямо внутри этого же табличного литерала —
-- то есть дубликаты уже объявленных выше арабского и японского блоков.
-- В Lua при повторе ключа в конструкторе таблицы ПОБЕЖДАЕТ ПОСЛЕДНИЙ: обе
-- полные таблицы переводов (по 128 строк каждая) молча выбрасывались и
-- заменялись этими короткими довесками на 48 строк. Наружу это выглядело
-- так, будто арабская и японская локализации почти целиком не работают —
-- игроки видели английский там, где перевод на самом деле давно написан.
-- Теперь довески не переопределяют блоки, а ДОПИСЫВАЮТСЯ в них.
local lateAdditions = {
	ar = {
		["Loaded Delivery"] = "توصيل محمّل", ["Fill at least 70% of your cart and sell all of it."] = "املأ عربتك بنسبة 70% على الأقل وبع الحمولة كلها.", ["Upgrade the Mine"] = "طوّر المنجم", ["Upgrade your Mine to tier 2."] = "طوّر منجمك إلى المستوى 2.", ["Upgrade the Cart"] = "طوّر العربة", ["Upgrade your Cart to tier 2."] = "طوّر عربتك إلى المستوى 2.", ["Upgrade the Pickaxe"] = "طوّر المعول", ["Upgrade your Pickaxe to tier 2."] = "طوّر معولك إلى المستوى 2.", ["Earn Your First Thousand"] = "اكسب أول ألف", ["Earn $1,000 from selling ore."] = "اكسب 1,000$ من بيع الخام.", ["Cargo Runner"] = "ناقل الحمولة", ["Complete five full cart sales."] = "أكمل خمس مبيعات لعربات ممتلئة.", ["Heavy Cargo"] = "حمولة ثقيلة", ["Deliver three carts filled to at least 70%."] = "سلّم ثلاث عربات ممتلئة بنسبة 70% على الأقل.", ["Geode Collector"] = "جامع الجيود", ["Open three geodes."] = "افتح ثلاث جيود.", ["Crystal Collection"] = "مجموعة البلورات", ["Collect ten crystal rewards."] = "اجمع عشر مكافآت بلورية.", ["Rare Find"] = "اكتشاف نادر", ["Discover a Rare or better crystal."] = "اكتشف بلورة نادرة أو أفضل.", ["Passive Fortune"] = "ثروة سلبية", ["Collect $10,000 from your income safe."] = "اجمع 10,000$ من خزنة دخلك.", ["Upgrade Path"] = "طريق التطوير", ["Buy three upgrades."] = "اشترِ ثلاثة تطويرات.", ["Balanced Growth"] = "نمو متوازن", ["Upgrade Mine, Cart, and Pickaxe at least once."] = "طوّر المنجم والعربة والمعول مرة واحدة على الأقل.", ["Ready to Fight"] = "مستعد للقتال", ["Hit other players or their carts ten times."] = "اضرب اللاعبين أو عرباتهم عشر مرات.", ["Ore Thief"] = "سارق الخام", ["Knock out or steal ten enemy ores."] = "أسقط أو اسرق عشر قطع خام للعدو.", ["Damage Dealer"] = "مسبب الضرر", ["Deal 500 damage to other players."] = "ألحق 500 ضرر باللاعبين الآخرين.", ["Safe Delivery"] = "توصيل آمن", ["Deliver and sell three full carts."] = "سلّم وبع ثلاث عربات ممتلئة.", ["Combo Master"] = "خبير السلسلة", ["Sell five carts at x4 combo."] = "بع خمس عربات بسلسلة x4.", ["Tier Master"] = "خبير المستويات", ["Reach the maximum Mine tier."] = "بلغ أقصى مستوى للمنجم.", ["Full Upgrade"] = "تطوير كامل", ["Reach the maximum tier in all three branches."] = "بلغ أقصى مستوى في الفروع الثلاثة.", ["Geode Expert"] = "خبير الجيود", ["Open fifty geodes."] = "افتح خمسين جيود.", ["Crystal Hoarder"] = "جامع البلورات", ["Collect 100 crystal rewards."] = "اجمع 100 مكافأة بلورية.", ["Master Miner"] = "عامل منجم محترف", ["Sell 500 pieces of ore."] = "بع 500 قطعة خام.", ["The Big Goal"] = "الهدف الكبير", ["Reach and complete your first rebirth."] = "بلغ وأكمل أول ولادة جديدة.",
	},
	ja = {
		["Loaded Delivery"] = "満載配送", ["Fill at least 70% of your cart and sell all of it."] = "カートを70%以上満たして、すべて売却しよう。", ["Upgrade the Mine"] = "鉱山を強化", ["Upgrade your Mine to tier 2."] = "鉱山をティア2に強化しよう。", ["Upgrade the Cart"] = "カートを強化", ["Upgrade your Cart to tier 2."] = "カートをティア2に強化しよう。", ["Upgrade the Pickaxe"] = "ツルハシを強化", ["Upgrade your Pickaxe to tier 2."] = "ツルハシをティア2に強化しよう。", ["Earn Your First Thousand"] = "最初の1000を稼ごう", ["Earn $1,000 from selling ore."] = "鉱石を売って$1,000稼ごう。", ["Cargo Runner"] = "カーゴランナー", ["Complete five full cart sales."] = "満載カートを5回売却しよう。", ["Heavy Cargo"] = "重量貨物", ["Deliver three carts filled to at least 70%."] = "70%以上積んだカートを3台届けよう。", ["Geode Collector"] = "ジオードコレクター", ["Open three geodes."] = "ジオードを3個開こう。", ["Crystal Collection"] = "クリスタルコレクション", ["Collect ten crystal rewards."] = "クリスタル報酬を10個集めよう。", ["Rare Find"] = "レア発見", ["Discover a Rare or better crystal."] = "レア以上のクリスタルを見つけよう。", ["Passive Fortune"] = "放置の富", ["Collect $10,000 from your income safe."] = "収入金庫から$10,000集めよう。", ["Upgrade Path"] = "強化への道", ["Buy three upgrades."] = "強化を3回購入しよう。", ["Balanced Growth"] = "バランス成長", ["Upgrade Mine, Cart, and Pickaxe at least once."] = "鉱山、カート、ツルハシをそれぞれ1回以上強化しよう。", ["Ready to Fight"] = "戦闘準備完了", ["Hit other players or their carts ten times."] = "他のプレイヤーかカートに10回攻撃を当てよう。", ["Ore Thief"] = "鉱石泥棒", ["Knock out or steal ten enemy ores."] = "敵の鉱石を10個奪うか落とさせよう。", ["Damage Dealer"] = "ダメージディーラー", ["Deal 500 damage to other players."] = "他のプレイヤーに500ダメージ与えよう。", ["Safe Delivery"] = "安全な配送", ["Deliver and sell three full carts."] = "満載カートを3台届けて売却しよう。", ["Combo Master"] = "コンボマスター", ["Sell five carts at x4 combo."] = "x4コンボでカートを5台売ろう。", ["Tier Master"] = "ティアマスター", ["Reach the maximum Mine tier."] = "鉱山を最大ティアにしよう。", ["Full Upgrade"] = "完全強化", ["Reach the maximum tier in all three branches."] = "3つの部門をすべて最大ティアにしよう。", ["Geode Expert"] = "ジオードの達人", ["Open fifty geodes."] = "ジオードを50個開こう。", ["Crystal Hoarder"] = "クリスタル収集家", ["Collect 100 crystal rewards."] = "クリスタル報酬を100個集めよう。", ["Master Miner"] = "マスターマイナー", ["Sell 500 pieces of ore."] = "鉱石を500個売ろう。", ["The Big Goal"] = "大きな目標", ["Reach and complete your first rebirth."] = "初めての転生を達成して完了しよう。",
	},
}
for language, entries in lateAdditions do
	local target = translations[language]
	if target then
		for key, value in entries do
			target[key] = value
		end
	else
		translations[language] = entries
	end
end

-- v20: подписи новых экранов (билдеры Shared.UiBuilders / *UiBuilder).
local uiV20Translations = {
	ru = {
		["CHEST OPENED!"] = "СУНДУК ОТКРЫТ!", ["CHESTS"] = "СУНДУКИ", ["GEODES"] = "ЖЕОДЫ", ["COLLECT ALL"] = "ЗАБРАТЬ ВСЁ",
		["DROP CHANCES"] = "ШАНСЫ ДРОПА", ["DROPS"] = "ДРОП", ["Daily"] = "Ежедневные", ["Weekly"] = "Недельные", ["Story"] = "Сюжет",
		["Daily Quests"] = "Ежедневные задания", ["Main Quests"] = "Основные задания", ["Quests"] = "Задания", ["Track"] = "Следить", ["Tracking"] = "Отслеживается",
		["Everything resets on prestige"] = "При престиже всё сбрасывается", ["FAVORITE = FREE REWARD"] = "В ИЗБРАННОЕ = НАГРАДА",
		["FAVORITE: FREE SKIN"] = "ИЗБРАННОЕ: СКИН БЕСПЛАТНО", ["GROUP: +10% CASH"] = "ГРУППА: +10% ДЕНЕГ", ["JOIN GROUP = MORE CASH"] = "ВСТУПИ В ГРУППУ = БОЛЬШЕ ДЕНЕГ",
		["LIKE THE GAME!"] = "ПОСТАВЬ ЛАЙК!", ["KNOCKDOWN!"] = "НОКДАУН!", ["STUNNED!"] = "ОГЛУШЁН!", ["PERFECT BREAK!"] = "ИДЕАЛЬНЫЙ УДАР!",
		["Islands"] = "Острова", ["Unlock islands behind your base!"] = "Открывай острова за своей базой!", ["Tap a card to see what it gives"] = "Нажми на карточку, чтобы узнать, что она даёт",
		["LIMITED"] = "ЛИМИТ", ["LOCKED"] = "ЗАКРЫТО", ["NEW"] = "НОВОЕ", ["NEW!"] = "НОВОЕ!", ["YES"] = "ДА", ["NO"] = "НЕТ",
		["Needs 2+ players on the server"] = "Нужно 2+ игрока на сервере", ["Nothing in stock - wait for the next restock!"] = "Всё раскуплено - жди нового завоза!",
		["PICK A CRYSTAL"] = "ВЫБЕРИ КРИСТАЛЛ", ["PICK AN ITEM"] = "ВЫБЕРИ ПРЕДМЕТ", ["Play with a friend for 20 minutes"] = "Поиграй с другом 20 минут",
		["Playtime Rewards!"] = "Награды за игру!", ["RARE DROP!"] = "РЕДКИЙ ДРОП!", ["REWARD"] = "НАГРАДА", ["SHIELD"] = "ЩИТ", ["SKIP >"] = "ПРОПУСТИТЬ >",
		["STARTER KIT"] = "СТАРТОВЫЙ НАБОР", ["Starter Kit"] = "Стартовый набор", ["Search"] = "Поиск", ["Skins"] = "Скины", ["Upgrades"] = "Улучшения",
		["TAP TO CONTINUE"] = "НАЖМИ, ЧТОБЫ ПРОДОЛЖИТЬ", ["TAP!"] = "ЖМИ!", ["THANK YOU! ❤"] = "СПАСИБО! ❤", ["Welcome Back!"] = "С возвращением!",
		["What you get"] = "Что ты получишь", ["What you need"] = "Что нужно", ["You need"] = "Нужно", ["You were gone"] = "Тебя не было",
		["Your cart is loaded - deliver it to the bank"] = "Тележка загружена - отвези её в банк", ["Your like helps us make updates!"] = "Твой лайк помогает нам делать обновления!",
		["< BACK"] = "< НАЗАД", ["⛏ CRACK"] = "⛏ РАСКОЛОТЬ", ["✅ EQUIPPED"] = "✅ НАДЕТО", ["⭐ FAVORITE & CLAIM"] = "⭐ В ИЗБРАННОЕ И ЗАБРАТЬ",
		["⭐ Prestige"] = "⭐ Престиж", ["⭐ Prestige Perks"] = "⭐ Перки престижа", ["🎁 FREE REWARD"] = "🎁 БЕСПЛАТНАЯ НАГРАДА", ["🏦 Bank Vault"] = "🏦 Хранилище банка",
		["👥 JOIN & CLAIM"] = "👥 ВСТУПИТЬ И ЗАБРАТЬ", ["📖 Collection"] = "📖 Коллекция", ["🔍 ALL DROPS"] = "🔍 ВЕСЬ ДРОП", ["🛒 BUY"] = "🛒 КУПИТЬ",
		["Menu"] = "Меню", ["Permanent upgrade!"] = "Навсегда!", ["Instant delivery!"] = "Мгновенно!", ["OWNED"] = "КУПЛЕНО", ["BUY"] = "КУПИТЬ",
		["Prospector's Shop"] = "Лавка старателя", ["BACK"] = "НАЗАД", ["UPGRADE"] = "УЛУЧШИТЬ", ["MAX LEVEL"] = "МАКС. УРОВЕНЬ",
		["SKIP TUTORIAL"] = "ПРОПУСТИТЬ ОБУЧЕНИЕ",
		["Blasts boulders and knocks players"] = "Взрывает валуны и отбрасывает игроков", ["Click to throw · click a boulder to plant"] = "Клик - бросить · клик по валуну - заложить",
		["Opens after a timer with loot inside"] = "Открывается по таймеру, внутри лут", ["Click the ground of your base to place"] = "Кликни по земле своей базы, чтобы поставить",
		["Click to drink"] = "Клик - выпить", ["Go to your podium and press APPLY ESSENCE"] = "Подойди к подиуму и нажми APPLY ESSENCE",
		["Click your base to place · R to rotate"] = "Клик по базе - поставить · R - повернуть", ["Decoration for your base"] = "Украшение для базы",
		["Cart Package"] = "Упакованная тележка", ["Your mining cart, still packed"] = "Твоя тележка, ещё в упаковке", ["Click the ground at your base to unpack it"] = "Кликни по земле базы, чтобы распаковать",
		["Breaks boulders, hits players and carts"] = "Ломает валуны, бьёт игроков и тележки", ["Click to swing"] = "Клик - удар",
		["Claim"] = "Забрать", ["Refresh in:"] = "Обновление через:", ["BEST VALUE!"] = "ВЫГОДНЕЕ ВСЕГО!", ["COMING SOON"] = "СКОРО",
		["Forever Pack"] = "Вечный набор", ["Mega Cash"] = "Мега-деньги", ["Special Offers"] = "Спецпредложения", ["Game Passes"] = "Геймпассы",
		["Weather"] = "Погода", ["Geodes"] = "Жеоды", ["Dynamite"] = "Динамит", ["Cash"] = "Деньги", ["Boosts"] = "Усиления", ["Skins"] = "Скины", ["drag to rotate"] = "тяни, чтобы вращать", ["CRYSTAL"] = "КРИСТАЛЛ",
	},
}
for language, entries in uiV20Translations do
	local target = translations[language]
	if target then
		for key, value in entries do
			if target[key] == nil then target[key] = value end
		end
	end
end


local questTranslations = {
	ru = {
		["Loaded Delivery"] = "Загруженная доставка", ["Fill at least 70% of your cart and sell all of it."] = "Заполните тележку минимум на 70% и продайте весь груз.",
		["Upgrade the Mine"] = "Улучшите шахту", ["Upgrade your Mine to tier 2."] = "Улучшите шахту до 2 тира.", ["Upgrade the Cart"] = "Улучшите тележку", ["Upgrade your Cart to tier 2."] = "Улучшите тележку до 2 тира.", ["Upgrade the Pickaxe"] = "Улучшите кирку", ["Upgrade your Pickaxe to tier 2."] = "Улучшите кирку до 2 тира.",
		["Earn Your First Thousand"] = "Заработайте первую тысячу", ["Earn $1,000 from selling ore."] = "Заработайте $1 000 на продаже руды.", ["Cargo Runner"] = "Грузовой рейс", ["Complete five full cart sales."] = "Завершите пять полных продаж тележки.", ["Heavy Cargo"] = "Тяжёлый груз", ["Deliver three carts filled to at least 70%."] = "Доставьте три тележки, заполненные минимум на 70%.",
		["Geode Collector"] = "Коллекционер жеод", ["Open three geodes."] = "Откройте три жеоды.", ["Crystal Collection"] = "Коллекция кристаллов", ["Collect ten crystal rewards."] = "Получите десять кристаллических наград.", ["Rare Find"] = "Редкая находка", ["Discover a Rare or better crystal."] = "Найдите редкий или более ценный кристалл.",
		["Passive Fortune"] = "Пассивное состояние", ["Collect $10,000 from your income safe."] = "Соберите $10 000 из сейфа дохода.", ["Upgrade Path"] = "Путь улучшений", ["Buy three upgrades."] = "Купите три улучшения.", ["Balanced Growth"] = "Сбалансированный рост", ["Upgrade Mine, Cart, and Pickaxe at least once."] = "Улучшите шахту, тележку и кирку хотя бы по разу.",
		["Ready to Fight"] = "Готовы к бою", ["Hit other players or their carts ten times."] = "Попадите по игрокам или их тележкам десять раз.", ["Ore Thief"] = "Похититель руды", ["Knock out or steal ten enemy ores."] = "Выбейте или украдите десять единиц вражеской руды.", ["Damage Dealer"] = "Нанесите урон", ["Deal 500 damage to other players."] = "Нанесите другим игрокам 500 урона.",
		["Safe Delivery"] = "Безопасная доставка", ["Deliver and sell three full carts."] = "Доставьте и продайте три полные тележки.", ["Combo Master"] = "Мастер комбо", ["Sell five carts at x4 combo."] = "Продайте пять тележек с комбо x4.", ["Tier Master"] = "Мастер тиров", ["Reach the maximum Mine tier."] = "Достигните максимального тира шахты.", ["Full Upgrade"] = "Полное улучшение", ["Reach the maximum tier in all three branches."] = "Достигните максимального тира во всех трёх ветках.", ["Geode Expert"] = "Эксперт по жеодам", ["Open fifty geodes."] = "Откройте пятьдесят жеод.", ["Crystal Hoarder"] = "Собиратель кристаллов", ["Collect 100 crystal rewards."] = "Получите 100 кристаллических наград.", ["Master Miner"] = "Мастер шахты", ["Sell 500 pieces of ore."] = "Продайте 500 единиц руды.", ["The Big Goal"] = "Большая цель", ["Reach and complete your first rebirth."] = "Достигните и завершите первое перерождение.",
	},
	es = {
		["Loaded Delivery"] = "Entrega cargada", ["Fill at least 70% of your cart and sell all of it."] = "Llena al menos el 70% del carro y véndelo todo.", ["Upgrade the Mine"] = "Mejora la mina", ["Upgrade your Mine to tier 2."] = "Mejora tu mina al nivel 2.", ["Upgrade the Cart"] = "Mejora el carro", ["Upgrade your Cart to tier 2."] = "Mejora tu carro al nivel 2.", ["Upgrade the Pickaxe"] = "Mejora el pico", ["Upgrade your Pickaxe to tier 2."] = "Mejora tu pico al nivel 2.",
		["Earn Your First Thousand"] = "Gana tus primeros mil", ["Earn $1,000 from selling ore."] = "Gana $1,000 vendiendo mineral.", ["Cargo Runner"] = "Transportista", ["Complete five full cart sales."] = "Completa cinco ventas de carros llenos.", ["Heavy Cargo"] = "Carga pesada", ["Deliver three carts filled to at least 70%."] = "Entrega tres carros llenos al menos al 70%.", ["Geode Collector"] = "Coleccionista de geodas", ["Open three geodes."] = "Abre tres geodas.", ["Crystal Collection"] = "Colección de cristales", ["Collect ten crystal rewards."] = "Consigue diez recompensas de cristal.", ["Rare Find"] = "Hallazgo raro", ["Discover a Rare or better crystal."] = "Descubre un cristal Raro o mejor.",
		["Passive Fortune"] = "Fortuna pasiva", ["Collect $10,000 from your income safe."] = "Recoge $10,000 de tu caja fuerte.", ["Upgrade Path"] = "Ruta de mejoras", ["Buy three upgrades."] = "Compra tres mejoras.", ["Balanced Growth"] = "Crecimiento equilibrado", ["Upgrade Mine, Cart, and Pickaxe at least once."] = "Mejora la mina, el carro y el pico al menos una vez.", ["Ready to Fight"] = "Listo para luchar", ["Hit other players or their carts ten times."] = "Golpea a jugadores o sus carros diez veces.", ["Ore Thief"] = "Ladrón de mineral", ["Knock out or steal ten enemy ores."] = "Arrebata o roba diez minerales enemigos.", ["Damage Dealer"] = "Repartidor de daño", ["Deal 500 damage to other players."] = "Inflige 500 de daño a otros jugadores.", ["Safe Delivery"] = "Entrega segura", ["Deliver and sell three full carts."] = "Entrega y vende tres carros llenos.", ["Combo Master"] = "Maestro del combo", ["Sell five carts at x4 combo."] = "Vende cinco carros con combo x4.", ["Tier Master"] = "Maestro de niveles", ["Reach the maximum Mine tier."] = "Alcanza el nivel máximo de la mina.", ["Full Upgrade"] = "Mejora completa", ["Reach the maximum tier in all three branches."] = "Alcanza el nivel máximo en las tres ramas.", ["Geode Expert"] = "Experto en geodas", ["Open fifty geodes."] = "Abre cincuenta geodas.", ["Crystal Hoarder"] = "Acaparador de cristales", ["Collect 100 crystal rewards."] = "Consigue 100 recompensas de cristal.", ["Master Miner"] = "Minero maestro", ["Sell 500 pieces of ore."] = "Vende 500 minerales.", ["The Big Goal"] = "El gran objetivo", ["Reach and complete your first rebirth."] = "Alcanza y completa tu primer renacimiento.",
	},
	["pt-br"] = {
		["Loaded Delivery"] = "Entrega carregada", ["Fill at least 70% of your cart and sell all of it."] = "Encha pelo menos 70% do carrinho e venda tudo.", ["Upgrade the Mine"] = "Melhore a mina", ["Upgrade your Mine to tier 2."] = "Melhore sua mina para o nível 2.", ["Upgrade the Cart"] = "Melhore o carrinho", ["Upgrade your Cart to tier 2."] = "Melhore seu carrinho para o nível 2.", ["Upgrade the Pickaxe"] = "Melhore a picareta", ["Upgrade your Pickaxe to tier 2."] = "Melhore sua picareta para o nível 2.", ["Earn Your First Thousand"] = "Ganhe seus primeiros mil", ["Earn $1,000 from selling ore."] = "Ganhe $1.000 vendendo minério.", ["Cargo Runner"] = "Transportador", ["Complete five full cart sales."] = "Complete cinco vendas de carrinhos cheios.", ["Heavy Cargo"] = "Carga pesada", ["Deliver three carts filled to at least 70%."] = "Entregue três carrinhos com pelo menos 70% de carga.", ["Geode Collector"] = "Colecionador de geodos", ["Open three geodes."] = "Abra três geodos.", ["Crystal Collection"] = "Coleção de cristais", ["Collect ten crystal rewards."] = "Consiga dez recompensas de cristal.", ["Rare Find"] = "Descoberta rara", ["Discover a Rare or better crystal."] = "Descubra um cristal Raro ou melhor.", ["Passive Fortune"] = "Fortuna passiva", ["Collect $10,000 from your income safe."] = "Colete $10.000 do seu cofre de renda.", ["Upgrade Path"] = "Caminho das melhorias", ["Buy three upgrades."] = "Compre três melhorias.", ["Balanced Growth"] = "Crescimento equilibrado", ["Upgrade Mine, Cart, and Pickaxe at least once."] = "Melhore a mina, o carrinho e a picareta pelo menos uma vez.", ["Ready to Fight"] = "Pronto para lutar", ["Hit other players or their carts ten times."] = "Acerte jogadores ou carrinhos dez vezes.", ["Ore Thief"] = "Ladrão de minério", ["Knock out or steal ten enemy ores."] = "Derrube ou roube dez minérios inimigos.", ["Damage Dealer"] = "Causador de dano", ["Deal 500 damage to other players."] = "Cause 500 de dano a outros jogadores.", ["Safe Delivery"] = "Entrega segura", ["Deliver and sell three full carts."] = "Entregue e venda três carrinhos cheios.", ["Combo Master"] = "Mestre do combo", ["Sell five carts at x4 combo."] = "Venda cinco carrinhos com combo x4.", ["Tier Master"] = "Mestre dos níveis", ["Reach the maximum Mine tier."] = "Alcance o nível máximo da mina.", ["Full Upgrade"] = "Melhoria completa", ["Reach the maximum tier in all three branches."] = "Alcance o nível máximo nos três ramos.", ["Geode Expert"] = "Especialista em geodos", ["Open fifty geodes."] = "Abra cinquenta geodos.", ["Crystal Hoarder"] = "Acumulador de cristais", ["Collect 100 crystal rewards."] = "Consiga 100 recompensas de cristal.", ["Master Miner"] = "Minerador mestre", ["Sell 500 pieces of ore."] = "Venda 500 minérios.", ["The Big Goal"] = "O grande objetivo", ["Reach and complete your first rebirth."] = "Alcance e conclua seu primeiro renascimento.",
	},
}

function Localization.Normalize(localeId)
	local locale = string.lower(tostring(localeId or "en")):gsub("_", "-")
	if locale:sub(1, 2) == "ru" then return "ru" end
	if locale:sub(1, 2) == "es" then return "es" end
	if locale:sub(1, 2) == "pt" then return "pt-br" end
	if locale:sub(1, 2) == "ar" then return "ar" end
	if locale:sub(1, 2) == "ja" then return "ja" end
	return "en"
end

local function format(text, args)
	if typeof(text) ~= "string" then return text end
	if not args then return text end
	return (text:gsub("{([%w_]+)}", function(key)
		local value = args[key]
		return value == nil and ("{" .. key .. "}") or tostring(value)
	end))
end

function Localization.Translate(localeId, source, args)
	if typeof(source) ~= "string" or source == "" then return source end
	local locale = Localization.Normalize(localeId)
	local dictionary = translations[locale]
	local translated = dictionary and dictionary[source]
	if not translated then
		local questDictionary = questTranslations[locale]
		translated = questDictionary and questDictionary[source]
	end
	if not translated and source:find("\n", 1, true) then
		local lines = {}
		for line in source:gmatch("[^\n]+") do table.insert(lines, Localization.Translate(locale, line)) end
		translated = table.concat(lines, "\n")
	end
	if not translated then
		local combo = source:match("^COMBO%s+(.+)$")
		if combo and dictionary then translated = format(dictionary["COMBO {value}"], { value = combo }) end
	end
	if not translated then
		local seconds = source:match("^Shield %+(%d+)s$")
		if seconds and dictionary then translated = format(dictionary["Shield +{seconds}s"], { seconds = seconds }) end
	end
	if not translated then
		local tier = source:match("^Need PRESTIGE %(cap tier (%d+)%)$")
		if tier and dictionary then translated = format(dictionary["Need REBIRTH (cap tier {tier})"], { tier = tier }) end
	end
	if not translated then
		local id = source:match("^User (%d+)$")
		if id and dictionary then translated = format(dictionary["User {id}"], { id = id }) end
	end
	return format(translated or source, args)
end

function Localization.Bind(root, localeId)
	local locale = Localization.Normalize(localeId)
	local bound = setmetatable({}, { __mode = "k" })
	local function bind(instance)
		if bound[instance] then return end
		local textProperty
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then textProperty = "Text"
		elseif instance:IsA("TextBox") then textProperty = "PlaceholderText" end
		if not textProperty then return end
		bound[instance] = true
		if locale == "ar" or locale == "ja" then
			instance.Font = Enum.Font.GothamBold
		end
		local updating = false
		local function refresh()
			if updating then return end
			local current = instance[textProperty]
			local translated = Localization.Translate(localeId, current)
			if translated ~= current then
				updating = true
				instance[textProperty] = translated
				updating = false
			end
		end
		refresh()
		instance:GetPropertyChangedSignal(textProperty):Connect(refresh)
	end
	bind(root)
	for _, descendant in root:GetDescendants() do bind(descendant) end
	root.DescendantAdded:Connect(bind)
end

return Localization
