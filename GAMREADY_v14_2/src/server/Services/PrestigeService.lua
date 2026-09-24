--------------------------------------------------------------------------------
-- PrestigeService — престиж v8 на очках (см. Config.Prestige).
--
--   • Очки престижа (data.PrestigePoints) дают RebirthService за каждый
--     престиж: чем глубже пещера на момент престижа, тем больше.
--   • Перки (data.Perks[id] = уровень) качаются по клику в чемоданчике у
--     NPC ребёрта и НЕ сбрасываются никогда.
--   • Stat(player, name) — ЕДИНАЯ точка для всех бонусов: перк + скин
--     кирки (Config.SkinBuffs). PerkBonus — только перк (для мест, где
--     скин уже учитывается через InventoryService:GetSkinBuffs).
--   • Клиенту бонусы публикуются атрибутами PerkBonus_<Id> (доли) и
--     PrestigePoints — их читают PerkUI и общие модули (OreIncome).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local PrestigeService = {}
local Services = nil
local remote = nil
local cases = {} -- [player] = Model
local lastRequest = {}

local PERK_BY_ID = {}
for _, perk in Config.Prestige.Perks do
	PERK_BY_ID[perk.Id] = perk
end

-- v9: дерево — какой перк нужен, чтобы открыть этот (предыдущий в ветке).
local REQUIRES = {}
for _, branch in Config.Prestige.Branches or {} do
	for index, perkId in branch.Perks do
		if index > 1 then REQUIRES[perkId] = branch.Perks[index - 1] end
	end
end
PrestigeService.Requires = REQUIRES

local function dataOf(player)
	return Services.DataService:GetGeodeData(player)
end

local function perkLevel(data, perkId)
	return math.max(0, math.floor(tonumber(data and data.Perks and data.Perks[perkId]) or 0))
end

function PrestigeService.PerkCost(perk, level)
	return math.max(1, math.floor(perk.CostBase + level * perk.CostGrowth))
end

function PrestigeService:GetPerkLevel(player, perkId)
	return perkLevel(dataOf(player), perkId)
end

-- Бонус ТОЛЬКО от перка (доля или штуки — как PerLevel в конфиге).
function PrestigeService:PerkBonus(player, perkId)
	local perk = PERK_BY_ID[perkId]
	if not perk then return 0 end
	return perkLevel(dataOf(player), perkId) * perk.PerLevel
end

-- Бонус от надетого скина кирки (Config.SkinBuffs).
function PrestigeService:SkinBonus(player, stat)
	local data = dataOf(player)
	local skinId = data and data.EquippedSkins and data.EquippedSkins.Pickaxe or ""
	local buffs = Config.SkinBuffs and Config.SkinBuffs[skinId]
	return buffs and tonumber(buffs[stat]) or 0
end

-- Перк + скин.
function PrestigeService:Stat(player, stat)
	return self:PerkBonus(player, stat) + self:SkinBonus(player, stat)
end

local function publish(player)
	local data = dataOf(player)
	if not data then return end
	player:SetAttribute("PrestigePoints", math.max(0, math.floor(tonumber(data.PrestigePoints) or 0)))
	for _, perk in Config.Prestige.Perks do
		player:SetAttribute("PerkBonus_" .. perk.Id, perkLevel(data, perk.Id) * perk.PerLevel)
	end
end

