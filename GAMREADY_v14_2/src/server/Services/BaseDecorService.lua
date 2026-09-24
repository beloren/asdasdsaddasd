--------------------------------------------------------------------------------
-- BaseDecorService — ТОТЕМЫ, ДЕКОР И РЕЛИКВИИ НА БАЗЕ (v14.1).
--
-- ВСЁ ЛЕЖИТ В ОБЫЧНОМ ИНВЕНТАРЕ. Тотемы и декор — это ключи data.Gear
-- (как динамит/сундуки/зелья): Gear["Totem_Fortune_T3"] = 2. Реликвия —
-- тоже ключ Gear, по одному на каждую: "Relic:<Id>:<Serial>:<Uid>" = 1;
-- её метаданные (кто нашёл, когда) — в data.Relics.
--
-- УСТАНОВКА: взял предмет в руку из инвентаря/хотбара → клиент рисует
-- призрак (client/PlacementGhost) → клик → GearRequest "Use" с CFrame →
-- GearService → PlaceFromGear. Ставится ТОЛЬКО на землю своего участка
-- (shared/GroundCheck), сколько угодно штук.
-- ПОДБОР: зажать E у предмета (только владелец) → обратно в инвентарь.
--
-- data.PlacedDecor — { Uid, Item | RelicUid, X, Y, Z, R }, позиция и поворот
-- ОТНОСИТЕЛЬНО plot.Pad: база встаёт как была на любом участке.
--
-- БАФФЫ (читают другие сервисы; суммарные потолки — Config.Placeables.Caps):
--   GetLuckBonus / GetIncomeBonus / GetBoulderRespawnCut / MergeMutationBoosts.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local PlaceableCatalog = require(ReplicatedStorage.Shared.PlaceableCatalog)
local PlaceableFactory = require(ReplicatedStorage.Shared.PlaceableFactory)
local GroundCheck = require(ReplicatedStorage.Shared.GroundCheck)

local BaseDecorService = {}

local Services = nil
local CFG = Config.Placeables
local RELICS = Config.Relics

local serialStore = nil
local spawned = {}   -- [player] = { [uid] = model }
local buffCache = {} -- [player] = { Luck, Income, BoulderRespawn, Mutation = {} }
local placing = {}   -- [player] = true, пока идёт установка (защита от двойного клика)

local GLOBAL_TOPIC = "RelicFound_v1"

local function dataOf(player)
	return Services.DataService:GetGeodeData(player)
end

local function nextUid(data)
	data.BaseUidCounter = (tonumber(data.BaseUidCounter) or 0) + 1
	return ("%d_%d"):format(os.time(), data.BaseUidCounter)
end

local function findRelic(data, uid)
	for index, relic in data.Relics do
		if relic.Uid == uid then return relic, index end
	end
	return nil
end

local function findPlaced(data, uid)
	for index, record in data.PlacedDecor do
		if record.Uid == uid then return record, index end
	end
	return nil
end

local function relicIsPlaced(data, relicUid)
	for _, record in data.PlacedDecor do
		if record.RelicUid == relicUid then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- КЛЮЧИ ИНВЕНТАРЯ
--------------------------------------------------------------------------------
function BaseDecorService.RelicKey(relic)
	return ("Relic:%s:%d:%s"):format(tostring(relic.Id), tonumber(relic.Serial) or 0, tostring(relic.Uid))
end

function BaseDecorService.ParseRelicKey(key)
	if typeof(key) ~= "string" then return nil end
	local relicId, serial, uid = key:match("^Relic:([%w]+):(%d+):(.+)$")
	return relicId, tonumber(serial), uid
end

function BaseDecorService.IsPlaceableKey(key)
	if typeof(key) ~= "string" then return false end
	return PlaceableCatalog.Info(key) ~= nil or key:match("^Relic:") ~= nil
end

local function gearCount(data, key)
	return math.max(0, math.floor(tonumber(data.Gear and data.Gear[key]) or 0))
end

