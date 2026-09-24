--------------------------------------------------------------------------------
-- GearService — «снаряжение» v8: динамит (Config.Dynamite) и сундуки
-- (Config.Chests). Хранится в data.Gear = { Dynamite = n, Chest_Rare = n, … },
-- поставленные сундуки — в data.PlacedChests (таймер по os.time → идёт и
-- оффлайн).
--
-- В РУКЕ: атрибут игрока HeldGear ("Dynamite" / "Chest_Epic" / ""). Пока
-- что-то в руке — кирка убрана, замах киркой не работает (CombatService).
-- Клик клиента (GearHud.client.lua) → "Use" с точкой прицела:
--   • динамит по валуну — прилипает и взрывается через PlaceFuse;
--   • динамит в другое место — бросок дугой, взрыв откидывает игроков в
--     рагдолл на 1 сек и выбивает 1 руду (CombatService:BlastKnock);
--   • сундук — ставится на землю СВОЕГО участка, идёт таймер открытия.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local DropTables = require(ReplicatedStorage.Shared.DropTables)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local GearService = {}
local Services = nil
local remote = nil
local dynamiteFxRemote = nil -- v16: RemoteEvent "DynamiteFx"
local chestFxRemote = nil -- v16: RemoteEvent "ChestFx"
local lastRequest = {}
local lastThrow = {}
local heldVisuals = {} -- [player] = Model
local chestModels = {} -- [player] = { [chestId] = { Model, Billboard, Prompt } }
local plotsByPlayer = {} -- [player] = plot
local pendingSkip = {} -- [player] = chestId (покупка пропуска таймера)

local function dataOf(player)
	return Services.DataService:GetGeodeData(player)
end

local function gearCount(data, key)
	return math.max(0, math.floor(tonumber(data and data.Gear and data.Gear[key]) or 0))
end

local function statFor(player, stat)
	if Services.PrestigeService then
		local ok, value = pcall(Services.PrestigeService.Stat, Services.PrestigeService, player, stat)
		if ok and value then return value end
	end
	return 0
end

-- v4: цена динамита фиксированная (Config.Dynamite.Types[key].Price).
function GearService:DynamitePrice(_player, key)
	local info = Config.Dynamite.Types[key or "Dynamite"] or Config.Dynamite.Types.Dynamite
	return math.max(1, math.floor(tonumber(info.Price) or 100))
end

-- v9: ОТКАТ ДИНАМИТА — по виду, общий для броска и установки на валун.
-- Клиент видит его в атрибуте игрока DynamiteReadyAt_<key> (серверное
-- время workspace:GetServerTimeNow()) и рисует отсчёт на слоте.
local function cooldownLeft(player, key)
	local readyAt = tonumber(player:GetAttribute("DynamiteReadyAt_" .. key)) or 0
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end
local function startCooldown(player, key)
	local info = Config.Dynamite.Types[key]
	if info then
		-- v10: пасс Demolition Expert — откат короче.
		local mult = 1
		if Services.MonetizationService and Services.MonetizationService:HasPass(player, "DemolitionExpert") then
			mult = Config.GamePasses.DemolitionExpert.CooldownMultiplier or 0.5
		end
		player:SetAttribute("DynamiteReadyAt_" .. key, workspace:GetServerTimeNow() + (info.Cooldown or 4) * mult)
	end
end

-- v10: Demolition Expert — раз в сутки бесплатный динамит самого большого
-- доступного (по пещере) вида.
function GearService:_checkDemolitionDaily(player)
	local monetization = Services.MonetizationService
	if not (monetization and monetization:HasPass(player, "DemolitionExpert")) then return end
	local data = dataOf(player)
	if not data then return end
	local now = os.time()
	local period = Config.GamePasses.DemolitionExpert.DailyFreeSeconds or 72000
	if now - (tonumber(data.DemolitionDailyAt) or 0) < period then return end
	data.DemolitionDailyAt = now
	local cave = Services.DataService:GetTiers(player).Mine or 1
	local best = "Dynamite"
	for _, key in Config.Dynamite.Order do
		local info = Config.Dynamite.Types[key]
		if cave >= (info.UnlockCave or 1) then best = key end
	end
	data.Gear = data.Gear or {}
	data.Gear[best] = (tonumber(data.Gear[best]) or 0) + 1
	self:SendState(player)
	if Services.InventoryService and Services.InventoryService.OnGearChanged then
		pcall(Services.InventoryService.OnGearChanged, Services.InventoryService, player, best, 1)
	end
	Services.NotifyService:Show(player, ("🧨 Daily free %s!"):format(Config.Dynamite.Types[best].DisplayName), { Icon = "Reward" })
	task.spawn(function() Services.DataService:SaveProfile(player) end)
end

function GearService:GetState(player)
	local data = dataOf(player)
	if not data then return nil end
	local placed = {}
	for _, entry in data.PlacedChests or {} do
		table.insert(placed, { Id = entry.Id, Rarity = entry.Rarity, ReadyAt = entry.ReadyAt })
	end
	return {
		Gear = table.clone(data.Gear or {}),
		Placed = placed,
		MaxPlaced = Config.Chests.MaxPlaced,
		DynamitePrice = self:DynamitePrice(player, "Dynamite"),
		DynamitePrices = (function()
			local prices = {}
			for _, key in Config.Dynamite.Order do prices[key] = self:DynamitePrice(player, key) end
			return prices
		end)(),
		Held = player:GetAttribute("HeldGear") or "",
		ChestSkinPity = tonumber(data.ChestSkinPity) or 0, -- v18: окно шансов
		ServerTime = os.time(),
	}
end

