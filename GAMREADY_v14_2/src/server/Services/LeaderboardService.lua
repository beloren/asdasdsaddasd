--------------------------------------------------------------------------------
-- LeaderboardService
-- v20.82: ТРИ ГЛОБАЛЬНЫХ ТОПА В ЦЕНТРЕ ГОРОДА - деньги, престиж, донат
-- (потраченные Robux: девпродукты + геймпассы). Каждая доска - стенд
-- Workspace/.../LeaderboardStands/<Spec>Stand (строит tools/BuildIslandMap):
--   Board      - BasePart, на его передней грани рисуется топ-10;
--   Plate      - табличка на постаменте «#1 ник · значение»;
--   StatueSpot - где стоит R6-риг игрока с 1-го места (как есть: одежда,
--                аксессуары), смотрит туда же, куда деталь.
-- Нет стендов на карте - строятся простые у банка. Доски у баз выключены
-- (Config.Leaderboards.PerPlotBoards).
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local LeaderboardService = {}

local Services = nil
local boards = {}
local stores = {}
local moneyValueStore = nil
local profileStore = nil
local legacyMoneyStore = nil
local lastPublished = {}
local nameCache = {}
local sessionStarted = {}

local SPECS = {
	{ Key = "Money", PartName = "MoneyBoard", Stand = "MoneyStand", Title = "Top Money", Color = Color3.fromRGB(110, 240, 140) },
	{ Key = "Rebirths", PartName = "RebirthBoard", Stand = "PrestigeStand", Title = "Top Prestige", Color = Color3.fromRGB(255, 95, 120) },
	{ Key = "Donated", PartName = "DonationBoard", Stand = "DonationStand", Title = "Top Robux Spent", Color = Color3.fromRGB(255, 214, 60), Prefix = "R$ " },
}
local stands = {} -- [spec.Key] = { Board=, Plate=, Spot=, StatueUserId=, Statue= }

local function formatNumber(value)
	if BigNum.is(value) then
		return NumberFormat.abbreviate(value)
	end
	value = math.floor(tonumber(value) or 0)
	local absValue = math.abs(value)
	for _, unit in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if absValue >= unit[1] then
			local shortened = value / unit[1]
			return shortened >= 100 and ("%.0f%s"):format(shortened, unit[2]) or ("%.1f%s"):format(shortened, unit[2])
		end
	end
	return tostring(value)
end