--------------------------------------------------------------------------------
-- БАФФЫ
--------------------------------------------------------------------------------
function BaseDecorService:_recompute(player)
	local data = dataOf(player)
	if not data then
		buffCache[player] = nil
		return
	end
	local luck, income, respawn = 0, 0, 0
	local mutation = {}
	local shrines = {} -- v4: [shrineId] = info (одинаковые не складываются)
	local idolLuck, idolIncome = 0, 0
	for _, record in data.PlacedDecor do
		if record.Item then
			local info = PlaceableCatalog.Info(record.Item)
			if info and info.Type == "Shrine" then
				if not shrines[info.ShrineId] then
					shrines[info.ShrineId] = info
					if info.Effect == "Luck" then
						idolLuck += info.Value
					elseif info.Effect == "Income" then
						idolIncome += info.Value
					end
				end
			elseif info and info.Kind == "Totem" then
				if info.Effect == "Luck" then
					luck += info.Value
				elseif info.Effect == "Income" then
					income += info.Value
				elseif info.Effect == "BoulderRespawn" then
					respawn += info.Value
				elseif info.Effect == "Mutation" and info.Mutation then
					mutation[info.Mutation] = (mutation[info.Mutation] or 0) + info.Value
				end
			end
		elseif record.RelicUid then
			local relic = findRelic(data, record.RelicUid)
			local relicInfo = relic and RELICS.Types[relic.Id]
			if relicInfo then income += relicInfo.IncomeBonus or 0 end
		end
	end
	local caps = CFG.Caps or {}
	luck = math.min(luck, caps.Luck or math.huge)
	income = math.min(income, caps.Income or math.huge)
	respawn = math.min(respawn, caps.BoulderRespawn or 0.9)
	for id, value in mutation do
		mutation[id] = math.min(value, caps.Mutation or math.huge)
	end
	-- v4: идолы святилищ — сверх потолков обычных тотемов.
	luck += idolLuck
	income += idolIncome
	buffCache[player] = { Luck = luck, Income = income, BoulderRespawn = respawn, Mutation = mutation, Shrines = shrines }
	player:SetAttribute("BaseLuckBonus", luck)
	player:SetAttribute("BaseIncomeBonus", income)
	player:SetAttribute("BaseRespawnBonus", respawn)
end

function BaseDecorService:GetLuckBonus(player)
	local cache = player and buffCache[player]
	return cache and cache.Luck or 0
end

function BaseDecorService:GetIncomeBonus(player)
	local cache = player and buffCache[player]
	return cache and cache.Income or 0
end

function BaseDecorService:GetBoulderRespawnCut(player)
	local cache = player and buffCache[player]
	return cache and cache.BoulderRespawn or 0
end

-- Погодные бусты { [mutationId] = множитель } + Prism-тотемы игрока.
function BaseDecorService:MergeMutationBoosts(player, weatherBoosts)
	local cache = player and buffCache[player]
	if not (cache and next(cache.Mutation)) then return weatherBoosts end
	local merged = {}
	for id, value in weatherBoosts or {} do merged[id] = value end
	for id, bonus in cache.Mutation do
		merged[id] = math.max(1, tonumber(merged[id]) or 1) * (1 + bonus)
	end
	return merged
end

-- v4: СВЯТИЛИЩА. Вызывается CrystalService на КАЖДУЮ руду, добытую в
-- шахте. Двигает счётчики поставленных святилищ и возвращает список
-- мутаций, которые этой руде положены гарантированно.
function BaseDecorService:TickShrines(player)
	local cache = player and buffCache[player]
	if not (cache and cache.Shrines and next(cache.Shrines)) then return nil end
	local data = dataOf(player)
	if not data then return nil end
	data.ShrineCounters = type(data.ShrineCounters) == "table" and data.ShrineCounters or {}
	local due = nil
	for shrineId, info in cache.Shrines do
		if info.Effect == "Shrine" and info.Mutation and (info.Every or 0) > 0 then
			-- v17: окно из Every руд (по умолчанию 3). В начале окна случайно
			-- выбирается ОДИН слот — эта руда получает мутацию. Итого ровно
			-- одна мутированная руда на каждые три, без «каждой 25-й».
			local every = math.max(1, math.floor(info.Every))
			local slotKey = shrineId .. "#slot"
			local count = (tonumber(data.ShrineCounters[shrineId]) or 0) + 1
			if count > every then count = 1 end -- старый счётчик «каждые 25» из профиля
			local slot = tonumber(data.ShrineCounters[slotKey])
			if not slot or slot < 1 or slot > every then
				slot = math.random(1, every)
			end
			if count == slot then
				due = due or {}
				table.insert(due, info.Mutation)
			end
			if count >= every then
				count = 0
				slot = math.random(1, every)
			end
			data.ShrineCounters[shrineId] = count
			data.ShrineCounters[slotKey] = slot
			player:SetAttribute("ShrineLeft_" .. shrineId, every - count)
		end
	end
	return due
