local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)
local OreIncome = require(ReplicatedStorage.Shared.OreIncome)
local CollectionKey = require(ReplicatedStorage.Shared.CollectionKey)
local MutationRoll = require(ReplicatedStorage.Shared.MutationRoll)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local RockService = {}
local Services

local function colorHex(color)
	return ("%02X%02X%02X"):format(
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end
local active = {}
local carrying = {}
local transferring = {}
local characterConnections = {}

local ORE_BY_TIER = { "Rubblegem", "Ironflake", "Coalheart", "Duskstone", "VerdantCore", "Emberite", "Frostvein", "Wyrmglass", "UmbralShard", "Titanheart" }

-- tierForOre должен уметь резолвить тир для ЛЮБОЙ руды, а не только для 10
-- кастомных валунных — "Достать в руки" (PassiveIncomeService:Extract)
-- умеет вынести в руки ЛЮБОЙ кристалл из постоянной коллекции, включая
-- обычные жеодные (Sapphire, Quartz и т.д.), так что при падении/депозите
-- такого кристалла (см. DropCarrying/DepositCarrying) нужен его настоящий
-- тир, а не дефолтная единица.
local GEODE_TYPE_TIER = {}
for tier, geodeType in Config.Geodes.Order do GEODE_TYPE_TIER[geodeType] = tier end

local function tierForOre(oreId)
	for tier, candidate in ORE_BY_TIER do
		if candidate == oreId then return tier end
	end
	for geodeType, info in Config.Geodes.Types do
		for _, candidate in info.Ores do
			if candidate == oreId then return GEODE_TYPE_TIER[geodeType] or 1 end
		end
	end
	return 1
end

local function rootOf(object)
	if object:IsA("BasePart") then return object end
	return object.PrimaryPart or object:FindFirstChild("Root", true) or object:FindFirstChildWhichIsA("BasePart", true)
end

-- Удача владельца валуна: ровно та же, что у руды из шахты (см.
-- CrystalService и Config.Mutations.LuckBonus). Раньше здесь была своя
-- урезанная копия ролла, которая даже не считала множитель — просто список.
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

local function setModelPhysics(model, anchored)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = true
			-- При переноске кристалл приварен к голове. Без Massless его вес
			-- добавляется к assembly персонажа и создаёт рывки/тяжёлую ходьбу.
			descendant.Massless = not anchored
		end
	end
end

local function pivotInstance(instance, cframe)
	if instance:IsA("Model") then instance:PivotTo(cframe) else instance.CFrame = cframe end
end

local function placeCrystalAtFloor(crystal, root, floorPosition)
	pivotInstance(crystal, CFrame.new(floorPosition))
	local bottomY
	if crystal:IsA("Model") then
		local boundsCFrame, boundsSize = crystal:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	else
		bottomY = root.Position.Y - root.Size.Y * 0.5
	end
	local pivot = crystal:IsA("Model") and crystal:GetPivot() or root.CFrame
	pivotInstance(crystal, pivot + Vector3.new(0, floorPosition.Y - bottomY + 0.05, 0))
	return crystal:IsA("Model") and crystal:GetPivot() or root.CFrame
end

-- Кастомная модель валуна конкретного тира — ReplicatedStorage.Assets.
-- Boulder_Tier1 .. Boulder_Tier10 (Model с PrimaryPart ИЛИ частью с именем
-- "Root" — она и станет hit-точкой/местом крепления билборда здоровья).
-- Если ассета нет или он собран неправильно — тихо откатываемся на цветной
-- шар-плейсхолдер (тот же принцип "не найдено — не падаем", что и везде в
-- PlaceholderFactory).
local function findBoulderAsset(tier)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local asset = assets and assets:FindFirstChild("Boulder_Tier" .. tier)
	if not asset then return nil end
	if not asset:IsA("Model") then
		warn(("[RockService] ReplicatedStorage.Assets.Boulder_Tier%d должен быть Model — использую плейсхолдер."):format(tier))
		return nil
	end
	local root = asset.PrimaryPart or asset:FindFirstChild("Root", true)
	if not root or not root:IsA("BasePart") then
		warn(("[RockService] ReplicatedStorage.Assets.Boulder_Tier%d нужен PrimaryPart или часть с именем 'Root' — использую плейсхолдер."):format(tier))
		return nil
	end
	local clone = asset:Clone()
	clone.PrimaryPart = clone.PrimaryPart or clone:FindFirstChild(root.Name, true)
	return clone
end

local function createBoulder(tier, elite)
	local model = findBoulderAsset(tier)
	local root
	if model then
		root = model.PrimaryPart
	else
		model = Instance.new("Model")
		root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(7, 5, 6)
		root.Shape = Enum.PartType.Ball
		root.Material = Enum.Material.Slate
		root.Color = Config.MineTiers[tier].Color
		root.TopSurface = Enum.SurfaceType.Smooth
		root.BottomSurface = Enum.SurfaceType.Smooth
		root.Parent = model
		model.PrimaryPart = root
	end
	model.Name = "RubbleBoulder"
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
	setModelPhysics(model, true)
	model:SetAttribute("IsRubbleBoulder", true)
	model:SetAttribute("Tier", tier)
	model:SetAttribute("Elite", elite == true)
	return model
end

-- v19: цифра урона, виньетка и плашка ХП на клиенте (client/BoulderHitFX).
local hitFxRemote = ReplicatedStorage.Shared:FindFirstChild("BoulderHitFx")
if not hitFxRemote then
	hitFxRemote = Instance.new("RemoteEvent")
	hitFxRemote.Name = "BoulderHitFx"
	hitFxRemote.Parent = ReplicatedStorage.Shared
end

local HEALTH_RING_SEGMENTS = 10

-- Кольцо-индикатор ХП ПРЯМО НА КАМНЕ (не на билборде) — по прямому
-- запросу вместо привычной полоски. HEALTH_RING_SEGMENTS клиновидных
-- кусочков расставлены по кругу чуть выше валуна; при уроне они гаснут
-- один за другим (по доле оставшегося здоровья), а не плавно "тают" —
-- читается как "кольцо разваливается" синхронно с самим камнем.
local function attachBoulderHealthRing(model, maxHealth)
	local root = rootOf(model)
	if not root then return nil end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local topOffset = boundsSize.Y * 0.5 + 0.6
	local radius = math.max(boundsSize.X, boundsSize.Z) * 0.5 + 0.6

	local ringFolder = Instance.new("Model")
	ringFolder.Name = "HealthRing"
	ringFolder.Parent = root

	local segments = {}
	for i = 1, HEALTH_RING_SEGMENTS do
		local angle = (i - 0.5) / HEALTH_RING_SEGMENTS * math.pi * 2
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Size = Vector3.new(0.55, 0.35, 0.9)
		segment.Material = Enum.Material.Neon
		segment.Color = Color3.fromRGB(90, 220, 90)
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
		segment.Transparency = 1 -- скрыт по умолчанию — виден только "на ударе" (см. attachBoulderHealthBillboard/showRingTemporarily), не постоянно
		local offset = Vector3.new(math.sin(angle) * radius, topOffset, math.cos(angle) * radius)
		local position = root.Position + offset
		-- Разворачиваем каждый кусочек "лицом" по касательной к кругу
		-- (смотрит вбок, а не в центр) — читается как сегмент кольца, а
		-- не как стрелки, направленные внутрь.
		segment.CFrame = CFrame.new(position, root.Position + Vector3.new(0, topOffset, 0))
			* CFrame.Angles(0, math.rad(90), 0)
		segment.Parent = ringFolder
		segments[i] = segment
	end

	return segments
end

local function updateBoulderHealthRing(segments, ratio)
	if not segments then return end
	local visibleCount = math.ceil(math.clamp(ratio, 0, 1) * #segments)
	local color = ratio <= 0.3 and Color3.fromRGB(230, 60, 60)
		or ratio <= 0.6 and Color3.fromRGB(245, 190, 55)
		or Color3.fromRGB(90, 220, 90)
	for i, segment in segments do
		if not segment.Parent then continue end
		segment.Transparency = i <= visibleCount and 0 or 1
		segment.Color = color
	end
end

local function attachBoulderHealthBillboard(model, tier, maxHealth)
	local root = rootOf(model)
	if not root then return end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
	local existingRing = root:FindFirstChild("HealthRing")
	if existingRing then existingRing:Destroy() end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local top = boundsCFrame:PointToWorldSpace(Vector3.new(0, boundsSize.Y * 0.5 + 0.5, 0))
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BoulderHealth"
	billboard.Adornee = root
	-- Ниже: раньше высота (41) была рассчитана под иконку + title + полоску
	-- ХП. Полоску убрали (см. attachBoulderHealthRing выше — она теперь
	-- прямо на камне), билборд остался чисто титульной табличкой — высота
	-- уменьшена вдвое, надпись КРУПНЕЕ (сама по себе, без соседства с
	-- полоской и текстом здоровья под ней).
	billboard.Size = UDim2.fromOffset(200, 22)
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.StudsOffsetWorldSpace = top - root.Position
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = (Config.HealthDisplay and Config.HealthDisplay.BoulderMaxDistance) or 55
	billboard.Parent = root

	local icon = Instance.new("ImageLabel")
	icon.Name = "BoulderIcon"
	icon.Size = UDim2.fromOffset(20, 20)
	icon.Position = UDim2.fromOffset(1, 1)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Image = Config.Boulders.IconImage or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = billboard

	local title = WorldUi.Text(nil, "Text", "Number")
	title.Name = "Title"
	title.Size = UDim2.new(1, -26, 1, 0)
	title.Position = UDim2.fromOffset(24, 0)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.RichText = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(238, 240, 235)
	title.Text = ("<b>BOULDER <font color=\"#69EB82\">LV. %d</font></b>"):format(tier)
	title.Parent = billboard

	local ringSegments = attachBoulderHealthRing(model, maxHealth)
	-- Кольцо ХП видно ТОЛЬКО когда камень реально бьют — не постоянно. На
	-- каждый удар (см. Health-атрибут ниже) кольцо показывается на
	-- HEALTH_RING_VISIBLE_DURATION секунд и гаснет обратно, если за это
	-- время не прилетело следующего удара. Токен — чтобы серия быстрых
	-- ударов не гасила кольцо ПОСЛЕ каждого отдельного удара раньше времени.
	local HEALTH_RING_VISIBLE_DURATION = 2.5
	local ringHideToken = 0

	local function update(health)
		local ratio = math.clamp((tonumber(health) or 0) / math.max(1, maxHealth), 0, 1)
		ringHideToken += 1
		local token = ringHideToken
		updateBoulderHealthRing(ringSegments, ratio)
		task.delay(HEALTH_RING_VISIBLE_DURATION, function()
			if token == ringHideToken and ringSegments then
				for _, segment in ringSegments do
					if segment.Parent then segment.Transparency = 1 end
				end
			end
		end)
		billboard.Enabled = ratio > 0
	end
	-- НЕ вызываем update(maxHealth) сразу при спавне — кольцо остаётся
	-- скрытым, пока не случится первый настоящий удар (см. выше).
	model:GetAttributeChangedSignal("Health"):Connect(function()
		update(model:GetAttribute("Health"))
	end)
end

-- existingMutations — мутации УЖЕ существующего кристалла (строка "a,b").
-- Передаётся, когда мы роняем в мир кристалл, который игрок нёс в руках.
-- Раньше этого параметра не было и rollMutations() вызывался ВСЕГДА: игрок
-- мог отпустить кристалл и тут же поднять его обратно, получив новый
-- случайный набор мутаций, и крутить так до редкой — то есть перероллить
-- мутации бесплатно и бесконечно. Новый набор бросаем только для реально
-- новых кристаллов (с валуна/из награды), где existingMutations нет.
local function spawnLooseCrystal(oreId, tier, position, existingMutations, owner, source, droppedByUserId)
	local crystal = PlaceholderFactory.CollectionOre(oreId)
	local root = rootOf(crystal)
	if not root then crystal:Destroy(); return end
	crystal.Name = "RubbleCrystal"
	crystal:SetAttribute("RubbleOreId", oreId)
	crystal:SetAttribute("CrystalTier", tier)
	crystal:SetAttribute("CrystalName", Config.Geodes.Ores[oreId].DisplayName)
	crystal:SetAttribute("CrystalSource", source or "")
	crystal:SetAttribute("DroppedByUserId", droppedByUserId)
	crystal:SetAttribute("Mutations", "")
	local mutations
	if existingMutations ~= nil then
		mutations = {}
		for mutationId in string.gmatch(existingMutations, "[^,]+") do
			table.insert(mutations, mutationId)
		end
	else
		local weatherBoosts = Services.WeatherService and Services.WeatherService:GetActiveBoosts()
		if owner and Services.BaseDecorService then weatherBoosts = Services.BaseDecorService:MergeMutationBoosts(owner, weatherBoosts) end
		local rollMultiplier
		mutations, rollMultiplier = MutationRoll.Roll(luckForPlayer(owner), weatherBoosts, mutationPotionFor(owner))
		local forcedMutation = Services.WeatherService and Services.WeatherService:GetForcedMutation()
		if forcedMutation then
			mutations, rollMultiplier = MutationRoll.ForceInclude(mutations, rollMultiplier, forcedMutation)
		end
	end
	if #mutations > 0 then
		crystal:SetAttribute("Mutations", table.concat(mutations, ","))
		crystal:SetAttribute("RubbleMutations", table.concat(mutations, ","))
		-- ОБЪЯВЛЕНИЕ В ЧАТ — такое же, как у руды из шахты (см.
		-- CrystalService:Create). Раньше валунные кристаллы не объявлялись
		-- вовсе: RockService не обращался к AnnounceService ни разу, и
		-- редчайшая находка проходила совершенно молча.
		--
		-- ЛИЧНОЕ УВЕДОМЛЕНИЕ (Toast, opts.Viewport) — ДОПОЛНИТЕЛЬНО к
		-- общему чату: сам нашедший игрок легко мог не заметить свою же
		-- строчку в общем чате (особенно во время боя/спама). Показывает
		-- 3D-превью ИМЕННО той руды+мутации, что выпала (тот же принцип,
		-- что в книге мутаций — см. CollectionMenu.client.lua/ensurePreview),
		-- а не плоскую картинку — так сразу видно, ЧТО именно нашлось.
		if owner and (Services.AnnounceService or Services.NotifyService) then
			local luck = luckForPlayer(owner)
			local weatherBoosts = Services.WeatherService and Services.WeatherService:GetActiveBoosts()
		if owner and Services.BaseDecorService then weatherBoosts = Services.BaseDecorService:MergeMutationBoosts(owner, weatherBoosts) end
			local names, combinedChance = {}, 1
			for _, mutationId in mutations do
				table.insert(names, Config.Mutations[mutationId].DisplayName)
				-- Шанс ФАКТИЧЕСКИЙ для этого игрока, а не базовый из
				-- конфига — требование Roblox к раскрытию вероятностей.
				combinedChance *= MutationRoll.EffectiveChance(mutationId, luck, weatherBoosts and weatherBoosts[mutationId])
			end
			local rarestId = mutations[#mutations] -- Order идёт от частых к редким
			local multiple = #mutations > 1
			local percent = combinedChance * 100
			-- Та же логика, что и formatChancePercent в CrystalService.lua
			-- (продублировано, а не вынесено в общий модуль — тут своя
			-- локальная переменная percent, не отдельная функция): растущая
			-- точность до 4 знаков, ниже — "<0.0001%" вместо округления в
			-- незаметный "0.00%" при комбинации нескольких редких мутаций.
			local percentText
			if percent <= 0 then
				percentText = "0%"
			elseif percent >= 1 then
				percentText = ("%.0f%%"):format(percent)
			elseif percent >= 0.1 then
				percentText = ("%.1f%%"):format(percent)
			elseif percent >= 0.01 then
				percentText = ("%.2f%%"):format(percent)
			elseif percent >= 0.001 then
				percentText = ("%.3f%%"):format(percent)
			elseif percent >= 0.0001 then
				percentText = ("%.4f%%"):format(percent)
			else
				percentText = "<0.0001%"
			end
			if Services.AnnounceService then
				Services.AnnounceService:Broadcast(nil, nil, {
					{ Text = ("%s cracked out %s "):format(owner.DisplayName, multiple and "rare" or "a rare"), Color = Color3.new(1, 1, 1) },
					{ Text = table.concat(names, " + "), Color = Config.Mutations[rarestId].Color },
					{ Text = (" %s ("):format(Config.Geodes.Ores[oreId].DisplayName), Color = Color3.new(1, 1, 1) },
					{ Text = percentText .. (multiple and " combined chance" or " chance"), Color = Color3.fromRGB(190, 190, 200) },
					{ Text = ")!", Color = Color3.new(1, 1, 1) },
				})
			end
			if Services.NotifyService then
				Services.NotifyService:Show(owner, ("RARE DROP: <font color=\"#%s\">%s</font> <font color=\"#6FE3FF\">%s</font> (<font color=\"#FFD966\">%s</font>)"):format(
					colorHex(Config.Mutations[rarestId].Color), table.concat(names, " + "),
					Config.Geodes.Ores[oreId].DisplayName, percentText
				), {
					Icon = "Crystal", -- запасной вариант, если вьюпорт по какой-то причине не соберётся на клиенте
					Duration = 3.5, -- покороче обычного тоста (Config.Notify.Duration = 4) — по запросу, "ненадолго"
					RichText = true,
					Viewport = { OreId = oreId, MutationId = rarestId },
				})
			end
		end
		-- Множитель нужен НА САМОМ инстансе: раньше мутации на валунных
		-- кристаллах были чисто косметическими — атрибут RubbleMutations
		-- писался, но нигде не читался для расчёта, и Celestial Titanheart
		-- давал ровно тот же пассивный доход, что обычный. Теперь множитель
		-- едет с кристаллом до самого депозита в коллекцию (см.
		-- RockService:DepositCarrying -> GeodeService:AddCollectionCopy).
		crystal:SetAttribute("MutationMultiplier", MutationRoll.MultiplierFor(mutations))
		local partGroups = MutationVisuals.SplitPartsForMutations(crystal, #mutations)
		for index, mutationId in mutations do MutationVisuals.Apply(crystal, mutationId, root, partGroups and partGroups[index]) end
	end
	-- v14: столб света над редким кристаллом (client/LootBeamFX).
	do
		local oreInfo = Config.Geodes.Ores[oreId]
		local rarity = oreInfo and oreInfo.Rarity
		local lootCfg = Config.BoulderLoot or {}
		if #mutations > 0 then
			local rarest = Config.Mutations[mutations[#mutations]]
			crystal:SetAttribute("LootBeamColor", rarest and rarest.Color or Color3.fromRGB(140, 220, 255))
		elseif rarity and lootCfg.BeamRarities and lootCfg.BeamRarities[rarity] then
			crystal:SetAttribute("LootBeamColor", Config.RarityColors[rarity] or Color3.fromRGB(140, 220, 255))
		end
	end
	local angle = math.random() * math.pi * 2
	local distance = math.random(7, 11)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local targetPosition = position + direction * distance
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { crystal }
	local hit = workspace:Raycast(targetPosition + Vector3.new(0, 12, 0), Vector3.new(0, -100, 0), rayParams)
	local floorPosition = hit and hit.Position or targetPosition
	local land = placeCrystalAtFloor(crystal, root, floorPosition)
	local startPosition = position + Vector3.new(0, 1.4, 0)
	local start = CFrame.new(startPosition)
	pivotInstance(crystal, start)
	setModelPhysics(crystal, true)
	root.Anchored = true
	root.CanCollide = false
	crystal.Parent = workspace
	Sfx.play("RewardCrystal", root)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RubbleCrystalPickup"
	prompt.ActionText = "PICK UP"
	prompt.ObjectText = Config.Geodes.Ores[oreId].DisplayName
	prompt.HoldDuration = Config.Boulders.CrystalPickupHoldDuration
	prompt.Enabled = false
	prompt.ClickablePrompt = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		if RockService:PickupDroppedCrystal(player, crystal) then prompt:Destroy() end
	end)
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local connection = progress.Changed:Connect(function(alpha)
		if not crystal.Parent then return end
		local horizontal = startPosition:Lerp(land.Position, alpha)
		local arcPosition = horizontal + Vector3.new(0, math.sin(alpha * math.pi) * 6, 0)
		pivotInstance(crystal, CFrame.new(arcPosition))
	end)
	local flight = TweenService:Create(progress, TweenInfo.new(0.75, Enum.EasingStyle.Linear), { Value = 1 })
	flight:Play()
	flight.Completed:Connect(function()
		if not crystal.Parent then return end
		pivotInstance(crystal, land)
		connection:Disconnect()
		progress:Destroy()
		task.wait((Config.BoulderLoot and Config.BoulderLoot.CrystalPromptDelay) or 1.25)
		if not crystal.Parent then return end
		prompt.Enabled = true
	end)
	Debris:AddItem(crystal, 120)
end

local function geodeTypeForTier(tier)
	local index = math.clamp(tier, 1, #Config.Geodes.Order)
	local current = Config.Geodes.Order[index]
	local nextType = Config.Geodes.Order[math.min(index + 1, #Config.Geodes.Order)]
	if nextType ~= current and math.random() < Config.Boulders.GeodeNextWeight then return nextType end
	return current
end

function RockService:Init(services)
	Services = services
	local tradeRemote = Instance.new("RemoteEvent")
	tradeRemote.Name = "RubbleCrystalTradeRequest"
	tradeRemote.Parent = ReplicatedStorage.Shared
	local lastGift = {}
	tradeRemote.OnServerEvent:Connect(function(player, target)
		local now = os.clock()
		local last = lastGift[player.UserId]
		if last and now - last < 0.25 then return end
		lastGift[player.UserId] = now
		if typeof(target) == "Instance" and target:IsA("Player") then
			self:GiftCrystal(player, target)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastGift[player.UserId] = nil
	end)
	if Config.BoulderGame and Config.BoulderGame.Enabled then
		self:_startBoulderGame()
		self:_startGoldenBoulder()
	end
	local folder = workspace:FindFirstChild("RubbleBoulderSpawnPoints")
	if not folder then
		warn("[RockService] workspace.RubbleBoulderSpawnPoints not found; add 16 BaseParts for boulder spawns")
	end
	Players.PlayerRemoving:Connect(function(player) self:DropCarrying(player) end)
end

--------------------------------------------------------------------------------
-- ЛИЧНЫЕ ВАЛУНЫ НА БАЗЕ (см. Config.Boulders.Base).
--
-- ЧЕМ ОТЛИЧАЮТСЯ ОТ ОБЫЧНЫХ. Обычные валуны стоят на общих точках
-- workspace.RubbleBoulderSpawnPoints, их тир крутится ротацией, и за них
-- конкурируют все игроки сервера. Эти — привязаны к участку одного игрока,
-- их тир считается от его шахты и кирки, и денег они не дают вообще.
--
-- ПОЧЕМУ ЧЕРЕЗ ТЕ ЖЕ SpawnAtPoint/active/Break. Соблазн был написать им
-- отдельный жизненный цикл, но тогда пришлось бы дублировать мини-игру
-- разбивания, полоску здоровья, осколки, элиту и респавн — то есть
-- половину файла. Вместо этого для каждого маркера создаётся обычная
-- точка-Part с атрибутами Tier и PlotOwnerUserId, и дальше валун живёт по
-- общим правилам; отличается только таблица дропа (см. GrantBoulderRewards)
-- и задержка респавна.
--------------------------------------------------------------------------------

local plotBoulderPoints = {} -- [player] = { Part, ... }

-- Тир базового валуна. Растёт с шахтой, но НИКОГДА не уходит от кирки
-- дальше, чем на Config.BoulderGame.MaxDiffWithPickaxe: валун на 2+ тира
-- выше кирки не ломается ничем, кроме динамита (см. boulderHitsNeeded), и
-- игрок с прокачанной шахтой, но отставшей киркой остался бы с двумя
-- вечными камнями, наглухо запирающими вход в собственную шахту.
local function plotBoulderTier(player)
	local tiers = Services.DataService:GetTiers(player)
	-- Шахта считается по 15-пещерной шкале, валуны — по 9-тировой.
	local fromMine = Config.NineTierForCave(tiers.Mine or 1)
	local pickaxe = tiers.Pickaxe or 1
	if Services.InventoryService then
		local ok, equipped = pcall(Services.InventoryService.GetEquippedPickaxeTier, Services.InventoryService, player)
		if ok and equipped then pickaxe = math.max(pickaxe, equipped) end
	end
	local ceiling = pickaxe + (Config.BoulderGame.MaxDiffWithPickaxe or 1)
	return math.clamp(math.min(fromMine, ceiling), 1, 9)
end

function RockService:SetupPlot(player, plot)
	local markers = plot and plot.BoulderCFrames
	if not markers or #markers == 0 then
		-- Не ошибка сама по себе, но обучение без них физически не может
		-- выдать игроку первую руду — предупреждаем явно, иначе причину
		-- "новичок застрял на первом шаге" пришлось бы искать вслепую.
		warn(("[RockService] В PlotTemplate нет ни одного маркера %s — на базе %s не будет валунов, и обучение не сможет выдать стартовую руду.")
			:format(Config.Boulders.Base.MarkerPrefix, player.Name))
		return
	end
	self:ReleasePlotBoulders(player)
	local tier = plotBoulderTier(player)
	local points = {}
	for index, cframe in markers do
		local point = Instance.new("Part")
		point.Name = ("PlotBoulderPoint_%s_%d"):format(player.Name, index)
		point.Size = Vector3.new(1, 1, 1)
		point.CFrame = cframe
		point.Anchored = true
		point.CanCollide = false
		point.CanQuery = false
		point.CanTouch = false
		point.Transparency = 1
		point:SetAttribute("Tier", tier)
		-- По этому атрибуту GrantBoulderRewards отличает базовый валун от
		-- обычного — таблица дропа у них разная.
		point:SetAttribute("PlotOwnerUserId", player.UserId)
		point.Parent = plot.Content
		table.insert(points, point)
		self:SpawnAtPoint(point, tier)
	end
	plotBoulderPoints[player] = points
end

-- Пересобрать тир после апгрейда шахты/кирки. НЕТРОНУТЫЕ валуны заменяются
-- сразу, а тот, который кто-то уже начал бить, — нет: подменить его значило
-- бы стереть вложенный труд (та же логика, что у state.Damaged в ротации
-- тиров обычных валунов). Он доживёт до слома и респавнится уже новым.
function RockService:RefreshPlotBoulders(player)
	local points = plotBoulderPoints[player]
	if not points then return end
	local tier = plotBoulderTier(player)
	for _, point in points do
		if point.Parent then
			point:SetAttribute("Tier", tier)
			local state = active[point]
			if state and not state.Damaged and state.Tier ~= tier then
				active[point] = nil
				if state.Model and state.Model.Parent then state.Model:Destroy() end
				self:SpawnAtPoint(point, tier)
			end
		end
	end
end

function RockService:ReleasePlotBoulders(player)
	local points = plotBoulderPoints[player]
	if not points then return end
	plotBoulderPoints[player] = nil
	for _, point in points do
		local state = active[point]
		if state then
			active[point] = nil
			if state.Model and state.Model.Parent then state.Model:Destroy() end
		end
		if point.Parent then point:Destroy() end
	end
end

-- Ближайший ЖИВОЙ базовый валун игрока — цель стрелки обучения (см.
-- TutorialService:_resolveTarget). Возвращает nil, когда все сломаны и ещё
-- не респавнились: клиент в этом случае просто прячет стрелку.
function RockService:GetNearestPlotBoulder(player)
	local points = plotBoulderPoints[player]
	if not points then return nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local best, bestDistance = nil, math.huge
	for _, point in points do
		local state = active[point]
		local model = state and state.Model
		if model and model.Parent then
			local distance = root and (model:GetPivot().Position - root.Position).Magnitude or 0
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

function RockService:IsPlotBoulder(state)
	return state ~= nil and state.Point ~= nil and state.Point:GetAttribute("PlotOwnerUserId") ~= nil
end

function RockService:Start()
	local folder = workspace:FindFirstChild("RubbleBoulderSpawnPoints")
	local points = {}
	if folder then
		for _, point in folder:GetChildren() do
			if point:IsA("BasePart") then table.insert(points, point) end
		end
		table.sort(points, function(a, b) return a.Name < b.Name end)
	end
	if #points < Config.Boulders.MaxActive then
		warn(("[RockService] %d RubbleBoulderSpawnPoints found; %d required for the full pool"):format(#points, Config.Boulders.MaxActive))
	end
	local activeCount = math.min(#points, Config.Boulders.MaxActive)

	-- Тир каждой точки: явный атрибут Tier, если проставлен в Studio,
	-- иначе цикл 1..9 по кругу (при 16 точках это само по себе уже
	-- покрывает все 9 тиров минимум одной точкой).
	local tiers = {}
	local countByTier = {}
	for index = 1, activeCount do
		local tier = math.clamp(math.floor(tonumber(points[index]:GetAttribute("Tier")) or (((index - 1) % 9) + 1)), 1, 9)
		tiers[index] = tier
		countByTier[tier] = (countByTier[tier] or 0) + 1
	end

	-- ГАРАНТИЯ "хотя бы один валун на каждый тир 1-9" — на случай, если
	-- вручную расставленные в Studio атрибуты Tier случайно оставили
	-- какой-то тир вообще без единой точки (игрок этого тира остался бы
	-- совсем без доступного валуна). Забираем лишнюю точку у тира, который
	-- представлен больше одного раза, и переставляем на недостающий тир —
	-- ЗАПИСЫВАЕМ атрибут прямо на точку (не только в память), чтобы
	-- поправка сохранялась и при будущих респавнах на этом месте (см.
	-- SpawnAtPoint — он всегда сперва смотрит на атрибут точки).
	for tier = 1, 9 do
		if not countByTier[tier] then
			for index = 1, activeCount do
				local donorTier = tiers[index]
				if countByTier[donorTier] and countByTier[donorTier] > 1 then
					countByTier[donorTier] -= 1
					tiers[index] = tier
					countByTier[tier] = 1
					points[index]:SetAttribute("Tier", tier)
					warn(("[RockService] Тир %d не был представлен ни одной точкой спавна — переназначил точку %s (был тир %d), чтобы у каждого тира был хотя бы один валун."):format(tier, points[index].Name, donorTier))
					break
				end
			end
		end
	end

	for index = 1, activeCount do
		self:SpawnAtPoint(points[index], tiers[index])
	end

	self:_startTierRotation()
end

-- Плавное растворение/проявление модели валуна. Используется только
-- ротацией тиров: там валун не ломается, а тихо подменяется, и резкий скачок
-- выглядел бы как баг подгрузки.
local function fadeBoulder(model, toInvisible, duration, onDone)
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, { Part = descendant, Base = descendant.Transparency })
		end
	end
	local billboard = model:FindFirstChild("BoulderHealth", true)
	if billboard and toInvisible then billboard.Enabled = false end

	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local connection = progress.Changed:Connect(function(alpha)
		for _, entry in parts do
			if entry.Part.Parent then
				entry.Part.Transparency = toInvisible
					and (entry.Base + (1 - entry.Base) * alpha)
					or (1 + (entry.Base - 1) * alpha)
			end
		end
	end)
	if not toInvisible then
		-- Стартуем полностью прозрачными, иначе первый кадр мигнёт.
		for _, entry in parts do entry.Part.Transparency = 1 end
	end
	local tween = TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Quad), { Value = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		connection:Disconnect()
		progress:Destroy()
		if billboard and not toInvisible then billboard.Enabled = true end
		if onDone then onDone() end
	end)
end

-- РОТАЦИЯ ТИРОВ У НЕТРОНУТЫХ ВАЛУНОВ (см. Config.Boulders.TierRotation).
-- Валун, простоявший IdleSeconds без единого удара, подменяется валуном
-- другого тира на той же точке — чтобы раскладка тиров по карте не застывала
-- навсегда в том виде, в каком её расставили в Studio.
function RockService:_startTierRotation()
	local cfg = Config.Boulders.TierRotation
	if not cfg or cfg.Enabled == false then return end

	-- Сколько валунов сейчас приходится на каждый тир. Нужно, чтобы не
	-- нарушить гарантию "хотя бы один валун на каждый тир 1-10", ради
	-- которой выше в Start переназначаются точки: если этот валун —
	-- ЕДИНСТВЕННЫЙ представитель своего тира, менять его нельзя, иначе
	-- игрок этого тира останется вообще без доступной цели.
	local function tierCounts()
		local counts = {}
		for _, state in active do
			counts[state.Tier] = (counts[state.Tier] or 0) + 1
		end
		return counts
	end

	-- Новый тир выбираем среди НАИМЕНЕЕ представленных — так ротация не
	-- просто перемешивает, а выравнивает раскладку по карте.
	local function pickNewTier(currentTier, counts)
		local best, bestCount = nil, math.huge
		for tier = 1, 9 do
			if tier ~= currentTier then
				local count = counts[tier] or 0
				if count < bestCount then best, bestCount = tier, count end
			end
		end
		return best
	end

	local function playerNearby(position)
		local limit = cfg.MinPlayerDistance or 0
		if limit <= 0 then return false end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude <= limit then return true end
		end
		return false
	end

	task.spawn(function()
		while true do
			task.wait(cfg.CheckInterval or 5)
			-- pcall внутри цикла — как и у остальных фоновых циклов в
			-- проекте: одна ошибка не должна навсегда убить ротацию.
			local ok, err = pcall(function()
				local now = os.clock()
				local counts = tierCounts()
				local due = {}
				for point, state in active do
					if not state.Damaged
						and state.Model.Parent
						and state.Health >= state.MaxHealth
						and now - (state.SpawnedAt or now) >= (cfg.IdleSeconds or 90)
						and (counts[state.Tier] or 0) > 1
						and not playerNearby(state.Model:GetPivot().Position)
					then
						table.insert(due, { Point = point, State = state })
					end
				end
				for _, entry in due do
					local state = entry.State
					-- Пересчитываем на каждом шаге: предыдущая подмена в
					-- этом же проходе уже изменила раскладку.
					local liveCounts = tierCounts()
					if (liveCounts[state.Tier] or 0) > 1 and active[entry.Point] == state and not state.Damaged then
						local newTier = pickNewTier(state.Tier, liveCounts)
						if newTier then
							local point, model = entry.Point, state.Model
							-- Снимаем с учёта СРАЗУ: пока идёт растворение,
							-- валун уже не должен находиться FindInHitbox.
							active[point] = nil
							fadeBoulder(model, true, cfg.FadeDuration or 0.35, function()
								if model.Parent then model:Destroy() end
								point:SetAttribute("Tier", newTier)
								local fresh = self:SpawnAtPoint(point, newTier)
								if fresh then
									fadeBoulder(fresh.Model, false, cfg.FadeDuration or 0.35)
								end
							end)
						end
					end
				end
			end)
			if not ok then
				warn("[RockService] Проход ротации тиров валунов упал (цикл продолжает работать):", err)
			end
		end
	end)
end

function RockService:SpawnAtPoint(point, fallbackTier)
	if active[point] then return end
	local tier = math.clamp(math.floor(tonumber(point:GetAttribute("Tier")) or fallbackTier or 1), 1, 9)
	local elite = math.random() < Config.Boulders.EliteChance
	local model = createBoulder(tier, elite)
	local assetRotation = model:GetPivot().Rotation
	-- Случайный разворот, кратный Config.Boulders.SpawnRotationStep — чтобы
	-- одна модель не выглядела штампованной сразу на всех точках.
	--
	-- ВАЖНО: берём от точки спавна ТОЛЬКО ПОЗИЦИЮ, а не весь её CFrame.
	-- Раньше сюда шёл полный поворот точки (point.CFrame + смещение) —
	-- если точка в Studio стоит не идеально ровно (наклонена под склон,
	-- задета в нише и т.п.), валун наследовал этот наклон целиком и мог
	-- выглядеть заваленным набок или вовсе перевёрнутым "с ног на голову".
	-- Сам наклон точки спавна для его ориентации не используется вообще.
	--
	-- Разворот только вокруг ВЕРТИКАЛЬНОЙ оси (Y, yaw): валун крутится по
	-- горизонтали и не заваливается на бок или на другие грани.
	local step = tonumber(Config.Boulders.SpawnRotationStep) or 0
	local spin = CFrame.identity
	if step > 0 then
		local variants = math.max(1, math.floor(360 / step))
		spin = CFrame.Angles(0, math.rad(step * math.random(0, variants - 1)), 0)
	end
	local maxHealth = Config.PickaxeTiers[tier].Damage * 10 * (elite and Config.Boulders.EliteHealthMultiplier or 1)
	model:SetAttribute("Health", maxHealth)
	model:SetAttribute("MaxHealth", maxHealth)
	model:PivotTo(CFrame.new(point.Position + Vector3.new(0, 2.5, 0)) * spin * assetRotation)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	model:PivotTo(model:GetPivot() + Vector3.new(0, point.Position.Y - bottomY, 0))
	-- v19: ХП валуна рисует клиент (client/BoulderHitFX — плашка в стиле
	-- The Forge). Кольцо из партов над камнем и серверный билборд убраны.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") or descendant.Name == "HealthRing" then descendant:Destroy() end
	end
	local state = { Point = point, Model = model, Tier = tier, Elite = elite, Health = maxHealth, MaxHealth = maxHealth, Contributors = {},
		-- Для ротации тиров (см. Config.Boulders.TierRotation и цикл в
		-- Start). SpawnedAt — от какого момента отсчитывается простой,
		-- Damaged — необратимый флаг "по валуну уже били".
		SpawnedAt = os.clock(), Damaged = false }
	active[point] = state
	model.Parent = workspace
	return state
end

-- ГАБАРИТЫ ВАЛУНА ПО ВИДИМОЙ ГЕОМЕТРИИ, А НЕ ПО PrimaryPart.
--
-- ЗАЧЕМ ОТДЕЛЬНАЯ ФУНКЦИЯ: у кастомной модели Boulder_TierN PrimaryPart
-- ("Root") вполне может быть маленькой служебной деталью внутри крупного
-- валуна — все точки "на поверхности" (осколки удара, вспышка попадания)
-- считались от неё и оказывались ГЛУБОКО ВНУТРИ камня, то есть невидимыми.
-- GetBoundingBox даёт реальные габариты того, что игрок видит.
local function boulderBounds(model)
	if model:IsA("Model") then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		return boundsCFrame.Position, boundsSize
	end
	local root = rootOf(model)
	if not root then return model:GetPivot().Position, Vector3.one end
	return root.Position, root.Size
end

-- Точка НА ПОВЕРХНОСТИ валуна со стороны того, кто по нему бьёт, плюс
-- наружная горизонтальная нормаль и радиус камня. Всё, что должно быть
-- видно при ударе (осколки, вспышка), обязано рождаться здесь, а не в
-- центре модели.
local function boulderSurfacePoint(model, fromPosition)
	local center, size = boulderBounds(model)
	local radius = math.max(size.X, size.Z) * 0.5
	local outward = Vector3.new(fromPosition.X - center.X, 0, fromPosition.Z - center.Z)
	outward = outward.Magnitude > 0.05 and outward.Unit or Vector3.new(0, 0, 1)
	-- Чуть выше центра: игрок бьёт киркой примерно в верхнюю половину камня,
	-- а не строго в его геометрический центр по высоте.
	local surface = center + outward * radius * 0.95 + Vector3.new(0, size.Y * 0.12, 0)
	return surface, outward, radius
end

function RockService:FindInHitbox(attacker, hrp, hitboxSize, forwardOffset)
	local half = hitboxSize / 2
	local best, bestDistance
	for _, state in active do
		if state.Model.Parent and state.Health > 0 then
			local position = state.Model:GetPivot().Position
			local localPosition = hrp.CFrame:PointToObjectSpace(position)
			if math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y + 3
				and localPosition.Z >= -forwardOffset - half.Z and localPosition.Z <= -forwardOffset + half.Z then
				local distance = (position - hrp.Position).Magnitude
				if not bestDistance or distance < bestDistance then
					bestDistance = distance
					-- HitPosition остаётся ЦЕНТРОМ валуна: по нему
					-- CombatService повторно проверяет попадание в хитбокс и
					-- выбирает ближайшую жертву (см. findVictim/consider).
					-- Подменять его точкой на поверхности нельзя — это молча
					-- сдвинуло бы саму зону поражения кирки.
					--
					-- SurfacePosition — ОТДЕЛЬНОЕ поле только для визуала:
					-- вспышка удара и всплывающая цифра урона раньше брали
					-- центр модели и рождались ВНУТРИ камня, то есть их не
					-- было видно. consider() перезаписывает HitPosition, но
					-- это поле не трогает, поэтому оно доживает до ApplyHit.
					best = {
						Rock = state,
						Hrp = rootOf(state.Model),
						HitPosition = position,
						SurfacePosition = boulderSurfacePoint(state.Model, hrp.Position),
					}
				end
			end
		end
	end
	return best
end

-- Небольшая тряска при каждом ударе киркой — понятная анимация "по камню
-- реально бьют", а не только при финальном разрушении. Двигаем именно
-- PrimaryPart (Root) — декорации кастомной модели должны быть приварены к
-- нему через WeldConstraint (см. PLACEHOLDERS_GUIDE.md), тогда едут вместе.
local function shakeBoulder(root)
	if not root or not root.Parent then return end
	local baseCFrame = root.CFrame
	local baseSize = root.Size
	local jolt = CFrame.new((math.random() - 0.5) * 0.6, 0, (math.random() - 0.5) * 0.6)
		* CFrame.Angles(0, math.rad((math.random() - 0.5) * 8), 0)
	local shakeOut = TweenService:Create(root, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = baseCFrame * jolt })
	shakeOut:Play()
	-- Небольшой "punch" размера поверх смещения — по прямому запросу
	-- "чтобы камень немного как-то интереснее трясся", без усложнения:
	-- один короткий твин туда-обратно, никакой новой геометрии/партиклов.
	root.Size = baseSize * 1.04
	TweenService:Create(root, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = baseSize }):Play()
	shakeOut.Completed:Once(function()
		if root.Parent then
			TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = baseCFrame }):Play()
		end
	end)
end

-- ОСКОЛКИ ПРИ УДАРЕ — маленькие кубические Part'ы, цвет по тиру (см.
-- Config.Boulders.HitDebrisColors). НЕ используют реальную физику
-- (Anchored = true, дуга разыгрывается двумя твинами) — та же причина, что
-- и у анимации разрушения ниже: одновременно активно до 16 валунов, бьют
-- несколько игроков сразу, реальные физические обломки дали бы всплеск
-- объектов ровно в тот момент, когда сервер и так занят.
--
-- ПОЧЕМУ ОСКОЛКОВ РАНЬШЕ НЕ БЫЛО ВИДНО ВООБЩЕ (главный баг):
--   1) они рождались в root.Position — это ЦЕНТР валуна;
--   2) улетали всего на 1.8–3.2 студа.
-- Плейсхолдер-валун — шар 7x5x6, то есть радиусом ~3.5 студа, а кастомные
-- модели бывают и крупнее. Осколок появлялся внутри камня и внутри же
-- камня умирал, ни разу не показавшись наружу. Код при этом отрабатывал
-- полностью, поэтому в консоли не было ни единой жалобы.
--
-- Теперь точка рождения — ПОВЕРХНОСТЬ валуна со стороны удара
-- (boulderSurfacePoint), а разлёт считается ОТ РАДИУСА камня, а не
-- абсолютным числом студов: на большом валуне осколки летят дальше, на
-- маленьком — ближе, но наружу видно всегда.
local function spawnHitDebris(model, tier, hitPosition)
	if not model or not model.Parent then return end
	local center, size = boulderBounds(model)
	local radius = math.max(size.X, size.Z) * 0.5
	local origin = hitPosition or (center + Vector3.new(0, size.Y * 0.12, 0))
	local color = (Config.Boulders.HitDebrisColors and Config.Boulders.HitDebrisColors[tier]) or Color3.fromRGB(150, 150, 150)
	-- Размер осколка тоже от габаритов камня — на огромной модели крошка в
	-- треть студа была бы неразличима с обычной дистанции.
	local pieceSize = math.clamp(radius * 0.16, 0.3, 0.9)
	local count = 6
	for i = 1, count do
		local piece = Instance.new("Part")
		piece.Name = "BoulderDebris"
		piece.Size = Vector3.one * pieceSize * (0.7 + math.random() * 0.6)
		piece.Color = color
		piece.Material = Enum.Material.Slate
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false

		-- УДАР: разлёт веером НАРУЖУ со стороны бьющего (полукруг) — ровное
		-- кольцо вокруг центра половиной осколков всё равно уходило бы
		-- внутрь валуна.
		-- РАЗРУШЕНИЕ (hitPosition не передан): полное кольцо во все стороны,
		-- и точка старта — на поверхности камня, а не в его центре.
		local direction, startPosition
		local startRotation = CFrame.Angles(math.random() * math.pi, math.random() * math.pi, math.random() * math.pi)
		if hitPosition then
			local outward = Vector3.new(origin.X - center.X, 0, origin.Z - center.Z)
			outward = outward.Magnitude > 0.05 and outward.Unit or Vector3.new(0, 0, 1)
			local spread = (i - 1) / count * math.pi - math.pi * 0.5 + (math.random() - 0.5) * 0.5
			direction = (CFrame.Angles(0, spread, 0) * outward).Unit
			startPosition = origin + direction * 0.2
		else
			local angle = ((i - 1) / count + math.random() * 0.4) * math.pi * 2
			direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			startPosition = origin + direction * radius * 0.85
		end
		piece.CFrame = CFrame.new(startPosition) * startRotation
		piece.Parent = workspace

		-- Верхняя точка дуги и точка падения считаются от радиуса валуна:
		-- гарантированно ЗА пределами модели, как бы её ни собрали.
		local distance = radius * (1.15 + math.random() * 0.75) + 1.5
		local apex = startPosition + direction * distance * 0.55 + Vector3.new(0, 1.4 + math.random() * 1.1, 0)
		local landing = startPosition + direction * distance + Vector3.new(0, -0.5 - math.random() * 0.8, 0)
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)

		-- Настоящая дуга: подъём (Quad/Out) → падение (Quad/In) с
		-- затуханием. Один твин "просто наружу" читался как скольжение по
		-- воздуху, а не как отлетевший кусок камня.
		local rise = TweenService:Create(piece, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(apex) * startRotation * spin,
		})
		rise:Play()
		rise.Completed:Once(function()
			if not piece.Parent then return end
			TweenService:Create(piece, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(landing) * startRotation * spin * spin,
				Transparency = 1,
				Size = piece.Size * 0.35,
			}):Play()
		end)
		Debris:AddItem(piece, 0.65)
	end
