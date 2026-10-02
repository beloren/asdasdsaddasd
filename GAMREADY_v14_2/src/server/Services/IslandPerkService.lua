--------------------------------------------------------------------------------
-- IslandPerkService (v20.140) — МИНИ-ДЕРЕВЬЯ ОСТРОВОВ (Config.IslandPerks).
-- У каждого купленного острова - две «звезды» с уровнями и финальный узел,
-- который открывается, когда обе звезды прокачаны до конца. НЕ сбрасываются
-- при престиже (острова тоже остаются).
--   data.IslandPerks = { AnvilCrystal = 3, AnvilFinal = 1, ... }
--   IslandPerkService:Bonus(player, "IncomeRate")      -> доля
--   IslandPerkService.BonusData(data, "SmeltSpeed")     -> доля (без игрока)
-- Клиенту: атрибуты IslandPerk_<Effect> (суммарная доля по эффекту) и
-- RemoteFunction IslandPerkRequest ("Get" / "Buy", perkId).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local IslandPerkService = {}
local Services
local lastBuy = {}

local function cfg()
	return Config.IslandPerks or { Order = {}, Islands = {} }
end

-- perkId -> { Island = id, Def = def, IsFinal = bool }
local perkIndex = {}
local function rebuildIndex()
	table.clear(perkIndex)
	for islandId, island in cfg().Islands do
		for _, def in island.Stars or {} do
			perkIndex[def.Id] = { Island = islandId, Def = def, IsFinal = false }
		end
		if island.Final then
			perkIndex[island.Final.Id] = { Island = islandId, Def = island.Final, IsFinal = true }
		end
	end
end
rebuildIndex()

local function levelIn(data, perkId)
	local perks = data and data.IslandPerks
	return type(perks) == "table" and math.max(0, math.floor(tonumber(perks[perkId]) or 0)) or 0
end

local function valueOf(entry, level)
	if level <= 0 then return 0 end
	if entry.IsFinal then return entry.Def.Value or 0 end
	return level * (entry.Def.PerLevel or 0)
end

-- Сумма по эффекту (у звезды и финала может быть один Effect).
function IslandPerkService.BonusData(data, effect)
	if not data then return 0 end
	local total = 0
	for perkId, entry in perkIndex do
		if (entry.Def.Effect or perkId) == effect then
			total += valueOf(entry, levelIn(data, perkId))
		end
	end
	return total
end

function IslandPerkService:Bonus(player, effect)
	return IslandPerkService.BonusData(Services.DataService:GetGeodeData(player), effect)
end

local function costOf(entry, level)
	if entry.IsFinal then return entry.Def.Cost or 0 end
	local raw = (entry.Def.CostBase or 1000) * (entry.Def.CostGrowth or 1.5) ^ level
	local digits = math.max(0, math.floor(math.log10(math.max(raw, 1))) - 1)
	local unit = 10 ^ digits
	return math.floor(raw / unit + 0.5) * unit
end

local function maxOf(entry)
	return entry.IsFinal and 1 or (entry.Def.MaxLevel or 10)
end

local function finalUnlocked(data, islandId)
	local island = cfg().Islands[islandId]
	for _, def in island and island.Stars or {} do
		if levelIn(data, def.Id) < (def.MaxLevel or 10) then return false end
	end
	return true
end

function IslandPerkService:State(player)
	local data = Services.DataService:GetGeodeData(player)
	local money = Services.DataService:GetMoney(player)
	local out = {}
	for perkId, entry in perkIndex do
		local level = levelIn(data, perkId)
		local maxLevel = maxOf(entry)
		local owned = Services.IslandService and Services.IslandService:Owns(player, entry.Island)
		local locked = not owned or (entry.IsFinal and not finalUnlocked(data, entry.Island))
		local cost = level < maxLevel and costOf(entry, level) or nil
		out[perkId] = {
			Level = level,
			MaxLevel = maxLevel,
			Value = valueOf(entry, level),
			NextValue = level < maxLevel and valueOf(entry, level + 1) or nil,
			Cost = cost,
			CanAfford = cost ~= nil and not BigNum.lt(money, cost),
			Locked = locked,
			Owned = owned,
		}
	end
	return out
end

local function publish(player)
	local data = Services.DataService:GetGeodeData(player)
	local effects = {}
	for perkId, entry in perkIndex do effects[entry.Def.Effect or perkId] = true end
	for effect in effects do
		player:SetAttribute("IslandPerk_" .. effect, IslandPerkService.BonusData(data, effect))
	end
end

function IslandPerkService:Buy(player, perkId)
	local entry = perkIndex[perkId]
	local data = Services.DataService:GetGeodeData(player)
	if not (entry and data) then return false, "Unknown" end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Try again" end
	local now = os.clock()
	if now - (lastBuy[player] or 0) < 0.15 then return false, "Slow down" end
	lastBuy[player] = now
	if not (Services.IslandService and Services.IslandService:Owns(player, entry.Island)) then return false, "Buy the island first" end
	if entry.IsFinal and not finalUnlocked(data, entry.Island) then return false, "Max both stars first" end
	if type(data.IslandPerks) ~= "table" then data.IslandPerks = {} end
	local level = levelIn(data, perkId)
	if level >= maxOf(entry) then return false, "Max level" end
	local cost = costOf(entry, level)
	if BigNum.lt(Services.DataService:GetMoney(player), cost) then
		if Services.MonetizationService then pcall(Services.MonetizationService.NotEnoughMoney, Services.MonetizationService, player, cost, "IslandPerk:" .. perkId) end
		return false, "Not enough money"
	end
	Services.DataService:AddMoney(player, -cost)
	data.IslandPerks[perkId] = level + 1
	publish(player)
	if Services.PassiveIncomeService and Services.PassiveIncomeService.UpdateDisplay then
		pcall(Services.PassiveIncomeService.UpdateDisplay, Services.PassiveIncomeService, player)
	end
	return true
end

function IslandPerkService:Init(services)
	Services = services
	local remote = Instance.new("RemoteFunction")
	remote.Name = "IslandPerkRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerInvoke = function(player, action, perkId)
		if action == "Buy" and typeof(perkId) == "string" then
			local ok, reason = self:Buy(player, perkId)
			return ok, reason, self:State(player)
		end
		return true, nil, self:State(player)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player) lastBuy[player] = nil end)
end

function IslandPerkService:Start()
	local Players = game:GetService("Players")
	local function hook(player)
		task.spawn(function()
			for _ = 1, 30 do
				if Services.DataService:GetGeodeData(player) then break end
				task.wait(1)
			end
			if player.Parent then publish(player) end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do hook(player) end
end

return IslandPerkService