end

-- v4: есть ли у игрока святилище (в инвентаре или на базе).
function BaseDecorService:OwnsShrine(player, shrineId)
	local data = dataOf(player)
	if not data then return false end
	local key = PlaceableCatalog.ShrineId(shrineId)
	if gearCount(data, key) > 0 then return true end
	for _, record in data.PlacedDecor do
		if record.Item == key then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- ВЫДАЧА (всё — в обычный инвентарь через GearService)
--------------------------------------------------------------------------------
function BaseDecorService:GrantItem(player, itemId, count)
	count = math.max(1, math.floor(tonumber(count) or 1))
	if not PlaceableCatalog.Info(itemId) then return false end
	return Services.GearService:AddGear(player, itemId, count) > 0
end

--------------------------------------------------------------------------------
-- МОДЕЛИ НА УЧАСТКЕ
--------------------------------------------------------------------------------
local function folderFor(plot)
	if not (plot and plot.Content and plot.Content.Parent) then return nil end
	local folder = plot.Content:FindFirstChild("BaseDecor")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BaseDecor"
		folder.Parent = plot.Content
	end
	return folder
end

local function worldCFrame(plot, record)
	local base = plot.Pad.CFrame * CFrame.new(record.X or 0, record.Y or 0, record.Z or 0)
	if record.RX then
		-- v14.4: полный поворот (стена/склон).
		return base * CFrame.fromOrientation(math.rad(record.RX), math.rad(record.RY or record.R or 0), math.rad(record.RZ or 0))
	end
	return base * CFrame.Angles(0, math.rad(record.R or 0), 0)
end

-- Подпись над тотемом/трофеем: шрифт как у денег в HUD, имя цветом
-- предмета, ниже — строки поменьше.
-- v20.12: подпись — «табличка» в мире (как советуют на DevForum): размер
-- BillboardGui в SCALE (стадах), текст TextScaled по всей высоте строки.
-- Тогда надпись держит один размер относительно тотема/трофея: камера
-- отъехала — табличка уменьшилась вместе с предметом, а не раздувается,
-- как было с размером в пикселях. DistanceLowerLimit не даёт ей стать
-- огромной вплотную. https://devforum.roblox.com/t/3247495
local LABEL_WIDTH = 7 -- стадов
local LABEL_TITLE_HEIGHT = 1.1
local LABEL_LINE_HEIGHT = 0.75

local function addLabel(model, anchor, lines, maxDistance, heightOffset)
	local total = LABEL_TITLE_HEIGHT + LABEL_LINE_HEIGHT * math.max(0, #lines - 1)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DecorLabel"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromScale(LABEL_WIDTH, total)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, heightOffset + total / 2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.DistanceLowerLimit = 8
	billboard.MaxDistance = maxDistance
	billboard.Parent = model
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard
	for index, line in lines do
		local label = WorldUi.Text(nil, "Text", index == 1 and "Label" or "LabelSub")
		label.LayoutOrder = index
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, (index == 1 and LABEL_TITLE_HEIGHT or LABEL_LINE_HEIGHT) / total)
		label.TextScaled = true
		label.Text = line.Text
		if line.Color then label.TextColor3 = line.Color end
		label.Parent = billboard
	end
end