function GearService:SendState(player, command, extra)
	if remote and player.Parent then
		remote:FireClient(player, command or "State", self:GetState(player), extra)
	end
end

local function save(player)
	task.spawn(function() Services.DataService:SaveProfile(player) end)
end

function GearService:AddGear(player, key, amount)
	local data = dataOf(player)
	amount = math.floor(tonumber(amount) or 0)
	if not data or amount == 0 then return 0 end
	data.Gear = data.Gear or {}
	local limit = (Config.Dynamite.Types[key] and Config.Dynamite.MaxStack)
		or (Config.Potions and Config.Potions.Types[key] and Config.Potions.MaxStack)
		or math.huge
	local before = gearCount(data, key)
	local after = math.clamp(before + amount, 0, limit)
	data.Gear[key] = after
	if after == 0 and player:GetAttribute("HeldGear") == key then
		self:Unequip(player)
	end
	self:SendState(player)
	-- Разовые подсказки при ПЕРВОМ получении (Config.Tutorial.Hints).
	-- Здесь, а не в местах выдачи: снаряжение приходит из магазина,
	-- валунов, наград квестов и дейликов, а AddGear — общий вход для всех.
	if after > before and Services.TutorialService then
		if Config.Dynamite.Types[key] then
			pcall(function() Services.TutorialService:ShowHint(player, "FirstDynamite") end)
		elseif string.sub(key, 1, 6) == "Chest_" then
			pcall(function() Services.TutorialService:ShowHint(player, "FirstChest") end)
		end
	end
	-- v18: эссенции — промпт нанесения у подиума включается/гаснет сам.
	if DropTables.EssenceMutation(key) and Services.PassiveIncomeService and Services.PassiveIncomeService.RefreshEssencePrompt then
		pcall(Services.PassiveIncomeService.RefreshEssencePrompt, Services.PassiveIncomeService, player)
	end
	-- v9: снаряжение лежит в инвентаре — новое сразу встаёт в хотбар.
	if Services.InventoryService and Services.InventoryService.OnGearChanged then
		pcall(Services.InventoryService.OnGearChanged, Services.InventoryService, player, key, after - before)
	end
	return after - before
end

--------------------------------------------------------------------------------
-- ВИЗУАЛ В РУКЕ
--------------------------------------------------------------------------------
-- v20.9: модель сундука общая с клиентом (призрак установки) — PlaceableFactory.BuildChest.
local function chestAsset(rarity)
	return require(ReplicatedStorage.Shared.PlaceableFactory).BuildChest(rarity)
end

local function dynamiteModel(key)
	key = key or "Dynamite"
	local info = Config.Dynamite.Types[key] or Config.Dynamite.Types.Dynamite
	local folder = ReplicatedStorage:FindFirstChild("Assets")
	-- Своя модель вида (Assets/.../Dynamite_Mega), иначе обычная — перекрашенная и крупнее.
	local asset = folder and (folder:FindFirstChild(key, true) or folder:FindFirstChild("Dynamite", true))
	local tint = asset and asset.Name ~= key
	local function finish(result)
		if tint and (info.ModelScale or 1) ~= 1 then
			if result:IsA("Model") then
				pcall(function() result:ScaleTo(result:GetScale() * info.ModelScale) end)
			else
				result.Size *= info.ModelScale
			end
		end
		return result
	end
	if asset and asset:IsA("BasePart") then
		return finish(asset:Clone())
	elseif asset and asset:IsA("Model") then
		local clone = asset:Clone()
		local root = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if root then
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") and part ~= root then
					local w = Instance.new("WeldConstraint")
					w.Part0 = root
					w.Part1 = part
					w.Parent = root
				end
			end
			clone.PrimaryPart = root
		end
		return finish(clone)
	end
	local stick = Instance.new("Part")
	stick.Name = key
	stick.Shape = Enum.PartType.Cylinder
	stick.Size = Vector3.new(1.4, 0.45, 0.45) * (info.ModelScale or 1)
	stick.Color = info.Color
	stick.Material = Enum.Material.SmoothPlastic
	local fuse = Instance.new("Attachment")
	fuse.Name = "Fuse"
	fuse.Position = Vector3.new(0.75, 0, 0)
	fuse.Parent = stick
	return stick
end

local function rootPart(instance)
	if instance:IsA("BasePart") then return instance end
	return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
end

local function setPhysics(instance, anchored, canCollide)
	local parts = instance:IsA("BasePart") and { instance } or instance:GetDescendants()
	for _, part in parts do
		if part:IsA("BasePart") then
			part.Anchored = anchored
			part.CanCollide = canCollide
			part.CanQuery = false
			part.Massless = true
		end
	end
end

-- Все части модели — к корню (ассеты могут прийти без внутренних сварок).
local function weldAll(instance, root)
	if not instance:IsA("Model") then return end
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
end

local function clearHeldVisual(player)
	local visual = heldVisuals[player]
	if visual then visual:Destroy() end
	heldVisuals[player] = nil
end

function GearService:Unequip(player)
	clearHeldVisual(player)
	if player.Parent then
		player:SetAttribute("HeldGear", "")
		-- v12: гасим и "коробка над головой" — иначе визуал упаковки остался
		-- бы висеть после того, как предмет убрали из рук (или потратили).
		player:SetAttribute("HeldCartPackage", nil)
		player:SetAttribute("HeldPotion", nil)
	end
	-- v18: текст промпта эссенции зависит от того, что в руке.
	if Services and Services.PassiveIncomeService and Services.PassiveIncomeService.RefreshEssencePrompt then
		task.defer(function()
			pcall(Services.PassiveIncomeService.RefreshEssencePrompt, Services.PassiveIncomeService, player)
		end)
	end
