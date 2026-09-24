--------------------------------------------------------------------------------
-- LeaderboardService
-- Three global OrderedDataStore rankings rendered on physical boards at every
-- plot. Values are batched to protect the DataStore request budget.
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
	{ Key = "Money", PartName = "MoneyBoard", Title = "TOP MONEY", Color = Color3.fromRGB(255, 211, 75) },
	{ Key = "Rebirths", PartName = "RebirthBoard", Title = "TOP PRESTIGE", Color = Color3.fromRGB(105, 225, 255) },
	{ Key = "PlayTime", PartName = "CartDamageBoard", Title = "TOP PLAYTIME", Color = Color3.fromRGB(255, 105, 105), IsTime = true },
}

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

local function renderBoard(part, spec, entries, errorText)
	local old = part:FindFirstChild("LeaderboardGui")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Config.Leaderboards.BoardFace
	gui.CanvasSize = Vector2.new(700, 900)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	background.BorderSizePixel = 0
	background.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 110)
	title.BackgroundColor3 = spec.Color
	title.BorderSizePixel = 0
	title.Font = Enum.Font.Arcade
	title.Text = spec.Title
	title.TextColor3 = Color3.fromRGB(20, 22, 26)
	title.TextSize = 45
	title.Parent = background

	local status = errorText or (#entries == 0 and "NO PLAYERS YET" or nil)
	if status then
		local label = Instance.new("TextLabel")
		label.Position = UDim2.new(0, 25, 0, 135)
		label.Size = UDim2.new(1, -50, 1, -160)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.Text = status
		label.TextColor3 = Color3.fromRGB(190, 195, 205)
		label.TextSize = 31
		label.TextWrapped = true
		label.Parent = background
		return
	end

	for rank, entry in entries do
		local row = Instance.new("Frame")
		row.Position = UDim2.new(0, 20, 0, 125 + (rank - 1) * 73)
		row.Size = UDim2.new(1, -40, 0, 62)
		row.BackgroundColor3 = rank % 2 == 1 and Color3.fromRGB(31, 34, 43) or Color3.fromRGB(25, 28, 36)
		row.BorderSizePixel = 0
		row.Parent = background

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, 70, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Font = Enum.Font.Arcade
		rankLabel.Text = "#" .. rank
		rankLabel.TextColor3 = rank <= 3 and spec.Color or Color3.fromRGB(185, 190, 200)
		rankLabel.TextSize = 27
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Position = UDim2.new(0, 75, 0, 0)
		nameLabel.Size = UDim2.new(1, -255, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Arcade
		nameLabel.Text = entry.Name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextSize = 25
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.AnchorPoint = Vector2.new(1, 0)
		valueLabel.Position = UDim2.fromScale(1, 0)
		valueLabel.Size = UDim2.new(0, 175, 1, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.Arcade
		valueLabel.Text = spec.IsTime and formatPlayTime(entry.Value) or formatNumber(entry.Value)
		valueLabel.TextColor3 = spec.Color
		valueLabel.TextSize = 27
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Parent = row
	end
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
			table.insert(entries, { Name = playerName(userId), Value = value })
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
					table.insert(entries, { Name = playerName(userId), Value = value })
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
	end
end

function LeaderboardService:SetupPlot(plot)
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