function BaseDecorService:_spawnRecord(player, plot, record)
	local data = dataOf(player)
	local folder = folderFor(plot)
	if not (data and folder) then return nil end
	local model, displayName
	if record.Item then
		local info = PlaceableCatalog.Info(record.Item)
		if not info then return nil end
		model = PlaceableFactory.BuildItem(record.Item)
		displayName = info.DisplayName
		if model and info.Kind == "Totem" then
			local _, size = model:GetBoundingBox()
			addLabel(model, model.PrimaryPart, {
				{ Text = info.DisplayName, Color = info.TierColor },
				{ Text = PlaceableCatalog.EffectText(info), Color = Color3.fromRGB(230, 230, 230) },
			}, 28, size.Y + 1.2)
		end
	elseif record.RelicUid then
		local relic = findRelic(data, record.RelicUid)
		local info = relic and RELICS.Types[relic.Id]
		if not info then return nil end
		model = PlaceableFactory.BuildRelic(relic.Id)
		displayName = info.DisplayName
		if model then
			local _, size = model:GetBoundingBox()
			local serialText = (tonumber(relic.Serial) or 0) > 0 and ("#%d"):format(relic.Serial) or "#?"
			addLabel(model, model.PrimaryPart, {
				{ Text = ("%s %s"):format(info.DisplayName, serialText), Color = PlaceableCatalog.RarityColor(info.Rarity) },
				{ Text = ("found by %s"):format(tostring(relic.Finder or player.DisplayName)), Color = Color3.fromRGB(235, 235, 235) },
				{ Text = ("+%d%% Sell Income"):format(math.floor((info.IncomeBonus or 0) * 100 + 0.5)), Color = Color3.fromRGB(120, 255, 150) },
			}, 70, size.Y + 1.5)
		end
	end
	if not model then return nil end
	model:PivotTo(worldCFrame(plot, record))
	model:SetAttribute("BaseDecorUid", record.Uid)
	model:SetAttribute("OwnerUserId", player.UserId)

	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if anchor then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BaseDecorPickup"
		prompt.ActionText = "PICK UP"
		prompt.ObjectText = displayName or ""
		prompt.HoldDuration = CFG.PickupHoldDuration or 1.2
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt:SetAttribute("OwnerUserId", player.UserId)
		prompt:SetAttribute("PromptOffset", Vector3.new(0, 1.5, 0))
		prompt.Parent = anchor
		local uid = record.Uid
		prompt.Triggered:Connect(function(who)
			if who == player then self:PickUp(player, uid) end
		end)
	end
	model.Parent = folder
	spawned[player] = spawned[player] or {}
	spawned[player][record.Uid] = model
	return model
end

function BaseDecorService:_clearSpawned(player)
	local list = spawned[player]
	spawned[player] = nil
	for _, model in list or {} do
		if model.Parent then model:Destroy() end
	end
end

-- Разовые переносы из ранней v14: отдельный инвентарь базы (data.BaseItems)
-- → обычный data.Gear; реликвии без ключа в инвентаре → ключ.
local function migrate(data)
	data.Gear = data.Gear or {}
	if type(data.BaseItems) == "table" then
		for itemId, count in data.BaseItems do
			if PlaceableCatalog.Info(itemId) and (tonumber(count) or 0) > 0 then
				data.Gear[itemId] = gearCount(data, itemId) + math.floor(count)
			end
		end
		data.BaseItems = nil
	end
	for _, relic in data.Relics do
		local key = BaseDecorService.RelicKey(relic)
		if not relicIsPlaced(data, relic.Uid) and gearCount(data, key) <= 0 then
			data.Gear[key] = 1
		end
	end
	-- v20: книга трофеев. Старые профили: всё, что сейчас лежит в Relics,
	-- считаем найденным.
	if type(data.RelicsFound) ~= "table" then data.RelicsFound = {} end
	if data.RelicsFoundMigrated ~= true then
		data.RelicsFoundMigrated = true
		for _, relic in data.Relics do
			local entry = data.RelicsFound[relic.Id] or { Count = 0, BestSerial = 0, FirstAt = relic.FoundAt or 0 }
			entry.Count += 1
			local serial = tonumber(relic.Serial) or 0
			if serial > 0 and (entry.BestSerial == 0 or serial < entry.BestSerial) then entry.BestSerial = serial end
			data.RelicsFound[relic.Id] = entry
		end
	end
end

-- v20: книга трофеев на клиенте читает атрибуты игрока
-- RelicFound_<Id> (сколько раз найдено) и RelicBest_<Id> (лучший серийник).
local function publishRelicsFound(player, data)
	for relicId in RELICS.Types do
		local entry = data.RelicsFound and data.RelicsFound[relicId]
		player:SetAttribute("RelicFound_" .. relicId, entry and entry.Count or 0)
		player:SetAttribute("RelicBest_" .. relicId, entry and entry.BestSerial or 0)
	end
end