end

function GearService:Equip(player, key)
	local data = dataOf(player)
	if typeof(key) ~= "string" or gearCount(data, key) <= 0 then
		self:Unequip(player)
		return
	end
	if player:GetAttribute("CarryingCart") then
		Services.NotifyService:Show(player, "Put your cart down first!", { Icon = "Cart" })
		return
	end

	--------------------------------------------------------------------------
	-- v12: УПАКОВКА ТЕЛЕЖКИ — единственный предмет снаряжения, который НЕ
	-- вкладывается в руку.
	--
	-- Она носится НАД ГОЛОВОЙ, ровно как кусок руды: коробку и позу рук
	-- рисует у КАЖДОГО клиента OreCarryPose.client.lua по атрибуту
	-- HeldCartPackage (в точности та же схема, что у HeldOre — сервер
	-- владеет фактом, клиенты картинкой). Поэтому здесь мы не клонируем
	-- никакую модель и не варим её к руке: только выставляем атрибуты.
	-- Значение атрибута — ТИР тележки: клиент по нему и коробку подписывает,
	-- и предпросмотр строит из нужной модели Cart_TierN.
	--------------------------------------------------------------------------
	-- ЗЕЛЬЕ (Config.Potions) — как упаковка тележки, в руку НЕ вкладывается:
	-- колба-пузырёк парит над головой, её у каждого клиента рисует
	-- PotionBubble.client.lua по атрибуту HeldPotion. Клик — выпить.
	if Config.Potions and Config.Potions.Types[key] then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		humanoid:UnequipTools()
		if Services.InventoryService then
			pcall(Services.InventoryService.SetHeldOre, Services.InventoryService, player, nil)
		end
		clearHeldVisual(player)
		player:SetAttribute("HeldCartPackage", nil)
		player:SetAttribute("HeldGear", key)
		player:SetAttribute("HeldPotion", key)
		return
	end
	-- v18: ЭССЕНЦИЯ МУТАЦИИ — в руку не вкладывается; держишь её — и у
	-- своего подиума промпт APPLY ESSENCE нанесёт именно эту эссенцию.
	if DropTables.EssenceMutation(key) then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		humanoid:UnequipTools()
		if Services.InventoryService then
			pcall(Services.InventoryService.SetHeldOre, Services.InventoryService, player, nil)
		end
		clearHeldVisual(player)
		player:SetAttribute("HeldCartPackage", nil)
		player:SetAttribute("HeldPotion", nil)
		player:SetAttribute("HeldGear", key)
		if Services.PassiveIncomeService and Services.PassiveIncomeService.RefreshEssencePrompt then
			pcall(Services.PassiveIncomeService.RefreshEssencePrompt, Services.PassiveIncomeService, player)
		end
		return
	end
	-- v14: ТОТЕМ / ДЕКОР / РЕЛИКВИЯ — в руку не вкладываются: клиент рисует
	-- призрак на земле (PlacementGhost.client.lua), клик — поставить.
	if Services.BaseDecorService and Services.BaseDecorService.IsPlaceableKey(key) then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		humanoid:UnequipTools()
		if Services.InventoryService then
			pcall(Services.InventoryService.SetHeldOre, Services.InventoryService, player, nil)
		end
		clearHeldVisual(player)
		player:SetAttribute("HeldCartPackage", nil)
		player:SetAttribute("HeldPotion", nil)
		player:SetAttribute("HeldGear", key)
		return
	end
	if key == (Config.CartPackage and Config.CartPackage.GearKey or "CartPackage") then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		humanoid:UnequipTools() -- кирка и упаковка одновременно в руках не бывают
		if Services.InventoryService then
			pcall(Services.InventoryService.SetHeldOre, Services.InventoryService, player, nil)
		end
		clearHeldVisual(player)
		player:SetAttribute("HeldGear", key)
		player:SetAttribute("HeldCartPackage", Services.DataService:GetTiers(player).Cart)
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hand = character and (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand"))
	if not (humanoid and hand) then return end
	humanoid:UnequipTools()
	if Services.InventoryService then
		pcall(Services.InventoryService.SetHeldOre, Services.InventoryService, player, nil)
	end
	clearHeldVisual(player)
	local visual
	if Config.Dynamite.Types[key] then
		visual = dynamiteModel(key)
	else
		visual = chestAsset((key:gsub("^Chest_", "")))
		if visual:IsA("Model") then visual:ScaleTo(0.45) end
	end
	local root = rootPart(visual)
	weldAll(visual, root)
	setPhysics(visual, false, false)
	visual.Name = "HeldGear"
	if visual:IsA("Model") then
		visual:PivotTo(hand.CFrame * CFrame.new(0, -1.2, -0.6))
	else
		visual.CFrame = hand.CFrame * CFrame.new(0, -1.2, -0.3) * CFrame.Angles(0, math.rad(90), 0)
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = root
	weld.Parent = root
	visual.Parent = character
	heldVisuals[player] = visual
	player:SetAttribute("HeldGear", key)
end

--------------------------------------------------------------------------------
-- ЗЕЛЬЯ
--------------------------------------------------------------------------------
local lastDrinkAt = {}

function GearService:_drinkPotion(player, key)
	local info = Config.Potions.Types[key]
	local data = dataOf(player)
	if not (info and data) or gearCount(data, key) <= 0 then return false end
	-- Защита от двойного клика: одно зелье за 0.6 с, иначе серия тапов
	-- на телефоне выпивала бы весь запас разом.
	local now = os.clock()
	if lastDrinkAt[player] and now - lastDrinkAt[player] < 0.6 then return false end
	lastDrinkAt[player] = now

	-- Второе зелье того же вида ПРОДЛЕВАЕТ действие: BuffService:Grant
	-- при равной силе берёт max(конец, сейчас + длительность), и без
	-- этого зелье, выпитое поверх активного, просто сгорало бы.
	local seconds = info.Seconds or 180
	for _, active in Services.BuffService:GetActiveBuffs(player) do
		if active.Kind == info.Buff and active.Amount <= info.Amount then
			seconds += active.SecondsLeft
		end
	end
	-- Клиенты по этому атрибуту играют "бульк" пузырька над головой —
	-- ставим ДО списания: последнее зелье снимается с руки в AddGear.
	player:SetAttribute("PotionDrankKey", key)
	player:SetAttribute("PotionDrankAt", workspace:GetServerTimeNow())
	self:AddGear(player, key, -1)
	-- v18: у Mutation Magnet сила — это ЗАРЯДЫ, второй амулет их докладывает.
	local amount = info.Amount
	if info.Buff == "MutationMagnet" then
		amount += Services.BuffService:GetBonus(player, info.Buff)
		seconds = info.Seconds or 600
	end
	Services.BuffService:Grant(player, info.Buff, amount, seconds, info.DisplayName)
	pcall(function() Services.BuffService:PushState(player) end)
	Services.NotifyService:Show(player, ("%s %s — %d:%02d"):format(info.Icon, info.DisplayName, seconds // 60, seconds % 60), {
		Icon = "Reward", Duration = 2.5, TextColor = info.Color,
	})
	save(player)
	return true
end

--------------------------------------------------------------------------------
-- ДИНАМИТ
--------------------------------------------------------------------------------

function GearService:_explode(player, position, boulderState, boulderPower, stats)
	local cfg = stats or Config.Dynamite
	local power = 1 + statFor(player, "Dynamite")
	local radius = (cfg.Radius or Config.Dynamite.Radius) * (1 + math.max(0, statFor(player, "Dynamite")) * 0.5)
	-- v16: взрыв рисуют клиенты (DynamiteFX) — пульсация уже закончилась.
	if dynamiteFxRemote then
		dynamiteFxRemote:FireAllClients("Boom", {
			Key = cfg.Key or "Dynamite", Position = position, Radius = radius,
		})
	end
	if boulderState then
		Services.RockService:ApplyDynamite(boulderState, player, (boulderPower or 1) * power)
	end
	-- v9: свой динамит бьёт и по хозяину — рагдолл без потери руды,
	-- щит и безопасная зона от СВОЕГО взрыва не спасают.
	for _, other in Players:GetPlayers() do
		local hrp = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - position).Magnitude <= radius then
			local options = { Stats = stats, Radius = radius, Blast = true }
			if other == player then options.Self = true end
			pcall(Services.CombatService.BlastKnock, Services.CombatService, other, position, player, options)
		end
	end