local function formatPlayTime(value)
	local seconds = math.max(0, math.floor(tonumber(value) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor(seconds % 86400 / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if days > 0 then return ("%dd %dh"):format(days, hours) end
	if hours > 0 then return ("%dh %dm"):format(hours, minutes) end
	return ("%dm %ds"):format(minutes, seconds % 60)
end

local function playerName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local name = ok and result or ("User " .. userId)
	nameCache[userId] = name
	return name
end

local MONEY_SCORE_EXPONENT_SCALE = 1000000000
local MONEY_SCORE_MANTISSA_SCALE = 100000000

local function moneyRankScore(money)
	money = BigNum.new(money)
	if not money:isPositive() then
		return 0
	end
	-- OrderedDataStore принимает только number, поэтому сортируем BigNum через
	-- компактный score: сначала порядок 10^e, затем мантисса.
	return math.max(0, money.e * MONEY_SCORE_EXPONENT_SCALE + math.floor(money.m * MONEY_SCORE_MANTISSA_SCALE))
end

local function moneyFromRankScore(score)
	score = math.max(0, math.floor(tonumber(score) or 0))
	local exponent = math.floor(score / MONEY_SCORE_EXPONENT_SCALE)
	local mantissa = (score % MONEY_SCORE_EXPONENT_SCALE) / MONEY_SCORE_MANTISSA_SCALE
	return BigNum.fromData({ s = score > 0 and 1 or 0, m = mantissa, e = exponent })
end

local function valueFor(player, key)
	if key == "Money" then
		local money = Services.DataService:GetMoney(player)
		return moneyRankScore(money), money:toData()
	elseif key == "Rebirths" then
		return Services.DataService:GetRebirths(player)
	elseif key == "PlayTime" then
		return Services.DataService:GetPlayTime(player) + math.max(0, os.time() - (sessionStarted[player] or os.time()))
	elseif key == "Donated" then
		return Services.DataService:GetRobuxSpent(player)
	end
	return Services.DataService:GetCartDamage(player)
end

local function moneyDisplayValue(userId, fallback)
	if moneyValueStore then
		local ok, data = pcall(moneyValueStore.GetAsync, moneyValueStore, tostring(userId))
		if ok and data ~= nil then
			return BigNum.fromData(data)
		end
		if not ok then
			warn("[LeaderboardService] Не удалось прочитать MoneyValue для " .. tostring(userId) .. ":", data)
		end
	end
	if profileStore then
		local ok, data = pcall(profileStore.GetAsync, profileStore, "profile_" .. tostring(userId))
		if ok and typeof(data) == "table" and data.Money ~= nil then
			return BigNum.fromData(data.Money)
		end
		if not ok then
			warn("[LeaderboardService] Не удалось прочитать профиль для Money leaderboard " .. tostring(userId) .. ":", data)
		end
	end
	return fallback
end

-- v20.106: ДЕРЕВЯННЫЙ СТИЛЬ (как на референсе). v20.117: рисование вынесено
-- в Shared.LeaderboardBoardGui - тот же вид показывает пример в Studio
-- (tools/BuildLeaderboardStands). Внизу доски - место под строку игрока
-- («YouRow»): её рисует клиент (LeaderboardSelfRow), значения игрока сервер
-- кладёт в атрибуты LbValue_<Key>.
local BoardGui = require(ReplicatedStorage.Shared.LeaderboardBoardGui)

local function formatValue(spec, value)
	return spec.IsTime and formatPlayTime(value) or ((spec.Prefix or "") .. formatNumber(value))
end

local function renderBoard(part, spec, entries, errorText)
	BoardGui.Board(part, spec, entries, {
		Format = formatValue,
		Status = errorText,
		Face = Config.Leaderboards.BoardFace,
	})
end

local function fetchEntries(spec)
	local store = stores[spec.Key]
	if not store then
		return {}, "DATASTORE UNAVAILABLE"
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, Config.Leaderboards.TopCount)
	if not ok then
		warn("[LeaderboardService] Не удалось прочитать рейтинг " .. spec.Key .. ":", pages)
		return {}, "ENABLE API SERVICES TO LOAD GLOBAL DATA"
	end
	local entries = {}
	local seen = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			seen[userId] = true
			local value = spec.Key == "Money" and moneyDisplayValue(userId, moneyFromRankScore(item.value)) or item.value
			table.insert(entries, { Name = playerName(userId), Value = value, UserId = userId })
		end
	end
	if spec.Key == "Money" and legacyMoneyStore then
		local legacyOk, legacyPages = pcall(legacyMoneyStore.GetSortedAsync, legacyMoneyStore, false, Config.Leaderboards.TopCount)
		if legacyOk then
			for _, item in legacyPages:GetCurrentPage() do
				local userId = tonumber(item.key)
				if userId and not seen[userId] then
					seen[userId] = true
					local value = moneyDisplayValue(userId, BigNum.new(item.value))
					table.insert(entries, { Name = playerName(userId), Value = value, UserId = userId })
				end
			end
		else
			warn("[LeaderboardService] Не удалось прочитать старый Money рейтинг:", legacyPages)
		end
		table.sort(entries, function(a, b)
			return BigNum.gt(a.Value, b.Value)
		end)
		while #entries > Config.Leaderboards.TopCount do
			table.remove(entries)
		end
	end
	return entries, nil
end

--------------------------------------------------------------------------------
-- v20.85: ТОП-1 НА ПОСТАМЕНТЕ - обычный R6-риг игрока как есть (одежда,
-- лицо, аксессуары, цвета). Корень заякорен, остальное держится на
-- сварках - поэтому сначала риг ставится в мир, сварки раскладывают
-- аксессуары и конечности по местам, и только потом ноги сажаются ровно на
-- постамент (раньше всё якорилось сразу: аксессуары оставались в центре
-- мира, габарит «растягивался» вниз - и риг висел в воздухе).
--------------------------------------------------------------------------------
local function buildRig(userId)
	local okDesc, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
	if not okDesc or not description then return nil end
	local okModel, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R6)
	if not okModel or not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		model:Destroy()
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanTouch = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
	end
	model.PrimaryPart = root
	model.Name = "TopPlayer"
	return model, root
end

local function feetBottom(model)
	local lowest = nil
	for _, name in { "Left Leg", "Right Leg" } do
		local leg = model:FindFirstChild(name)
		if leg and leg:IsA("BasePart") then
			local bottom = leg.Position.Y - leg.Size.Y / 2
			lowest = lowest and math.min(lowest, bottom) or bottom
		end
	end
	if lowest then return lowest end
	local boxCF, size = model:GetBoundingBox()
	return boxCF.Position.Y - size.Y / 2
end

local function placeStatue(stand, userId)
	if stand.StatueUserId == userId and stand.Statue and stand.Statue.Parent then return end
	if stand.Statue then stand.Statue:Destroy() end
	stand.Statue, stand.StatueUserId = nil, userId
	if not userId then return end
	local rig = buildRig(userId)
	if not rig then
		stand.StatueUserId = nil -- попробуем в следующий раз
		return
	end
	local spot = stand.Spot
	local topY = spot.Position.Y + spot.Size.Y / 2
	local facing = spot.CFrame.LookVector
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	-- R6: корень на 3 стада над подошвой - ставим примерно, потом точно.
	rig:PivotTo(CFrame.lookAt(Vector3.new(spot.Position.X, topY + 3, spot.Position.Z), Vector3.new(spot.Position.X, topY + 3, spot.Position.Z) + flat))
	rig.Parent = stand.Board.Parent
	-- дать сваркам разложить конечности и аксессуары
	for _ = 1, 3 do task.wait() end
	if not rig.Parent then return end
	rig:PivotTo(rig:GetPivot() + Vector3.new(0, topY - feetBottom(rig), 0))
	stand.Statue = rig
end

local function renderPlate(stand, spec, entry)
	local plate = stand.Plate
	if not (plate and plate.Parent) then return end
	BoardGui.Plate(plate, spec,
		entry and ("#1 " .. entry.Name) or "#1 ???",
		entry and ((spec.Prefix or "") .. formatNumber(entry.Value)) or spec.Title)
end

-- Простые стенды у банка, если на карте нет LeaderboardStands.
local function buildFallbackStands()
	local folder = Instance.new("Model")
	folder.Name = "LeaderboardStands"
	local sellZone = Services.WorldService and Services.WorldService:GetSellZone()
	local center = sellZone and sellZone.Position or Vector3.zero
	local base = CFrame.new(center + Vector3.new(0, 0, 50)) * CFrame.Angles(0, 0, 0)
	local lookCF = CFrame.lookAt(base.Position, Vector3.new(center.X, base.Position.Y, center.Z))
	local function part(parent, name, size, cf, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end
	for index, spec in SPECS do
		local stand = Instance.new("Model")
		stand.Name = spec.Stand
		stand.Parent = folder
		local cf = lookCF * CFrame.new((index - 2) * 17, 0, 0)
		part(stand, "Board", Vector3.new(13, 16, 0.8), cf * CFrame.new(0, 16, 0), BoardGui.Colors.WoodDark)
		part(stand, "Pedestal", Vector3.new(5, 3, 5), cf * CFrame.new(0, 1.5, -6), Color3.fromRGB(120, 122, 130))
		part(stand, "Plate", Vector3.new(4.6, 1.4, 0.2), cf * CFrame.new(0, 1.6, -8.6), BoardGui.Colors.WoodDark)
		local spot = part(stand, "StatueSpot", Vector3.new(2, 0.2, 2), cf * CFrame.new(0, 3.1, -6), Color3.new(1, 1, 1))
		spot.Transparency = 1
		spot.CanCollide = false
	end
	folder.Parent = workspace
	return folder
end

function LeaderboardService:_setupStands()
	local folder = workspace:FindFirstChild("LeaderboardStands", true) or buildFallbackStands()
	for _, spec in SPECS do
		local standModel = folder:FindFirstChild(spec.Stand)
		local board = standModel and standModel:FindFirstChild("Board", true)
		if board and board:IsA("BasePart") then
			-- превью из tools/BuildLeaderboardStands - в игре заменяем настоящим
			for _, name in { "StatuePreview" } do
				local preview = standModel:FindFirstChild(name, true)
				if preview then preview:Destroy() end
			end
			local spot = standModel:FindFirstChild("StatueSpot", true)
			local plate = standModel:FindFirstChild("Plate", true)
			local oldPlateGui = plate and plate:FindFirstChild("PlateGui")
			if oldPlateGui then oldPlateGui:Destroy() end
			stands[spec.Key] = { Board = board, Plate = plate, Spot = spot and spot:IsA("BasePart") and spot or nil }
			renderBoard(board, spec, {}, nil)
			renderPlate(stands[spec.Key], spec, nil)
		else
			warn("[LeaderboardService] В LeaderboardStands нет " .. spec.Stand .. "/Board - доска " .. spec.Title .. " не показывается.")
		end
	end
end

function LeaderboardService:Init(services)
	Services = services
	for _, spec in SPECS do
		local storeName = Config.Leaderboards.StorePrefix .. "_" .. spec.Key
		if spec.Key == "Money" then
			storeName = storeName .. "_BigNumScore_v1"
		end
		local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, storeName)
		if ok then
			stores[spec.Key] = result
		else
			warn("[LeaderboardService] OrderedDataStore недоступен для " .. spec.Key .. ":", result)
		end
	end
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Config.Leaderboards.StorePrefix .. "_MoneyBigNumValue_v1")
	if ok then
		moneyValueStore = result
	else
		warn("[LeaderboardService] DataStore недоступен для MoneyBigNumValue:", result)
	end
	ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Config.Data.StoreName)
	if ok then
		profileStore = result
	else
		warn("[LeaderboardService] DataStore профилей недоступен для Money leaderboard:", result)
	end
	ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Config.Leaderboards.StorePrefix .. "_Money")
	if ok then
		legacyMoneyStore = result
	else
		warn("[LeaderboardService] Старый Money OrderedDataStore недоступен:", result)
	end