end

-- АНИМАЦИЯ РАЗРУШЕНИЯ ВАЛУНА — "замах и усадка" (тайминги и величины:
-- Config.Boulders.BreakFx). Две фазы:
--   1) короткий замах — валун чуть раздувается и приседает (анти-ципация,
--      классический приём: перед резким движением объект сначала уходит в
--      противоход, иначе усадка читается как простое исчезновение);
--   2) УСАДКА — валун быстро уменьшается почти в точку, слегка
--      подкручиваясь, и одновременно растворяется. Низ всё это время
--      прибит к земле, поэтому камень словно осыпается сам в себя, а не
--      парит, уменьшаясь. По прямому запросу это заменило прежний
--      "раздулся и лопнул": хлопок читался как надувной шарик, а не как
--      разрушенный камень.
-- Вспышка, партиклы, ударная волна по земле и разлёт осколков идут ровно в
-- момент начала усадки.
--
-- ПОЧЕМУ САМ ВАЛУН НЕ РАЗЛЕТАЕТСЯ НА ФИЗИЧЕСКИЕ КУСКИ: здесь не создаётся
-- ни одной новой физической детали. Одновременно активно до
-- Config.Boulders.MaxActive (16) валунов, и по каждому может бить
-- несколько игроков — настоящие физические обломки дали бы всплеск
-- объектов ровно в тот момент, когда сервер и так занят выдачей награды.
-- Осколки (spawnHitDebris) — это Anchored-детали на твинах, они дёшевы.
--
-- Работает с ЛЮБЫМ ассетом, без доработки моделей:
--   • кастомная Boulder_TierN (много деталей) — через Model:ScaleTo;
--   • шар-плейсхолдер (одна деталь) — через прямое изменение Size, там
--     замах получается настоящим, неравномерным (ниже и шире).
--
-- Анимация НЕ ЗАДЕРЖИВАЕТ выдачу награды: Break запускает её отдельным
-- task.spawn и тут же идёт дальше (см. вызов ниже). Кристаллы по дуге летят
-- из ещё осыпающегося валуна — так и задумано.
local function playBreakAnimation(model, tier)
	local root = model.PrimaryPart or rootOf(model)
	if not root then model:Destroy(); return end

	local cfg = Config.Boulders.BreakFx
	-- Значения по умолчанию продублированы прямо здесь: если Config.lua
	-- окажется старой версии (без новых ключей), анимация обязана
	-- отработать, а не упасть на арифметике с nil — тот же приём защиты от
	-- рассинхрона, что и в остальных модулях проекта.
	local anticipateDuration = cfg.AnticipateDuration or 0.1
	local shrinkDuration = cfg.ShrinkDuration or 0.34
	local anticipateScale = cfg.AnticipateScale or 1.14
	local anticipateStretch = cfg.AnticipateStretch or 0.9
	local shrinkScale = cfg.ShrinkScale or 0.03
	local spinDegrees = cfg.SpinDegrees or 55
	local total = anticipateDuration + shrinkDuration
	local anticipateEnd = anticipateDuration / total

	-- Полоска здоровья гаснет сразу: иначе всю анимацию над валуном висело бы
	-- "BOULDER LV. 5  0/900".
	local billboard = model:FindFirstChild("BoulderHealth", true)
	if billboard then billboard.Enabled = false end

	-- Исходная прозрачность запоминается У КАЖДОЙ детали отдельно, а не
	-- считается нулевой: в кастомном ассете вполне могут быть полупрозрачные
	-- элементы (стекло, кристаллические жилы), и растворять их надо от их
	-- собственного значения, иначе на первом же кадре они скачком станут
	-- непрозрачными.
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, { Part = descendant, Transparency = descendant.Transparency })
		end
	end
	if model:IsA("BasePart") then table.insert(parts, { Part = model, Transparency = model.Transparency }) end

	local singlePart = #parts == 1 and parts[1].Part == root
	local baseCFrame = root.CFrame
	local baseSize = root.Size
	local basePivot = model:IsA("Model") and model:GetPivot() or baseCFrame
	local baseHalfHeight = baseSize.Y * 0.5
	if model:IsA("Model") and not singlePart then
		local _, boundsSize = model:GetBoundingBox()
		baseHalfHeight = boundsSize.Y * 0.5
	end
	-- Уровень земли под валуном — низ фиксируется здесь на всю анимацию,
	-- чтобы при сжатии он "вдавливался" в землю, а не парил, уменьшаясь.
	local groundY = basePivot.Position.Y - baseHalfHeight

	Sfx.play("BoulderBreak", root)

	local popped = false
	local function pop()
		if popped then return end
		popped = true
		local color = Config.MineTiers[tier] and Config.MineTiers[tier].Color or Color3.new(1, 1, 1)

		-- 1) Бурст партиклов: каменная крошка + пыль, перекрашенные в цвет
		-- тира. Свою версию можно положить как Attachment "BoulderBreakVFX"
		-- в ReplicatedStorage/Assets — см. PlaceholderFactory.
		-- BoulderBreakVFX всегда возвращает Attachment (свой из Assets либо
		-- встроенный плейсхолдер), но раньше при кривом ассете он БРОСАЛ
		-- assert прямо здесь, и валун переставал лопаться вообще —
		-- вместе со всей остальной логикой Break(). Проверка на nil +
		-- pcall делают эффект необязательным: не собрался — валун всё
		-- равно нормально ломается, просто без частиц.
		local okVfx, attachment = pcall(PlaceholderFactory.BoulderBreakVFX)
		if not okVfx then
			warn("[RockService] BoulderBreakVFX не собрался:", attachment)
			attachment = nil
		end
		local vfxHolder = Instance.new("Part")
		vfxHolder.Name = "BoulderBreakVFXHolder"
		vfxHolder.Size = Vector3.new(0.2, 0.2, 0.2)
		-- Центр ВИДИМОГО валуна, а не PrimaryPart: у кастомной модели
		-- PrimaryPart может стоять где угодно внутри (или сбоку), и бурст
		-- частиц уезжал бы мимо самого камня.
		vfxHolder.CFrame = CFrame.new(basePivot.Position)
		vfxHolder.Transparency = 1
		vfxHolder.Anchored = true
		vfxHolder.CanCollide = false
		vfxHolder.CanTouch = false
		vfxHolder.CanQuery = false
		vfxHolder.CastShadow = false
		vfxHolder.Parent = workspace
		local maxParticleLifetime = 0
		if attachment then
			attachment.Parent = vfxHolder
			for _, emitter in attachment:GetDescendants() do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = false
					emitter.Color = ColorSequence.new(color)
					emitter:Emit(math.max(1, math.floor(tonumber(emitter:GetAttribute("EmitCount")) or 10)))
					maxParticleLifetime = math.max(maxParticleLifetime, emitter.Lifetime.Max)
				end
			end
		end
		Debris:AddItem(vfxHolder, math.max(1, maxParticleLifetime + 0.25))

		-- 2) Вспышка света в момент разлома. Гаснет за то же время, что идёт
		-- усадка, поэтому не остаётся висеть после исчезновения валуна.
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Brightness = 6
		flash.Range = 26
		flash.Shadows = false
		flash.Parent = root
		TweenService:Create(flash, TweenInfo.new(shrinkDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0,
			Range = 8,
		}):Play()

		-- 2.5) РАЗЛЁТ ОСКОЛКОВ — теперь и при разрушении, а не только при
		-- обычных ударах. Раньше камень исчезал совсем без обломков, из-за
		-- чего конец добычи читался слабее самого процесса. Осколки летят
		-- по кругу от центра, поэтому hitPosition сюда не передаём.
		for _ = 1, math.max(1, math.floor(tonumber(cfg.BreakDebrisBursts) or 3)) do
			spawnHitDebris(model, tier, nil)
		end

		-- 3) Ударная волна по земле — плоское кольцо, разлетающееся наружу.
		-- Отдельная деталь, НЕ привязанная к модели валуна: та вот-вот
		-- удалится, а волна должна доиграть. Anchored + CanCollide=false +
		-- CanQuery=false, чтобы ни во что не упереться и не ловить лучи.
		local wave = Instance.new("Part")
		wave.Name = "BoulderBreakShockwave"
		wave.Shape = Enum.PartType.Cylinder
		wave.Size = Vector3.new(0.4, 4, 4)
		wave.CFrame = CFrame.new(groundY and Vector3.new(basePivot.Position.X, groundY + 0.3, basePivot.Position.Z) or root.Position)
			* CFrame.Angles(0, 0, math.rad(90))
		wave.Color = color
		wave.Material = Enum.Material.Neon
		wave.Transparency = 0.35
		wave.Anchored = true
		wave.CanCollide = false
		wave.CanQuery = false
		wave.CanTouch = false
		wave.CastShadow = false
		wave.Parent = workspace
		local waveSize = 10 + tier * 2.5 -- крупный тир — заметнее волна
		TweenService:Create(wave, TweenInfo.new(shrinkDuration * 1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.4, waveSize, waveSize),
			Transparency = 1,
		}):Play()
		Debris:AddItem(wave, shrinkDuration * 1.6 + 0.2)
	end

	-- Тот же приём, что в spawnLooseCrystal выше: TweenService не умеет
	-- анимировать вызов метода (Model:ScaleTo), поэтому твиним обычный
	-- NumberValue и пересчитываем всё в его Changed.
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local connection
	connection = progress.Changed:Connect(function(t)
		if not root.Parent then return end
		local uniform, stretch, spin
		if t <= anticipateEnd then
			-- ФАЗА 1 — замах: короткий "вдох" перед усадкой.
			local alpha = TweenService:GetValue(t / anticipateEnd, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			uniform = 1 + (anticipateScale - 1) * alpha
			stretch = 1 + (anticipateStretch - 1) * alpha
			spin = 0
		else
			-- ФАЗА 2 — УСАДКА: камень уменьшается почти в точку и
			-- растворяется. Back/In — сначала едва заметно "подтягивается"
			-- обратно, потом уходит в ноль резко: так усадка читается как
			-- обрушение, а не как плавное затухание прозрачности.
			pop() -- вспышка/партиклы/волна/осколки ровно в начале усадки, один раз
			local raw = (t - anticipateEnd) / (1 - anticipateEnd)
			local alpha = TweenService:GetValue(raw, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			uniform = anticipateScale + (shrinkScale - anticipateScale) * alpha
			stretch = anticipateStretch + (shrinkScale - anticipateStretch) * alpha
			spin = math.rad(spinDegrees) * raw
			-- Прозрачность догоняет размер с отставанием (raw^1.6): камень
			-- успевает заметно уменьшиться, пока ещё непрозрачен, и только
			-- в самом конце исчезает. Если растворять линейно, он выглядит
			-- полупрозрачным почти всю анимацию.
			local fade = raw ^ 1.6
			for _, entry in parts do
				if entry.Part.Parent then
					entry.Part.Transparency = entry.Transparency + (1 - entry.Transparency) * fade
				end
			end
		end
		-- Отрицательный масштаб физически невозможен (Size/ScaleTo его не
		-- принимают) — Back/In на последних кадрах способен увести
		-- значение ниже нуля, поэтому подрезаем снизу.
		uniform = math.max(uniform, 0.01)
		stretch = math.max(stretch, 0.01)

		if singlePart then
			-- Настоящее неравномерное сжатие: ниже и одновременно шире.
			local newSize = Vector3.new(baseSize.X * stretch, baseSize.Y * uniform, baseSize.Z * stretch)
			root.Size = newSize
			root.CFrame = CFrame.new(baseCFrame.Position.X, groundY + newSize.Y * 0.5, baseCFrame.Position.Z)
				* (baseCFrame - baseCFrame.Position)
				* CFrame.Angles(0, spin, 0)
		elseif model:IsA("Model") then
			-- ScaleTo умеет только равномерно, зато не ломает сварку деталей
			-- кастомной модели. Низ докручиваем сами через PivotTo, чтобы
			-- камень оседал В ЗЕМЛЮ, а не парил, уменьшаясь.
			model:ScaleTo(uniform)
			model:PivotTo((basePivot + Vector3.new(0, baseHalfHeight * (uniform - 1), 0)) * CFrame.Angles(0, spin, 0))
		end
	end)

	local tween = TweenService:Create(progress, TweenInfo.new(total, Enum.EasingStyle.Linear), { Value = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		connection:Disconnect()
		progress:Destroy()
		if model.Parent then model:Destroy() end
	end)
	-- Страховка: если твин по любой причине не доиграет (модель убрали
	-- извне, ошибка в обработчике), валун не должен остаться висеть в мире
	-- полупрозрачным и раздутым.
	Debris:AddItem(model, total + 1)
end

function RockService:Damage(state, player, damage)
	damage = tonumber(damage)
	if not damage or damage ~= damage or math.abs(damage) == math.huge or damage <= 0 then return 0 end
	if not state or not state.Model.Parent or state.Health <= 0 then return 0 end
	local playerTier = Services.DataService:GetBranchTier(player, "Pickaxe")
	local difference = state.Tier - playerTier
	if difference >= 3 then
		Services.NotifyService:Show(player, ("Not strong enough — requires at least tier %d"):format(state.Tier - 2), { Icon = "Pickaxe" })
		return 0
	end
	local multiplier = difference == 2 and Config.Boulders.GroupDamageMultiplier or 1
	local dealt = damage * multiplier
	local healthBefore = state.Health
	state.Health = math.max(0, state.Health - dealt)
	-- Валун "тронут" — с этого момента ротация тиров его не подменит уже
	-- никогда (см. Config.Boulders.TierRotation). Флаг ставится ЗДЕСЬ, а не
	-- по факту урона больше нуля: даже удар с групповым штрафом
	-- GroupDamageMultiplier — это вложенный игроком труд.
	state.Damaged = true
	state.Contributors[player] = true
	state.Model:SetAttribute("Health", state.Health)
	-- v19: цифра урона/виньетка (client/BoulderHitFX).
	if player and player.Parent and healthBefore > state.Health then
		local hitHrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		hitFxRemote:FireClient(player, state.Model, math.floor(healthBefore - state.Health + 0.5), "Good", state.Health <= 0,
			hitHrp and boulderSurfacePoint(state.Model, hitHrp.Position) or nil)
	end
	if state.Health > 0 then
		shakeBoulder(state.Model.PrimaryPart)
		-- Осколки строятся от МОДЕЛИ (её реальных габаритов) и от точки на
		-- поверхности со стороны бьющего, а не от PrimaryPart: у кастомного
		-- ассета PrimaryPart может быть крошечной служебной деталью внутри
		-- камня, и всё, что от неё отсчитывается, оказывается под геометрией.
		local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local hitPosition = hrp and boulderSurfacePoint(state.Model, hrp.Position) or nil
		spawnHitDebris(state.Model, state.Tier, hitPosition)
	end
	if state.Health <= 0 then self:Break(state, player) end
	return math.min(dealt, healthBefore)
end

--------------------------------------------------------------------------------
-- ДРОП БАЗОВОГО ВАЛУНА — руда пещеры игрока, без денег (см.
-- Config.Boulders.Base). Куски ложатся в ту же кучу, что и руда из шахты
-- (workspace.MineGroundOre), поэтому подбираются проходом в рюкзак ИЛИ
-- собираются наездом тележки: один и тот же камень работает и до первой
-- тележки, и после неё.
--------------------------------------------------------------------------------
local function spawnBaseBoulderOre(player, position, count)
	if not Services.CrystalService then return 0, {} end
	local cfg = Config.Boulders.Base
	local lootCfg = Config.BoulderLoot or {}
	local mineTier = Services.DataService:GetTiers(player).Mine or 1

	-- v14: РУДА ВЫЛЕТАЕТ ИЗ ВАЛУНА ПО ДУГЕ. Раньше куски телепортировались в
	-- точку «над валуном + 1.2» без проверки пола: висели в воздухе, тонули
	-- в земле или в самом камне и появлялись все разом. Теперь — тот же
	-- полёт, что у руды из шахты (MineService:EjectToGround: сквош/стретч,
	-- трейл, посадка на пол по рейкасту, левитация), по одному куску с
	-- интервалом StaggerSeconds, веером вокруг валуна. Подбирать (ногами,
	-- тележкой) можно только через PickupDelay после приземления — игрок
	-- успевает увидеть, что именно выпало.
	local folder = workspace:FindFirstChild("MineGroundOre")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MineGroundOre"
		folder.Parent = workspace
	end

	local created = {}
	for _ = 1, count do
		local ok, crystal = pcall(function()
			return Services.CrystalService:Create(mineTier, player, nil, "Boulder")
		end)
		if ok and crystal then table.insert(created, crystal) end
	end
	local stagger = lootCfg.StaggerSeconds or 0.12
	local flight = lootCfg.FlightSeconds or 0.75
	local startAngle = math.random() * math.pi * 2
	for index, crystal in created do
		local rarity = crystal:GetAttribute("CrystalRarity")
		if rarity and lootCfg.BeamRarities and lootCfg.BeamRarities[rarity] then
			crystal:SetAttribute("LootBeamColor", Config.RarityColors[rarity] or Color3.new(1, 1, 1))
		end
		crystal:SetAttribute("BoulderLoot", true)
		local delaySeconds = (index - 1) * stagger
		crystal:SetAttribute("PickupRetryAt", os.clock() + delaySeconds + flight + (lootCfg.PickupDelay or 1.8))
		task.delay(delaySeconds, function()
			if not player.Parent then crystal:Destroy() return end
			local angle = startAngle + (index - 1) / math.max(1, #created) * math.pi * 2 + (math.random() - 0.5) * 0.6
			local spreadMin = lootCfg.SpreadMin or 4
			local spreadMax = lootCfg.SpreadMax or (cfg.OreSpreadStuds or 8)
			local distance = spreadMin + math.random() * (spreadMax - spreadMin)
			local land = position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local ejected = false
			if Services.MineService and Services.MineService.EjectToGround then
				local ok, result = pcall(Services.MineService.EjectToGround, Services.MineService, player, crystal, position, land, flight, lootCfg.ArcHeight or 7)
				ejected = ok and result == true
			end
			if not ejected then
				-- Запасной путь (нет MineService): кладём на пол по рейкасту.
				local root = CrystalUtil.GetRoot(crystal)
				if root then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { crystal, folder }
					local hit = workspace:Raycast(land + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
					root.CFrame = CFrame.new((hit and hit.Position or land) + Vector3.new(0, root.Size.Y / 2 + 0.3, 0))
					root.Anchored = true
					root.CanCollide = false
				end
				crystal:SetAttribute("GroundOreOwner", player.UserId)
				crystal:SetAttribute("Landed", true)
				crystal:SetAttribute("PickupReady", true)
				crystal.Parent = folder
			end
		end)
	end
	return #created, created
end

-- v14: бросок реликвии (Config.Relics). Выдача йилдит (серийник из
-- DataStore), поэтому идёт отдельным потоком; в ленту лута пишем сразу.
function RockService:_rollRelicReward(player, tier, rich, result, options)
	local decor = Services.BaseDecorService
	if not decor then return end
	options = options or {}
	local streakCfg = Config.BoulderGame.Streak or {}
	local streakBonus = math.max(0, (options.Streak or 0) - (streakCfg.Min or 2) + 1) * (streakCfg.RelicBonusPerStreak or 0)
	local relicId
	if options.Golden then
		if options.IsBreaker or math.random() < (Config.GoldenBoulder.ContributorRelicChance or 0) then
			relicId = decor:RollRelic(player, tier, { Golden = true })
		end
	else
		relicId = decor:RollRelic(player, tier, {
			Plot = options.PlotBoulder == true,
			Perfect = result ~= nil and (result.ExtraRolls or 0) > 0,
			StreakBonus = streakBonus,
		})
	end
	if not relicId then return end
	local info = Config.Relics.Types[relicId]
	table.insert(rich, 1, { Kind = "Relic", Icon = info.Icon, Rarity = info.Rarity, Text = info.DisplayName, Color = info.Color })
	task.spawn(function()
		local ok, err = pcall(decor.GrantRelic, decor, player, relicId, options.Golden and "GoldenBoulder" or "Boulder")
		if not ok then warn("[RockService] выдача реликвии упала:", err) end
	end)
end

function RockService:GrantBoulderRewards(player, tier, position, deferNotification, result, options)
	-- БАЗОВЫЙ ВАЛУН — своя, отдельная таблица дропа. Пропускаем весь роллер
	-- ниже целиком: там деньги занимают 72.5% весов, а на первом тире это
	-- сразу $67 с камня — новичок покупал бы шахту, ни разу не узнав, где
	-- вообще находится банк, и шаг «продай руду» схлопывался бы сам собой.
	if options and options.PlotBoulder then
		local cfg = Config.Boulders.Base
		local repaired = not Services.TutorialService or Services.TutorialService:IsMineRepaired(player)
		local range = repaired and cfg.OreCountRepaired or cfg.OreCountBroken
		local count = math.random(range[1], range[2])
		-- Пока шахта сломана, суммарная стоимость руды со ВСЕХ базовых
		-- валунов участка обязана дотянуть до цены починки. Делим цель на
		-- число валунов и на число кусков — каждый кусок получает свой пол.
		-- УДАЛЕНА ПОДТЯЖКА ЦЕНЫ СТАРТОВОЙ РУДЫ. Раньше стоимость руды с
		-- базовых валунов искусственно задиралась до цены починки шахты:
		-- в прологе был шаг "продай руду, чтобы накопить", и без надбавки
		-- честный ролл пещеры 1 на него не хватал. Теперь починка и первая
		-- тележка бесплатны, копить не на что, и руда стоит ровно столько,
		-- сколько стоит.
		local _, crystals = spawnBaseBoulderOre(player, position, count)

		local rich = {}
		-- Лента лута: руда по названию и редкости («Iron x2»).
		local grouped, order = {}, {}
		for _, crystal in crystals do
			local name = crystal:GetAttribute("CrystalName") or "Ore"
			local rarity = crystal:GetAttribute("CrystalRarity") or "Common"
			local key = name .. "|" .. rarity
			if not grouped[key] then
				grouped[key] = { Name = name, Rarity = rarity, Count = 0 }
				table.insert(order, key)
			end
			grouped[key].Count += 1
		end
		for _, key in order do
			local entry = grouped[key]
			table.insert(rich, {
				Kind = "Ore", Icon = "⛏️", Rarity = entry.Rarity,
				Text = entry.Count > 1 and ("%s x%d"):format(entry.Name, entry.Count) or entry.Name,
				Color = Config.RarityColors[entry.Rarity] or Color3.fromRGB(140, 220, 255),
			})
		end
		self:_rollRelicReward(player, tier, rich, result, options)
		if math.random() < (cfg.GeodeChance or 0) then
			local geodeType = geodeTypeForTier(tier)
			local color = Config.Geodes.Types[geodeType] and Config.Geodes.Types[geodeType].Color or Color3.new(1, 1, 1)
			table.insert(rich, { Kind = "Geode", Icon = "🪨", Text = tostring(geodeType), Color = color })
			-- ЗАЧИСЛЕНИЕ — В ОТДЕЛЬНОЙ КОРУТИНЕ. AddGeodesAndSave ходит в
			-- DataStore, а UpdateBuilding пересобирает модель хранилища; и
			-- то и другое висело прямо на кадре разбития валуна и давало
			-- заметный подвис ровно в момент удара. Карточка дропа при этом
			-- показывается сразу — игрок видит награду мгновенно, а запись
			-- догоняет через мгновение.
			task.spawn(function()
				local transactionId = HttpService:GenerateGUID(false)
				local ok = Services.DataService:AddGeodesAndSave(player, { [geodeType] = 1 }, transactionId)
				if not ok then return end
				Services.GeodeService:UpdateBuilding(player)
				Services.GeodeService:SendState(player)
				if Services.TutorialService then
					pcall(function() Services.TutorialService:ShowHint(player, "FirstGeode") end)
				end
			end)
		end
		return {}, rich
	end

	local rewardCount = math.random() < Config.Boulders.RewardCountExtraChance and math.random(2, 3) or 1
	-- v8: качество мини-игры — доп. роллы и множитель денег.
	rewardCount += result and result.ExtraRolls or 0
	local moneyMult = result and result.MoneyMult or 1
	-- v14: серия PERFECT подряд и Золотой валун.
	local streakCfg = Config.BoulderGame.Streak
	if streakCfg and options and (options.Streak or 0) >= streakCfg.Min then
		rewardCount += streakCfg.ExtraRolls or 0
	end
	if options and options.Golden and Config.GoldenBoulder then
		rewardCount += Config.GoldenBoulder.ExtraRolls or 0
		moneyMult *= Config.GoldenBoulder.MoneyMult or 1
	end
	local rewardIndex = 0
	local lootStagger = (Config.BoulderLoot and Config.BoulderLoot.RewardStagger) or 0.15
	local crystalRolled = false
	local geodeCounts = {}
	local drops = {}
	local rich = {} -- v9: для красивой карточки дропа у клиента
	for _ = 1, rewardCount do
		rewardIndex += 1
		local visualDelay = (rewardIndex - 1) * lootStagger
		local odds = Config.Boulders.RewardOdds
		local crystalChance = crystalRolled and 0 or odds.Crystal
		local moneyChance = odds.Money + (crystalRolled and odds.Crystal or 0)
		local roll = math.random()
		local kind
		if roll < moneyChance then
			kind = "Money"
		elseif roll < moneyChance + odds.Geode then
			kind = "Geode"
		elseif not crystalRolled and roll < moneyChance + odds.Geode + crystalChance then
			kind = "Crystal"
		else
			kind = "Skin"
		end
		if kind == "Money" then
			local amount = math.max(1, math.floor(Config.Boulders.RewardMoneyByTier[tier] * moneyMult))
			table.insert(drops, "MONEY: $" .. NumberFormat.abbreviate(amount))
			table.insert(rich, { Kind = "Money", Icon = "💰", Text = "$" .. NumberFormat.abbreviate(amount), Color = Color3.fromRGB(110, 255, 140) })
			Services.DataService:AddMoney(player, amount, position, true) -- suppressCoinBurst: визуал даёт SpawnLooseReward ниже, не нужен второй одновременно
			if Services.GoblinService then
				task.delay(visualDelay, function()
					Services.GoblinService:SpawnLooseReward(player, "Money", nil, position, Config.CoinFx.CoinColor)
				end)
			end
		elseif kind == "Geode" then
			local geodeType = geodeTypeForTier(tier)
			geodeCounts[geodeType] = (geodeCounts[geodeType] or 0) + 1
			table.insert(drops, "GEODE: " .. geodeType)
			table.insert(rich, { Kind = "Geode", Icon = "🪨", Text = tostring(geodeType), Color = Config.Geodes.Types[geodeType] and Config.Geodes.Types[geodeType].Color or Color3.new(1, 1, 1) })
			if Services.GoblinService then
				local geodeColor = Config.Geodes.Types[geodeType] and Config.Geodes.Types[geodeType].Color or Color3.new(1, 1, 1)
				task.delay(visualDelay, function()
					Services.GoblinService:SpawnLooseReward(player, "Geode", geodeType, position, geodeColor)
				end)
			end
		elseif kind == "Crystal" then
			crystalRolled = true
			local oreId = ORE_BY_TIER[tier]
			table.insert(drops, "CRYSTAL: " .. (Config.Geodes.Ores[oreId].DisplayName or oreId))
			local oreRarity = Config.Geodes.Ores[oreId].Rarity or "Rare"
			table.insert(rich, { Kind = "Crystal", Icon = "💎", Rarity = oreRarity, Text = Config.Geodes.Ores[oreId].DisplayName or oreId, Color = Config.RarityColors[oreRarity] or Color3.fromRGB(140, 220, 255) })
			task.delay(visualDelay, function()
				spawnLooseCrystal(oreId, tier, position, nil, player, "Boulder")
			end)
		else
			-- v18: скины падают ТОЛЬКО из сундуков — бывший «скин с валуна»
			-- стал Rare-сундуком (в нём пиратские скины).
			if Services.GearService then Services.GearService:GrantChest(player, "Rare", 1, true) end
			local chestColor = Config.Chests.Types.Rare.Color
			table.insert(drops, "RARE CHEST")
			table.insert(rich, { Kind = "Chest", Icon = "🎁", Rarity = "Rare", Text = "Rare Chest", Color = chestColor })
			if Services.GoblinService then
				Services.GoblinService:SpawnLooseReward(player, "Skin", nil, position, chestColor)
			end
		end
	end
	self:_rollRelicReward(player, tier, rich, result, options)
	if Services.NotifyService and #drops > 0 and not deferNotification then
		-- Читаемый заголовок вместо технического "BOULDER T5 DROP:".
		Services.NotifyService:Show(player, ("You cracked a tier %d boulder!\n%s"):format(tier, table.concat(drops, "\n")), {
			Duration = 4,
			TextColor = Color3.new(1, 1, 1),
			Icon = "Boulder",
		})
	end
	if next(geodeCounts) then
		-- Как и AddGeodeDirectly в GeodeService — идём через настоящий
		-- транзакционный API с durable-сохранением, а не пишем в
		-- data.Geodes напрямую. Иначе награда живёт только в памяти (может
		-- потеряться при краше до следующего автосейва) и жеода-UI игрока
		-- не обновится, пока не случится какой-то другой рефреш.
		local transactionId = HttpService:GenerateGUID(false)
		if Services.DataService:AddGeodesAndSave(player, geodeCounts, transactionId) then
			Services.GeodeService:UpdateBuilding(player)
			Services.GeodeService:SendState(player)
		end
	end
	return drops, rich
end

--------------------------------------------------------------------------------
-- v8 — МИНИ-ИГРА ВАЛУНОВ (Config.BoulderGame). Первый удар киркой по валуну
-- открывает у игрока панель справа от камня: бегунок ходит вверх-вниз,
-- клик = удар с оценкой. Сервер САМ знает, где был бегунок (фаза от
-- момента открытия + скорость), и принимает присланное клиентом значение
-- только если оно совпадает с серверной траекторией в окне пинга.
-- Прогресс валуна общий (несколько игроков), качество — у каждого своё.
--------------------------------------------------------------------------------
local boulderSessions = {} -- [player] = { State, Need, StartedAt, Speed, Zones, LastStrike, LastActivity }
local boulderRemote = nil

local function equippedPickaxeTierFor(player)
	local tier = Services.DataService:GetBranchTier(player, "Pickaxe")
	if Services.InventoryService then
		local ok, equipped = pcall(Services.InventoryService.GetEquippedPickaxeTier, Services.InventoryService, player)
		if ok and equipped then tier = equipped end
	end
	return tier
end

local function boulderHitsNeeded(boulderTier, pickaxeTier)
	local cfg = Config.BoulderGame
	local diff = boulderTier - pickaxeTier
	if diff <= cfg.InstantBelowDiff then return 1 end
	if diff > cfg.MaxDiffWithPickaxe then return nil end
	return cfg.HitsByDiff[diff]
end

local function runnerSpeedFor(tier)
	local cfg = Config.BoulderGame
	return cfg.RunnerCyclesPerSecond + cfg.RunnerSpeedPerTier * math.max(0, tier - 1)
end

-- Треугольная волна 0..1..0 — ровно та же формула на клиенте.
local function runnerAt(elapsed, speed)
	local phase = (elapsed * speed) % 1
	return phase < 0.5 and phase * 2 or (1 - phase) * 2
end

local function statFor(player, stat)
	if Services.PrestigeService then
		local ok, value = pcall(Services.PrestigeService.Stat, Services.PrestigeService, player, stat)
		if ok and value then return value end
	end
	return 0
end

local function rollZones(player)
	local cfg = Config.BoulderGame
	local goodWidth = cfg.GoodWidth
	local perfectWidth = math.clamp(cfg.PerfectWidth * (1 + statFor(player, "Perfect")), 0.03, goodWidth)
	local goodMin = 0.04 + math.random() * (0.92 - goodWidth)
	local perfectMin = goodMin + math.random() * (goodWidth - perfectWidth)
	return { GoodMin = goodMin, GoodMax = goodMin + goodWidth, PerfectMin = perfectMin, PerfectMax = perfectMin + perfectWidth }
end

local function gradeFor(value, zones)
	if value >= zones.PerfectMin and value <= zones.PerfectMax then return "Perfect" end
	if value >= zones.GoodMin and value <= zones.GoodMax then return "Good" end
	return "Miss"
end

local function resultFor(quality)
	for _, row in Config.BoulderGame.Results do
		if quality >= row.Min then return row end
	end
	return Config.BoulderGame.Results[#Config.BoulderGame.Results]
end

local function boulderCenter(state)
	local model = state.Model
	if model:IsA("Model") then
		return model:GetBoundingBox().Position
	end
	return model.Position
end

local function recordQuality(state, player, score)
	state.Quality = state.Quality or {}
	local entry = state.Quality[player] or { Sum = 0, Count = 0 }
	entry.Sum += score
	entry.Count += 1
	state.Quality[player] = entry
	state.Contributors[player] = true
end

local function applyProgress(self, state, player, gain, grade)
	local healthBefore = state.Health
	state.Progress = math.min(1, (state.Progress or 0) + gain)
	state.Damaged = true
	state.Health = math.max(0, state.MaxHealth * (1 - state.Progress))
	state.Model:SetAttribute("Health", state.Health)
	local dealt = math.max(0, (healthBefore or state.MaxHealth) - state.Health)
	if player and player.Parent and dealt > 0 then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local hitPoint = hrp and boulderSurfacePoint(state.Model, hrp.Position) or nil
		hitFxRemote:FireClient(player, state.Model, math.floor(dealt + 0.5), grade or "Good", state.Health <= 0, hitPoint)
	end
	-- v14: клиент подсвечивает трещины изнутри по этому атрибуту.
	state.Model:SetAttribute("CrackProgress", state.Progress)
	if state.Progress < 1 then
		shakeBoulder(state.Model.PrimaryPart or rootOf(state.Model))
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		spawnHitDebris(state.Model, state.Tier, hrp and boulderSurfacePoint(state.Model, hrp.Position) or nil)
	else
		self:Break(state, player)
	end
end

-- v10: 🎯 Perfect Strike купили ПРЯМО во время мини-игры — добиваем валун
-- сразу на PERFECT (заряд тратится). Нет сессии — заряд ждёт следующего валуна.
function RockService:ForcePerfect(player)
	local session = boulderSessions[player]
	if not (session and session.State and session.State.Model.Parent) then return false end
	local profile = Services.DataService:GetGeodeData(player)
	if not profile or (tonumber(profile.PerfectStrikes) or 0) <= 0 then return false end
	profile.PerfectStrikes -= 1
	player:SetAttribute("PerfectStrikes", profile.PerfectStrikes)
	local state = session.State
	state.Quality = state.Quality or {}
	state.Quality[player] = { Sum = Config.BoulderGame.Grades.Perfect, Count = 1 }
	state.Contributors[player] = true
	applyProgress(self, state, player, 1)
	return true
end

function RockService:HasSession(player)
	local session = boulderSessions[player]
	return session ~= nil and session.State.Model.Parent ~= nil
end

function RockService:_closeSession(player, payload)
	if boulderSessions[player] then
		boulderSessions[player] = nil
		if boulderRemote and player.Parent then
			boulderRemote:FireClient(player, "Close", payload or {})
		end
	end
end

-- Удар киркой (через обычный хитбокс) по валуну.
function RockService:OnPickaxeHit(state, player)
	if not state or not state.Model.Parent or (state.Progress or 0) >= 1 then return end
	local pickaxeTier = equippedPickaxeTierFor(player)
	local need = boulderHitsNeeded(state.Tier, pickaxeTier)
	if not need then
		Services.NotifyService:Show(player, ("Too tough for your pickaxe — use DYNAMITE (or pickaxe tier %d)"):format(state.Tier - Config.BoulderGame.MaxDiffWithPickaxe), { Icon = "Pickaxe" })
		return
	end
	-- v10: 🎯 PERFECT STRIKE (микротранзакция) — валун сразу ломается на PERFECT.
	local profile = Services.DataService:GetGeodeData(player)
	if profile and (tonumber(profile.PerfectStrikes) or 0) > 0 then
		profile.PerfectStrikes -= 1
		player:SetAttribute("PerfectStrikes", profile.PerfectStrikes)
		recordQuality(state, player, Config.BoulderGame.Grades.Perfect)
		applyProgress(self, state, player, 1)
		return
	end
	-- v10: 🚀 ракетная кирка слабо копает — ударов на валун больше.
	if Services.CombatService and Services.CombatService.IsRocketActive and Services.CombatService:IsRocketActive(player) then
		need = math.max(2, math.ceil(need * (Config.RocketPickaxe.BoulderHitsMultiplier or 1.8)))
	end
	-- v14: Золотой валун — ударов больше, прогресс общий, мгновенно не ломается.
	if state.Golden and Config.GoldenBoulder then
		need = math.max(3, math.ceil(need * (Config.GoldenBoulder.HitsMultiplier or 2)))
	end
	if need == 1 then
		-- Совсем слабый валун — ломается с одного удара, без мини-игры.
		recordQuality(state, player, Config.BoulderGame.Grades.Good)
		applyProgress(self, state, player, 1)
		return
	end
	local existing = boulderSessions[player]
	if existing and existing.State == state then return end
	if existing then self:_closeSession(player) end
	local now = os.clock()
	local session = {
		State = state,
		Need = need,
		StartedAt = now,
		Speed = runnerSpeedFor(state.Tier),
		Zones = rollZones(player),
		LastStrike = 0,
		LastActivity = now,
	}
	boulderSessions[player] = session
	state.Contributors[player] = true
	boulderRemote:FireClient(player, "Open", {
		Boulder = state.Model,
		Tier = state.Tier,
		Need = need,
		Progress = state.Progress or 0,
		Speed = session.Speed,
		Zones = session.Zones,
		Golden = state.Golden == true,
	})
end

function RockService:_strike(player, value)
	local cfg = Config.BoulderGame
	local session = boulderSessions[player]
	if not session then return end
	local state = session.State
	if not state.Model.Parent or (state.Progress or 0) >= 1 then
		self:_closeSession(player)
		return
	end
	local now = os.clock()
	if state.PendingBreak then return end
	if now - session.LastStrike < cfg.StrikeCooldown then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - boulderCenter(state)).Magnitude > cfg.SessionRange then
		self:_closeSession(player, { Reason = "TooFar" })
		return
	end
	value = tonumber(value)
	local elapsed = now - session.StartedAt
	local serverValue = runnerAt(math.max(0, elapsed - 0.1), session.Speed)
	local accepted = serverValue
	if value and value == value and value >= 0 and value <= 1 then
		local t = elapsed
		local floor = math.max(0, elapsed - cfg.LatencyWindow)
		while t >= floor do
			if math.abs(runnerAt(t, session.Speed) - value) <= cfg.Tolerance then
				accepted = value
				break
			end
			t -= 0.012
		end
	end
	session.LastStrike = now
	session.LastActivity = now
	local grade = gradeFor(accepted, session.Zones)
	local score = cfg.Grades[grade] or 0
	recordQuality(state, player, score)
	session.Zones = rollZones(player)
	if Services.CombatService and Services.CombatService.PlaySwingVisual then
		Services.CombatService:PlaySwingVisual(player)
	end
	-- v14: ТЯЖЁЛЫЙ УДАР. Сила зависит от попадания (GradePower), серия
	-- PERFECT копится для бонуса к луту. Урон применяется не сразу, а через
	-- ImpactDelay — ровно в момент, когда на клиенте кирка «достаёт» камень
	-- (хитстоп, FOV, тряска). Финальный удар ещё и держит паузу FinalPause
	-- (слоу-мо) и только потом ломает валун.
	local power = (cfg.GradePower and cfg.GradePower[grade]) or 1
	local gain = (1 / session.Need) * power * math.max(0.3, 1 + statFor(player, "Boulder"))
	if grade == "Perfect" then
		session.Streak = (session.Streak or 0) + 1
	elseif grade == "Miss" then
		session.Streak = 0
	end
	state.Streaks = state.Streaks or {}
	state.Streaks[player] = math.max(state.Streaks[player] or 0, session.Streak or 0)
	local predicted = math.min(1, (state.Progress or 0) + (state.PendingGain or 0) + gain)
	local final = predicted >= 1
	state.PendingGain = (state.PendingGain or 0) + gain
	if final then state.PendingBreak = true end
	local quality = state.Quality[player]
	local impactDelay = cfg.ImpactDelay or 0.3
	local finalPause = cfg.FinalPause or 0.5
	boulderRemote:FireClient(player, "Update", {
		Grade = grade,
		Progress = predicted,
		Zones = session.Zones,
		Quality = quality.Sum / math.max(1, quality.Count),
		Final = final,
		Streak = session.Streak or 0,
		ImpactDelay = impactDelay,
		FinalPause = final and finalPause or 0,
	})
	task.delay(impactDelay, function()
		state.PendingGain = math.max(0, (state.PendingGain or 0) - gain)
		if not state.Model.Parent or (state.Progress or 0) >= 1 then return end
		Sfx.play("PickaxeHit", state.Model)
		if (state.Progress or 0) + gain >= 1 then
			-- Контакт финального удара: трясём, но ломаем после паузы (слоу-мо).
			shakeBoulder(state.Model.PrimaryPart or rootOf(state.Model))
			task.delay(finalPause, function()
				if state.Model.Parent and (state.Progress or 0) < 1 then
					applyProgress(self, state, player, gain, grade)
				end
			end)
		else
			applyProgress(self, state, player, gain, grade)
		end
	end)
end

-- Динамит (GearService): доля прогресса по разнице тиров. true — сработал.
function RockService:ApplyDynamite(state, player, powerMultiplier)
	if not state or not state.Model.Parent or (state.Progress or 0) >= 1 then return false end
	local cfg = Config.Dynamite
	local diff = state.Tier - equippedPickaxeTierFor(player)
	if diff > cfg.MaxBoulderDiff then
		Services.NotifyService:Show(player, "Even dynamite can't crack this one yet!", { Icon = "Boulder" })
		return false
	end
	local best, gain = -math.huge, 0.2
	for maxDiff, progress in cfg.BoulderProgressByDiff do
		if diff <= maxDiff and (best == -math.huge or maxDiff < best) then
			best, gain = maxDiff, progress
		end
	end
	gain *= math.max(0.2, powerMultiplier or 1)
	if state.Golden and Config.GoldenBoulder then
		gain /= math.max(1, Config.GoldenBoulder.HitsMultiplier or 1)
	end
	if not (state.Quality and state.Quality[player]) then
		recordQuality(state, player, Config.BoulderGame.Grades.Good)
	else
		state.Contributors[player] = true
	end
	applyProgress(self, state, player, gain, "Dynamite")
	return true
end

-- Валун в радиусе от точки (для брошенного динамита).
function RockService:FindBoulderNear(position, radius)
	local bestState, bestDistance = nil, radius
	for _, state in active do
		if state.Model.Parent then
			local distance = (boulderCenter(state) - position).Magnitude
			if distance <= bestDistance then
				bestState, bestDistance = state, distance
			end
		end
	end
	return bestState
end

function RockService:FindBoulderByModel(model)
	for _, state in active do
		if state.Model == model or (model and model:IsDescendantOf(state.Model)) then
			return state
		end
	end
	return nil
end

function RockService:_startBoulderGame()
	boulderRemote = Instance.new("RemoteEvent")
	boulderRemote.Name = "BoulderGameEvent"
	boulderRemote.Parent = ReplicatedStorage.Shared
	local lastMessage = {}
	boulderRemote.OnServerEvent:Connect(function(player, action, value)
		local now = os.clock()
		if lastMessage[player] and now - lastMessage[player] < 0.08 then return end
		lastMessage[player] = now
		if action == "Strike" then
			self:_strike(player, value)
		elseif action == "Cancel" then
			self:_closeSession(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		boulderSessions[player] = nil
		lastMessage[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for player, session in boulderSessions do
				local state = session.State
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not player.Parent or not state.Model.Parent or (state.Progress or 0) >= 1 then
					self:_closeSession(player)
				elseif not hrp or (hrp.Position - boulderCenter(state)).Magnitude > Config.BoulderGame.SessionRange then
					self:_closeSession(player, { Reason = "TooFar" })
				elseif now - session.LastActivity > Config.BoulderGame.SessionIdleTimeout then
					self:_closeSession(player, { Reason = "Idle" })
				end
			end
		end
	end)
end

function RockService:Break(state, breaker)
	if not state.Model.Parent then return end
	-- ТОЧКА, ИЗ КОТОРОЙ ВЫЛЕТАЕТ НАГРАДА — верх валуна, а не его центр.
	--
	-- Раньше сюда шёл GetPivot().Position, то есть геометрический центр
	-- модели, и всё, что "выпадает из камня" (монета, жеода, кристалл,
	-- коробка со скином), начинало полёт ВНУТРИ ещё не исчезнувшего валуна.
	-- Первые кадры дуги предмет был спрятан геометрией, и вместо "из камня
	-- что-то вылетело" получалось "что-то появилось рядом с камнем".
	-- Тот же по сути баг, что и с осколками удара (см. spawnHitDebris).
	local center, size = boulderBounds(state.Model)
	local position = center + Vector3.new(0, size.Y * 0.45, 0)
	-- Гоблин-элита появляется от ЦЕНТРА валуна, как и раньше: он живой
	-- персонаж и встаёт на землю, поднимать точку его спавна незачем.
	local groundPosition = state.Model:GetPivot().Position
	-- Снимаем валун с учёта ДО анимации: пока он доигрывает разрушение, он
	-- уже не должен находиться FindInHitbox и принимать новые удары.
	active[state.Point] = nil
	-- Отдельным потоком, чтобы анимация ни на кадр не задержала выдачу
	-- награды ниже (GrantBoulderRewards йилдит на сохранении жеод).
	local model = state.Model
	task.spawn(function()
		local ok, err = pcall(playBreakAnimation, model, state.Tier)
		if not ok then
			warn("[RockService] анимация разрушения валуна упала:", err)
			if model.Parent then model:Destroy() end
		end
	end)
	-- Метрика для стартовых квестов FirstBoulder/BoulderHunter (см.
	-- Config.Quests.Starter). До этого RockService не репортил в
	-- QuestService вообще ничего, метрики "BouldersBroken" не существовало.
	if breaker and breaker.Parent and Services.QuestService then
		Services.QuestService:RecordMetric(breaker, "BouldersBroken", 1)
	end
	-- v8: награда КАЖДОМУ, кто бил в мини-игре, по его качеству ударов.
	local isPlotBoulder = self:IsPlotBoulder(state)
	local plotOwnerUserId = isPlotBoulder and state.Point:GetAttribute("PlotOwnerUserId") or nil
	local rewarded = {}
	local function reward(player)
		if not player or rewarded[player] or not player.Parent then return end
		rewarded[player] = true
		local entry = state.Quality and state.Quality[player]
		local quality = entry and entry.Sum / math.max(1, entry.Count) or Config.BoulderGame.Grades.Good
		local result = resultFor(quality)
		-- ВАЖНО: личный валун даёт свой дроп ТОЛЬКО владельцу базы. Чужой
		-- игрок, забредший на участок и добивший камень, получает обычную
		-- таблицу — иначе базовые валуны превратились бы в способ фармить
		-- бесплатную руду по чужим базам.
		local options = {
			PlotBoulder = (isPlotBoulder and player.UserId == plotOwnerUserId) or nil,
			Streak = state.Streaks and state.Streaks[player] or 0,
			Golden = state.Golden == true,
			IsBreaker = player == breaker,
		}
		local _, rich = self:GrantBoulderRewards(player, state.Tier, position, boulderRemote ~= nil, result, options)
		rich = rich or {}
		-- Сундуки из базовых валунов не падают: это личный, бесконкурентный
		-- источник, и класть в него ещё и лутбоксы значило бы обесценить
		-- обычные валуны на карте, за которые игроки реально соревнуются.
		if not options.PlotBoulder and Services.GearService and Services.GearService.RollBoulderChest then
			local okChest, chest = pcall(Services.GearService.RollBoulderChest, Services.GearService, player, state.Tier, result.ChestMult or 1, position)
			local chestInfo = okChest and chest and Config.Chests.Types[chest]
			if chestInfo then
				table.insert(rich, { Kind = "Chest", Icon = "🎁", Text = chestInfo.DisplayName, Color = chestInfo.Color })
			end
		end
		if boulderRemote then
			boulderRemote:FireClient(player, "Close", { Result = result.Label, Color = result.Color, Quality = quality, Rewards = rich, Position = position })
		end
		boulderSessions[player] = nil
	end
	reward(breaker)
	for player in state.Quality or {} do reward(player) end
	for player, session in boulderSessions do
		if session.State == state then self:_closeSession(player) end
	end
	-- Элита из базового валуна не вылезает: гоблин-элита на собственной
	-- базе новичка, который только что впервые взял кирку в руки, — это не
	-- сложность, а отъём тележки на первой минуте.
	if state.Elite and not isPlotBoulder and Services.GoblinService then
		Services.GoblinService:SpawnEliteForBoulder(breaker, groundPosition, state.Tier, state.Contributors)
	end
	-- Шаг обучения «расчисти завал» считает ТОЛЬКО свои базовые валуны:
	-- иначе его можно было бы закрыть, разбив два случайных камня на
	-- карте, так и не узнав, что у шахты вообще есть вход.
	if isPlotBoulder and breaker and breaker.Parent and breaker.UserId == plotOwnerUserId
		and Services.TutorialService
	then
		pcall(function() Services.TutorialService:Count(breaker, "BaseBouldersBroken", 1) end)
	end
	local respawnDelay = isPlotBoulder
		and (Config.Boulders.Base.RespawnDelay or Config.Boulders.RespawnDelay)
		or Config.Boulders.RespawnDelay
	-- v14: Quake-тотемы хозяина базы ускоряют респавн его валунов.
	if isPlotBoulder and Services.BaseDecorService and plotOwnerUserId then
		local owner = Players:GetPlayerByUserId(plotOwnerUserId)
		if owner then
			respawnDelay *= 1 - Services.BaseDecorService:GetBoulderRespawnCut(owner)
		end
	end
	if state.Golden then
		state.Golden = false
		if Services.AnnounceService and breaker then
			pcall(function()
				Services.AnnounceService:Broadcast(("⭐ %s cracked the GOLDEN BOULDER!"):format(breaker.DisplayName), Config.GoldenBoulder.Color)
			end)
		end
	end
	task.delay(respawnDelay, function()
		if state.Point.Parent then self:SpawnAtPoint(state.Point, state.Tier) end
	end)
	-- Стрелка обучения смотрела на только что сломанный валун — переводим
	-- её на следующий, не дожидаясь секундного опроса в TutorialService.
	if isPlotBoulder and breaker and breaker.Parent and Services.TutorialService then
		pcall(function() Services.TutorialService:RefreshTarget(breaker) end)
	end
end

--------------------------------------------------------------------------------
-- v14 — ЗОЛОТОЙ ВАЛУН (Config.GoldenBoulder). Раз в IntervalMin..Max один
-- нетронутый валун на карте становится золотым: золотой цвет, свет, луч в
-- небо, подпись видна издалека, анонс в чат. Не добили за LifetimeSeconds —
-- валун пересоздаётся обычным.
--------------------------------------------------------------------------------
local function decorateGolden(model)
	local cfg = Config.GoldenBoulder
	local gold = cfg.Color or Color3.fromRGB(255, 200, 40)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Color = part.Color:Lerp(gold, 0.8)
			if part.Material ~= Enum.Material.Neon then part.Material = Enum.Material.Foil end
		end
	end
	local root = model.PrimaryPart or rootOf(model)
	if not root then return end
	local _, size = boulderBounds(model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "GoldenHighlight"
	highlight.FillColor = gold
	highlight.FillTransparency = 0.65
	highlight.OutlineColor = Color3.fromRGB(255, 245, 180)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Brightness = 3
	light.Range = 24
	light.Parent = root
	local a0 = Instance.new("Attachment")
	a0.Name = "GoldenBeamBottom"
	a0.Parent = root
	a0.WorldPosition = model:GetBoundingBox().Position + Vector3.new(0, size.Y * 0.5, 0)
	local a1 = Instance.new("Attachment")
	a1.Name = "GoldenBeamTop"
	a1.Parent = root
	a1.WorldPosition = a0.WorldPosition + Vector3.new(0, cfg.BeamHeight or 120, 0)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(gold)
	beam.LightEmission = 1
	beam.Width0 = 3
	beam.Width1 = 0.5
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(gold)
	emitter.LightEmission = 1
	emitter.Rate = 18
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = a0
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GoldenLabel"
	billboard.Size = UDim2.fromOffset(260, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y * 0.5 + 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 800
	billboard.LightInfluence = 0
	billboard.Adornee = root
	billboard.Parent = model
	local label = WorldUi.Text(nil, "Text", "Heading")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = "⭐ GOLDEN BOULDER ⭐"
	label.TextColor3 = gold
	label.Parent = billboard
	model:SetAttribute("GoldenBoulder", true)
end

function RockService:_makeGolden()
	local cfg = Config.GoldenBoulder
	local candidates = {}
	for _, state in active do
		if state.Model.Parent and not state.Golden and not self:IsPlotBoulder(state)
			and (state.Progress or 0) == 0 and not state.Damaged
		then
			table.insert(candidates, state)
		end
	end
	if #candidates == 0 then return false end
	local state = candidates[math.random(1, #candidates)]
	state.Golden = true
	decorateGolden(state.Model)
	if Services.AnnounceService then
		pcall(function()
			Services.AnnounceService:Broadcast(("⭐ A GOLDEN BOULDER (tier %d) appeared! Whoever cracks it gets a RELIC!"):format(state.Tier), cfg.Color)
		end)
	end
	local point = state.Point
	task.delay(cfg.LifetimeSeconds or 300, function()
		if active[point] ~= state or not state.Golden then return end
		-- Не успели: пересоздаём обычным валуном.
		for player, session in boulderSessions do
			if session.State == state then self:_closeSession(player) end
		end
		active[point] = nil
		if state.Model.Parent then state.Model:Destroy() end
		if point.Parent then self:SpawnAtPoint(point, state.Tier) end
	end)
	return true
end

function RockService:_startGoldenBoulder()
	local cfg = Config.GoldenBoulder
	if not (cfg and cfg.Enabled) then return end
	task.spawn(function()
		task.wait(cfg.FirstDelay or 300)
		while true do
			local ok, err = pcall(self._makeGolden, self)
			if not ok then warn("[RockService] Золотой валун не создан:", err) end
			task.wait(math.random(cfg.IntervalMin or 900, cfg.IntervalMax or 1500))
		end
	end)
end

function RockService:SetupPlayer(player)
	player:SetAttribute("CarryingCrystal", "")
	local function hook(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			-- Раньше коннект просто ПЕРЕЗАПИСЫВАЛСЯ на каждом респавне, а
			-- старый не отключался — они копились по одному за смерть.
			local previous = characterConnections[player]
			if previous then previous:Disconnect() end
			characterConnections[player] = humanoid.Died:Connect(function() self:DropCarrying(player) end)
		end
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then hook(player.Character) end
end

function RockService:CarryCrystal(player, oreId, mutations, owned, source)
	if carrying[player] or player:GetAttribute("CarryingCrystal") ~= "" then return false end
	-- Config.Geodes.Ores содержит И обычные жеодные руды, И 10 кастомных
	-- валунных (они смерджены туда в Config.lua) — раньше тут проверялось
	-- только Config.Boulders.CustomOres, из-за чего "достать в руки" любой
	-- обычной жеодной руды (не с валуна) молча проваливалось.
	local info = Config.Geodes.Ores[oreId]
	if not info then return false end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return false end
	local model = PlaceholderFactory.CollectionOre(oreId)
	local root = rootOf(model)
	if not root then model:Destroy(); return false end
	setModelPhysics(model, false)
	-- ВАЖНО: setModelPhysics обходит ТОЛЬКО model:GetDescendants() — если
	-- CollectionOre вернул голый Part (а не Model), у него нет descendants
	-- вообще, и Anchored там НЕ трогается циклом внутри setModelPhysics.
	-- CollectionOre создаёт фолбэк-руду с Anchored=true — без явного сброса
	-- здесь она так и оставалась заанкоренной навсегда, и WeldConstraint к
	-- голове не мог её сдвинуть: кристалл просто зависал в воздухе на месте
	-- поднятия, не следуя за игроком.
	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.Massless = true
	if model:IsA("Model") then model:PivotTo(head.CFrame * CFrame.new(0, 3, 0)) else root.CFrame = head.CFrame * CFrame.new(0, 3, 0) end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = root
	weld.Parent = root

	-- МУТАЦИИ: раньше строка mutations приходила в функцию и клалась в
	-- carrying[player].Mutations (нужна для возврата в ту же ячейку
	-- коллекции), но визуально НИКОГДА не применялась к модели в руках —
	-- ржавый/замороженный/т.д. кристалл, взятый в руки, выглядел как
	-- обычный. На подиуме (PassiveIncomeService:UpdateDisplay) это
	-- применяется, здесь просто забыли аналогичный вызов.
	local mutationIds = {}
	if mutations and mutations ~= "" then
		for id in mutations:gmatch("[^,]+") do
			table.insert(mutationIds, id)
		end
	end
	local partGroups = MutationVisuals.SplitPartsForMutations(model, #mutationIds)
	for index, mutationId in mutationIds do
		MutationVisuals.Apply(model, mutationId, root, partGroups and partGroups[index])
	end

	-- ТАБЛИЧКА НАД КРИСТАЛЛОМ В РУКАХ — то же самое, что висит над ним на
	-- подиуме (название + доход + мутация), просто теперь как BillboardGui
	-- над самим кристаллом в мире, а не над подиумом.
	local carryLabel = Instance.new("BillboardGui")
	carryLabel.Name = "CarryInfoGui"
	carryLabel.Size = UDim2.fromOffset(220, 70)
	carryLabel.StudsOffset = Vector3.new(0, 1.6, 0)
	carryLabel.AlwaysOnTop = true
	carryLabel.MaxDistance = 60
	carryLabel.Adornee = root
	carryLabel.Parent = root
	local carryText = WorldUi.Text(nil, "Text", "Number")
	carryText.Size = UDim2.fromScale(1, 1)
	carryText.BackgroundTransparency = 1
	carryText.TextScaled = true
	carryText.TextColor3 = info.Color
	local mutationNames = {}
	for _, mutationId in mutationIds do
		local mutationInfo = Config.Mutations[mutationId]
		if mutationInfo then table.insert(mutationNames, mutationInfo.DisplayName:upper()) end
	end
	MutationVisuals.StyleOverheadLabel(carryText, mutationIds, info.Color)
	-- Доход считаем ЖИВОЙ формулой (см. OreIncome.lua), а не сырым полем
	-- info.IncomePerMinute: это поле теперь хранит только ПЛОСКУЮ часть
	-- ставки, и табличка над кристаллом в руках показывала бы число в разы
	-- меньше того, что реально капает у этого игрока на подиуме.
	local carryKey = CollectionKey.Make(oreId, mutationIds)
	local carryIncome = OreIncome.PerMinuteForPlayer(player, carryKey, 1)
	carryText.Text = ("%s\n$%s/SEC"):format(info.DisplayName, NumberFormat.perSecond(carryIncome))
		.. (#mutationNames > 0 and ("\n" .. MutationVisuals.ColoredNames(mutationIds)) or "")
	carryText.Parent = carryLabel
	-- "Отпустить" — обычный ProximityPrompt на самом кристалле, тем же
	-- стилем/ключом, что и "GRAB CART" (Style=Custom рендерится общим
	-- механизмом игры — см. CustomCartUI.client.lua, ничего своего в UI
	-- писать не нужно). Клик/E прямо по кристаллу у себя над головой.
	local releasePrompt = Instance.new("ProximityPrompt")
	releasePrompt.Name = "ReleaseCrystalPrompt"
	releasePrompt.ActionText = "RELEASE"
	releasePrompt.ObjectText = info.DisplayName
	releasePrompt.HoldDuration = 0
	releasePrompt.ClickablePrompt = true
	releasePrompt.RequiresLineOfSight = false
	releasePrompt.KeyboardKeyCode = Enum.KeyCode.E
	releasePrompt.Style = Enum.ProximityPromptStyle.Custom
	releasePrompt.Parent = root
	releasePrompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == player then self:ReleaseCarrying(player) end
	end)
	model.Parent = character
	carrying[player] = { OreId = oreId, Model = model, Mutations = mutations or "", Owned = owned == true, Source = source }
	player:SetAttribute("CarryingCrystal", oreId)
	return true
end

function RockService:PickupDroppedCrystal(player, crystal)
	if not crystal or not crystal.Parent then return false end
	local oreId = crystal:GetAttribute("RubbleOreId")
	local source = crystal:GetAttribute("CrystalSource")
	local droppedByUserId = crystal:GetAttribute("DroppedByUserId")
	if not oreId or not self:CarryCrystal(player, oreId, crystal:GetAttribute("RubbleMutations") or crystal:GetAttribute("Mutations") or "", false, source) then return false end
	Sfx.play(droppedByUserId and droppedByUserId ~= player.UserId and "CrystalStolenPickup" or "CrystalPickup", CrystalUtil.GetRoot(crystal))
	crystal:Destroy()
	if Services.NotifyService then
		local info = Config.Geodes.Ores[oreId]
		Services.NotifyService:Show(player, "CRYSTAL COLLECTED: " .. (info and info.DisplayName or oreId), { Icon = "Crystal" })
		if source == "Boulder" or (droppedByUserId and droppedByUserId ~= player.UserId) then
			Services.NotifyService:ShowBankTrailOnce(player, "Rubble")
		end
	end
	return true
end

function RockService:DropCarrying(player)
	if transferring[player] then return false end
	local entry = carrying[player]
	if not entry then player:SetAttribute("CarryingCrystal", ""); return false end
	local character = player.Character
	local root = character and rootOf(character)
	local position = root and root.Position or Vector3.zero
	entry.Model:Destroy()
	carrying[player] = nil
	player:SetAttribute("CarryingCrystal", "")
	spawnLooseCrystal(entry.OreId, tierForOre(entry.OreId), position, entry.Mutations or "", nil, entry.Source, player.UserId)
	return true
end

function RockService:CancelCarrying(player)
	local entry = carrying[player]
	if not entry then return false end
	if entry.Model.Parent then entry.Model:Destroy() end
	carrying[player] = nil
	player:SetAttribute("CarryingCrystal", "")
	return true
end

-- Добровольное "отпустить" — отдельно от DropCarrying (смерть/дисконнект) и
-- CancelCarrying (внутренняя уборка модели без последствий). Если кристалл
-- был СВОИМ (вытащен из собственной коллекции через "Достать в руки") —
-- возвращаем его обратно в хранилище бесплатно и мгновенно, идти в банк не
-- нужно: он и так был безопасен, просто временно физически в руках ради
-- трейда. Если кристалл НЕ свой (добыт с валуна или получен в подарок) —
-- отпускание всё равно роняет его в мир, как при смерти: иначе это была бы
-- дыра, позволяющая обходить весь риск экстракшена одной кнопкой.
function RockService:ReleaseCarrying(player)
	local entry = carrying[player]
	if not entry then return false end
	if entry.Owned then
		if not Services.GeodeService:AddCollectionCopy(player, entry.OreId, entry.Mutations) then return false end
		self:CancelCarrying(player)
		Services.NotifyService:Show(player, "CRYSTAL RETURNED TO STORAGE", { Icon = "Crystal" })
		return true
	end
	return self:DropCarrying(player)
end

function RockService:DepositCarrying(player)
	if transferring[player] then return false end
	local entry = carrying[player]
	if not entry then return false end
	if not Services.GeodeService:AddCollectionCopy(player, entry.OreId, entry.Mutations) then return false end
	if Services.MutationBookService and entry.Mutations ~= "" then
		for mutationId in string.gmatch(entry.Mutations, "[^,]+") do
			Services.MutationBookService:RecordFound(player, tierForOre(entry.OreId), mutationId)
		end
	end
	entry.Model:Destroy()
	carrying[player] = nil
	player:SetAttribute("CarryingCrystal", "")
	-- v14.2: кристалл «продаётся» торговцу банка и уходит в сток банка
	-- (коллекция): оттуда его ставят на подиум острова Income ради пассивки.
	local oreInfo = Config.Geodes.Ores[entry.OreId]
	local rarity = oreInfo and oreInfo.Rarity or "Rare"
	Services.NotifyService:LootFeed(player, {
		{ Icon = "💎", Text = ("%s → BANK STOCK"):format(oreInfo and oreInfo.DisplayName or entry.OreId), Sub = "Sold to the merchant", Rarity = rarity, Color = Config.RarityColors[rarity] },
	})
	Services.NotifyService:Show(player, "CRYSTAL SOLD → BANK STOCK", { Icon = "Crystal" })
	return true
end

function RockService:GetCarrying(player)
	return carrying[player]
end

function RockService:GiftCrystal(sender, target)
	local entry = carrying[sender]
	if transferring[sender] or not entry or not target.Parent or sender == target then return false end
	local senderRoot = sender.Character and sender.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not senderRoot or not targetRoot or (senderRoot.Position - targetRoot.Position).Magnitude > 12 then return false end
	if carrying[target] or target:GetAttribute("CarryingCrystal") ~= "" then
		transferring[sender] = true
		carrying[sender] = nil
		sender:SetAttribute("CarryingCrystal", "")
		local callOk, stored = pcall(Services.GeodeService.AddCollectionCopy, Services.GeodeService, target, entry.OreId, entry.Mutations)
		transferring[sender] = nil
		if not callOk or not stored then
			if not callOk then warn("[RockService] Gift-to-storage failed safely:", stored) end
			if sender.Parent then
				carrying[sender] = entry
				sender:SetAttribute("CarryingCrystal", entry.OreId)
			elseif entry.Model.Parent then
				entry.Model:Destroy()
			end
			return false
		end
		if entry.Model.Parent then entry.Model:Destroy() end
		Services.NotifyService:Show(target, ("Gift sent to storage (hands full): %s"):format(Config.Geodes.Ores[entry.OreId].DisplayName), { Icon = "Gift" })
		Services.NotifyService:Show(sender, ("Gift delivered to %s"):format(target.DisplayName or target.Name), { Icon = "Gift" })
		if Services.QuestService then Services.QuestService:RecordMetric(sender, "CrystalsGifted", 1) end
		return true
	end
	local oreId = entry.OreId
	local senderModel = entry.Model
	-- ВАЖНО: мутации обязаны переехать вместе с кристаллом. Раньше здесь было
	-- self:CarryCrystal(target, oreId) БЕЗ третьего аргумента — принимающий
	-- получал Mutations = "", то есть при передаче мутации просто
	-- уничтожались: их нельзя было ни записать в энциклопедию через
	-- DepositCarrying, ни как-то использовать. PickupDroppedCrystal мутации
	-- передаёт правильно — здесь их потеряли по недосмотру.
	transferring[sender] = true
	if not self:CarryCrystal(target, oreId, entry.Mutations) then transferring[sender] = nil; return false end
	if senderModel.Parent then senderModel:Destroy() end
	carrying[sender] = nil
	sender:SetAttribute("CarryingCrystal", "")
	transferring[sender] = nil
	Services.NotifyService:Show(target, ("Gift: %s"):format(Config.Geodes.Ores[oreId].DisplayName), { Icon = "Gift" })
	Services.NotifyService:ShowBankTrailOnce(target, "Rubble")
	-- Отправителю раньше не приходило ничего: он отдавал кристалл "в пустоту"
	-- без единого подтверждения, что передача вообще состоялась.
	Services.NotifyService:Show(sender, ("Gift delivered to %s"):format(target.DisplayName or target.Name), { Icon = "Gift" })
	-- Метрика стартового квеста GiftCrystal (см. Config.Quests.Starter).
	-- Засчитывается ДАРИТЕЛЮ и только по факту успешной передачи — все
	-- проверки (дистанция 12 студов, sender ~= target, кристалл реально был
	-- в руках) уже пройдены выше.
	if Services.QuestService then Services.QuestService:RecordMetric(sender, "CrystalsGifted", 1) end
	return true
end

function RockService:CleanupPlayer(player)
	if characterConnections[player] then characterConnections[player]:Disconnect(); characterConnections[player] = nil end
	carrying[player] = nil
	transferring[player] = nil
	for _, state in active do
		if state.Contributors then state.Contributors[player] = nil end
	end
end

return RockService