end

local function consumeDynamite(self, player, key)
	local data = dataOf(player)
	if gearCount(data, key) <= 0 then return false end
	data.Gear[key] -= 1
	if data.Gear[key] <= 0 then
		self:Unequip(player)
	end
	self:SendState(player)
	if Services.InventoryService then pcall(Services.InventoryService.Sync, Services.InventoryService, player) end
	return true
end

function GearService:_useDynamite(player, key, targetInstance, targetPosition)
	local cfg = Config.Dynamite
	local stats = Config.Dynamite.Types[key]
	if not stats then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or typeof(targetPosition) ~= "Vector3" then return end
	if player:GetAttribute("Ragdolled") == true then return end
	-- v9: откат вида (и для броска, и для установки).
	local left = cooldownLeft(player, key)
	if left > 0 then
		Services.NotifyService:Show(player, ("%s %s — %ds"):format(stats.Icon, stats.DisplayName, math.ceil(left)), { Icon = "Pickaxe", Duration = 1.2 })
		return
	end
	local fuse = stats.Fuse or cfg.PlaceFuse
	local now = workspace:GetServerTimeNow()

	-- 1) Точно по валуну рядом — прилипает и взрывается.
	local boulderState = typeof(targetInstance) == "Instance" and Services.RockService:FindBoulderByModel(targetInstance) or nil
	if boulderState and (targetPosition - hrp.Position).Magnitude <= cfg.PlaceRange + 6 then
		if not consumeDynamite(self, player, key) then return end
		startCooldown(player, key)
		if Services.QuestService then pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "DynamiteUsed", 1) end
		Services.CombatService:PlaySwingVisual(player)
		if dynamiteFxRemote then
			dynamiteFxRemote:FireAllClients("Place", {
				Key = key, Position = targetPosition, Face = hrp.Position,
				LandAt = now, BoomAt = now + fuse,
			})
		end
		task.delay(fuse, function()
			self:_explode(player, targetPosition, boulderState.Model.Parent and boulderState or nil, stats.BoulderPower or 1, stats)
		end)
		return
	end

	-- 2) Бросок дугой (v16: полёт рисуют клиенты — у всех плавно).
	local offset = targetPosition - hrp.Position
	if offset.Magnitude > cfg.ThrowRange then
		targetPosition = hrp.Position + offset.Unit * cfg.ThrowRange
	end
	if not consumeDynamite(self, player, key) then return end
	startCooldown(player, key)
	if Services.QuestService then pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "DynamiteUsed", 1) end
	Services.CombatService:PlaySwingVisual(player)
	local start = hrp.Position + Vector3.new(0, 2.5, 0)
	local distance = (targetPosition - start).Magnitude
	local flight = math.clamp(distance / 40, 0.35, 1.1)
	local apex = math.max(4, distance * 0.35)
	if dynamiteFxRemote then
		dynamiteFxRemote:FireAllClients("Throw", {
			Key = key, From = start, To = targetPosition, Apex = apex,
			StartAt = now, LandAt = now + flight, BoomAt = now + flight + fuse,
		})
	end
	task.delay(flight + fuse, function()
		local nearBoulder = Services.RockService:FindBoulderNear(targetPosition, cfg.ThrowBoulderRadius)
		self:_explode(player, targetPosition, nearBoulder, stats.ThrowBoulderPower or 0.5, stats)
	end)
