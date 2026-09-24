local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local MutationRoll = require(ReplicatedStorage.Shared.MutationRoll)
local CollectionKey = require(ReplicatedStorage.Shared.CollectionKey)
local OreIncome = require(ReplicatedStorage.Shared.OreIncome)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local DropTables = require(ReplicatedStorage.Shared.DropTables)

local GeodeService = {}

local function colorHex(color)
	return ("%02X%02X%02X"):format(
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end
local Services
local remote
local buildings = {}
local opening = {}
local transactions = {}
local lastRequest = {}
local lastOpenRequest = {}

local function copyTable(source)
	local result = {}
	for key, value in source do
		result[key] = typeof(value) == "table" and copyTable(value) or value
	end
	return result
end

local function levelForCopies(copies)
	local level = 1
	for candidate, required in Config.Geodes.DuplicateCopiesPerLevel do
		if copies >= required then level = candidate else break end
	end
	return math.min(level, Config.Geodes.MaxOreLevel)
end

-- Множитель мутации, ЗАПЕЧЁННЫЙ в ячейку коллекции. Ограничен потолком
-- Config.Mutations.IncomeMultiplierCap: полный множитель Celestial (x15) на
-- Titanheart дал бы 840 млрд/мин, то есть четверть всего Config.Economy.
-- MaxCurrency за одну суточную оффлайн-выплату. На ПРОДАЖУ руды из шахты
-- потолок не распространяется — там мутация работает целиком.
-- Удача игрока для мутаций — та же формула, что в CrystalService и
-- RockService (см. Config.Mutations.LuckBonus).
-- Множитель шанса мутаций от баффа "зелье мутаций" (Config.Buffs
-- .MutationPotion). Нет баффа — 1, то есть обычный расклад.
local function mutationPotionFor(player)
	if not (player and Services and Services.BuffService) then return 1 end
	local ok, value = pcall(function()
		return Services.BuffService:GetBonus(player, "MutationPotion")
	end)
	if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
	return 1
end

local function luckForPlayer(player)
	if not player then return 0 end
	local ok, luck = pcall(function()
		return MutationRoll.LuckFor(
			Services.DataService:GetRebirths(player),
			Services.DataService:GetTiers(player).Mine
		)
	end)
	return ok and luck or 0
end

-- Принимает КЛЮЧ ячейки ("Quartz" или "Quartz#Rusty"), а не голый oreId:
-- множитель мутации берётся из самого ключа (см. CollectionKey.Multiplier),
-- поэтому отдельным полем его хранить и синхронизировать не нужно.
-- Формула переехала в src/shared/OreIncome.lua (там же обоснование нового
-- баланса). Доход теперь зависит и от тиров игрока, поэтому нужен player —
-- иначе карточки в интерфейсе показывали бы не то, что реально капает.
local function incomeFor(player, key, level)
	return OreIncome.PerMinuteForPlayer(player, key, level)
end

function GeodeService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("GeodeRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "GeodeRequest"
		remote.Parent = ReplicatedStorage.Shared
	end
	remote.OnServerEvent:Connect(function(player, action, value, extra)
		if action == "OpenGeode" then
			self:OpenGeode(player, value, extra)
		elseif action == "RequestState" then
			local now = os.clock()
			if now - (lastRequest[player] or 0) < 0.15 then return end
			lastRequest[player] = now
			self:SendState(player)
		elseif action == "SetCrackingPromptEnabled" then
			-- Клиент шлёт это ДО того, как реально начинает тап-последовательность
			-- (ещё ничего не спрашивая у сервера про саму жеоду) — специально,
			-- чтобы физически выключить GeodePrompt на время тапанья, точно так
			-- же, как ShopNpcService/UpgradeService выключают свой промпт на
			-- время диалога. Раньше промпт ничего не знал о том, что игрок
			-- прямо сейчас тапает жеоду, и случайное повторное срабатывание
			-- (промпт кликабельный мгновенно, без удержания — см. GeodePrompt.ClickablePrompt)
			-- дёргало "OpenVault" прямо посреди анимации — см. фикс в
			-- GeodeUI.client.lua. PodiumPrompt стоит рядом на том же участке и
			-- ловит ровно ту же проблему через "OpenPodium" — выключаем оба.
			local building = buildings[player]
			local prompt = building and building.Crusher and building.Crusher:FindFirstChild("GeodePrompt")
			if prompt then
				prompt.Enabled = value == true
			end
			if Services.PassiveIncomeService then
				Services.PassiveIncomeService:SetPodiumPromptEnabled(player, value == true)
			end
		end
	end)
end

function GeodeService:SendGoblinResult(player, result)
	if player.Parent and remote then
		remote:FireClient(player, "GoblinResult", result)
	end
end

function GeodeService:TryBeginTransaction(player)
	if transactions[player] or player:GetAttribute("EconomyTransactionLocked") == true then return false end
	transactions[player] = true
	player:SetAttribute("EconomyTransactionLocked", true)
	return true
end

function GeodeService:EndTransaction(player)
	transactions[player] = nil
	player:SetAttribute("EconomyTransactionLocked", false)
end

function GeodeService:IsBusy(player)
	return transactions[player] == true
end

function GeodeService:CreateGeode(geodeType)
	local geode = PlaceholderFactory.Geode(geodeType)
	geode:SetAttribute("IsGeode", true)
	geode:SetAttribute("GeodeType", geodeType)
	geode:SetAttribute("CrystalValue", 0)
	geode:SetAttribute("CrystalPoints", 0)
	return geode
end

function GeodeService:ShowCartSpawnVfx(cart, geode)
	local geodeRoot = geode:IsA("BasePart") and geode or geode.PrimaryPart or geode:FindFirstChild("Root", true)
	if not geodeRoot then return end
	local effect, effectRoot = PlaceholderFactory.GeodeCartVFX()
	effectRoot.CFrame = geodeRoot.CFrame
	effect.Parent = cart.Model
	if effect:IsA("Model") then
		effect:PivotTo(geodeRoot.CFrame)
	end
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = geodeRoot
			weld.Part1 = descendant
			weld.Parent = descendant
		end
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(math.max(1, tonumber(descendant:GetAttribute("EmitCount")) or 24))
		end
	end
	if effect:IsA("BasePart") then
		effect.Anchored = false
		effect.CanCollide = false
		effect.CanTouch = false
		effect.CanQuery = false
		effect.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = geodeRoot
		weld.Part1 = effect
		weld.Parent = effect
	end
	game:GetService("Debris"):AddItem(effect, Config.Geodes.CartSpawnVfxDuration)
end

function GeodeService:SpawnGuaranteedTutorialGeode(player, cart, dropPosition)
	if not cart or Services.CartService:GetGeodeCount(cart) > 0 then return false end
	local geode = self:CreateGeode(Config.Tutorial.GuaranteedGeodeType or "Stone")
	if not Services.CartService:AddGeode(cart, geode, false, dropPosition) then
		geode:Destroy()
		return false
	end
	player:SetAttribute("TutorialGeodeSpawned", true)
	cart.TutorialGeodeGenerated = true
	local ok, err = pcall(function() self:ShowCartSpawnVfx(cart, geode) end)
	if not ok then warn("[GeodeService] GeodeCartVFX failed:", err) end
	return true
end

function GeodeService:TrySpawnForMine(player, cart, tier, dropPosition, forceTutorialGeode)
	if Services.CartService:GetGeodeCount(cart) >= Config.Geodes.MaxPerCart then
		return false
	end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	-- Типов жеод теперь ровно столько же, сколько тиров шахты (10) — раньше
	-- их было 8, и тиры 9-10 доигрывали на потолочной Nebula. Клэмп оставлен
	-- намеренно: он ничего не отсекает при совпадающих длинах, но остаётся
	-- страховкой, если Config.Geodes.Order когда-нибудь снова окажется
	-- короче списка тиров — иначе здесь молча получится nil.
	-- v3: 15 пещер на 10 типов жеод — см. Config.GeodeTypeIndexForCave.
	local geodeTier = Config.GeodeTypeIndexForCave and Config.GeodeTypeIndexForCave(tier) or math.min(tier, #Config.Geodes.Order)
	local spawnInfo = Config.Geodes.SpawnByMineTier[geodeTier]
	local tutorialActive = Services.DataService:IsTutorialRequired(player)
	local geodeCount = Services.CartService:GetGeodeCount(cart)
	if tutorialActive and (geodeCount > 0
		or player:GetAttribute("TutorialGeodeStored") == true
		or player:GetAttribute("TutorialGeodeOpened") == true) then
		return false
	end
	local tutorialGuaranteed = tutorialActive
		and player:GetAttribute("TutorialGeodeSpawned") ~= true
		and forceTutorialGeode == true
	local guaranteed = tutorialGuaranteed or data.GeodeSpawnPity >= Config.Geodes.SpawnPity
	if tutorialActive and not tutorialGuaranteed then return false end
	-- v8: перк Geode Finder.
	local geodeChance = spawnInfo.Chance * (1 + (Services.PrestigeService and Services.PrestigeService:PerkBonus(player, "GeodeLuck") or 0))
	if not guaranteed and math.random() >= geodeChance then
		data.GeodeSpawnPity += 1
		return false
	end
	local geodeType
	if tutorialGuaranteed then
		geodeType = Config.Tutorial.GuaranteedGeodeType or "Stone"
	else
		local order = Config.Geodes.Order
		local currentType = order[geodeTier]
		local nextType = order[math.min(geodeTier + 1, #order)]
		geodeType = (nextType ~= currentType and math.random() < spawnInfo.NextWeight) and nextType or currentType
	end
	local geode = self:CreateGeode(geodeType)
	if Services.CartService:AddGeode(cart, geode, false, dropPosition) then
		data.GeodeSpawnPity = 0
		if tutorialGuaranteed then
			player:SetAttribute("TutorialGeodeSpawned", true)
		elseif Services.AnnounceService then
			-- Не объявляем гарантированную туториальную жеоду — это не
			-- "находка", а срежиссированный шаг обучения.
			local geodeInfo = Config.Geodes.Types[geodeType]
			Services.AnnounceService:Broadcast(nil, nil, {
				{ Text = ("%s found a "):format(player.DisplayName), Color = Color3.new(1, 1, 1) },
				{ Text = geodeInfo.DisplayName, Color = geodeInfo.Color },
				{ Text = "!", Color = Color3.new(1, 1, 1) },
			})
			if Services.NotifyService then
				Services.NotifyService:Show(player, ("GEODE FOUND: <font color=\"#%s\">%s</font>"):format(
					colorHex(geodeInfo.Color), geodeInfo.DisplayName
				), {
					Icon = "Geode",
					Duration = 3.5,
					RichText = true,
					Viewport = { GeodeType = geodeType },
				})
			end
		end
		local vfxOk, vfxErr = pcall(function() self:ShowCartSpawnVfx(cart, geode) end)
		if not vfxOk then warn("[GeodeService] GeodeCartVFX failed:", vfxErr) end
		return true
	end
	geode:Destroy()
	return false
end

-- Зачисляет ОДНУ жеоду напрямую в постоянное хранилище игрока, минуя
-- тележку — используется CrystalService, когда подобравшему (обычно вору
-- без своей тележки под рукой) физически некуда её положить (см. комментарий
-- в CrystalService.lua у ветки IsGeode). Та же durable-инфраструктура
-- (транзакция + идемпотентный GUID), что и у EvacuateCart ниже, просто без
-- физического груза, который можно было бы вернуть при неудаче.
function GeodeService:AddGeodeDirectly(player, geodeType, transactionId)
	if not Config.Geodes.Types[geodeType] then return false end
	if not self:TryBeginTransaction(player) then return false end
	transactionId = transactionId or HttpService:GenerateGUID(false)
	local ok, status = Services.DataService:AddGeodesAndSave(player, { [geodeType] = 1 }, transactionId)
	self:EndTransaction(player)
	if ok then
		self:UpdateBuilding(player)
		self:SendState(player)
	end
	return ok, status
end

-- mutations — необязательная строка вида "Frozen,Molten" (атрибут кристалла).
-- Множитель ЗАПОМИНАЕТСЯ В ЯЧЕЙКЕ и берётся ЛУЧШИЙ за всё время: сдал
-- Celestial-руду — ячейка навсегда получила её множитель, и последующая
-- обычная копия его не сбросит. Иначе игрок терял бы редкую находку, просто
-- подобрав такую же руду без мутаций.
function GeodeService:AddCollectionCopy(player, oreId, mutations)
	if not Config.Geodes.Ores[oreId] then return false end
	if not self:TryBeginTransaction(player) then return false end
	local data = Services.DataService:GetGeodeData(player)
	-- Мутировавшая руда ложится в ОТДЕЛЬНУЮ ячейку: обычный Quartz и Rusty
	-- Quartz — два разных слота со своими уровнями и доходом.
	local key = CollectionKey.Make(oreId, mutations)
	local entry = data and data.GeodeCollection[key]
	local maxCopies = Config.Geodes.DuplicateCopiesPerLevel[#Config.Geodes.DuplicateCopiesPerLevel]
	if not data or (entry and entry.Copies >= maxCopies) then
		self:EndTransaction(player)
		return false
	end
	if entry then
		entry.Copies += 1
		entry.Level = levelForCopies(entry.Copies)
	else
		data.GeodeCollection[key] = { Copies = 1, Level = 1 }
	end
	if not Services.DataService:SaveProfile(player) then
		if entry then
			entry.Copies -= 1
			entry.Level = levelForCopies(entry.Copies)
		else
			data.GeodeCollection[key] = nil -- откатываем ровно тот ключ, который создали выше
		end
		self:EndTransaction(player)
		return false
	end
	self:EndTransaction(player)
	self:SendState(player)
	-- Квесты "Crystal Collection" (OresCollected) и "Rare Find" (RareOres)
	-- обещают в описании "from geodes OR BOULDERS", но метрики писались
	-- ТОЛЬКО в OpenGeode. Подобранный с валуна кристалл ложился в коллекцию
	-- и не двигал прогресс вообще — игрок видел руду в книге и ноль в квесте.
	if Services.QuestService then
		Services.QuestService:RecordMetric(player, "OresCollected", 1)
		local info = Config.Geodes.Ores[oreId]
		local rarity = info and info.Rarity
		if rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" or rarity == "Mythic" then
			Services.DataService:AwardBadge(player, Config.Badges and Config.Badges.RareOre)
			Services.QuestService:RecordMetric(player, "RareOres", 1)
		end
	end
	return true
end

function GeodeService:EvacuateCart(player, cart)
	if not self:TryBeginTransaction(player) then return 0 end
	local transactionId = cart.PendingGeodeEvacuationId or HttpService:GenerateGUID(false)
	cart.PendingGeodeEvacuationId = nil
	local removed = Services.CartService:RemoveGeodes(cart, Services.CartService:GetGeodeCount(cart), true)
	if #removed == 0 then cart.GeodeSavePending = false; self:EndTransaction(player); return 0 end
	local counts = {}
	for _, geode in removed do
		if geode:IsA("BasePart") then
			geode.Anchored = true
			geode.CanCollide = false
		end
		for _, descendant in geode:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		local geodeType = geode:GetAttribute("GeodeType") or "Stone"
		counts[geodeType] = (counts[geodeType] or 0) + 1
	end
	if not Services.DataService:AddGeodesAndSave(player, counts, transactionId) then
		if cart.Model.Parent then
			for index = #removed, 1, -1 do
				if removed[index].Parent then Services.CartService:AddGeode(cart, removed[index], true) end
			end
			cart.PendingGeodeEvacuationId = transactionId
			cart.GeodeSavePending = true
		end
		Services.NotifyService:Show(player, "Geode save is unavailable. Cargo was returned; try again.", { Icon = "Error" })
		self:EndTransaction(player)
		return 0
	end
	cart.PendingGeodeEvacuationId = nil
	cart.GeodeSavePending = false
	if player:GetAttribute("NeedsTutorial") == true then player:SetAttribute("TutorialGeodeStored", true) end
	for _, geode in removed do
		local root = geode:IsA("BasePart") and geode or (geode.PrimaryPart or geode:FindFirstChild("Root", true))
		if root then
			geode.Parent = workspace
			local startCFrame = geode:IsA("Model") and geode:GetPivot() or root.CFrame
			local targetCFrame = CFrame.new(Services.WorldService:GetBankTopPosition())
			local startPosition = startCFrame.Position
			local targetPosition = targetCFrame.Position
			local distance = (targetPosition - startPosition).Magnitude
			local controlPosition = (startPosition + targetPosition) * 0.5 + Vector3.new(0, math.clamp(distance * 0.4, 9, 32), 0)
			local progress = Instance.new("NumberValue")
			local tween = TweenService:Create(progress, TweenInfo.new(math.clamp(distance / 48, 0.7, 1.5), Enum.EasingStyle.Linear), { Value = 1 })
			local connection
			connection = progress.Changed:Connect(function(value)
				if not geode.Parent then return end
				local inverse = 1 - value
				local arcPosition = inverse * inverse * startPosition
					+ 2 * inverse * value * controlPosition
					+ value * value * targetPosition
				local rotation = startCFrame:Lerp(targetCFrame, value).Rotation
				local flightCFrame = CFrame.new(arcPosition) * rotation * CFrame.Angles(value * math.pi * 4, value * math.pi * 2, 0)
				if geode:IsA("Model") then geode:PivotTo(flightCFrame) else root.CFrame = flightCFrame end
			end)
			tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				progress:Destroy()
				geode:Destroy()
			end)
			tween:Play()
		else
			geode:Destroy()
		end
	end
	for geodeType, amount in counts do
		local name = Config.Geodes.Types[geodeType].DisplayName:upper()
		Services.NotifyService:Show(player, ("%s EVACUATED x%d\nSent to your base"):format(name, amount), { Icon = "Geode" })
	end
	self:UpdateBuilding(player)
	self:SendState(player)
	self:EndTransaction(player)
	return #removed
end

function GeodeService:GetState(player)
	if Services.PassiveIncomeService and not self:IsBusy(player) then Services.PassiveIncomeService:Accrue(player) end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	local collection = {}
	for key, entry in data.GeodeCollection do
		-- key — это "Quartz" либо "Quartz#Rusty" (см. CollectionKey). Базовая
		-- руда нужна для картинки/цвета/редкости, список мутаций — чтобы
		-- клиент нарисовал иконку мутации поверх иконки руды.
		local oreId, mutations = CollectionKey.Parse(key)
		local info = Config.Geodes.Ores[oreId]
		if info then
			collection[key] = {
				OreId = oreId,
				Copies = entry.Copies,
				Level = entry.Level,
				DisplayName = CollectionKey.DisplayName(key),
				Rarity = info.Rarity,
				ImageId = info.ImageId,
				Color = info.Color,
				IncomePerMinute = incomeFor(player, key, entry.Level),
				Mutations = #mutations > 0 and mutations or nil,
				MutationMultiplier = #mutations > 0 and CollectionKey.Multiplier(key) or nil,
			}
		end
	end
	local installed = data.InstalledGeodeOre
	return {
		Geodes = copyTable(data.Geodes),
		GeodeHearts = tonumber(data.GeodeHearts) or 0, -- v18
		Collection = collection,
		InstalledOre = installed,
		SafeBalance = math.floor(data.GeodeSafeBalance),
	}
end

function GeodeService:SendState(player, command, payload)
	if player.Parent then remote:FireClient(player, command or "State", payload or self:GetState(player)) end
end

function GeodeService:OpenGeode(player, geodeType, requestedCount)
	local now = os.clock()
	if now - (lastOpenRequest[player] or 0) < 0.5 then
		if player.Parent then remote:FireClient(player, "OpenFailed") end
		return
	end
	lastOpenRequest[player] = now
	-- Открытие разрешено только у своей наковальни. Проверка обязательна на
	-- сервере: клиентский OpenGeode нельзя считать подтверждением proximity prompt.
	local building = buildings[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local crusher = building and building.Crusher
	local crusherRoot = crusher and (crusher:IsA("BasePart") and crusher or crusher:FindFirstChildWhichIsA("BasePart", true))
	if not (root and crusherRoot and (root.Position - crusherRoot.Position).Magnitude <= 14) then
		-- Нет наковальни вообще — значит, остров ещё не куплен: говорим
		-- игроку прямо, куда идти, а не молча отказываем.
		if not building and Services.IslandService and not Services.IslandService:Owns(player, "Anvil") then
			Services.NotifyService:Show(player, "Unlock the Anvil Island at the Island Keeper in town to open geodes!", { Icon = "Quest" })
		end
		if player.Parent then remote:FireClient(player, "OpenFailed") end
		return
	end
	if Services.MonetizationService and not Services.MonetizationService:IsEntitlementsReady(player) then
		Services.NotifyService:Show(player, "Purchase bonuses are still loading. Try again in a moment.", { Icon = "Pending" })
		if player.Parent then remote:FireClient(player, "OpenFailed") end
		return
	end
	requestedCount = math.clamp(math.floor(tonumber(requestedCount) or 1), 1, 5)
	if requestedCount ~= 1 and requestedCount ~= 3 and requestedCount ~= 5 then
		if player.Parent then remote:FireClient(player, "OpenFailed") end
		return
	end
	if opening[player] or not Config.Geodes.Types[geodeType] or not self:TryBeginTransaction(player) then
		if player.Parent then remote:FireClient(player, "OpenFailed") end
		return
	end
	-- Гейт прежнего гайда ("открывать жеоду только после шага «положи в
	-- сейф»") снят: в обучении v7 такого шага нет, а SetupPlot сбрасывал
	-- TutorialGeodeStored на каждом заходе — жеоды, выпавшие с базовых
	-- валунов в прологе, было невозможно открыть до его конца.
	local data = Services.DataService:GetGeodeData(player)
	local availableCount = data and (data.Geodes[geodeType] or 0) or 0
	if availableCount <= 0 then
		self:EndTransaction(player)
		if player.Parent then remote:FireClient(player, "OpenFailed") end
		return
	end
	-- x3/x5 — постоянная разблокировка (Game Pass), купил один раз —
	-- открываешь пачками бесплатно навсегда. x3 и x5 — РАЗНЫЕ пассы.
	if requestedCount ~= 1 then
		local passKey = "GeodeMaster" -- v10: x3 и x5 — один пасс
		if not (Services.MonetizationService and Services.MonetizationService:HasPass(player, passKey)) then
			self:EndTransaction(player)
			if player.Parent then remote:FireClient(player, "OpenFailed", "PassRequired", requestedCount) end
			return
		end
	end
	local openCount = math.min(requestedCount, availableCount)
	opening[player] = true
	local snapshot = {
		Geodes = copyTable(data.Geodes),
		Collection = copyTable(data.GeodeCollection),
		OwnedSkins = copyTable(data.OwnedSkins),
		Money = copyTable(data.Money),
		MutationsFound = copyTable(data.MutationsFound or {}),
		OpenPity = data.GeodeOpenPity,
		First = data.FirstGeodeOreGranted,
		Gear = copyTable(data.Gear or {}), -- v18: эссенции
		Hearts = data.GeodeHearts,
	}
	local committed = false
	local succeeded, errorMessage = xpcall(function()
	data.Geodes[geodeType] -= openCount
	local cfg = Config.Geodes.Types[geodeType]
	local tutorialNeedsOre = player:GetAttribute("NeedsTutorial") == true
		and player:GetAttribute("TutorialGeodeOpened") ~= true
	local results = {}
	local newSkins = {}
	local oreTier = 1
	for tier, orderedType in Config.Geodes.Order do
		if orderedType == geodeType then oreTier = tier; break end
	end

	-- v18: единая таблица шансов (shared/DropTables) — те же строки видит
	-- игрок в окне шансов. Кристаллы / деньги / эссенции / сердце (+ мусор).
	local dropTable = DropTables.Geode(geodeType)
	local function isCrystalRow(r) return r.Kind == "Crystal" end
	local function rollReward(advancesGeodeProgress)
		local forceOre = advancesGeodeProgress and (tutorialNeedsOre
			or not data.FirstGeodeOreGranted
			or data.GeodeOpenPity >= Config.Geodes.OpenPity)
		local row = DropTables.Pick(dropTable.Rows, forceOre and isCrystalRow or nil)
			or DropTables.Pick(dropTable.Rows, isCrystalRow)
		local junk = row.Kind == "Junk" and Config.RollJunk and (function()
			-- вид мусора — по весам Config.Junk.Items (шанс «мусор ли» уже в строке)
			local total = 0
			for _, item in Config.Junk.Items do total += item.Weight end
			local pick = math.random() * total
			for _, item in Config.Junk.Items do
				pick -= item.Weight
				if pick <= 0 then return item end
			end
			return Config.Junk.Items[#Config.Junk.Items]
		end)()
		if junk then
			if advancesGeodeProgress then data.GeodeOpenPity += 1 end
			local stored = false
			if Services.InventoryService then
				local okAdd, added = pcall(Services.InventoryService.AddOre, Services.InventoryService, player, junk.Key, 1, nil, junk.Value or 0, 1, false, { Chance = junk.Chance })
				stored = okAdd and added == true
			end
			if not stored then
				-- Рюкзак полон — хлам просто остаётся лежать у наковальни.
				task.defer(function()
					local crystal = Services.CrystalService and Services.CrystalService:CreateJunk(junk, 1)
					local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if crystal and rootPart then
						crystal:PivotTo(rootPart.CFrame * CFrame.new(0, 1, -3))
						Services.CrystalService:MakeLoose(crystal, Vector3.new(0, 18, 0), player.UserId)
					elseif crystal then
						crystal:Destroy()
					end
				end)
			end
			return {
				Kind = "Junk", OreId = junk.Key, Title = junk.DisplayName, Rarity = "Common",
				ImageId = 0, Value = junk.Value or 0, Chance = row.Chance * (junk.Chance or 1),
			}
		end
		local result
		if row.Kind == "Crystal" then
			local tutorialOre = advancesGeodeProgress and tutorialNeedsOre
			local oreId = tutorialOre and cfg.Ores[1] or row.OreId
			local mutations
			if tutorialOre then
				mutations = {}
			else
				local weatherBoosts = Services.WeatherService and Services.WeatherService:GetActiveBoosts()
				if player and Services.BaseDecorService then weatherBoosts = Services.BaseDecorService:MergeMutationBoosts(player, weatherBoosts) end
				local rollMultiplier
				mutations, rollMultiplier = MutationRoll.Roll(luckForPlayer(player), weatherBoosts, mutationPotionFor(player))
				local forcedMutation = Services.WeatherService and Services.WeatherService:GetForcedMutation()
				if forcedMutation then
					mutations, rollMultiplier = MutationRoll.ForceInclude(mutations, rollMultiplier, forcedMutation)
				end
			end
			local key = CollectionKey.Make(oreId, mutations)
			local entry = data.GeodeCollection[key]
			local info = Config.Geodes.Ores[oreId]
			local maxCopies = Config.Geodes.DuplicateCopiesPerLevel[#Config.Geodes.DuplicateCopiesPerLevel]
			if not tutorialOre and entry and entry.Level >= Config.Geodes.MaxOreLevel and entry.Copies >= maxCopies then
				-- Компенсация за дубликат руды, которая уже прокачана в
				-- максимум. Раньше это было "5 минут дохода" по СЫРОМУ
				-- полю IncomePerMinute — а оно теперь хранит только
				-- ПЛОСКУЮ часть формулы (см. OreIncome.lua), то есть
				-- десятки долларов вместо реальной ставки. Считаем по той
				-- же живой формуле, что и всё остальное.
				local amount = math.max(1, math.floor(incomeFor(player, key, Config.Geodes.MaxOreLevel) * 5))
				Services.DataService:AddMoney(player, amount)
				result = { Kind = "Money", Title = "MAX DUPLICATE +$" .. NumberFormat.abbreviate(amount), Amount = amount, Rarity = info.Rarity, ImageId = Config.Geodes.Images.MoneySmall }
			else
				local previousLevel = entry and entry.Level or 0
				if entry then
					entry.Copies = math.min(entry.Copies + 1, maxCopies)
					entry.Level = levelForCopies(entry.Copies)
				else
					entry = { Copies = 1, Level = 1 }
					data.GeodeCollection[key] = entry
				end
				if #mutations > 0 and Services.MutationBookService then
					for _, mutationId in mutations do
						Services.MutationBookService:RecordFound(player, oreTier, mutationId)
					end
				end
				local mutationNames = {}
				for _, mutationId in mutations do
					table.insert(mutationNames, Config.Mutations[mutationId].DisplayName)
				end
				result = {
					Kind = "Ore", OreId = oreId, CollectionKey = key,
					Title = info.DisplayName, Rarity = info.Rarity,
					ImageId = info.ImageId, Level = entry.Level, Upgraded = entry.Level > previousLevel and previousLevel > 0,
					IncomePerMinute = incomeFor(player, key, entry.Level),
					Mutations = #mutations > 0 and mutations or nil,
					MutationNames = #mutationNames > 0 and table.concat(mutationNames, " + "):upper() or nil,
				}
			end
			if advancesGeodeProgress then
				data.GeodeOpenPity = 0
				data.FirstGeodeOreGranted = true
			end
		elseif row.Kind == "Money" then
			if advancesGeodeProgress then data.GeodeOpenPity += 1 end
			local amount = row.Amount
			Services.DataService:AddMoney(player, amount)
			local moneyImage = row.Index == 3 and Config.Geodes.Images.MoneyJackpot
				or row.Index == 2 and Config.Geodes.Images.MoneyLarge
				or Config.Geodes.Images.MoneySmall
			result = { Kind = "Money", Title = "+$" .. NumberFormat.abbreviate(amount), Amount = amount, Jackpot = row.Index == 3, Rarity = row.Rarity, ImageId = moneyImage }
		elseif row.Kind == "Essence" then
			if advancesGeodeProgress then data.GeodeOpenPity += 1 end
			local key = DropTables.EssenceKey(row.Mutation)
			if Services.GearService then Services.GearService:AddGear(player, key, 1) end
			result = { Kind = "Essence", Mutation = row.Mutation, Title = row.Title, Rarity = row.Rarity, ImageId = 0 }
		elseif row.Kind == "Heart" then
			if advancesGeodeProgress then data.GeodeOpenPity += 1 end
			data.GeodeHearts = (tonumber(data.GeodeHearts) or 0) + 1
			result = { Kind = "Heart", Title = row.Title, Rarity = "Mythic", ImageId = 0 }
		end
		if result then result.Chance = result.Chance or row.Chance end
		return result
	end

	local rewardCount = math.clamp(math.floor(tonumber(Services.MonetizationService:GetGeodeRewardCount(player)) or 1), 1, 2)
	for geodeIndex = 1, openCount do
		-- v18: СЕРДЦЕ ЖЕОДЫ — эта жеода даёт сразу Heart.Rewards наград.
		local count = rewardCount
		local heartUsed = false
		if (tonumber(data.GeodeHearts) or 0) > 0 then
			data.GeodeHearts -= 1
			count = math.max(count, Config.Geodes.Heart.Rewards or 3)
			heartUsed = true
		end
		for rewardIndex = 1, count do
			local rolled = rollReward(rewardIndex == 1)
			if typeof(rolled) == "table" then
				if heartUsed then rolled.FromHeart = true end
				table.insert(results, rolled)
			end
		end
	end
	-- Здесь стоял ещё один проход по results, который сбрасывал GeodeOpenPity
	-- при ЛЮБОЙ выпавшей руде — включая бонусные роллы от геймпасса
	-- DoubleDrops (у них advancesGeodeProgress = false). rollReward уже
	-- обработал пити правильно: счётчик двигают только "главные" роллы.
	-- Из-за лишнего прохода владелец DoubleDrops получал удвоенный шанс
	-- сбить собственную систему жалости — то есть пасс на БОЛЬШЕ дропа
	-- работал против него. Проход удалён.
	if not Services.DataService:SaveProfile(player) then
		data.Geodes = snapshot.Geodes
		data.GeodeCollection = snapshot.Collection
		data.OwnedSkins = snapshot.OwnedSkins
		data.Money = snapshot.Money
		data.MutationsFound = snapshot.MutationsFound
		data.GeodeOpenPity = snapshot.OpenPity
		data.FirstGeodeOreGranted = snapshot.First
		data.Gear = snapshot.Gear
		data.GeodeHearts = snapshot.Hearts
		if Services.GearService then pcall(Services.GearService.SendState, Services.GearService, player) end
		Services.DataService:AddMoney(player, 0, nil, true)
		if Services.MutationBookService then Services.MutationBookService:SendState(player) end
		opening[player] = nil
		self:EndTransaction(player)
		Services.NotifyService:Show(player, "Opening failed safely. Your geode was returned.", { Icon = "Error" })
		if player.Parent then remote:FireClient(player, "OpenFailed"); self:SendState(player) end
		return
	end
	committed = true
	opening[player] = nil
	self:EndTransaction(player)
	local oreCount = 0
	local rareOreCount = 0
	for _, result in results do
		if result.Kind == "Ore" then
			oreCount += 1
			if result.Rarity == "Rare" or result.Rarity == "Epic" or result.Rarity == "Legendary" or result.Rarity == "Mythic" then
				rareOreCount += 1
			end
		end
	end
	if player:GetAttribute("NeedsTutorial") == true and oreCount > 0 then
		player:SetAttribute("TutorialGeodeOpened", true)
	end
	if Services.QuestService then
		Services.QuestService:RecordMetric(player, "GeodesOpened", openCount)
		if oreCount > 0 then Services.QuestService:RecordMetric(player, "OresCollected", oreCount) end
		if rareOreCount > 0 then
			Services.DataService:AwardBadge(player, Config.Badges and Config.Badges.RareOre)
			Services.QuestService:RecordMetric(player, "RareOres", rareOreCount)
		end
	end
	if Services.AnnounceService then
		for _, definition in newSkins do
			local color = Config.RarityColors[definition.Rarity] or Color3.new(1, 1, 1)
			Services.AnnounceService:Broadcast(nil, nil, {
				{ Text = ("%s got the skin: "):format(player.DisplayName), Color = Color3.new(1, 1, 1) },
				{ Text = definition.DisplayName, Color = color },
				{ Text = "!", Color = Color3.new(1, 1, 1) },
			})
			if Services.NotifyService then
				Services.NotifyService:Show(player, ("SKIN UNLOCKED: <font color=\"#%s\">%s</font>"):format(
					colorHex(color), definition.DisplayName
				), {
					Icon = "Skin",
					Duration = 3.5,
					RichText = true,
				})
			end
		end
	end
	Sfx.play("GeodeReveal", buildings[player] and buildings[player].Root)
	self:UpdateBuilding(player)
	Services.SkinService:SendState(player)
	if player.Parent then remote:FireClient(player, "OpenResult", { Results = results }, self:GetState(player)) end
	end, debug.traceback)
	if not succeeded then
		opening[player] = nil
		self:EndTransaction(player)
		if not committed then
			data.Geodes = snapshot.Geodes
			data.GeodeCollection = snapshot.Collection
			data.OwnedSkins = snapshot.OwnedSkins
			data.Money = snapshot.Money
			data.MutationsFound = snapshot.MutationsFound
			data.GeodeOpenPity = snapshot.OpenPity
			data.FirstGeodeOreGranted = snapshot.First
			data.Gear = snapshot.Gear
			data.GeodeHearts = snapshot.Hearts
			if Services.GearService then pcall(Services.GearService.SendState, Services.GearService, player) end
			Services.DataService:AddMoney(player, 0, nil, true)
			if Services.MutationBookService then Services.MutationBookService:SendState(player) end
		end
		warn("[GeodeService] OpenGeode failed safely:", errorMessage)
		if player.Parent then
			Services.NotifyService:Show(player, committed and "Reward saved, but its animation failed." or "Opening failed safely. Your geode was returned.", { Icon = "Error" })
			remote:FireClient(player, committed and "State" or "OpenFailed", self:GetState(player))
		end
	end
end

function GeodeService:SetupPlot(player, plot)
	local profile = Services.DataService:GetGeodeData(player)
	if profile then
		local storedCount = 0
		for geodeType in Config.Geodes.Types do storedCount += (profile.Geodes[geodeType] or 0) end
		local stored = storedCount > 0 or profile.FirstGeodeOreGranted == true
		if player:GetAttribute("NeedsTutorial") == true then
			-- Existing vault contents belong to an older session and must not
			-- complete the current bank/opening objectives.
			player:SetAttribute("TutorialGeodeStored", false)
			player:SetAttribute("TutorialGeodeOpened", false)
		else
			player:SetAttribute("TutorialGeodeStored", stored)
			player:SetAttribute("TutorialGeodeOpened", profile.FirstGeodeOreGranted == true)
		end
	end
	-- НАКОВАЛЬНЯ ТЕПЕРЬ СТОИТ НА ОСТРОВЕ (см. Config.Islands / IslandService):
	-- её строит IslandService через BuildBuilding, когда остров куплен.
	-- Если острова отключены в конфиге — строим по-старому, на участке.
	if Services.IslandService and Config.Islands and Config.Islands.Enabled then return end
	self:BuildBuilding(player, plot.GeodeBuildingCFrame, plot.Content)
end

-- Строит наковальню (здание открытия жеод) в cframe и кладёт в parent.
-- Возвращает модель. Вызывается IslandService при постройке острова.
function GeodeService:BuildBuilding(player, cframe, parent)
	local plot = { GeodeBuildingCFrame = cframe, Content = parent }
	local model = PlaceholderFactory.GeodeBuilding()
	local root
	local crusher
	if model then
		root = model.PrimaryPart or model:FindFirstChild("Root", true)
		model.PrimaryPart = root
		model:PivotTo(plot.GeodeBuildingCFrame)
		crusher = model:FindFirstChild("Crusher", true)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then descendant.Anchored = true end
		end
	else
		model = Instance.new("Model")
		model.Name = "GeodeBuilding"
		root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(10, 5, 7)
		root.Color = Color3.fromRGB(42, 48, 62)
		root.Anchored = true
		root.CFrame = plot.GeodeBuildingCFrame
		root.Parent = model
		model.PrimaryPart = root
		crusher = Instance.new("Part")
		crusher.Name = "Crusher"
		crusher.Size = Vector3.new(3.5, 2.5, 2.5)
		crusher.Color = Color3.fromRGB(95, 135, 175)
		crusher.Anchored = true
		crusher.CFrame = root.CFrame * CFrame.new(0, 0, -4)
		crusher.Parent = model
	end
	local prompt = crusher:FindFirstChild("GeodePrompt") or crusher:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "GeodePrompt"
	prompt.ActionText = "OPEN GEODES"
	prompt.ObjectText = "Geode Vault"
	prompt.HoldDuration = 0 -- было 0.25 (удержание) — теперь мгновенный клик, см. фидбек "везде, где нужно зажимать, сделай по клику"
	prompt.ClickablePrompt = true
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = crusher
	local gui
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") and descendant.Name == "StatusGui" then
			gui = descendant
			break
		end
	end
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
	if not (gui and gui:IsA("BillboardGui") and label) then
		gui = Instance.new("BillboardGui")
		gui.Name = "StatusGui"
		gui.Size = UDim2.fromOffset(260, 52)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 80
		gui.Parent = root
		label = WorldUi.Text(nil, "Text", "Number")
		label.Name = "Status"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Parent = gui
	end
	model.Parent = plot.Content
	buildings[player] = { Model = model, Root = root, Crusher = crusher, Label = label }
	prompt.Triggered:Connect(function(triggerer)
		if triggerer:GetAttribute("UpgradeInProgress") == true then return end
		if triggerer == player then self:SendState(player, "OpenVault", self:GetState(player)) end
	end)
	self:UpdateBuilding(player)
	return model
end

function GeodeService:UpdateBuilding(player)
	local building = buildings[player]
	local data = Services.DataService:GetGeodeData(player)
	if building and data then
		local available = false
		for geodeType in Config.Geodes.Types do
			if (data.Geodes[geodeType] or 0) > 0 then available = true; break end
		end
		building.Label.Text = available and "AVAILABLE" or "UNAVAILABLE"
		building.Label.TextColor3 = available and Color3.fromRGB(90, 255, 125) or Color3.fromRGB(255, 85, 85)
	end
end

function GeodeService:CleanupPlayer(player)
	opening[player] = nil
	transactions[player] = nil
	lastRequest[player] = nil
	lastOpenRequest[player] = nil
	player:SetAttribute("EconomyTransactionLocked", false)
	buildings[player] = nil
end

return GeodeService