end

function LeaderboardService:Start()
	task.spawn(function()
		task.wait(3)
		local ok, err = pcall(self._setupStands, self)
		if not ok then warn("[LeaderboardService] Стенды топов не построены:", err) end
		while true do
			self:Refresh()
			task.wait(Config.Leaderboards.RefreshInterval)
		end
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			self:_commitPlayTime(player)
			self:_publishPlayer(player)
		end
	end)
end

function LeaderboardService:SetupPlayer(player)
	lastPublished[player.UserId] = {}
	sessionStarted[player] = os.time()
end

function LeaderboardService:_commitPlayTime(player)
	local startedAt = sessionStarted[player]
	if not startedAt then return end
	local now = os.time()
	Services.DataService:AddPlayTime(player, math.max(0, now - startedAt))
	sessionStarted[player] = now
end

function LeaderboardService:_publishPlayer(player)
	local previous = lastPublished[player.UserId] or {}
	lastPublished[player.UserId] = previous
	for _, spec in SPECS do
		local value, displayValue = valueFor(player, spec.Key)
		value = math.floor(math.max(0, value))
		-- v20.106: своя строка внизу доски (клиент LeaderboardSelfRow)
		if spec.Key == "Money" then
			player:SetAttribute("LbValue_" .. spec.Key, "$" .. NumberFormat.abbreviate(Services.DataService:GetMoney(player)))
		else
			player:SetAttribute("LbValue_" .. spec.Key, formatValue(spec, value))
		end
		if previous[spec.Key] ~= value and stores[spec.Key] then
			-- ФИКС "ТОПЫ ДОЛЖНЫ СОХРАНЯТЬСЯ ПО САМОМУ БОЛЬШОМУ РЕЗУЛЬТАТУ":
			-- раньше здесь был SetAsync, который слепо ЗАПИСЫВАЛ ТЕКУЩЕЕ
			-- значение поверх старого — если игрок потратил деньги (или
			-- любое другое значение временно упало), его рекорд в топе
			-- стирался текущим, более низким числом. UpdateAsync с
			-- max(старое, новое) — рекорд может только РАСТИ, никогда не
			-- уменьшается, независимо от того, что происходит с текущим
			-- значением у игрока. OrderedDataStore и так общий на ВСЮ игру
			-- (не привязан к конкретному серверу/JobId), поэтому "движение
			-- между серверами" уже работает само собой — не хватало только
			-- этого "не понижать" правила.
			local ok, err = pcall(stores[spec.Key].UpdateAsync, stores[spec.Key], tostring(player.UserId), function(oldValue)
				return math.max(oldValue or 0, value)
			end)
			local displayOk = true
			local displayErr = nil
			if ok and spec.Key == "Money" and moneyValueStore and displayValue then
				displayOk, displayErr = pcall(moneyValueStore.UpdateAsync, moneyValueStore, tostring(player.UserId), function(oldData)
					local oldMoney = BigNum.fromData(oldData)
					local newMoney = BigNum.fromData(displayValue)
					return BigNum.gt(oldMoney, newMoney) and oldMoney:toData() or newMoney:toData()
				end)
			end
			if ok and displayOk then
				previous[spec.Key] = value
			else
				warn("[LeaderboardService] Не удалось записать " .. spec.Key .. " для " .. player.Name .. ":", err or displayErr)
			end
		end
	end