function BaseDecorService:SetupPlot(player, plot)
	self:_clearSpawned(player)
	local data = dataOf(player)
	if not (data and plot and plot.Pad) then return end
	migrate(data)
	local valid = {}
	for _, record in data.PlacedDecor do
		local ok = typeof(record) == "table" and typeof(record.Uid) == "string"
		if ok and record.Item then
			ok = PlaceableCatalog.Info(record.Item) ~= nil
		elseif ok and record.RelicUid then
			ok = findRelic(data, record.RelicUid) ~= nil
		else
			ok = false
		end
		if ok then table.insert(valid, record) end
	end
	data.PlacedDecor = valid
	for _, record in data.PlacedDecor do
		local ok, err = pcall(self._spawnRecord, self, player, plot, record)
		if not ok then warn("[BaseDecorService] не удалось поставить", record.Item or record.RelicUid, err) end
	end
	self:_recompute(player)
end

--------------------------------------------------------------------------------
-- ПОСТАВИТЬ (из руки) / ПОДНЯТЬ
--------------------------------------------------------------------------------
local function fail(player, text)
	if Services.NotifyService then Services.NotifyService:Show(player, text, { Icon = "Error", Duration = 2 }) end
	return false, text
end

function BaseDecorService:PlaceFromGear(player, key, targetCFrame)
	if typeof(key) ~= "string" or typeof(targetCFrame) ~= "CFrame" then return false end
	if placing[player] then return false end
	local data = dataOf(player)
	local plot = Services.PlotService:GetPlot(player)
	if not (data and plot and plot.Pad and plot.Content) then return fail(player, "You need a base first") end
	if gearCount(data, key) <= 0 then return false end

	local itemInfo = PlaceableCatalog.Info(key)
	local relicUid = nil
	if not itemInfo then
		local relicId, _, uid = BaseDecorService.ParseRelicKey(key)
		local relic = uid and findRelic(data, uid)
		if not (relic and relic.Id == relicId) then return false end
		if relicIsPlaced(data, uid) then return false end
		relicUid = uid
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local position = targetCFrame.Position
	if not hrp or (hrp.Position - position).Magnitude > (CFG.PlaceRange or 60) then return fail(player, "Too far away") end
	-- v14.4: территория — весь прямоугольник PlotTemplate.
	if not GroundCheck.InPlot(plot.Pad, position) then
		return fail(player, "Only on your own base!")
	end
	-- v14.4: ЛЮБАЯ ПОВЕРХНОСТЬ — пол, стена, склон, другой предмет. Тот же
	-- луч, что у призрака: вдоль «верха» предмета, который прислал клиент.
	local ignore = { workspace:FindFirstChild("MineGroundOre") }
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(ignore, other.Character) end
	end
	local onSurface, surfacePosition, surfaceNormal, surface = GroundCheck.Surface(position, targetCFrame.UpVector, ignore)
	if not onSurface then return fail(player, "Can't place it here!") end
	-- Итоговый поворот считает СЕРВЕР по настоящей нормали; от клиента
	-- берём только доворот вокруг неё.
	local rotation
	if GroundCheck.IsUpright(surfaceNormal) then
		local _, clientYaw = targetCFrame:ToOrientation()
		rotation = CFrame.Angles(0, clientYaw, 0)
	elseif targetCFrame.UpVector:Dot(surfaceNormal) > 0.95 then
		rotation = targetCFrame.Rotation
	else
		rotation = GroundCheck.Orientation(surfaceNormal, 0)
	end
	local snapped = CFrame.new(surfacePosition) * rotation
	local relative = plot.Pad.CFrame:ToObjectSpace(snapped)
	local rp = relative.Position
	-- Не впритык к другому предмету. Если ставим ПРЯМО НА другой предмет,
	-- проверку расстояния пропускаем: «впритык» тут и есть задумка.
	local onDecor = surface and surface:FindFirstAncestorWhichIsA("Model")
	while onDecor and onDecor:GetAttribute("BaseDecorUid") == nil do
		onDecor = onDecor.Parent and onDecor.Parent:FindFirstAncestorWhichIsA("Model")
	end
	for _, record in (onDecor and {} or data.PlacedDecor) do
		local dx, dy, dz = (record.X or 0) - rp.X, (record.Y or 0) - rp.Y, (record.Z or 0) - rp.Z
		if math.sqrt(dx * dx + dy * dy + dz * dz) < (CFG.MinSpacing or 2) then
			return fail(player, "Too close to another item")
		end
	end
	local rx, yaw, rz = relative:ToOrientation()

	placing[player] = true
	local record = {
		Uid = nextUid(data),
		Item = itemInfo and key or nil,
		RelicUid = relicUid,
		X = math.floor(rp.X * 100 + 0.5) / 100,
		Y = math.floor(rp.Y * 100 + 0.5) / 100,
		Z = math.floor(rp.Z * 100 + 0.5) / 100,
		R = math.floor(math.deg(yaw) * 10 + 0.5) / 10,
		-- v14.4: полный поворот (предмет может висеть на стене/склоне).
		RX = math.floor(math.deg(rx) * 10 + 0.5) / 10,
		RY = math.floor(math.deg(yaw) * 10 + 0.5) / 10,
		RZ = math.floor(math.deg(rz) * 10 + 0.5) / 10,
	}
	table.insert(data.PlacedDecor, record)
	local ok, model = pcall(self._spawnRecord, self, player, plot, record)
	if not (ok and model) then
		table.remove(data.PlacedDecor, #data.PlacedDecor)
		placing[player] = nil
		return fail(player, "Could not place")
	end
	Services.GearService:AddGear(player, key, -1)
	placing[player] = nil
	self:_recompute(player)
	if Services.QuestService then pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "ItemsPlaced", 1) end
	return true
