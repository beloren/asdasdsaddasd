--------------------------------------------------------------------------------
-- OreUnlockService (v20.109) — РУДЫ ШАХТЫ ЗА ПОКУПКУ (Config.MineRework).
--
--   • data.UnlockedOres = { [oreKey] = true } — купленные руды (стартовые
--     Config.MineRework.StarterOres открыты всегда);
--   • торговец (вкладка ORE) продаёт коробку "OreBox_<oreKey>" — она лежит
--     в снаряжении; взял в руку - держишь над головой, клик - открыть
--     (BeginOpen, v20.114): карточка «New ore appeared in the mine!»;
--   • data.OreGuarantee = { Key, Left } — следующий заход в шахту отдаёт
--     эту руду Left раз (CrystalService:Create → TakeGuarantee).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local OreUnlockService = {}
local Services = nil
local fxRemote

local BOX_PREFIX = "OreBox_"
OreUnlockService.BoxPrefix = BOX_PREFIX

local function dataOf(player)
	return Services.DataService and Services.DataService:GetGeodeData(player)
end

function OreUnlockService:GetUnlocked(player)
	local data = dataOf(player)
	if not data then return {} end
	if type(data.UnlockedOres) ~= "table" then data.UnlockedOres = {} end
	return data.UnlockedOres
end

-- v20.118: сколько раз куплена каждая руда ({ [oreKey] = N }, открытая = 1+).
function OreUnlockService:GetBuys(player)
	local data = dataOf(player)
	if not data then return {} end
	if type(data.OreBuys) ~= "table" then data.OreBuys = {} end
	for key in self:GetUnlocked(player) do
		if (tonumber(data.OreBuys[key]) or 0) < 1 then data.OreBuys[key] = 1 end
	end
	return data.OreBuys
end

-- Коробок этой руды в сумке.
function OreUnlockService:BoxCount(player, oreKey)
	local data = dataOf(player)
	return data and data.Gear and (tonumber(data.Gear[BOX_PREFIX .. oreKey]) or 0) or 0
end

function OreUnlockService:IsUnlocked(player, oreKey)
	return Config.IsStarterOre(oreKey) or self:GetUnlocked(player)[oreKey] == true
end

function OreUnlockService:HasBox(player, oreKey)
	local data = dataOf(player)
	return data and data.Gear and (tonumber(data.Gear[BOX_PREFIX .. oreKey]) or 0) > 0 or false
end

function OreUnlockService:_publish(player)
	if not player.Parent then return end
	local list = {}
	for key in self:GetUnlocked(player) do table.insert(list, key) end
	table.sort(list)
	player:SetAttribute("UnlockedOres", table.concat(list, ","))
	local data = dataOf(player)
	local guarantee = data and data.OreGuarantee
	player:SetAttribute("OreGuarantee", guarantee and guarantee.Key or nil)
end

-- Следующий кусок шахты — гарантированная руда (или nil).
function OreUnlockService:TakeGuarantee(player)
	local data = dataOf(player)
	local guarantee = data and data.OreGuarantee
	if type(guarantee) ~= "table" or not guarantee.Key then return nil end
	guarantee.Left = (tonumber(guarantee.Left) or 0) - 1
	local key = guarantee.Key
	if guarantee.Left <= 0 then
		data.OreGuarantee = nil
		self:_publish(player)
	end
	return key
end

function OreUnlockService:Unlock(player, oreKey)
	local ore = Config.OreByKey[oreKey]
	local data = dataOf(player)
	if not (ore and data) then return false end
	self:GetUnlocked(player)[oreKey] = true
	if Services.TutorialService then
		pcall(Services.TutorialService.Count, Services.TutorialService, player, "OreUnlocked", 1) -- v20.110
	end
	data.OreGuarantee = { Key = oreKey, Left = Config.MineRework.GuaranteedCount or 3 }
	self:_publish(player)
	fxRemote:FireClient(player, "Unlocked", {
		Ore = oreKey,
		Rarity = Config.OreBaseRarity(oreKey),
		Guaranteed = Config.MineRework.GuaranteedCount or 3,
	})
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("⛏ New ore appeared in the mine: %s!"):format(ore.DisplayName), { Icon = "Reward", Duration = 4 })
	end
	task.spawn(function() pcall(Services.DataService.SaveProfile, Services.DataService, player) end)
	return true
end

