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

-- v20.131: карточку/уведомление можно показать позже (рандом-бокс: сначала
-- лента, потом карточка), а сама руда в данные пишется сразу.
local fxDelay = 0
local function sendUnlockFx(player, payload)
	local d = fxDelay
	local function go()
		if player.Parent then fxRemote:FireClient(player, "Unlocked", payload) end
	end
	if d > 0 then task.delay(d, go) else go() end
end
local function notifyLater(player, text, opts)
	if not Services.NotifyService then return end
	local d = fxDelay
	local function go()
		if player.Parent then Services.NotifyService:Show(player, text, opts) end
	end
	if d > 0 then task.delay(d, go) else go() end
end
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
	sendUnlockFx(player, {
		Ore = oreKey,
		Rarity = Config.OreBaseRarity(oreKey),
		Guaranteed = Config.MineRework.GuaranteedCount or 3,
	})
	notifyLater(player, ("⛏ New ore appeared in the mine: %s!"):format(ore.DisplayName), { Icon = "Reward", Duration = 4 })
	task.spawn(function() pcall(Services.DataService.SaveProfile, Services.DataService, player) end)
	return true
end

-- Коробку взяли в руку — открываем.
function OreUnlockService:OpenBox(player, gearKey)
	local oreKey = typeof(gearKey) == "string" and gearKey:sub(#BOX_PREFIX + 1)
	if not (oreKey and Config.OreByKey[oreKey]) then return false end
	if not self:HasBox(player, oreKey) then return false end
	Services.GearService:AddGear(player, gearKey, -1)
	return self:_applyOre(player, oreKey)
end

-- Руда из коробки (обычной или рандом-бокса) попадает в шахту: новая -
-- открывается, уже открытая - падает чаще, на максимуме - возврат денег.
function OreUnlockService:_applyOre(player, oreKey)
	if self:IsUnlocked(player, oreKey) then
		-- v20.118: уже открыта - коробка усиливает руду (падает чаще)
		local buys = self:GetBuys(player)
		local maxBuys = Config.MineRework.MaxBuys or 10
		if (buys[oreKey] or 1) >= maxBuys then
			local refund = Config.OreShopPrice(oreKey)
			if refund ~= math.huge then Services.DataService:AddMoney(player, refund) end
			notifyLater(player, "This ore is already maxed out. Money refunded.", { Icon = "Refund" })
			return true
		end
		buys[oreKey] = (buys[oreKey] or 1) + 1
		local ore = Config.OreByKey[oreKey]
		sendUnlockFx(player, {
			Ore = oreKey,
			Rarity = Config.OreBaseRarity(oreKey),
			Boost = Config.OreRebuyMultiplier(buys[oreKey]),
			Buys = buys[oreKey],
		})
		notifyLater(player, ("⛏ %s drops more often now (x%.2f)!"):format(ore.DisplayName, Config.OreRebuyMultiplier(buys[oreKey])), { Icon = "Reward", Duration = 4 })
		task.spawn(function() pcall(Services.DataService.SaveProfile, Services.DataService, player) end)
		return true
	end
	self:GetBuys(player)[oreKey] = 1
	return self:Unlock(player, oreKey)
end

--------------------------------------------------------------------------------
-- v20.131: РАНДОМ-БОКСЫ ("OreRandom_<n>", Config.OreRandomBox)
--------------------------------------------------------------------------------
local RANDOM_PREFIX = "OreRandom_"
OreUnlockService.RandomPrefix = RANDOM_PREFIX

function OreUnlockService:RandomBoxCount(player, index)
	local data = dataOf(player)
	return data and data.Gear and (tonumber(data.Gear[RANDOM_PREFIX .. tostring(index)]) or 0) or 0
end

-- руды коробки, которые ещё не на максимуме: { [oreKey] = true }
function OreUnlockService:RandomCandidates(player, index)
	local out = {}
	local maxBuys = Config.MineRework.MaxBuys or 10
	for _, key in Config.OreRandomGroups()[tonumber(index) or 0] or {} do
		local owned = self:IsUnlocked(player, key) and (self:GetBuys(player)[key] or 1) or 0
		if owned + self:BoxCount(player, key) < maxBuys then out[key] = true end
	end
	return out
end

function OreUnlockService:_rollRandom(player, index)
	local chances = Config.OreRandomBoxChances(index, self:RandomCandidates(player, index))
	local roll = Random.new():NextNumber()
	local last
	for _, key in Config.OreRandomGroups()[index] or {} do
		if chances[key] then
			last = key
			roll -= chances[key]
			if roll <= 0 then return key end
		end
	end
	return last
end

function OreUnlockService:_beginRandom(player, gearKey, index)
	if self:RandomBoxCount(player, index) <= 0 then return false end
	local group = Config.OreRandomGroups()[index]
	if not group then return false end
	local cfg = Config.MineRework or {}
	local boxCfg = Config.OreRandomBox or {}
	player:SetAttribute("OreBoxOpening", true)
	player:SetAttribute("HeldOreBox", "Random:" .. index)
	fxRemote:FireAllClients("Opening", {
		Player = player,
		Ore = "Random:" .. index,
		Seconds = cfg.OpenSeconds or 1.8,
		Line = cfg.OpenLine or "what happened..?",
	})
	task.delay(cfg.OpenSeconds or 1.8, function()
		if not player.Parent then return end
		local result = self:_rollRandom(player, index)
		Services.GearService:AddGear(player, gearKey, -1)
		fxRemote:FireAllClients("Opened", { Player = player, Ore = "Random:" .. index })
		if not result then
			-- всё в коробке уже на максимуме - возвращаем деньги
			local refund = Config.OreRandomBoxPrice(index)
			if refund ~= math.huge then Services.DataService:AddMoney(player, refund) end
			if Services.NotifyService then
				Services.NotifyService:Show(player, "Every ore in this box is maxed out. Money refunded.", { Icon = "Refund" })
			end
			player:SetAttribute("OreBoxOpening", nil)
			player:SetAttribute("HeldOreBox", nil)
			return
		end
		local variant = Config.RollOreVariant().Variant
		local reelSeconds = boxCfg.ReelSeconds or 3.6
		fxRemote:FireClient(player, "RandomReel", {
			Group = index,
			Ores = group,
			Result = result,
			Variant = variant,
			Seconds = reelSeconds,
			Hold = boxCfg.HoldSeconds or 1.6,
		})
		-- руда пишется в данные СРАЗУ (вышел посреди ленты - не потерял),
		-- а карточка «новая руда» показывается после ленты
		local showAfter = reelSeconds + (boxCfg.HoldSeconds or 1.6) + 0.4
		fxDelay = showAfter
		local ok, err = pcall(self._applyOre, self, player, result)
		fxDelay = 0
		if not ok then warn("[OreUnlockService] рандом-бокс:", err) end
		task.delay(showAfter, function()
			if not player.Parent then return end
			player:SetAttribute("OreBoxOpening", nil)
			if self:RandomBoxCount(player, index) > 0 and player:GetAttribute("HeldGear") == gearKey then
				player:SetAttribute("HeldOreBox", "Random:" .. index)
			else
				player:SetAttribute("HeldOreBox", nil)
				if player:GetAttribute("HeldGear") == gearKey and Services.GearService then
					Services.GearService:Unequip(player)
				end
			end
		end)
	end)
	return true
end

-- v20.114: КЛИК С КОРОБКОЙ В РУКАХ. Коробка трясётся над головой, экран
-- трясётся, над игроком реплика («what happened..?»), через OpenSeconds -
-- открытие и карточка новой руды. Повторные клики во время открытия
-- игнорируются (атрибут OreBoxOpening).
function OreUnlockService:BeginOpen(player, gearKey)
	if player:GetAttribute("OreBoxOpening") == true then return false end
	local randomIndex = typeof(gearKey) == "string" and gearKey:match("^" .. RANDOM_PREFIX .. "(%d+)$")
	if randomIndex then return self:_beginRandom(player, gearKey, tonumber(randomIndex)) end
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

-- v20.138: престиж - купленные руды и их усиления сбрасываются; в шахте
-- снова только стартовые (Coal, Copper). Неоткрытые коробки остаются.
function OreUnlockService:ResetForPrestige(player)
	local data = dataOf(player)
	if not data then return end
	data.UnlockedOres = {}
	data.OreBuys = {}
	data.OreGuarantee = nil
	self:_publish(player)
	if Services.NotifyService then
		Services.NotifyService:Show(player, "⛏ Your mine reset to starter ores. Buy new ores at the Ore Merchant!", { Icon = "Quest", Duration = 6 })
	end
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