end

-- Что стоит СВЕРХУ на предмете uid (v14.3: ставить можно друг на друга).
-- Короткий луч вниз из-под каждого другого предмета; если первым он
-- упирается в модель uid — тот предмет «опирается» на неё.
function BaseDecorService:_itemsResting(player, uid)
	local list = {}
	local mine = spawned[player]
	local base = mine and mine[uid]
	if not (base and base.Parent) then return list end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { base }
	for otherUid, model in mine do
		if otherUid ~= uid and model.Parent then
			local pivot = model:GetPivot()
			if workspace:Raycast(pivot.Position + pivot.UpVector * 0.6, -pivot.UpVector * 1.6, params) then
				table.insert(list, otherUid)
			end
		end
	end
	return list
end

function BaseDecorService:PickUp(player, uid, _cascade)
	-- Сначала снимаем всё, что стоит сверху, — иначе оно повиснет в воздухе.
	for _, restingUid in self:_itemsResting(player, uid) do
		self:PickUp(player, restingUid, true)
	end
	local data = dataOf(player)
	if not data then return false end
	local record, index = findPlaced(data, uid)
	if not record then return false end
	local key, name
	if record.Item then
		key = record.Item
		local info = PlaceableCatalog.Info(record.Item)
		name = info and info.DisplayName or record.Item
	else
		local relic = findRelic(data, record.RelicUid)
		if not relic then return false end
		key = BaseDecorService.RelicKey(relic)
		local info = RELICS.Types[relic.Id]
		name = info and info.DisplayName or "Relic"
	end
	table.remove(data.PlacedDecor, index)
	local model = spawned[player] and spawned[player][uid]
	if model then
		spawned[player][uid] = nil
		if model.Parent then model:Destroy() end
	end
	Services.GearService:AddGear(player, key, 1)
	self:_recompute(player)
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("%s → inventory"):format(name), { Icon = "Crystal", Duration = 2 })
	end
	return true
end

--------------------------------------------------------------------------------
-- РЕЛИКВИИ
--------------------------------------------------------------------------------
-- Бросок реликвии. opts: { Plot, Perfect, StreakBonus, Golden, Chest = rarity }.
function BaseDecorService:RollRelic(player, tier, opts)
	opts = opts or {}
	if opts.Golden then
		local total = 0
		for _, weight in RELICS.GoldenWeights do total += weight end
		local pick = math.random() * total
		for _, relicId in RELICS.Order do
			pick -= RELICS.GoldenWeights[relicId] or 0
			if pick <= 0 then return relicId end
		end
		return RELICS.Order[1]
	end
	local multiplier = 1 + (RELICS.TierChanceBonus or 0) * math.max(0, (tonumber(tier) or 1) - 1)
	if opts.Plot then multiplier *= RELICS.PlotBoulderMultiplier or 1 end
	if opts.Perfect then multiplier *= RELICS.PerfectMultiplier or 1 end
	if opts.Chest then multiplier *= (RELICS.ChestMultiplier or {})[opts.Chest] or 1 end
	multiplier *= 1 + math.max(0, tonumber(opts.StreakBonus) or 0)
	multiplier *= 1 + self:GetLuckBonus(player)
	for index = #RELICS.Order, 1, -1 do
		local relicId = RELICS.Order[index]
		local info = RELICS.Types[relicId]
		if info and math.random() < info.Chance * multiplier then
			return relicId
		end
	end
	return nil