function PrestigeService:GetState(player)
	local data = dataOf(player)
	if not data then return nil end
	local perks = {}
	for _, perk in Config.Prestige.Perks do
		local level = perkLevel(data, perk.Id)
		local required = REQUIRES[perk.Id]
		table.insert(perks, {
			Id = perk.Id,
			-- Уже вложенное раньше (до дерева) не запираем.
			Locked = (required ~= nil and level == 0 and perkLevel(data, required) < (Config.Prestige.UnlockLevel or 1)) or nil,
			Requires = required,
			Level = level,
			MaxLevel = perk.MaxLevel,
			Cost = level < perk.MaxLevel and PrestigeService.PerkCost(perk, level) or nil,
		})
	end
	-- v4: святилища (Config.Prestige.Shrines) — куплено или нет.
	local shrines = {}
	local shrineCfg = Config.Prestige.Shrines
	for _, shrineId in shrineCfg and shrineCfg.Order or {} do
		local def = shrineCfg.Types[shrineId]
		if def then
			local owned = Services.BaseDecorService and Services.BaseDecorService:OwnsShrine(player, shrineId) or false
			table.insert(shrines, { Id = shrineId, Cost = def.Cost, Owned = owned })
		end
	end
	return {
		Points = math.max(0, math.floor(tonumber(data.PrestigePoints) or 0)),
		Perks = perks,
		Shrines = shrines,
		Prestiges = Services.DataService:GetRebirths(player),
	}
end

function PrestigeService:SendState(player, command)
	if remote and player.Parent then
		remote:FireClient(player, command or "State", self:GetState(player))
	end
end

function PrestigeService:AddPoints(player, amount)
	local data = dataOf(player)
	amount = math.floor(tonumber(amount) or 0)
	if not data or amount <= 0 then return end
	data.PrestigePoints = math.max(0, math.floor(tonumber(data.PrestigePoints) or 0)) + amount
	publish(player)
	self:SendState(player)
end

-- Очки за престиж с этой пещеры.
function PrestigeService.PointsForCave(cave)
	local best = 0
	for minCave, points in Config.Prestige.PointsByCave do
		if cave >= minCave and points > best then
			best = points
		end
	end
	return best
end

function PrestigeService:BuyPerk(player, perkId)
	local perk = PERK_BY_ID[perkId]
	local data = dataOf(player)
	if not (perk and data) then return false, "Unknown perk" end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Try again" end
	data.Perks = data.Perks or {}
	local level = perkLevel(data, perkId)
	if level >= perk.MaxLevel then return false, "Max level" end
	local required = REQUIRES[perkId]
	if required and level == 0 and perkLevel(data, required) < (Config.Prestige.UnlockLevel or 1) then
		return false, "Unlock the previous perk first"
	end
	local cost = PrestigeService.PerkCost(perk, level)
	local points = math.floor(tonumber(data.PrestigePoints) or 0)
	if points < cost then return false, "Not enough prestige points" end
	data.PrestigePoints = points - cost
	data.Perks[perkId] = level + 1
	publish(player)
	if Services.QuestService then pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "PerksBought", 1) end
	if perkId == "CartSpace" and Services.CartService and Services.CartService.RefreshCapacity then
		pcall(Services.CartService.RefreshCapacity, Services.CartService, player)
	end
	if perkId == "Speed" and Services.CartService then
		pcall(Services.CartService.RefreshSpeed, Services.CartService, player)
	end
	task.spawn(function() Services.DataService:SaveProfile(player) end)
	return true
end

-- v4: покупка святилища за очки престижа. Один раз на аккаунт; предмет
-- ложится в инвентарь (вкладка TOTEMS) и ставится на базу как тотем.
function PrestigeService:BuyShrine(player, shrineId)
	local shrineCfg = Config.Prestige.Shrines
	local def = shrineCfg and shrineCfg.Types[shrineId]
	local data = dataOf(player)
	if not (def and data) then return false, "Unknown shrine" end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Try again" end
	if not Services.BaseDecorService then return false, "Unavailable" end
	if Services.BaseDecorService:OwnsShrine(player, shrineId) then return false, "Already owned" end
	local cost = math.max(0, math.floor(tonumber(def.Cost) or 0))
	local points = math.floor(tonumber(data.PrestigePoints) or 0)
	if points < cost then return false, "Not enough prestige points" end
	data.PrestigePoints = points - cost
	if not Services.BaseDecorService:GrantItem(player, "Totem_Shrine_" .. shrineId, 1) then
		data.PrestigePoints = points
		return false, "Purchase failed"
	end
	publish(player)
	if Services.QuestService then pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "PerksBought", 1) end
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("%s %s is in your inventory — place it on your base!"):format(def.Icon or "🗿", def.DisplayName), { Icon = "Reward", Duration = 3 })
	end
	task.spawn(function() Services.DataService:SaveProfile(player) end)
	return true
