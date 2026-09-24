local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

-- Сессионные таблицы наград за время игры (см. ClaimPlaytimeReward).
-- Объявлены здесь, потому что PlayerRemoving чистит их значительно выше
-- по файлу, чем определены сами функции.
local sessionStart = {}
local playtimeClaimed = {}
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local QuestService = {}
local Services
local remote
local queuedStates = {}
local lastProgressSound = {}

local function utcDate(timestamp)
	return os.date("!%Y-%m-%d", timestamp or os.time())
end

--------------------------------------------------------------------------------
-- КВЕСТЫ, КОТОРЫЕ НЕЛЬЗЯ ПРОЙТИ В ОДИНОЧКУ
--
-- ПРОБЛЕМА, КОТОРУЮ ЭТО ЧИНИТ. Стартовая цепочка держит активным ровно ОДИН
-- квест — первый невыполненный по порядку (см. Config.Quests.Starter). А в
-- этой цепочке есть квесты, для которых физически нужен второй игрок:
-- "Share the Wealth" (передать кристалл другому), "Ready to Fight" (ударить
-- киркой другого), "Ore Thief", "Damage Dealer". На пустом сервере игрок
-- упирался в такой квест и прогресс вставал НАСМЕРТЬ: следующий квест не
-- выдавался, потому что предыдущий не закрыт, а закрыть его было некем.
-- Учитывая, что участков всего Config.World.PlotCount и на старте проекта
-- большинство серверов соло — это происходило с большинством новых игроков.
--
-- РЕШЕНИЕ. У квеста может стоять RequiresPlayers = N. Пока на сервере меньше
-- N человек, такой квест ПРОПУСКАЕТСЯ при выборе активного — игрок получает
-- следующий доступный и спокойно идёт дальше. Прогресс при этом НЕ теряется
-- и квест НЕ отмечается выполненным: как только кто-то зайдёт, он снова
-- станет в очередь и выдастся (см. вызовы RefreshAvailability из Main).
--
-- Осознанное ограничение: на ежедневные квесты гейт НЕ распространяется.
-- Там их всегда три (Simple/Medium/PvP), они генерируются на сутки вперёд
-- детерминированным сидом, и невыполнимый PvP-квест ничего не блокирует —
-- две другие ячейки работают. Менять суточный набор от того, сколько людей
-- сейчас на сервере, значило бы перевыдавать игроку задания в течение дня.
--------------------------------------------------------------------------------
local function questBlockedByPlayerCount(definition)
	local required = tonumber(definition and definition.RequiresPlayers)
	if not required or required <= 1 then return false end
	return #Players:GetPlayers() < required
end

local function utcWeek(timestamp)
	timestamp = timestamp or os.time()
	local weekday = tonumber(os.date("!%w", timestamp)) -- Sunday = 0
	local mondayOffset = (weekday + 6) % 7
	local thursday = timestamp + (3 - mondayOffset) * 86400
	local weekYear = os.date("!%Y", thursday)
	local weekNumber = (tonumber(os.date("!%W", thursday)) or 0) + 1
	return ("%s-W%02d"):format(weekYear, weekNumber)
end