end

function GearService:BuyDynamite(player, amount, key)
	key = typeof(key) == "string" and key or "Dynamite"
	local info = Config.Dynamite.Types[key]
	if not info then return false, "Bad item" end
	amount = math.floor(tonumber(amount) or 0)
	if not table.find(Config.Dynamite.BuyAmounts, amount) then return false, "Bad amount" end
	local data = dataOf(player)
	if not data then return false, "Try again" end
	if gearCount(data, key) + amount > Config.Dynamite.MaxStack then return false, "Bag full" end
	-- v9: вид открывается с пещеры UnlockCave (маленький/средний/большой).
	local cave = Services.DataService:GetTiers(player).Mine or 1
	if cave < (info.UnlockCave or 1) then return false, ("Unlocks at cave %d"):format(info.UnlockCave) end
	local cost = self:DynamitePrice(player, key) * amount
	local BigNum = require(ReplicatedStorage.Shared.BigNum)
	if BigNum.lt(Services.DataService:GetMoney(player), cost) then return false, "Not enough money" end
	Services.DataService:AddMoney(player, -cost)
	self:AddGear(player, key, amount)
	save(player)
	Services.NotifyService:Show(player, ("+%d %s %s  (%d in bag)"):format(amount, info.DisplayName, info.Icon, gearCount(data, key)), {
		Icon = "Reward", Duration = 2.5, TextColor = info.Color,
	})
	return true
end

--------------------------------------------------------------------------------
-- СУНДУКИ
--------------------------------------------------------------------------------
function GearService:GrantChest(player, rarity, count, silent)
	if not Config.Chests.Types[rarity] then return end
	self:AddGear(player, "Chest_" .. rarity, count or 1)
	if not silent then
		Services.NotifyService:Show(player, ("You found a %s! Take it to your base to open."):format(Config.Chests.Types[rarity].DisplayName), {
			Icon = "Geode", Duration = 4, TextColor = Config.Chests.Types[rarity].Color,
		})
	end
	save(player)
end

-- Шанс сундука с разбитого валуна (самый редкий из выпавших).
function GearService:RollBoulderChest(player, tier, qualityMult, _position)
	if not Config.Chests.Enabled then return end
	local luck = (qualityMult or 1) * (1 + statFor(player, "ChestLuck")) * (1 + 0.05 * math.max(0, (tier or 1) - 1))
	for index = #Config.Chests.Order, 1, -1 do
		local rarity = Config.Chests.Order[index]
		local chance = (Config.Chests.DropFromBoulder[rarity] or 0) * luck
		if math.random() < chance then
			self:GrantChest(player, rarity, 1)
			return rarity
		end
	end
	return nil
end

local function plotPad(player)
	local plot = plotsByPlayer[player] or (Services.PlotService and Services.PlotService:GetPlot(player))
	return plot and plot.Pad, plot
end

local function insidePad(pad, position)
	local localPoint = pad.CFrame:PointToObjectSpace(position)
	return math.abs(localPoint.X) <= pad.Size.X / 2 - 2 and math.abs(localPoint.Z) <= pad.Size.Z / 2 - 2
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 60 then
		return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
	end
	return ("%ds"):format(seconds)
end

local function chestBillboard()
	local existing = StarterGui:FindFirstChild("GearUi")
	local template = existing and existing:FindFirstChild("ChestTimerTemplate", true)
	if template then return template:Clone() end
	local builder = ReplicatedStorage.Shared:FindFirstChild("GearUiBuilder")
	if builder then return require(builder).BuildChestBillboard() end
	return nil
end

function GearService:_refreshChestVisual(player, entry)
	local record = chestModels[player] and chestModels[player][entry.Id]
	if not record then return end
	local info = Config.Chests.Types[entry.Rarity]
	local remaining = (entry.ReadyAt or 0) - os.time()
	local ready = remaining <= 0
	local billboard = record.Billboard
	if billboard then
		local titleLabel = billboard:FindFirstChild("Title", true)
		local timerLabel = billboard:FindFirstChild("Timer", true)
		if titleLabel then
			titleLabel.Text = info.DisplayName
			titleLabel.TextColor3 = info.Color
		end
		if timerLabel then
			timerLabel.Text = ready and "OPEN!" or formatTime(remaining)
			timerLabel.TextColor3 = ready and Color3.fromRGB(120, 255, 150) or Color3.new(1, 1, 1)
		end
	end
	local prompt = record.Prompt
	if prompt then
		if ready then
			-- v16: открытие — полное зажатие (анимация — client/ChestFX).
			prompt.ActionText = "HOLD TO OPEN"
			prompt.HoldDuration = (Config.Chests.HoldSeconds or {})[entry.Rarity] or 2
			prompt:SetAttribute("ChestOpen", true)
			prompt.Enabled = true
		elseif (info.SkipProductId or 0) ~= 0 then
			prompt.ActionText = ("SKIP  R$%d"):format(info.SkipRobux or 0)
			prompt.HoldDuration = 0
			prompt:SetAttribute("ChestOpen", false)
			prompt.Enabled = true
		else
			prompt.Enabled = false
		end
	end
