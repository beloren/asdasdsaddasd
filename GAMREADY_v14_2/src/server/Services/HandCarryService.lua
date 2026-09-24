--------------------------------------------------------------------------------
-- HandCarryService
-- Переноска выбитой руды ГОЛЫМИ РУКАМИ — альтернатива тележке для тех, кто
-- не хочет её красть/тащить. Работает ПОВЕРХ уже существующего выбития
-- кристаллов из чужой тележки в бою (см. CombatService:_swing →
-- CrystalService:MakeLoose): когда кто-то касается выбитого кристалла,
-- CrystalService сначала пробует его тележку (GetCartWithSpaceFor — как и
-- раньше), а если тележки нет или она полна — предлагает это место в руках.
--
-- ПРАВИЛА:
--   • Вместимость рук ограничена ТИРОМ КИРКИ (Config.HandCarry.CapacityByPickaxeTier) —
--     прокачал кирку → носишь больше руками, без тележки.
--   • НЕ грабится в PvP: CombatService трогает только содержимое тележки
--     (CartService:RemoveCrystals) — до этого стеша бой физически не
--     дотягивается, защита встроена самой архитектурой, а не отдельной проверкой.
--   • Смерть держателя роняет всё на землю (как и тележка) — риск за то, что
--     не потратился на тележку, но всё равно полез в бой с полными руками.
--   • Видно на спине — растущий стек кубиков, раскрашенных по тиру каждого
--     подобранного кусочка (тот же язык, что кристаллы в тележке).
--   • Продаётся в той же золотой зоне банка, что и тележка (см. BankService),
--     но БЕЗ её комбо-множителя — компромисс "безопасно, но без бонуса".
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)

local HandCarryService = {}

local Services = nil
local stash = {}   -- [userId] = { {Tier=, Value=}, ... }, порядок = порядок подбора (FIFO при продаже)
local visuals = {} -- [userId] = Model (стек на спине)

function HandCarryService:Init(services)
	Services = services
end