end

function BaseDecorService:_nextSerial(relicId)
	if not serialStore then return 0 end
	for attempt = 1, 3 do
		local ok, value = pcall(function()
			return serialStore:IncrementAsync(relicId, 1)
		end)
		if ok and tonumber(value) then return tonumber(value) end
		task.wait(attempt)
	end
	return 0
end

local function announceRelic(finderName, relicId, serial, global)
	local info = RELICS.Types[relicId]
	if not (info and Services.AnnounceService) then return end
	local color = PlaceableCatalog.RarityColor(info.Rarity)
	pcall(function()
		Services.AnnounceService:Broadcast(nil, nil, {
			{ Text = global and "🌍 " or "🏆 ", Color = Color3.new(1, 1, 1) },
			{ Text = finderName, Color = Color3.fromRGB(255, 235, 150) },
			{ Text = " found a ", Color = Color3.new(1, 1, 1) },
			{ Text = ("%s RELIC: %s #%s"):format(string.upper(info.Rarity), info.DisplayName, serial > 0 and tostring(serial) or "?"), Color = color },
			{ Text = "!", Color = Color3.new(1, 1, 1) },
		})
	end)
end

-- Выдать реликвию в инвентарь. Йилдит (серийник из DataStore).
function BaseDecorService:GrantRelic(player, relicId, source)
	local info = RELICS.Types[relicId]
	if not (info and dataOf(player)) then return nil end
	local serial = self:_nextSerial(relicId)
	local data = dataOf(player) -- профиль мог выгрузиться, пока ждали DataStore
	if not data then return nil end
	local record = {
		Uid = nextUid(data), Id = relicId, Serial = serial,
		FoundAt = os.time(), Finder = player.DisplayName, Source = tostring(source or ""),
	}
	table.insert(data.Relics, record)
	data.RelicsFound = data.RelicsFound or {}
	local found = data.RelicsFound[relicId] or { Count = 0, BestSerial = 0, FirstAt = record.FoundAt }
	found.Count += 1
	if serial > 0 and (found.BestSerial == 0 or serial < found.BestSerial) then found.BestSerial = serial end
	data.RelicsFound[relicId] = found
	publishRelicsFound(player, data)
	Services.GearService:AddGear(player, BaseDecorService.RelicKey(record), 1)
	task.spawn(function() pcall(Services.DataService.SaveProfile, Services.DataService, player) end)

	announceRelic(player.DisplayName, relicId, serial, false)
	if info.GlobalAnnounce then
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(GLOBAL_TOPIC, { Name = player.DisplayName, Id = relicId, Serial = serial, Job = game.JobId })
			end)
		end)
	end
	local color = PlaceableCatalog.RarityColor(info.Rarity)
	Services.NotifyService:LootFeed(player, {
		{ Icon = info.Icon, Text = ("%s #%s"):format(info.DisplayName, serial > 0 and tostring(serial) or "?"), Color = color, Rarity = info.Rarity, Sub = "RELIC → inventory" },
	}, { Title = "RELIC FOUND!", Color = color })
	return record
end

--------------------------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ
--------------------------------------------------------------------------------
function BaseDecorService:Init(services)
	Services = services
	local ok, store = pcall(function() return DataStoreService:GetDataStore(RELICS.SerialDataStore or "RelicSerials_v1") end)
	if ok then serialStore = store else warn("[BaseDecorService] DataStore серийников недоступен:", store) end
	Players.PlayerRemoving:Connect(function(player)
		spawned[player] = nil
		buffCache[player] = nil
		placing[player] = nil
	end)
end

function BaseDecorService:Start()
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(GLOBAL_TOPIC, function(message)
				local payload = message and message.Data
				if typeof(payload) ~= "table" or payload.Job == game.JobId then return end
				announceRelic(tostring(payload.Name or "Someone"), tostring(payload.Id), tonumber(payload.Serial) or 0, true)
			end)
		end)
	end)
end

function BaseDecorService:SetupPlayer(player)
	local data = dataOf(player)
	if data then
		migrate(data)
		publishRelicsFound(player, data)
	end
	self:_recompute(player)
	if Services.InventoryService and Services.InventoryService.Sync then
		pcall(Services.InventoryService.Sync, Services.InventoryService, player)
	end
end

return BaseDecorService
