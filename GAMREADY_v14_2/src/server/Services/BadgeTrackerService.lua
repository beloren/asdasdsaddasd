--------------------------------------------------------------------------------
-- BadgeTrackerService v20.106 — БЕЙДЖИ (Config.Badges). Выдача идёт через
-- DataService:AwardBadge (Id 0 = выключен, повторно Roblox не выдаёт).
--   • события: :OnMetric (из QuestService.RecordMetric), :Award(player, key)
--     из сервисов (Golden Boulder, нокдаун);
--   • раз в 15 с - проверка состояния (престиж, деньги, время в игре,
--     книга мутаций, первая руда).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local BadgeTrackerService = {}
local Services = nil

function BadgeTrackerService:Init(services)
	Services = services
end

function BadgeTrackerService:Award(player, key)
	local id = Config.Badges and Config.Badges[key]
	if not (id and tonumber(id) and tonumber(id) > 0) then return end
	local data = Services.DataService:GetGeodeData(player)
	if data then
		data.BadgeStats = type(data.BadgeStats) == "table" and data.BadgeStats or {}
		if data.BadgeStats["Got_" .. key] then return end
		data.BadgeStats["Got_" .. key] = true
	end
	Services.DataService:AwardBadge(player, id)
end

local function bump(player, key, amount)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return 0 end
	data.BadgeStats = type(data.BadgeStats) == "table" and data.BadgeStats or {}
	data.BadgeStats[key] = (tonumber(data.BadgeStats[key]) or 0) + (amount or 1)
	return data.BadgeStats[key]
end

function BadgeTrackerService:OnMetric(player, metric, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	if metric == "GeodesOpened" then
		local total = bump(player, "Geodes", amount)
		self:Award(player, "FirstGeode")
		if total >= 10 then self:Award(player, "Geodes10") end
		if total >= 100 then self:Award(player, "Geodes100") end
	end
end

-- Руда добыта (CrystalService): мифик / Celestial.
function BadgeTrackerService:OnOre(player, rarity, mutations)
	self:Award(player, "FirstOre")
	if rarity == "Mythic" then self:Award(player, "FirstMythic") end
	for _, id in mutations or {} do
		if id == "Celestial" then self:Award(player, "FirstCelestial") end
	end
end

function BadgeTrackerService:_check(player)
	local ds = Services.DataService
	local data = ds:GetGeodeData(player)
	if not data then return end
	local rebirths = tonumber(ds:GetRebirths(player)) or 0
	if rebirths >= 1 then self:Award(player, "Prestige1") end
	if rebirths >= 5 then self:Award(player, "Prestige5") end
	if rebirths >= 10 then self:Award(player, "Prestige10") end
	local money = ds:GetMoney(player)
	if not BigNum.lt(money, BigNum.new(1e6)) then self:Award(player, "Money1M") end
	if not BigNum.lt(money, BigNum.new(1e9)) then self:Award(player, "Money1B") end
	if (tonumber(ds:GetPlayTime(player)) or 0) >= 3600 then self:Award(player, "OneHour") end
	if type(data.OreBook) == "table" and next(data.OreBook) then self:Award(player, "FirstOre") end
	-- Книга мутаций: каждая мутация из Order найдена хотя бы на одном тире.
	if type(data.MutationsFound) == "table" then
		local found = {}
		for key in data.MutationsFound do
			local id = tostring(key):match("_(%a+)$")
			if id then found[id] = true end
		end
		local all = #Config.Mutations.Order > 0
		for _, id in Config.Mutations.Order do
			if not found[id] then all = false break end
		end
		if all then self:Award(player, "MutationBook") end
	end
end

function BadgeTrackerService:Start()
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				pcall(self._check, self, player)
			end
		end
	end)
end

return BadgeTrackerService