end

function GearService:_spawnChestModel(player, entry)
	local pad = plotPad(player)
	if not pad then return end
	chestModels[player] = chestModels[player] or {}
	local model = chestAsset(entry.Rarity)
	model.Name = "PlacedChest_" .. entry.Id
	setPhysics(model, true, true)
	local offset = entry.Offset or { 0, 0, 0, 0 }
	local world = pad.CFrame * CFrame.new(offset[1] or 0, 0, offset[3] or 0) * CFrame.Angles(0, offset[4] or 0, 0)
	local _, size = model:GetBoundingBox()
	local floorY = pad.Position.Y + pad.Size.Y / 2
	model:PivotTo(CFrame.new(world.Position.X, floorY + size.Y / 2, world.Position.Z) * world.Rotation)
	local _, plot = plotPad(player)
	model.Parent = plot and plot.Content or workspace
	local root = rootPart(model)
	local billboard = chestBillboard()
	if billboard then
		billboard.Enabled = true
		billboard.Adornee = root
		billboard.Parent = root
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = Config.Chests.Types[entry.Rarity].DisplayName
	prompt.ActionText = "OPEN"
	prompt.HoldDuration = 0.4
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt:SetAttribute("ChestRarity", entry.Rarity)
	prompt.Parent = root
	model:SetAttribute("ChestRarity", entry.Rarity)
	prompt.Triggered:Connect(function(who)
		if who == player then self:_chestPrompt(player, entry.Id) end
	end)
	-- v18: «[G] View Drops» — вторичный промпт, открывает окно шансов
	-- (client/DropPreviewUI ловит его по атрибуту DropPreview).
	local dropsPrompt = Instance.new("ProximityPrompt")
	dropsPrompt.Name = "DropsPrompt"
	dropsPrompt.ObjectText = prompt.ObjectText
	dropsPrompt.ActionText = "View Drops"
	dropsPrompt.KeyboardKeyCode = Enum.KeyCode.G
	dropsPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	dropsPrompt.HoldDuration = 0
	dropsPrompt.RequiresLineOfSight = false
	dropsPrompt.MaxActivationDistance = 10
	dropsPrompt.Style = Enum.ProximityPromptStyle.Custom
	dropsPrompt:SetAttribute("OwnerUserId", player.UserId)
	dropsPrompt:SetAttribute("SecondaryPrompt", true)
	dropsPrompt:SetAttribute("DropPreview", "Chest:" .. entry.Rarity)
	dropsPrompt.Parent = root
	chestModels[player][entry.Id] = { Model = model, Billboard = billboard, Prompt = prompt, DropsPrompt = dropsPrompt }
	self:_refreshChestVisual(player, entry)
end

function GearService:_placeChest(player, position)
	local key = player:GetAttribute("HeldGear") or ""
	local rarity = key:match("^Chest_(%a+)$")
	local data = dataOf(player)
	if not (rarity and data and Config.Chests.Types[rarity]) or gearCount(data, key) <= 0 then return end
	local pad = plotPad(player)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- v20.9: призрак установки (PlacementGhost) присылает CFrame — с поворотом.
	local placedCFrame = typeof(position) == "CFrame" and position or nil
	if placedCFrame then position = placedCFrame.Position end
	if not (pad and hrp) or typeof(position) ~= "Vector3" then return end
	if not insidePad(pad, position) then
		Services.NotifyService:Show(player, "Place chests on YOUR base!", { Icon = "Geode" })
		return
	end
	if (position - hrp.Position).Magnitude > 30 then return end
	data.PlacedChests = data.PlacedChests or {}
	if #data.PlacedChests >= Config.Chests.MaxPlaced then
		Services.NotifyService:Show(player, ("Only %d chests can open at once"):format(Config.Chests.MaxPlaced), { Icon = "Geode" })
		return
	end
	data.Gear[key] -= 1
	local localPoint = pad.CFrame:PointToObjectSpace(position)
	local look = (hrp.Position - position) * Vector3.new(1, 0, 1)
	local yaw = look.Magnitude > 0.1 and math.atan2(-look.X, -look.Z) or 0
	if placedCFrame then
		local _, localYaw = pad.CFrame.Rotation:ToObjectSpace(placedCFrame.Rotation):ToOrientation()
		yaw = localYaw
	end
	local entry = {
		Id = HttpService:GenerateGUID(false),
		Rarity = rarity,
		ReadyAt = os.time() + Config.Chests.Types[rarity].OpenSeconds,
		Offset = { localPoint.X, 0, localPoint.Z, yaw },
	}
	table.insert(data.PlacedChests, entry)
	if data.Gear[key] <= 0 then self:Unequip(player) end
	Sfx.play("ChestSpawn", hrp)
	self:_spawnChestModel(player, entry)
	self:SendState(player)
	save(player)
end

local function findPlaced(data, chestId)
	for index, entry in data.PlacedChests or {} do
		if entry.Id == chestId then return entry, index end
	end
	return nil
end