end

--------------------------------------------------------------------------------
-- ЧЕМОДАНЧИК У NPC РЕБЁРТА
--------------------------------------------------------------------------------
local function buildPlaceholderCase()
	local model = Instance.new("Model")
	model.Name = "PrestigeCase"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3.2, 2.2, 1.1)
	body.Color = Color3.fromRGB(110, 70, 40)
	body.Material = Enum.Material.Leather
	body.Anchored = true
	body.CanCollide = true
	body.Parent = model
	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Size = Vector3.new(3.3, 0.25, 1.15)
	trim.Color = Color3.fromRGB(255, 200, 70)
	trim.Material = Enum.Material.Metal
	trim.Anchored = true
	trim.CanCollide = false
	trim.CFrame = body.CFrame * CFrame.new(0, 0.3, 0)
	trim.Parent = model
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 0.3, 0.3)
	handle.Color = Color3.fromRGB(60, 40, 25)
	handle.Anchored = true
	handle.CanCollide = false
	handle.CFrame = body.CFrame * CFrame.new(0, 1.25, 0)
	handle.Parent = model
	model.PrimaryPart = body
	return model
end

local function findCaseAsset()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local asset = assets and assets:FindFirstChild(Config.Prestige.CaseModelName, true)
	if asset and asset:IsA("Model") then
		local clone = asset:Clone()
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored = true end
		end
		return clone
	end
	return buildPlaceholderCase()
end

function PrestigeService:SetupPlot(player, plot)
	local old = cases[player]
	if old then old:Destroy() end
	local npc = Services.RebirthService.GetNpc and Services.RebirthService:GetNpc(player)
	local anchor = npc and npc:GetPivot() or plot.RebirthCFrame
	if not anchor then return end
	local model = findCaseAsset()
	local floorY = plot.Pad.Position.Y + plot.Pad.Size.Y / 2
	local target = anchor * Config.Prestige.CaseOffset
	local _, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(target.Position.X, floorY + size.Y / 2, target.Position.Z) * target.Rotation)
	model.Parent = plot.Content

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "VIEW PERKS"
	prompt.ObjectText = "Prestige Case"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = root
	prompt.Triggered:Connect(function(who)
		if who == player then
			self:SendState(player, "Open")
		end
	end)
	cases[player] = model
end

function PrestigeService:SetupPlayer(player)
	local data = dataOf(player)
	if not data then return end
	data.Perks = data.Perks or {}
	data.PrestigePoints = math.max(0, math.floor(tonumber(data.PrestigePoints) or 0))
	-- Миграция: старые ребёрты (давали множитель x1.5) → по 1 очку за каждый.
	if data.PerksMigrated ~= true then
		data.PerksMigrated = true
		data.PrestigePoints += math.max(0, math.floor(tonumber(data.Rebirths) or 0))
	end
	publish(player)
end

function PrestigeService:CleanupPlayer(player)
	local case = cases[player]
	if case then case:Destroy() end
	cases[player] = nil
	lastRequest[player] = nil
end

function PrestigeService:Init(services)
	Services = services
	remote = Instance.new("RemoteEvent")
	remote.Name = "PrestigeRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerEvent:Connect(function(player, action, perkId)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.2 then return end
		lastRequest[player] = now
		if action == "GetState" then
			self:SendState(player)
		elseif action == "Buy" and typeof(perkId) == "string" then
			local ok, reason = self:BuyPerk(player, perkId)
			remote:FireClient(player, "BuyResult", { Ok = ok, Reason = reason, PerkId = perkId })
			self:SendState(player)
		elseif action == "BuyShrine" and typeof(perkId) == "string" then
			local ok, reason = self:BuyShrine(player, perkId)
			remote:FireClient(player, "BuyResult", { Ok = ok, Reason = reason, ShrineId = perkId })
			self:SendState(player)
		end
	end)
end

return PrestigeService