-- Коробку взяли в руку — открываем.
function OreUnlockService:OpenBox(player, gearKey)
	local oreKey = typeof(gearKey) == "string" and gearKey:sub(#BOX_PREFIX + 1)
	if not (oreKey and Config.OreByKey[oreKey]) then return false end
	if not self:HasBox(player, oreKey) then return false end
	Services.GearService:AddGear(player, gearKey, -1)
	if self:IsUnlocked(player, oreKey) then
		-- v20.118: уже открыта - коробка усиливает руду (падает чаще)
		local buys = self:GetBuys(player)
		local maxBuys = Config.MineRework.MaxBuys or 10
		if (buys[oreKey] or 1) >= maxBuys then
			local refund = Config.OreShopPrice(oreKey)
			if refund ~= math.huge then Services.DataService:AddMoney(player, refund) end
			if Services.NotifyService then
				Services.NotifyService:Show(player, "This ore is already maxed out. Money refunded.", { Icon = "Refund" })
			end
			return true
		end
		buys[oreKey] = (buys[oreKey] or 1) + 1
		local ore = Config.OreByKey[oreKey]
		fxRemote:FireClient(player, "Unlocked", {
			Ore = oreKey,
			Rarity = Config.OreBaseRarity(oreKey),
			Boost = Config.OreRebuyMultiplier(buys[oreKey]),
			Buys = buys[oreKey],
		})
		if Services.NotifyService then
			Services.NotifyService:Show(player, ("⛏ %s drops more often now (x%.2f)!"):format(ore.DisplayName, Config.OreRebuyMultiplier(buys[oreKey])), { Icon = "Reward", Duration = 4 })
		end
		task.spawn(function() pcall(Services.DataService.SaveProfile, Services.DataService, player) end)
		return true
	end
	self:GetBuys(player)[oreKey] = 1
	return self:Unlock(player, oreKey)
end

-- v20.114: КЛИК С КОРОБКОЙ В РУКАХ. Коробка трясётся над головой, экран
-- трясётся, над игроком реплика («what happened..?»), через OpenSeconds -
-- открытие и карточка новой руды. Повторные клики во время открытия
-- игнорируются (атрибут OreBoxOpening).
function OreUnlockService:BeginOpen(player, gearKey)
	if player:GetAttribute("OreBoxOpening") == true then return false end
	local oreKey = typeof(gearKey) == "string" and gearKey:sub(#BOX_PREFIX + 1)
	if not (oreKey and Config.OreByKey[oreKey] and self:HasBox(player, oreKey)) then return false end
	local cfg = Config.MineRework or {}
	player:SetAttribute("OreBoxOpening", true)
	player:SetAttribute("HeldOreBox", oreKey)
	fxRemote:FireAllClients("Opening", {
		Player = player,
		Ore = oreKey,
		Seconds = cfg.OpenSeconds or 1.8,
		Line = cfg.OpenLine or "what happened..?",
	})
	task.delay(cfg.OpenSeconds or 1.8, function()
		if not player.Parent then return end
		local ok, err = pcall(self.OpenBox, self, player, gearKey)
		if not ok then warn("[OreUnlockService] открытие коробки:", err) end
		player:SetAttribute("OreBoxOpening", nil)
		fxRemote:FireAllClients("Opened", { Player = player, Ore = oreKey })
		-- Ещё такие коробки есть - держим следующую, нет - руки свободны.
		if self:HasBox(player, oreKey) and player:GetAttribute("HeldGear") == gearKey then
			player:SetAttribute("HeldOreBox", oreKey)
		else
			player:SetAttribute("HeldOreBox", nil)
			if player:GetAttribute("HeldGear") == gearKey and Services.GearService then
				Services.GearService:Unequip(player)
			end
		end
	end)
	return true
end

function OreUnlockService:SetupPlayer(player)
	self:_publish(player)
	if player:GetAttribute("MineReworkWiped") and Services.NotifyService then
		task.delay(6, function()
			if player.Parent then
				Services.NotifyService:Show(player, "⛏ The mine was reworked! Buy new ores from the merchant (ORE tab).", { Icon = "Quest", Duration = 8 })
			end
		end)
	end
end

function OreUnlockService:Init(services)
	Services = services
	fxRemote = ReplicatedStorage.Shared:FindFirstChild("OreUnlockFx") or Instance.new("RemoteEvent")
	fxRemote.Name = "OreUnlockFx"
	fxRemote.Parent = ReplicatedStorage.Shared
end

function OreUnlockService:Start() end

return OreUnlockService