local function weightedPick(loot)
	local total = 0
	for _, row in loot do total += row.Weight end
	local roll = math.random() * total
	for _, row in loot do
		roll -= row.Weight
		if roll <= 0 then return row end
	end
	return loot[#loot]
end

function GearService:_grantLoot(player, rarity)
	-- v18: УНИКАЛЬНЫЙ ЛУТ СУНДУКОВ — деньги, пиратские скины (только из
	-- сундуков), амулеты, очко престижа. Шансы — shared/DropTables (те же
	-- строки видит игрок в окне шансов).
	local info = Config.Chests.Types[rarity]
	local tiers = Services.DataService:GetTiers(player)
	local data = dataOf(player)
	local results = {}
	local isAvailable = Services.SkinService and function(skinId)
		return Services.SkinService:IsSkinAvailable(skinId)
	end or nil
	local dropTable = DropTables.Chest(rarity, isAvailable)
	local cartValue = Config.CartValue(tiers.Mine, tiers.Cart)

	-- Гарантия скина: каждый Every-й сундук этих редкостей без скина.
	local pity = Config.Chests.SkinPity
	local pityApplies = pity and pity.Rarities[rarity] and data ~= nil
	local forceSkin = pityApplies and (tonumber(data.ChestSkinPity) or 0) + 1 >= pity.Every
	local gotSkin = false

	for rollIndex = 1, info.Rolls do
		local row
		if forceSkin and rollIndex == 1 then
			row = DropTables.Pick(dropTable.Rows, function(r) return r.Kind == "Skin" end)
		end
		row = row or DropTables.Pick(dropTable.Rows)
		if not row then continue end
		if row.Kind == "Money" then
			local carts = row.Carts[1] + math.random() * (row.Carts[2] - row.Carts[1])
			local amount = math.max(1, math.floor(cartValue * carts))
			Services.DataService:AddMoney(player, amount)
			table.insert(results, { Kind = "Money", Text = "$" .. NumberFormat.abbreviate(amount), Amount = amount, Rarity = "Uncommon", Chance = row.Chance })
		elseif row.Kind == "Skin" and Services.SkinService then
			gotSkin = true
			local definition = Config.Skins.Definitions[row.SkinId]
			if Services.SkinService:OwnsSkin(player, row.SkinId) then
				-- Дубль — деньги.
				local amount = math.max(1, math.floor(cartValue * ((Config.Chests.DuplicateCarts or {})[rarity] or 2)))
				Services.DataService:AddMoney(player, amount)
				table.insert(results, {
					Kind = "Skin", SkinId = row.SkinId, Duplicate = true, Amount = amount, Rarity = definition.Rarity, Chance = row.Chance,
					Text = ("DUPLICATE %s → $%s"):format(definition.DisplayName, NumberFormat.abbreviate(amount)),
				})
			elseif Services.SkinService:GrantSkin(player, row.SkinId) then
				table.insert(results, { Kind = "Skin", SkinId = row.SkinId, New = true, Rarity = definition.Rarity, Chance = row.Chance, Text = "SKIN: " .. definition.DisplayName })
				if Services.AnnounceService and (definition.Rarity == "Legendary" or definition.Rarity == "Mythic") then
					pcall(function()
						Services.AnnounceService:Broadcast(nil, nil, {
							{ Text = ("%s found "):format(player.DisplayName), Color = Color3.new(1, 1, 1) },
							{ Text = definition.DisplayName, Color = Config.RarityColors[definition.Rarity] or Color3.new(1, 1, 1) },
							{ Text = (" in a %s!"):format(info.DisplayName), Color = Color3.new(1, 1, 1) },
						})
					end)
				end
			else
				local amount = math.max(1, math.floor(cartValue * 2))
				Services.DataService:AddMoney(player, amount)
				table.insert(results, { Kind = "Money", Text = "$" .. NumberFormat.abbreviate(amount), Amount = amount, Rarity = "Uncommon" })
			end
		elseif row.Kind == "Charm" then
			self:AddGear(player, row.Charm, 1)
			table.insert(results, { Kind = "Charm", Charm = row.Charm, Rarity = row.Rarity, Chance = row.Chance, Text = row.Title })
		elseif row.Kind == "PrestigePoint" and Services.PrestigeService then
			Services.PrestigeService:AddPoints(player, 1)
			table.insert(results, { Kind = "PrestigePoint", Text = "+1 PRESTIGE POINT", Rarity = "Legendary", Chance = row.Chance })
		end
	end
	if pityApplies then
		data.ChestSkinPity = gotSkin and 0 or (tonumber(data.ChestSkinPity) or 0) + 1
	end
	-- v14: шанс реликвии из сундука (Config.Relics.ChestMultiplier).
	if Services.BaseDecorService then
		local relicId = Services.BaseDecorService:RollRelic(player, tiers.Mine or 1, { Chest = rarity })
		local relicInfo = relicId and Config.Relics.Types[relicId]
		if relicInfo then
			table.insert(results, 1, { Kind = "Relic", RelicId = relicId, Text = "RELIC: " .. relicInfo.DisplayName, Rarity = relicInfo.Rarity })
			task.spawn(function()
				pcall(Services.BaseDecorService.GrantRelic, Services.BaseDecorService, player, relicId, rarity .. " Chest")
			end)
		end
	end
	return results
end

function GearService:_chestPrompt(player, chestId)
	local data = dataOf(player)
	local entry, index = findPlaced(data, chestId)
	if not entry then return end
	local info = Config.Chests.Types[entry.Rarity]
	if (entry.ReadyAt or 0) > os.time() then
		if (info.SkipProductId or 0) ~= 0 then
			pendingSkip[player] = chestId
			MarketplaceService:PromptProductPurchase(player, info.SkipProductId)
		end
		return
	end
	table.remove(data.PlacedChests, index)
	local record = chestModels[player] and chestModels[player][chestId]
	if chestModels[player] then chestModels[player][chestId] = nil end
	local results = self:_grantLoot(player, entry.Rarity)
	save(player)
	if Services.QuestService then pcall(Services.QuestService.RecordMetric, Services.QuestService, player, "ChestsOpened", 1) end
	-- v16: открытие рисуют клиенты (client/ChestFX): крышка улетает, луч,
	-- лут вылетает в мир. Серверная модель живёт ещё немного и удаляется.
	if record and record.Model then
		if record.Prompt then record.Prompt:Destroy() end
		if record.DropsPrompt then record.DropsPrompt:Destroy() end
		if chestFxRemote then
			chestFxRemote:FireAllClients("Open", {
				Model = record.Model, Rarity = entry.Rarity, Owner = player.UserId, Items = results,
			})
		end
		local model = record.Model
		task.delay(4, function()
			if model.Parent then model:Destroy() end
		end)
	end
	-- v18: вместо ленты справа владелец видит карточки открытия
	-- (shared/RevealCards, вызывает client/ChestFX после фонтана лута).
	self:SendState(player)
end

-- MonetizationService: покупка пропуска таймера прошла.
function GearService:SkipChestTimer(player, rarity)
	local data = dataOf(player)
	if not data then return false end
	local wanted = pendingSkip[player]
	local target = nil
	for _, entry in data.PlacedChests or {} do
		if entry.Rarity == rarity and (entry.ReadyAt or 0) > os.time() then
			if entry.Id == wanted or not target then target = entry end
		end
	end
	if not target then return false end
	target.ReadyAt = os.time()
	pendingSkip[player] = nil
	self:_refreshChestVisual(player, target)
	self:SendState(player)
	return true
end

function GearService:SetupPlot(player, plot)
	plotsByPlayer[player] = plot
	for _, record in chestModels[player] or {} do
		if record.Model then record.Model:Destroy() end
	end
	chestModels[player] = {}
	local data = dataOf(player)
	for _, entry in data and data.PlacedChests or {} do
		self:_spawnChestModel(player, entry)
	end
end

function GearService:SetupPlayer(player)
	local data = dataOf(player)
	if data then
		data.Gear = data.Gear or {}
		data.PlacedChests = data.PlacedChests or {}
	end
	player:SetAttribute("HeldGear", "")
	player:SetAttribute("HeldCartPackage", nil) -- v12: коробка над головой не переживает заход/респавн
	player.CharacterAdded:Connect(function(character)
		clearHeldVisual(player)
		player:SetAttribute("HeldGear", "")
		player:SetAttribute("HeldCartPackage", nil)
		-- Взял кирку/тул — снаряжение убирается из руки.
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and (player:GetAttribute("HeldGear") or "") ~= "" then
				self:Unequip(player)
			end
		end)
	end)
	self:SendState(player)
