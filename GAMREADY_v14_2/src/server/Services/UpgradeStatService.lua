--------------------------------------------------------------------------------
-- UpgradeStatService (v20.140) — МЕЛКИЕ УЛУЧШЕНИЯ ЗА ДЕНЬГИ («звёзды» в
-- дереве прокачки у Experienced Miner, Config.UpgradeStats): урон, удача,
-- скорость, цена продажи. Много уровней, каждый даёт чуть-чуть; цена растёт
-- с уровнем и с пещерой. Сбрасываются при престиже (как тиры).
--   data.UpgradeStats = { Damage = 3, Luck = 0, ... }
--   UpgradeStatService:Bonus(player, "Damage") -> доля (0.06 = +6%)
-- Клиенту - атрибуты UpgradeStat_<Id> (уровень) и RemoteFunction
-- UpgradeStatRequest ("Get" / "Buy", id).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local UpgradeStatService = {}
local Services
local lastBuy = {}

local function cfg()
	return Config.UpgradeStats or { Order = {}, Types = {} }
end

local function dataOf(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	if type(data.UpgradeStats) ~= "table" then data.UpgradeStats = {} end
	return data
end

function UpgradeStatService:Level(player, id)
	local data = dataOf(player)
	return data and math.max(0, math.floor(tonumber(data.UpgradeStats[id]) or 0)) or 0
end

function UpgradeStatService:Bonus(player, id)
	local def = cfg().Types[id]
	if not def then return 0 end
	return self:Level(player, id) * (def.PerLevel or 0)
end

function UpgradeStatService:Cost(player, id)
	local def = cfg().Types[id]
	if not def then return math.huge end
	local level = self:Level(player, id)
	local cave = Services.DataService:GetTiers(player).Mine or 1
	local raw = (def.CostBase or 100) * (def.CostGrowth or 1.25) ^ level * (cfg().CaveScale or 1.3) ^ math.max(0, cave - 1)
	-- красивое число: 2 значащие цифры
	local digits = math.max(0, math.floor(math.log10(math.max(raw, 1))) - 1)
	local unit = 10 ^ digits
	return math.floor(raw / unit + 0.5) * unit
end

function UpgradeStatService:State(player)
	local out = {}
	for _, id in cfg().Order do
		local def = cfg().Types[id]
		if def then
			local level = self:Level(player, id)
			local maxed = level >= (def.MaxLevel or 25)
			out[id] = {
				Level = level,
				MaxLevel = def.MaxLevel or 25,
				Bonus = level * (def.PerLevel or 0),
				NextBonus = (level + 1) * (def.PerLevel or 0),
				Cost = not maxed and self:Cost(player, id) or nil,
				CanAfford = not maxed and not BigNum.lt(Services.DataService:GetMoney(player), self:Cost(player, id)),
			}
		end
	end
	return out
end

local function publish(player)
	for _, id in cfg().Order do
		player:SetAttribute("UpgradeStat_" .. id, UpgradeStatService:Level(player, id))
	end
end

function UpgradeStatService:Buy(player, id)
	local def = cfg().Types[id]
	local data = dataOf(player)
	if not (def and data) then return false, "Unknown" end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Try again" end
	local now = os.clock()
	if now - (lastBuy[player] or 0) < 0.12 then return false, "Slow down" end
	lastBuy[player] = now
	local level = self:Level(player, id)
	if level >= (def.MaxLevel or 25) then return false, "Max level" end
	local cost = self:Cost(player, id)
	if BigNum.lt(Services.DataService:GetMoney(player), cost) then
		if Services.MonetizationService then pcall(Services.MonetizationService.NotEnoughMoney, Services.MonetizationService, player, cost, "UpgradeStat:" .. id) end
		return false, "Not enough money"
	end
	Services.DataService:AddMoney(player, -cost)
	data.UpgradeStats[id] = level + 1
	publish(player)
	if id == "Speed" and Services.CartService and Services.CartService.RecomputeWalkSpeed then
		pcall(Services.CartService.RecomputeWalkSpeed, Services.CartService, player)
	end
	if Services.QuestService and Services.QuestService.RecordMetric then
		pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "Upgrades", 1)
	end
	return true
end

function UpgradeStatService:ResetForPrestige(player)
	local data = dataOf(player)
	if not data then return end
	data.UpgradeStats = {}
	publish(player)
	if Services.CartService and Services.CartService.RecomputeWalkSpeed then
		pcall(Services.CartService.RecomputeWalkSpeed, Services.CartService, player)
	end
end

function UpgradeStatService:SetupPlayer(player)
	dataOf(player)
	publish(player)
end

function UpgradeStatService:Init(services)
	Services = services
	local remote = Instance.new("RemoteFunction")
	remote.Name = "UpgradeStatRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerInvoke = function(player, action, id)
		if action == "Buy" and typeof(id) == "string" then
			local ok, reason = self:Buy(player, id)
			return ok, reason, self:State(player)
		end
		return true, nil, self:State(player)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player) lastBuy[player] = nil end)
end

function UpgradeStatService:Start()
	local Players = game:GetService("Players")
	local function hook(player)
		task.spawn(function()
			for _ = 1, 30 do
				if Services.DataService:GetGeodeData(player) then break end
				task.wait(1)
			end
			if player.Parent then self:SetupPlayer(player) end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do hook(player) end
end

return UpgradeStatService