end

function LeaderboardService:Refresh()
	for _, player in Players:GetPlayers() do
		self:_commitPlayTime(player)
		self:_publishPlayer(player)
	end
	for _, spec in SPECS do
		local entries, errorText = fetchEntries(spec)
		for _, boardSet in boards do
			local part = boardSet[spec.PartName]
			if part and part.Parent then
				renderBoard(part, spec, entries, errorText)
			end
		end
		local stand = stands[spec.Key]
		if stand and stand.Board.Parent then
			renderBoard(stand.Board, spec, entries, errorText)
			renderPlate(stand, spec, entries[1])
			if stand.Spot then
				local ok, err = pcall(placeStatue, stand, entries[1] and entries[1].UserId or nil)
				if not ok then warn("[LeaderboardService] Статуя " .. spec.Title .. ":", err) end
			end
		end
	end
end

function LeaderboardService:SetupPlot(plot)
	-- v20.82: доски у каждой базы выключены - топы стоят в центре города.
	if not Config.Leaderboards.PerPlotBoards then return end
	if not plot.LeaderboardCFrame or not plot.Template then
		return
	end
	local model = PlaceholderFactory.LeaderboardBoards()
	model.Name = "LeaderboardBoards"
	model:PivotTo(plot.LeaderboardCFrame)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model.Parent = plot.Template

	local boardSet = { Model = model }
	for _, spec in SPECS do
		local part = model:FindFirstChild(spec.PartName, true)
		assert(part and part:IsA("BasePart"), "LeaderboardBoards обязан содержать BasePart '" .. spec.PartName .. "'")
		boardSet[spec.PartName] = part
		renderBoard(part, spec, {}, nil)
	end
	table.insert(boards, boardSet)
end

function LeaderboardService:CleanupPlayer(player)
	self:_commitPlayTime(player)
	self:_publishPlayer(player)
	sessionStarted[player] = nil
	lastPublished[player.UserId] = nil
end

return LeaderboardService