end

function GearService:CleanupPlayer(player)
	clearHeldVisual(player)
	lastDrinkAt[player] = nil
	for _, record in chestModels[player] or {} do
		if record.Model then record.Model:Destroy() end
	end
	chestModels[player] = nil
	plotsByPlayer[player] = nil
	lastRequest[player] = nil
	lastThrow[player] = nil
	pendingSkip[player] = nil
end

function GearService:Init(services)
	Services = services
	-- v16: визуал открытия сундука (client/ChestFX.client.lua).
	chestFxRemote = Instance.new("RemoteEvent")
	chestFxRemote.Name = "ChestFx"
	chestFxRemote.Parent = ReplicatedStorage.Shared
	-- v16: визуал динамита для всех клиентов (client/DynamiteFX.client.lua).
	dynamiteFxRemote = Instance.new("RemoteEvent")
	dynamiteFxRemote.Name = "DynamiteFx"
	dynamiteFxRemote.Parent = ReplicatedStorage.Shared
	remote = Instance.new("RemoteEvent")
	remote.Name = "GearRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerEvent:Connect(function(player, action, a, b)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.15 then return end
		lastRequest[player] = now
		if action == "GetState" then
			self:SendState(player)
		elseif action == "Equip" then
			if (player:GetAttribute("HeldGear") or "") == a then
				self:Unequip(player)
			else
				self:Equip(player, a)
			end
		elseif action == "Unequip" then
			self:Unequip(player)
		elseif action == "Use" then
			local held = player:GetAttribute("HeldGear") or ""
			if Config.Dynamite.Types[held] then
				self:_useDynamite(player, held, a, b)
			elseif held:match("^Chest_") then
				self:_placeChest(player, b)
			elseif Config.Potions and Config.Potions.Types[held] then
				self:_drinkPotion(player, held)
			elseif DropTables.EssenceMutation(held) then
				-- v18: эссенцию наносят у подиума, а не кликом.
				Services.NotifyService:Show(player, "Go to your Income Podium and press APPLY ESSENCE!", { Icon = "Quest", Duration = 2.5 })
			elseif Services.BaseDecorService and Services.BaseDecorService.IsPlaceableKey(held) and typeof(b) == "CFrame" then
				pcall(Services.BaseDecorService.PlaceFromGear, Services.BaseDecorService, player, held, b)
			end
		elseif action == "BuyDynamite" then
			local ok, reason = self:BuyDynamite(player, a, b)
			remote:FireClient(player, "BuyResult", { Ok = ok, Reason = reason })
			self:SendState(player)
		end
	end)
	-- v10: ежедневный бесплатный динамит владельцам Demolition Expert.
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in Players:GetPlayers() do
				pcall(self._checkDemolitionDaily, self, player)
			end
		end
	end)
	-- Таймеры сундуков — раз в секунду.
	task.spawn(function()
		while true do
			task.wait(1)
			for player, records in chestModels do
				local data = player.Parent and dataOf(player)
				if data then
					for _, entry in data.PlacedChests or {} do
						if records[entry.Id] then self:_refreshChestVisual(player, entry) end
					end
				end
			end
		end
	end)
end

return GearService