local function playerRoot(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function rewardAmount(player, reward)
	if typeof(reward) == "number" then return math.max(0, math.floor(reward)) end
	if typeof(reward) ~= "table" then return 0 end
	local mineTier = Services.DataService:GetBranchTier(player, "Mine")
	local cartTier = Services.DataService:GetBranchTier(player, "Cart")
	local rebirthMultiplier = Services.DataService:GetCrystalMultiplier(player)
	-- v3: «рейс» = реальный средний доход полной тележки (Config.CartValue),
	-- а не цена самой редкой руды тира × вместимость (завышало в разы).
	local tripValue = Config.CartValue(mineTier, cartTier) * rebirthMultiplier
	local amount = tripValue * (reward.TripValue or 1)
	return math.max(0, math.floor(math.max(amount, reward.MinMoney or 0)))
end

-- v16: предметы награды (Reward.Items) — динамит/зелья, сундуки, жеоды,
-- тотемы, очки престижа. Выдаются ПОСЛЕ денег и сохранения.
local function itemLabel(item)
	if item.Kind == "Gear" then
		local dynamite = Config.Dynamite.Types[item.Key]
		local potion = Config.Potions and Config.Potions.Types[item.Key]
		local name = (dynamite and dynamite.DisplayName) or (potion and potion.DisplayName) or tostring(item.Key)
		local icon = (dynamite and dynamite.Icon) or (potion and potion.Icon) or "🧨"
		return icon, ((item.Count or 1) > 1 and ("%d× %s"):format(item.Count, name) or name)
	elseif item.Kind == "Chest" then
		local info = Config.Chests.Types[item.Rarity]
		return "🎁", info and info.DisplayName or (tostring(item.Rarity) .. " Chest")
	elseif item.Kind == "Geode" then
		return "🪨", "Geode"
	elseif item.Kind == "Placeable" then
		local ok, catalog = pcall(require, ReplicatedStorage.Shared.PlaceableCatalog)
		local info = ok and catalog.Info(item.Id)
		return info and info.Icon or "🗿", info and info.DisplayName or tostring(item.Id)
	elseif item.Kind == "PrestigePoints" then
		return "⭐", ("+%d Prestige Point%s"):format(item.Count or 1, (item.Count or 1) == 1 and "" or "s")
	end
	return "🎁", tostring(item.Kind)
end

local function rewardChips(player, reward)
	local chips = {}
	local money = rewardAmount(player, reward)
	if money > 0 then table.insert(chips, { Icon = "💰", Text = "$" .. NumberFormat.abbreviate(money) }) end
	for _, item in typeof(reward) == "table" and reward.Items or {} do
		local icon, text = itemLabel(item)
		table.insert(chips, { Icon = icon, Text = text })
	end
	return chips
end

local function grantItems(player, reward)
	if typeof(reward) ~= "table" or typeof(reward.Items) ~= "table" then return end
	local tiers = Services.DataService:GetTiers(player)
	for _, item in reward.Items do
		pcall(function()
			if item.Kind == "Gear" and Services.GearService then
				Services.GearService:AddGear(player, item.Key, item.Count or 1)
			elseif item.Kind == "Chest" and Services.GearService then
				Services.GearService:GrantChest(player, item.Rarity, item.Count or 1, true)
			elseif item.Kind == "Geode" and Services.GeodeService then
				local index = math.clamp(Config.GeodeTypeIndexForCave(tiers.Mine) + (item.Offset or 0), 1, #Config.Geodes.Order)
				Services.GeodeService:AddGeodeDirectly(player, Config.Geodes.Order[index])
			elseif item.Kind == "Placeable" and Services.BaseDecorService then
				Services.BaseDecorService:GrantItem(player, item.Id, item.Count or 1)
			elseif item.Kind == "PrestigePoints" and Services.PrestigeService then
				Services.PrestigeService:AddPoints(player, item.Count or 1)
			end
		end)
	end
	if Services.NotifyService and Services.NotifyService.LootFeed then
		local feed = {}
		for _, item in reward.Items do
			local icon, text = itemLabel(item)
			table.insert(feed, { Icon = icon, Text = text, Rarity = item.Rarity or "Rare" })
		end
		if #feed > 0 then pcall(Services.NotifyService.LootFeed, Services.NotifyService, player, feed) end
	end
end

-- v16: недельные сундуки за очки дейликов (Config.Quests.WeeklyChests).
local function grantWeeklyChests(player, data)
	data.WeeklyChestsClaimed = typeof(data.WeeklyChestsClaimed) == "table" and data.WeeklyChestsClaimed or {}
	for index, milestone in Config.Quests.WeeklyChests or {} do
		local key = tostring(index)
		if not data.WeeklyChestsClaimed[key] and (data.WeeklyQuestPoints or 0) >= milestone.Points then
			data.WeeklyChestsClaimed[key] = true
			if Services.GearService then
				pcall(Services.GearService.GrantChest, Services.GearService, player, milestone.Rarity, 1, true)
			end
			if Services.NotifyService then
				local info = Config.Chests.Types[milestone.Rarity]
				Services.NotifyService:Show(player, ("WEEKLY REWARD: %s!"):format(info and info.DisplayName or milestone.Rarity), { Icon = "Reward", Duration = 4 })
			end
		end
	end
end

local function skipObsoleteStarterQuests(player, data)
	local tiers = Services.DataService:GetTiers(player)
	local maxTier = math.max(tiers.Mine or 1, tiers.Cart or 1, tiers.Pickaxe or 1)
	local changed = false
	for _, definition in Config.Quests.Starter do
		if definition.SkipWhenMaxTierAtLeast and maxTier >= definition.SkipWhenMaxTierAtLeast then
			local progress = data.StarterQuestProgress[definition.Id]
			if typeof(progress) ~= "table" then
				progress = { Progress = 0, Rewarded = false }
				data.StarterQuestProgress[definition.Id] = progress
			end
			if progress.Rewarded ~= true then
				progress.Progress = definition.Target
				progress.Rewarded = true
				progress.Skipped = true
				changed = true
			end
		end
	end
	return changed
end

local function nextDailyReward(data, now)
	now = now or os.time()
	local streak
	if data.LastDailyClaimDate == utcDate(now) then
		streak = math.max(1, data.DailyRewardStreak)
	elseif data.LastDailyClaimDate == utcDate(now - 86400) then
		streak = data.DailyRewardStreak + 1
	elseif data.DailyRewardStreak > 0 then
		streak = math.max(1, data.DailyRewardStreak - 1) -- missed days only step back once
	else
		streak = 1
	end
	return (streak - 1) % #Config.Quests.DailyRewards + 1, streak
end

local function findDailyTemplate(id)
	for _, pool in Config.Quests.Daily do
		for _, template in pool do
			if template.Id == id then return template end
		end
	end
	return nil
end

function QuestService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("QuestRequest") or Instance.new("RemoteEvent")
	remote.Name = "QuestRequest"
	remote.Parent = ReplicatedStorage.Shared
	-- Дебаунс — единственный ремоут в проекте, у которого его не было
	-- (у GeodeService/SkinService/UpgradeService/RebirthService такой же,
	-- 0.15с). Каждый "RequestState" собирает и сериализует всё состояние
	-- квестов, так что без ограничения это дешёвый способ нагрузить сервер.
	--
	-- ДЕБАУНС СЧИТАЕТСЯ НА ПАРУ (игрок + ДЕЙСТВИЕ), а не на ремоут целиком.
	-- Это принципиально: на QuestRequest сидят ДВА разных клиентских
	-- скрипта — QuestUI.client.lua и DailyRewardUI.client.lua, — и оба шлют
	-- "RequestState" при старте. С общим дебаунсом один из двух стартовых
	-- запросов молча съедался, а окно ежедневной награды открывается на
	-- входе именно по ответу на свой RequestState (см. openedOnJoin в
	-- DailyRewardUI) — то есть оно просто не открывалось. По той же причине
	-- нельзя было бы забрать награду сразу после обновления состояния.
	local lastRequest = {} -- [userId] = { [action] = os.clock() }
	remote.OnServerEvent:Connect(function(player, action, value)
		if typeof(action) ~= "string" then return end
		local now = os.clock()
		local byAction = lastRequest[player.UserId]
		if not byAction then
			byAction = {}
			lastRequest[player.UserId] = byAction
		end
		local last = byAction[action]
		if last and now - last < 0.15 then
			return
		end
		byAction[action] = now

		if action == "RequestState" then
			self:SendState(player)
		elseif action == "ClaimDailyReward" then
			self:ClaimDailyReward(player)
		elseif action == "ClaimPlaytimeReward" then
			self:ClaimPlaytimeReward(player, value)
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player.UserId] = nil
		-- Сессия закончилась — таймер и отметки уходят вместе с ней.
		sessionStart[player.UserId] = nil
		playtimeClaimed[player.UserId] = nil
	end)
end

function QuestService:_ensureDaily(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	local now = os.time()
	local today = utcDate(now)
	local week = utcWeek(now)
	data.WeeklyQuestPoints = math.max(0, math.floor(tonumber(data.WeeklyQuestPoints) or 0))
	data.DailyRewardStreak = math.max(0, math.floor(tonumber(data.DailyRewardStreak) or 0))
	data.DailyMiningBoostEndsAt = math.max(0, math.floor(tonumber(data.DailyMiningBoostEndsAt) or 0))
	if data.WeeklyQuestWeek ~= week then
		data.WeeklyQuestWeek = week
		data.WeeklyQuestPoints = 0
		data.WeeklyChestsClaimed = {}
	end
	local dailyValid = data.DailyQuestDate == today and #data.DailyQuests == 3
	if dailyValid then
		for slot, quest in data.DailyQuests do
			local template = typeof(quest) == "table" and findDailyTemplate(quest.Id)
			if not template then dailyValid = false; break end
			quest.Slot = slot
			quest.Metric = template.Metric
			quest.Title = template.Title
			quest.Description = template.Description
			quest.Short = template.Short
			quest.Target = template.Target
			quest.Reward = template.Reward
			quest.WeeklyPoints = template.WeeklyPoints
			quest.Progress = math.clamp(tonumber(quest.Progress) or 0, 0, template.Target)
			quest.Claimed = quest.Claimed == true
		end
	end
	if not dailyValid then
		data.DailyQuestDate = today
		data.DailyRewardClaimed = data.LastDailyClaimDate == today
		data.DailyRewardEligible = true
		data.DailyQuests = {}
		local seed = player.UserId + math.floor(now / 86400) * 7919
		local random = Random.new(seed)
		for slot, category in { "Simple", "Medium", "PvP" } do
			local pool = Config.Quests.Daily[category]
			local template = pool[random:NextInteger(1, #pool)]
			data.DailyQuests[slot] = {
				Slot = slot,
				Id = template.Id,
				Metric = template.Metric,
				Title = template.Title,
				Description = template.Description,
				Short = template.Short,
				Target = template.Target,
				Reward = template.Reward,
				WeeklyPoints = template.WeeklyPoints,
				Progress = 0,
				Claimed = false,
			}
		end
	end
	data.DailyRewardEligible = not data.DailyRewardClaimed
	return data
end

--------------------------------------------------------------------------------
-- Вызывается из Main при заходе/выходе ЛЮБОГО игрока: набор доступных
-- квестов зависит от числа людей на сервере (см. questBlockedByPlayerCount),
-- поэтому смена состава обязана перерисовать панель квестов у всех. Без
-- этого новый квест появлялся бы только при следующем случайном обновлении
-- состояния, и связь "кто-то зашёл → открылось задание" терялась.
--------------------------------------------------------------------------------
function QuestService:RefreshAvailability()
	for _, player in Players:GetPlayers() do
		pcall(function() self:SendState(player) end)
	end
end

function QuestService:SetupPlayer(player)
	local data = self:_ensureDaily(player)
	if not data then return end
	skipObsoleteStarterQuests(player, data)
	player:SetAttribute("DailyMiningBoostEndsAt", data.DailyMiningBoostEndsAt)
	player:SetAttribute("DailyCartColorUnlocked", data.DailyCartColorUnlocked == true)
	if not data.DailyRewardClaimed then Sfx.play("DailyRewardReady", playerRoot(player)) end
	self:_refreshDerived(player)
	self:SendState(player)
	task.delay(5, function()
		if player.Parent then self:_maybeShowQuestActivationTip(player, data) end
	end)

	-- ИГРОВОЕ ВРЕМЯ ЗА СЕССИЮ (метрика "PlayTime", в секундах) — квесты
	-- "поиграй 5/10/15 минут" (см. Config.Quests, Id Play5Minutes и т.п.)
	-- требуют живого тика, а не единичного события вроде прыжка/смерти,
	-- поэтому отдельный цикл. derived=true, как у тиров: репортим
	-- АБСОЛЮТНОЕ "сколько уже прошло", а не суммируем дельты — тогда
	-- повторный SetupPlayer (переподключение и т.п.) не может задвоить счёт.
	-- Цикл сам останавливается, когда игрок выходит (player.Parent).
	task.spawn(function()
		local sessionStart = os.clock()
		while player.Parent do
			task.wait(10)
			if not player.Parent then break end
			self:RecordMetric(player, "PlayTime", math.floor(os.clock() - sessionStart), true)
		end
	end)
	-- Подсказки про gift/boulders (см. Config.Tips) — если игрок уже
	-- проходил основной гайд РАНЬШЕ (в прошлой сессии), это подхватит
	-- недостающие/недопоказанные подсказки и сейчас. Если гайд ещё не
	-- пройден или уже пройден в ЭТУ сессию — функция сама разберётся
	-- (см. её собственные guard'ы) или её позовут заново из
	-- DataService:CompleteTutorialRequest в момент завершения.
	self:_scheduleTips(player)

	-- "Абсурдные" квесты (см. Config.Quests.Daily) — прыжки и смерти,
	-- реально засчитываются, а не бутафория. Humanoid пересоздаётся на
	-- каждый респавн, поэтому подключаемся заново на каждый CharacterAdded.
	-- (ЧАТ намеренно не трогаем: Player.Chatted на сервере — известный повод
	-- для модерации Roblox "Misusing Roblox Services" в 2026 году, а
	-- рекомендуемая замена, TextChatService.MessageReceived на сервере,
	-- сама по себе ненадёжно срабатывает по массовым жалобам на форуме
	-- разработчиков — рисковать не стоит.)
	local function hookCharacterQuestEvents(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.Jumping:Connect(function(active)
			if active then self:RecordMetric(player, "Jumps", 1) end
		end)
		humanoid.Died:Connect(function()
			self:RecordMetric(player, "Deaths", 1)
		end)
	end
	if player.Character then hookCharacterQuestEvents(player.Character) end
	player.CharacterAdded:Connect(hookCharacterQuestEvents)
end

function QuestService:_refreshDerived(player)
	local data = Services.DataService:GetGeodeData(player)
	if data and data.TutorialVersion >= Config.Tutorial.Version then
		self:RecordMetric(player, "TutorialComplete", 1, true)
	end
	local tiers = Services.DataService:GetTiers(player)
	self:RecordMetric(player, "MineTier", tiers.Mine, true)
	self:RecordMetric(player, "CartTier", tiers.Cart, true)
	self:RecordMetric(player, "PickaxeTier", tiers.Pickaxe, true)
	-- v16: у каждой ветки свой максимум (пещера 15, тележка/кирка 9).
	-- Раньше все три сравнивались с 15 — квест FULL UPGRADE не выполнялся никогда.
	local ds = Services.DataService
	if tiers.Mine >= ds:GetBranchMaxTier("Mine") and tiers.Cart >= ds:GetBranchMaxTier("Cart") and tiers.Pickaxe >= ds:GetBranchMaxTier("Pickaxe") then
		self:RecordMetric(player, "FullUpgrade", 1, true)
	end
	if tiers.Mine > 1 and tiers.Cart > 1 and tiers.Pickaxe > 1 then
		self:RecordMetric(player, "BalancedUpgrades", 1, true)
	end
	if Services.DataService:GetRebirths(player) > 0 then
		self:RecordMetric(player, "Rebirths", Services.DataService:GetRebirths(player), true)
	end	if Services.IslandService and Services.IslandService.CountOwned then
		local owned = Services.IslandService:CountOwned(player)
		if owned > 0 then self:RecordMetric(player, "IslandsOwned", owned, true) end
	end
end

function QuestService:_queueState(player)
	if queuedStates[player] then return end
	queuedStates[player] = true
	task.delay(0.2, function()
		queuedStates[player] = nil
		if player.Parent then self:SendState(player) end
	end)
end

-- Ищет ТЕКУЩИЙ активный стартовый квест (первый несданный, не
-- заблокированный по числу игроков — та же логика, что и в
-- GetState/RecordMetric) и, если у него задан OnActivateTip и подсказка
-- для него ещё не показывалась (data.ShownQuestTips), присылает тост
-- ОДИН РАЗ. В отличие от Config.Tips (те — по фиксированному таймеру
-- после тутора), это привязано к РЕАЛЬНОМУ моменту, когда квест
-- становится актуальным — если игрок долго возится с предыдущим шагом,
-- подсказка про валуны/подарки не всплывёт раньше времени и не
-- потеряется, если он, наоборот, прошёл всё быстро.
function QuestService:_maybeShowQuestActivationTip(player, data)
	if not data then return end
	data.ShownQuestTips = data.ShownQuestTips or {}
	for _, definition in Config.Quests.Starter do
		local progress = data.StarterQuestProgress[definition.Id]
		local rewarded = typeof(progress) == "table" and progress.Rewarded == true
		if not rewarded and not questBlockedByPlayerCount(definition) then
			if definition.OnActivateTip and not data.ShownQuestTips[definition.Id] then
				data.ShownQuestTips[definition.Id] = true
				if Services.NotifyService then
					Services.NotifyService:Show(player, definition.OnActivateTip, { Icon = "Quest", Duration = 8 })
				end
			end
			return -- дошли до первого активного — дальше по списку смотреть не нужно
		end
	end
end

function QuestService:RecordMetric(player, metric, amount, derived)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	-- v16: удачные моменты для мягких предложений (группа/избранное).
	if Services.SocialOfferService then
		pcall(Services.SocialOfferService.OnMetric, Services.SocialOfferService, player, metric)
	end
	local data = self:_ensureDaily(player)
	if not data then return end
	local changed = skipObsoleteStarterQuests(player, data)
	local starterCompletedNow = false
	local completedAny = false
	local dailyClaims = {}
	local activeDefinition
	local activeProgress
	for _, definition in Config.Quests.Starter do
		local progress = data.StarterQuestProgress[definition.Id]
		if typeof(progress) ~= "table" then
			progress = { Progress = 0, Rewarded = false }
			data.StarterQuestProgress[definition.Id] = progress
		end
		progress.Progress = math.clamp(tonumber(progress.Progress) or 0, 0, definition.Target)
		progress.Rewarded = progress.Rewarded == true
		if not progress.Rewarded and not activeDefinition and not questBlockedByPlayerCount(definition) then
			activeDefinition = definition
			activeProgress = progress
		end
	end
	if activeDefinition and activeDefinition.Metric == metric then
		local old = activeProgress.Progress
		activeProgress.Progress = math.min(activeDefinition.Target, derived and math.max(old, amount) or old + amount)
		-- ИСПРАВЛЕНИЕ ПОТЕРИ ОБНОВЛЕНИЙ UI: здесь стояло `changed = ...`,
		-- то есть присваивание ЗАТИРАЛО значение, полученное выше от
		-- skipObsoleteStarterQuests. Если та функция что-то поменяла
		-- (например, пропустила ставший неактуальным квест), а этот
		-- конкретный вызов прогресс не сдвинул, changed становился false —
		-- и _queueState в конце не вызывался. Игрок видел устаревший
		-- список квестов до следующего случайного обновления. Нужен `or`:
		-- "изменилось хоть что-то", а не "изменилось последнее".
		changed = changed or activeProgress.Progress ~= old
		if activeProgress.Progress >= activeDefinition.Target then
			activeProgress.Rewarded = true
			starterCompletedNow = true
			local reward = rewardAmount(player, activeDefinition.Reward)
			if not activeDefinition.ExternallyRewarded and reward > 0 then
				-- Раньше здесь был голый AddMoney без сохранения: ежедневки ниже
				-- уже уходили через SaveProfile с полным откатом, а стартовые
				-- квесты — нет. Награда за них бывает в разы крупнее (TripValue
				-- до x30 от полного рейса), и терять её на краше сервера до
				-- автосейва (до 120 сек) нельзя. Откатываем ВСЁ разом: и деньги,
				-- и отметку "квест сдан", иначе игрок потеряет и то и другое.
				local previousLock = player:GetAttribute("EconomyTransactionLocked") == true
				player:SetAttribute("EconomyTransactionLocked", true)
				Services.DataService:AddMoney(player, reward)
				if not Services.DataService:SaveProfile(player) then
					Services.DataService:AddMoney(player, -reward)
					activeProgress.Rewarded = false
					activeProgress.Progress = old
					starterCompletedNow = false
					changed = false
					if Services.NotifyService then
						Services.NotifyService:Show(player, "Quest reward save failed. Try again in a moment.", { Icon = "Error" })
					end
				end
				if not previousLock then player:SetAttribute("EconomyTransactionLocked", false) end
			end
			if starterCompletedNow then
				completedAny = true
				grantItems(player, activeDefinition.Reward)
				Sfx.play("QuestComplete", playerRoot(player))
				if Services.NotifyService then Services.NotifyService:Show(player, activeDefinition.Title .. " COMPLETE", { Icon = "Quest" }) end
				-- Квест только что сдан — следующий по списку стал активным
				-- ПРЯМО СЕЙЧАС. Если у него есть OnActivateTip — самое
				-- время его показать (см. _maybeShowQuestActivationTip).
				self:_maybeShowQuestActivationTip(player, data)
			end
		end
	end

	for _, quest in data.DailyQuests do
		if quest.Metric == metric and not quest.Claimed then
			local old = quest.Progress
			quest.Progress = math.min(quest.Target, old + amount)
			changed = changed or quest.Progress ~= old
			if old < quest.Target and quest.Progress >= quest.Target then
				local reward = rewardAmount(player, quest.Reward)
				table.insert(dailyClaims, { Quest = quest, OldProgress = old, Reward = reward, WeeklyPoints = quest.WeeklyPoints })
				quest.Claimed = true
				data.WeeklyQuestPoints += quest.WeeklyPoints
				Services.DataService:AddMoney(player, reward)
				completedAny = true
			end
		end
	end
	if #dailyClaims > 0 then
		local previousLock = player:GetAttribute("EconomyTransactionLocked") == true
		player:SetAttribute("EconomyTransactionLocked", true)
		local saved = Services.DataService:SaveProfile(player)
		if not saved then
			for _, claim in dailyClaims do
				claim.Quest.Claimed = false
				claim.Quest.Progress = claim.OldProgress
				data.WeeklyQuestPoints = math.max(0, data.WeeklyQuestPoints - claim.WeeklyPoints)
				Services.DataService:AddMoney(player, -claim.Reward)
			end
			completedAny = starterCompletedNow
		else
			Sfx.play("QuestComplete", playerRoot(player))
			for _, claim in dailyClaims do
				grantItems(player, claim.Quest.Reward)
				if Services.NotifyService then
					Services.NotifyService:Show(player, claim.Quest.Title .. " COMPLETE", { Icon = "Quest" })
				end
			end
			grantWeeklyChests(player, data)
		end
		if not previousLock then player:SetAttribute("EconomyTransactionLocked", false) end
	end
	if changed then
		self:_queueState(player)
		local now = os.clock()
		if not completedAny and now - (lastProgressSound[player] or 0) >= 0.6 then
			lastProgressSound[player] = now
			Sfx.play("QuestProgress", playerRoot(player))
		end
	end
	if starterCompletedNow then task.defer(function() if player.Parent then self:_refreshDerived(player) end end) end
end

function QuestService:GetState(player)
	local data = self:_ensureDaily(player)
	if not data then return nil end
	skipObsoleteStarterQuests(player, data)
	local starter = {}
	local activeFound = false
	for _, definition in Config.Quests.Starter do
		local progress = data.StarterQuestProgress[definition.Id]
		if typeof(progress) ~= "table" then progress = { Progress = 0, Rewarded = false }; data.StarterQuestProgress[definition.Id] = progress end
		progress.Progress = math.clamp(tonumber(progress.Progress) or 0, 0, definition.Target)
		progress.Rewarded = progress.Rewarded == true
		local completed = progress.Rewarded
		-- Тот же гейт, что и в RecordMetric выше. Оба места обязаны решать
		-- ОДИНАКОВО: если бы UI показывал заблокированный квест активным, а
		-- сервер засчитывал прогресс уже в следующий, игрок видел бы одно
		-- задание, а выполнял другое.
		local active = not completed and not activeFound and not questBlockedByPlayerCount(definition)
		if active then activeFound = true end
		if (completed and progress.Skipped ~= true) or active then
			local description = definition.Description
			if definition.Id == "BigGoal" then
				description = ("Reach $%s and prestige"):format(
					NumberFormat.abbreviate(Services.DataService:GetRebirthCost(player))
				)
			end
			table.insert(starter, {
				-- Short — та же цель в 2-4 словах. Нужна закреплённой
				-- плашке: она узкая, а полные Description написаны
				-- предложениями ("Break a glowing boulder near the bank
				-- and collect the ore") и там обрезались многоточием на
				-- середине. В самом списке квестов по-прежнему показывается
				-- полный текст — места там хватает.
				Id = definition.Id, Title = definition.Title, Description = description,
				Short = definition.Short, Metric = definition.Metric, Nav = definition.Nav, Why = definition.Why,
				Progress = progress.Progress, Target = definition.Target, Completed = completed,
				Reward = rewardAmount(player, definition.Reward) > 0 and ("$" .. NumberFormat.abbreviate(rewardAmount(player, definition.Reward))) or "LONG-TERM GOAL", Active = active,
				Chips = rewardChips(player, definition.Reward),
			})
		end
	end
	local daily = {}
	local dailyUnlocked = data.TutorialVersion >= Config.Tutorial.Version
	for _, quest in data.DailyQuests do
		table.insert(daily, {
			Slot = quest.Slot, Id = quest.Id, Title = quest.Title, Description = quest.Description, Short = quest.Short, Progress = quest.Progress,
			Target = quest.Target, Claimed = quest.Claimed, Reward = "$" .. NumberFormat.abbreviate(rewardAmount(player, quest.Reward)),
			WeeklyPoints = quest.WeeklyPoints, Metric = quest.Metric, Chips = rewardChips(player, quest.Reward),
			Blocked = questBlockedByPlayerCount(findDailyTemplate(quest.Id)) or nil,
		})
	end
	local day = nextDailyReward(data, os.time())
	local reward = Config.Quests.DailyRewards[day]
	-- Та же подмена, что в ClaimDailyReward — иначе окно обещало бы "GOLD
	-- skin" игроку, которому на повторном круге стрика реально придут деньги.
	local rewardText = reward.Text
	if reward.Kind == "Skin" and Services.SkinService:OwnsSkin(player, reward.SkinId) then
		local fallbackAmount = 0
		for _, candidate in Config.Quests.DailyRewards do
			if candidate.Kind == "Money" and candidate.Amount > fallbackAmount then
				fallbackAmount = candidate.Amount
			end
		end
		rewardText = "$" .. NumberFormat.abbreviate(fallbackAmount)
	end
	return {
		Playtime = self:GetPlaytimeState(player),
		Starter = starter,
		Daily = daily,
		DailyUnlocked = dailyUnlocked,
		WeeklyPoints = data.WeeklyQuestPoints,
		-- v16: недельные сундуки и таймеры сброса.
		Weekly = (function()
			local chests = {}
			for index, milestone in Config.Quests.WeeklyChests or {} do
				table.insert(chests, {
					Points = milestone.Points, Rarity = milestone.Rarity,
					Claimed = typeof(data.WeeklyChestsClaimed) == "table" and data.WeeklyChestsClaimed[tostring(index)] == true,
				})
			end
			return chests
		end)(),
		DailyResetsAt = (math.floor(os.time() / 86400) + 1) * 86400,
		DailyReward = {
			Eligible = data.DailyRewardEligible,
			Claimed = data.DailyRewardClaimed,
			Streak = data.DailyRewardStreak,
			Day = day,
			RewardText = rewardText,
		},
	}
end

--------------------------------------------------------------------------------
-- НАГРАДЫ ЗА ВРЕМЯ В ИГРЕ (см. Config.Quests.PlaytimeRewards)
--
-- Отсчёт от входа на сервер, сброс при выходе. Хранить в профиле нечего:
-- сессия и так заканчивается вместе с отметками, а перезаход обнуляет
-- таймер вместе с ними — накрутить ступени переподключением нельзя.
--
-- ВРЕМЯ СЧИТАЕТ СЕРВЕР. Клиент присылает только номер ступени, которую
-- хочет забрать; сколько игрок наиграл, решаем здесь — иначе ступени
-- забирались бы сразу все.
--------------------------------------------------------------------------------

function QuestService:GetPlaytimeSeconds(player)
	local start = sessionStart[player.UserId]
	if not start then
		start = os.clock()
		sessionStart[player.UserId] = start
	end
	return os.clock() - start
end

function QuestService:GetPlaytimeState(player)
	local claimed = playtimeClaimed[player.UserId] or {}
	local elapsed = self:GetPlaytimeSeconds(player)
	local entries = {}
	for index, reward in Config.Quests.PlaytimeRewards do
		table.insert(entries, {
			Index = index,
			Seconds = reward.Seconds,
			Text = reward.Text,
			Kind = reward.Kind,
			Claimed = claimed[index] == true,
			Ready = elapsed >= reward.Seconds and claimed[index] ~= true,
		})
	end
	return { Elapsed = math.floor(elapsed), Entries = entries }
end

function QuestService:ClaimPlaytimeReward(player, index)
	if typeof(index) ~= "number" then return end
	index = math.floor(index)
	local reward = Config.Quests.PlaytimeRewards[index]
	if not reward then return end
	if player:GetAttribute("EconomyTransactionLocked") == true then return end

	local claimed = playtimeClaimed[player.UserId]
	if not claimed then
		claimed = {}
		playtimeClaimed[player.UserId] = claimed
	end
	if claimed[index] then return end
	if self:GetPlaytimeSeconds(player) < reward.Seconds then return end

	local data = Services.DataService:GetGeodeData(player)
	if not data then return end

	-- Отмечаем ДО начисления: если начисление упадёт, повторная попытка
	-- не выдаст награду дважды. Потерянная награда лечится перезаходом,
	-- дублирующая — нет.
	claimed[index] = true

	local now = os.time()
	if reward.Kind == "Money" then
		Services.DataService:AddMoney(player, reward.Amount)
	elseif reward.Kind == "Buff" then
		-- Награда выдаёт НАСТОЯЩИЙ бафф через BuffService — тот же путь,
		-- которым баффы падают из жеод. Отдельной ветки "множитель добычи"
		-- больше нет: она давала прибавку к тому, что игрок и так делает,
		-- и на состав дропа не влияла вообще.
		local info = Config.Buffs[reward.Buff]
		if info and Services.BuffService then
			Services.BuffService:Grant(player, reward.Buff, info.Amount, reward.Duration, info.DisplayName)
		end
	end

	if Services.NotifyService then
		Services.NotifyService:Show(player, "Playtime reward claimed!", { Icon = "Success" })
	end
	self:SendState(player, "State")
end

function QuestService:SendState(player, command)
	if player.Parent then remote:FireClient(player, command or "State", self:GetState(player)) end
end

function QuestService:ClaimDailyReward(player)
	local data = self:_ensureDaily(player)
	if not data or data.DailyRewardClaimed or player:GetAttribute("EconomyTransactionLocked") == true then return end
	local now = os.time()
	local day, nextStreak = nextDailyReward(data, now)
	local reward = Config.Quests.DailyRewards[day]
	-- ПОВТОРНЫЙ КРУГ СТРИКА. Наград семь, а nextDailyReward зацикливает их
	-- через ((streak - 1) % #DailyRewards) + 1 — то есть на 14-й, 21-й день
	-- и далее снова выпадает седьмая, скин GOLD. GrantNpcSkin на уже
	-- открытом скине возвращает success, НИЧЕГО не выдав: игрок жал "CLAIM",
	-- терял день стрика и получал пустоту. Подменяем на денежный эквивалент
	-- предыдущей денежной ступени.
	if reward.Kind == "Skin" and Services.SkinService:OwnsSkin(player, reward.SkinId) then
		local fallbackAmount = 0
		for _, candidate in Config.Quests.DailyRewards do
			if candidate.Kind == "Money" and candidate.Amount > fallbackAmount then
				fallbackAmount = candidate.Amount
			end
		end
		reward = { Kind = "Money", Amount = fallbackAmount, Text = "$" .. NumberFormat.abbreviate(fallbackAmount) }
	end
	if reward.Kind == "Skin" then
		local granted, reason = Services.SkinService:GrantNpcSkin(player, reward.SkinId)
		if not granted then
			if Services.NotifyService then Services.NotifyService:Show(player, reason == "MissingAsset" and "This reward is not available yet." or "Skin reward could not be granted. Try again.", { Icon = "Error" }) end
			self:SendState(player, "Open")
			return
		end
	end
	local snapshot = {
		Streak = data.DailyRewardStreak,
		LastClaim = data.LastDailyClaimDate,
		Claimed = data.DailyRewardClaimed,
		BoostEndsAt = data.DailyMiningBoostEndsAt,
		BoostMultiplier = data.DailyMiningBoostMultiplier,
		CartColor = data.DailyCartColorUnlocked,
	}
	player:SetAttribute("EconomyTransactionLocked", true)
	if reward.Kind == "Money" then
		Services.DataService:AddMoney(player, reward.Amount)
	elseif reward.Kind == "Buff" then
		-- Ежедневные награды выдают баффы тем же путём, что и награды за
		-- время игры, — через BuffService. Ветка "множитель добычи"
		-- убрана: этот бафф ускорял то, что игрок и так делает, и на
		-- состав дропа не влиял вообще.
		local info = Config.Buffs[reward.Buff]
		if info and Services.BuffService then
			Services.BuffService:Grant(player, reward.Buff, info.Amount, reward.Duration, info.DisplayName)
		end
	end
	data.DailyRewardStreak = nextStreak
	data.LastDailyClaimDate = utcDate(now)
	data.DailyRewardClaimed = true
	if not Services.DataService:SaveProfile(player) then
		if reward.Kind == "Money" then Services.DataService:AddMoney(player, -reward.Amount) end
		data.DailyRewardStreak = snapshot.Streak
		data.LastDailyClaimDate = snapshot.LastClaim
		data.DailyRewardClaimed = snapshot.Claimed
		data.DailyMiningBoostEndsAt = snapshot.BoostEndsAt
		data.DailyMiningBoostMultiplier = snapshot.BoostMultiplier
		data.DailyCartColorUnlocked = snapshot.CartColor
		player:SetAttribute("DailyMiningBoostEndsAt", snapshot.BoostEndsAt)
		player:SetAttribute("EconomyTransactionLocked", false)
		if Services.NotifyService then Services.NotifyService:Show(player, "Daily reward save failed. Please try again.", { Icon = "Error" }) end
		self:SendState(player, "Open")
		return
	end
	player:SetAttribute("DailyCartColorUnlocked", data.DailyCartColorUnlocked == true)
	if reward.Kind == "CartColor" and Services.CartService then Services.CartService:ApplyDailyRewardColor(player) end
	player:SetAttribute("EconomyTransactionLocked", false)
	Sfx.play("DailyRewardClaim", playerRoot(player))

	--------------------------------------------------------------------------
	-- "СТРИК СГОРИТ ЧЕРЕЗ ...". Раньше стрик считался молча: игрок видел
	-- только текущий номер дня и не знал ни того, что серия вообще может
	-- прерваться, ни когда именно. Крючок возврата, о котором игрок не
	-- знает, крючком не работает — поэтому срок теперь называется вслух
	-- ровно в тот момент, когда игрок только что получил награду и ему
	-- приятнее всего услышать "приходи завтра".
	--
	-- КОГДА ИМЕННО СГОРАЕТ. Серия продолжается, если следующий клейм
	-- случился в СЛЕДУЮЩИЙ календарный день UTC (см. nextDailyReward выше:
	-- сравнение с utcDate(now - 86400)). Значит крайний срок — конец
	-- завтрашних суток UTC. Unix-эпоха выровнена по UTC-полуночи, поэтому
	-- now % 86400 — это ровно секунды, прошедшие с начала текущих суток, и
	-- отдельной возни с календарём не требуется.
	local secondsLeft = 2 * 86400 - (now % 86400)
	local hoursLeft = math.floor(secondsLeft / 3600)
	local minutesLeft = math.floor((secondsLeft % 3600) / 60)
	local deadline = hoursLeft > 0
		and ("%dh %02dm"):format(hoursLeft, minutesLeft)
		or ("%dm"):format(minutesLeft)
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("DAY %d STREAK\nCome back within %s or it resets")
			:format(data.DailyRewardStreak, deadline), { Icon = "Reward" })
	end

	self:SendState(player)
end

function QuestService:GetMiningBoostMultiplier(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data or data.DailyMiningBoostEndsAt <= os.time() then return 1 end
	-- Множитель берём из того, что РЕАЛЬНО было зафиксировано при клейме
	-- (см. ClaimDailyReward ниже), а НЕ пересканируем текущий
	-- Config.Quests.DailyRewards — тот может содержать несколько разных
	-- MiningBoost-наград, и старое сканирование всегда возвращало бы
	-- множитель ПЕРВОЙ найденной, что для второй и далее было бы неверно.
	local multiplier = tonumber(data.DailyMiningBoostMultiplier) or 1
	return multiplier > 0 and multiplier or 1
end

--------------------------------------------------------------------------------
-- ПОДСКАЗКИ ПРО GIFT/BOULDERS (см. Config.Tips — развёрнутое обоснование
-- там же: механики, которые НЕ входят в основной гайд и без подсказки
-- игрок может никогда не открыть их сам).
--
-- Вызывается из DataService (в момент завершения гайда — самый частый
-- случай) и из SetupPlayer выше (на случай, если гайд был пройден в
-- ПРОШЛОЙ сессии — сервер тогда мог не успеть/не был перезапущен и не
-- показал часть подсказок; task.delay ниже не переживает рестарт сервера,
-- поэтому эта повторная проверка при каждом заходе — не подстраховка "на
-- всякий случай", а реально необходимый повторный вход в очередь).
--------------------------------------------------------------------------------
local TIP_ICONS = { GiftCrystal = "Gift", SmashBoulders = "Boulder" }

function QuestService:_scheduleTips(player)
	if player:GetAttribute("NeedsTutorial") == true then return end -- ждём завершения гайда
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	local completedAt = tonumber(data.TutorialCompletedAt) or 0
	if completedAt <= 0 then return end
	data.TipsShown = data.TipsShown or {}
	for _, tip in Config.Tips do
		if not data.TipsShown[tip.Id] then
			local remaining = (completedAt + tip.DelayAfterTutorial) - os.time()
			task.delay(math.max(remaining, 1), function()
				if not player.Parent then return end
				local freshData = Services.DataService:GetGeodeData(player)
				if not freshData then return end
				freshData.TipsShown = freshData.TipsShown or {}
				if freshData.TipsShown[tip.Id] then return end -- уже показали (например, из другого вызова _scheduleTips)
				freshData.TipsShown[tip.Id] = true
				Services.NotifyService:Show(player, tip.Text, { Icon = TIP_ICONS[tip.Id] or "Default", Duration = tip.Duration })
				Services.DataService:SaveProfile(player)
			end)
		end
	end
end

function QuestService:HasDailyCartColor(player)
	local data = Services.DataService:GetGeodeData(player)
	return data and data.DailyCartColorUnlocked == true or false
end

function QuestService:CleanupPlayer(player)
	queuedStates[player] = nil
	lastProgressSound[player] = nil
end

return QuestService