local function capacityFor(player)
	local tier = Services.DataService:GetTiers(player).Pickaxe
	local list = Config.HandCarry.CapacityByPickaxeTier
	local base = list[tier] or list[#list]
	local pouchBonus = Services.MonetizationService and Services.MonetizationService:GetPouchBonus(player) or 0
	return base + pouchBonus -- геймпасс Extra Pouch: +2 сверху тира кирки, см. Config.GamePasses.ExtraPouch
end

-- Груз в руках замедляет ходьбу (см. Config.HandCarry.SlowdownPerItem) —
-- пересчитывается через CartService, единую точку правды по скорости
-- (она же учитывает нагрузку тележки и микро-стан, см. CartService).
local function refreshSpeed(player)
	if Services.CartService then
		Services.CartService:RecomputeSpeed(player)
	end
end

-- Пересчитать и записать атрибут HandOreCapacity немедленно — нужен
-- MonetizationService сразу после покупки Extra Pouch посреди сессии
-- (иначе игрок увидел бы новую вместимость только со следующим подбором).
function HandCarryService:RefreshCapacity(player)
	player:SetAttribute("HandOreCapacity", capacityFor(player))
end

function HandCarryService:GetCount(player)
	local list = stash[player.UserId]
	return list and #list or 0
end

function HandCarryService:HasSpace(player)
	return self:GetCount(player) < capacityFor(player)
end

function HandCarryService:HasOre(player)
	local list = stash[player.UserId]
	return list ~= nil and #list > 0
end

--------------------------------------------------------------------------------
-- Визуал: уменьшенные реальные модели Crystal_TierN на спине.
-- Пересобирается целиком при любом изменении: стеш крошечный (максимум ~10
-- по текущему конфигу), пересборка не заметна по производительности.
--------------------------------------------------------------------------------
local function rebuildVisual(player)
	local old = visuals[player.UserId]
	if old then
		old:Destroy()
		visuals[player.UserId] = nil
	end

	local list = stash[player.UserId]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or not list or #list == 0 then
		return
	end

	local model = Instance.new("Model")
	model.Name = "HandOreStack"

	local firstRoot = nil
	for i, entry in list do
		local ore = PlaceholderFactory.Crystal(entry.Tier)
		ore.Name = "Ore_Tier" .. entry.Tier
		ore.Parent = model
		for _, descendant in ore:GetDescendants() do
			if descendant:IsA("BillboardGui") or descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end
		if ore:IsA("Model") then
			pcall(function()
				ore:ScaleTo(0.55)
			end)
		elseif ore:IsA("BasePart") then
			ore.Size *= 0.55
		end

		local column = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local target = hrp.CFrame * CFrame.new((column - 0.5) * 0.8, -0.65 + row * 0.72, 0.85)
		ore:PivotTo(target * CFrame.Angles(0, math.rad(90), 0))
		local oreRoot = CrystalUtil.GetRoot(ore)
		firstRoot = firstRoot or oreRoot
		local oreParts = ore:GetDescendants()
		if ore:IsA("BasePart") then
			table.insert(oreParts, ore)
		end
		for _, descendant in oreParts do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	model.PrimaryPart = firstRoot

	local countGui = Instance.new("BillboardGui")
	countGui.Name = "CountGui"
	countGui.Size = UDim2.new(2.4, 0, 0.6, 0)
	countGui.StudsOffset = Vector3.new(0, 1.1, 0)
	countGui.AlwaysOnTop = true
	countGui.MaxDistance = 80
	countGui.Adornee = model.PrimaryPart
	countGui.Parent = model.PrimaryPart

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.fromScale(1, 1)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Enum.Font.FredokaOne
	countLabel.TextScaled = true
	countLabel.TextColor3 = Color3.new(1, 1, 1)
	countLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 25)
	countLabel.TextStrokeTransparency = 0
	countLabel.Text = ("✋ %d/%d"):format(#list, capacityFor(player))
	countLabel.Parent = countGui

	model.Parent = character
	visuals[player.UserId] = model
end

-- Пробует подобрать кристалл в руки. true — забрал (вызывающий сам решает,
-- что делать с исходным Instance — см. CrystalService:_flyToHand).
function HandCarryService:TryPickup(player, crystal)
	if not self:HasSpace(player) then
		return false
	end
	local list = stash[player.UserId]
	if not list then
		list = {}
		stash[player.UserId] = list
	end
	table.insert(list, {
		Tier = crystal:GetAttribute("CrystalTier") or 1,
		Value = crystal:GetAttribute("CrystalValue") or 0,
		Points = crystal:GetAttribute("CrystalPoints") or 0,
		OwnerUserId = crystal:GetAttribute("OwnerUserId"),
	})
	player:SetAttribute("HandOreCount", #list)
	player:SetAttribute("HandOreCapacity", capacityFor(player))
	rebuildVisual(player)
	refreshSpeed(player)
	return true
end

-- Возвращает руду, которую victim украл именно у owner, прямо в исходную
-- тележку. Сервер проверяет происхождение по OwnerUserId сохранённого куска.
function HandCarryService:ReturnStolenToOwner(victim, owner, amount)
	local list = stash[victim.UserId]
	local cart = Services.CartService:GetOwnedCart(owner)
	if not list or not cart or (cart.HolderUserId ~= nil and cart.HolderUserId ~= owner.UserId) or #cart.Crystals >= cart.Capacity then
		return 0
	end

	local returned = 0
	for index = #list, 1, -1 do
		local entry = list[index]
		if entry.OwnerUserId == owner.UserId then
			local crystal = PlaceholderFactory.Crystal(entry.Tier)
			crystal:SetAttribute("CrystalTier", entry.Tier)
			crystal:SetAttribute("CrystalValue", entry.Value)
			crystal:SetAttribute("CrystalPoints", entry.Points or 0)
			if Services.CartService:AddCrystal(cart, crystal, false) then
				table.remove(list, index)
				returned += 1
			else
				crystal:Destroy()
				break
			end
			if returned >= amount or #cart.Crystals >= cart.Capacity then
				break
			end
		end
	end
	if returned > 0 then
		victim:SetAttribute("HandOreCount", #list)
		rebuildVisual(victim)
		refreshSpeed(victim)
	end
	return returned
end

-- Продажа по одному, БЕЗ комбо-множителя тележки (см. BankService:_sellHands).
-- Возвращает (цена, тир, украдено?) следующего кусочка или nil, если стеш уже
-- пуст — тир нужен вызывающему, чтобы собрать временный кристалл для
-- анимации полёта. "Украдено" — OwnerUserId куска принадлежит КОМУ-ТО
-- ДРУГОМУ (не текущему продавцу и не "ничьё" nil) — см. Config.HandCarry.
-- StolenOreMultiplier в BankService:_sellHands.
function HandCarryService:SellOne(player)
	local list = stash[player.UserId]
	if not list or #list == 0 then
		return nil
	end
	local entry = table.remove(list, 1)
	player:SetAttribute("HandOreCount", #list)
	rebuildVisual(player)
	refreshSpeed(player)
	local stolen = entry.OwnerUserId ~= nil and entry.OwnerUserId ~= player.UserId
	return entry.Value, entry.Tier, stolen
end

-- Снять ОДИН кусок целиком (со всеми полями) — для перелива в тележку
-- (см. InventoryService:_depositOneToCart). В отличие от SellOne отдаёт
-- саму запись, чтобы ничего не потерять (Points, OwnerUserId).
function HandCarryService:TakeOne(player)
	local list = stash[player.UserId]
	if not list or #list == 0 then
		return nil
	end
	local entry = table.remove(list, 1)
	player:SetAttribute("HandOreCount", #list)
	rebuildVisual(player)
	refreshSpeed(player)
	return entry
end

-- Вернуть кусок в руки (перелив не удался — тележка внезапно заполнилась).
function HandCarryService:PutBack(player, entry)
	if not entry then return end
	local list = stash[player.UserId]
	if not list then
		list = {}
		stash[player.UserId] = list
	end
	table.insert(list, 1, entry)
	player:SetAttribute("HandOreCount", #list)
	rebuildVisual(player)
	refreshSpeed(player)
end

-- Часть руды выбита ударом (см. CombatService:ApplyHit) — тот же принцип,
-- что и выбитие из тележки, только источник данных другой. Возвращает список
-- {Tier=,Value=} снятых кусочков — вызывающий сам создаёт для них физические
-- Part'ы и разбрасывает по земле (см. PlaceholderFactory.Crystal + MakeLoose).
function HandCarryService:RemoveForKnockout(player, amount)
	local list = stash[player.UserId]
	if not list or #list == 0 then
		return {}
	end
	local removed = {}
	for _ = 1, math.min(amount, #list) do
		table.insert(removed, table.remove(list)) -- с конца — не важно в каком порядке теряются
	end
	player:SetAttribute("HandOreCount", #list)
	rebuildVisual(player)
	refreshSpeed(player)
	return removed
end

-- PvP v2: снять из рук ОДНУ самую дорогую руду (для рагдолла).
function HandCarryService:RemoveMostValuable(player)
	local list = stash[player.UserId]
	if not list or #list == 0 then
		return {}
	end
	local bestIndex, bestValue = #list, -math.huge
	for index, entry in list do
		local value = tonumber(entry.Value) or 0
		if value > bestValue then
			bestIndex, bestValue = index, value
		end
	end
	local removed = { table.remove(list, bestIndex) }
	player:SetAttribute("HandOreCount", #list)
	rebuildVisual(player)
	refreshSpeed(player)
	return removed
end

-- Смерть/выход — руки роняют всё на дорогу голыми кристаллами, чтобы кто
-- угодно мог подобрать: тот же риск потери добычи, что и с тележкой.
function HandCarryService:DropAll(player)
	local list = stash[player.UserId]
	if not list or #list == 0 then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local origin = (hrp and hrp.Position or Vector3.new(0, 5, 0)) + Vector3.new(0, 2, 0)

	for _, entry in list do
		-- Не через CrystalService:Create — та заново считает цену (текущий
		-- множитель ребёртов и т.п.). Кусок уже был честно добыт/оценен
		-- раньше — просто пересоздаём Part с уже сохранённой ценой/тиром.
		local crystal = PlaceholderFactory.Crystal(entry.Tier)
		crystal:SetAttribute("CrystalTier", entry.Tier)
		crystal:SetAttribute("CrystalValue", entry.Value)
		crystal:SetAttribute("CrystalPoints", entry.Points or 0)
		crystal:PivotTo(CFrame.new(origin)) -- :PivotTo работает и для BasePart, и для Model одинаково
		local velocity = Vector3.new(
			math.random(-6, 6), math.random(6, 14), math.random(-6, 6)
		)
		Services.CrystalService:MakeLoose(crystal, velocity, entry.OwnerUserId or player.UserId)
	end

	stash[player.UserId] = nil
	player:SetAttribute("HandOreCount", 0)
	rebuildVisual(player)
	refreshSpeed(player)
end

function HandCarryService:SetupPlayer(player)
	player:SetAttribute("HandOreCount", 0)
	player:SetAttribute("HandOreCapacity", capacityFor(player))

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			self:DropAll(player)
		end)
		task.wait(0.3) -- ждём HumanoidRootPart, как и остальные сервисы на CharacterAdded
		player:SetAttribute("HandOreCapacity", capacityFor(player)) -- тир кирки мог измениться с прошлой жизни
		rebuildVisual(player) -- новое тело — старый Model на спине уже не существует
	end)
end

function HandCarryService:CleanupPlayer(player)
	self:DropAll(player) -- честно роняем на выходе, не даём "стешить" руду выходом из игры
	stash[player.UserId] = nil
	local old = visuals[player.UserId]
	if old then
		old:Destroy()
		visuals[player.UserId] = nil
	end
end

return HandCarryService
