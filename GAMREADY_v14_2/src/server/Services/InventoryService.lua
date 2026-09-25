
--------------------------------------------------------------------------------
-- InventoryService — РЮКЗАК, ХОТБАР, КИРКИ (см. Config.Inventory).
--
-- ПРАВИЛА (согласованы напрямую, см. комментарий у Config.Inventory):
--   • Руда подбирается НАСТУПАНИЕМ (радиус PickupRadius), без промпта.
--   • Тележка В РУКАХ → руда идёт в тележку (старый путь, CartService
--     :AddCrystal, не тронут); иначе → в рюкзак.
--   • Продажа — ТОЛЬКО тележкой у банка (см. BankService). Вся руда
--     игрока сама переливается в свою тележку, когда он рядом с ней
--     (см. _depositOneToCart).
--   • Смерть: выпадает DeathDropFraction (25%) СЛУЧАЙНЫХ предметов.
--   • Слоты: BaseSlots + ExtraPouch.BonusSlots; InfinitePouch снимает лимит.
--   • Хотбар: центральный слот — всегда кирка (F), остальные — руда.
--     Выбранная руда берётся в руки; зажать на игроке — подарить.
--
-- ВСЯ экономика (цена руды) считается на СЕРВЕРЕ и уже запечена в каждой
-- стопке (Value) — клиент только рисует. Дарение/продажа/подбор проходят
-- серверную проверку, клиенту не верим нигде.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService") -- для Uid стопок, см. ensureUid

local Config = require(ReplicatedStorage.Shared.Config)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local InventoryService = {}
local Services = nil

local inventoryRemote -- RemoteEvent: сервер → клиент (снимок инвентаря), клиент → сервер (действия)
local pickupClock = 0

--------------------------------------------------------------------------------
-- ВМЕСТИМОСТЬ
--------------------------------------------------------------------------------
function InventoryService:HasInfinitePouch(player)
	return Services.MonetizationService and Services.MonetizationService:HasPass(player, "InfinitePouch") or false
end

function InventoryService:GetSlotCount(player)
	if self:HasInfinitePouch(player) then
		return math.huge
	end
	-- СТАРТОВЫЙ РЮКЗАК (см. Config.Inventory.StarterSlots). Пока первая
	-- тележка не куплена, руду можно продавать прямо из рюкзака (см.
	-- Config.Bank.InventorySellEnabled) — и без этого ограничения 24
	-- ячейки по 99 штук превратили бы пешую ходку в полноценную замену
	-- рейсу тележкой, причём доступную раньше неё. Пять ячеек — это
	-- «донести добычу с пары камней», а не «возить вместо тележки».
	--
	-- Платные расширения (ExtraPouch/InfinitePouch) поверх стартового
	-- лимита НЕ применяются: они куплены под полноценный рюкзак, и
	-- складывать их с временным ограничением обучения бессмысленно —
	-- лимит и так снимется сам через пару минут.
	local data = Services.DataService and Services.DataService:GetGeodeData(player)
	if data and data.CartUnlocked ~= true and Config.Inventory.StarterSlots then
		return Config.Inventory.StarterSlots
	end
	local slots = Config.Inventory.BaseSlots
	if Services.MonetizationService and Services.MonetizationService:HasPass(player, "ExtraPouch") then
		slots += Config.GamePasses.ExtraPouch.BonusSlots or 0
	end
	return slots
end

--------------------------------------------------------------------------------
-- ДОСТУП К ДАННЫМ
--------------------------------------------------------------------------------
local function backpackOf(player)
	-- GetGeodeData возвращает ВЕСЬ профиль игрока (имя историческое — оно
	-- появилось ради жеод, но отдаёт profile.Data целиком, см. DataService).
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	data.Backpack = data.Backpack or {}
	return data.Backpack
end

-- Две стопки объединяются, только если СОВПАДАЕТ всё, что влияет на цену и
-- на вид: руда, вариация и набор мутаций. Иначе "Iron II Frozen" слился бы
-- с обычным "Iron II" и игрок потерял бы редкую мутацию в общей куче.
-- smelted — слиток из плавильни (см. IslandService). Слиток той же руды
-- стоит дороже, поэтому в одну стопку с сырой рудой он попадать не должен:
-- стопка хранит ОДНУ цену на все куски, и слиток потерял бы свою.
local function sameStack(a, oreKey, variant, mutations, smelted, gigantic)
	return a.Ore == oreKey and a.Variant == variant and (a.Mutations or "") == (mutations or "")
		and (a.Smelted == true) == (smelted == true)
		and (a.Gigantic == true) == (gigantic == true)
end

-- v9: «всё, что было у куска», переживает рюкзак, тележку, печь и руки:
-- GIGANTIC, пещера-источник (для редкости) и честный шанс «1/N».
local function extraFromCrystal(crystal)
	if not crystal then return nil end
	return {
		Gigantic = crystal:GetAttribute("Gigantic") == true or nil,
		Tier = tonumber(crystal:GetAttribute("CrystalTier")),
		Chance = tonumber(crystal:GetAttribute("CrystalDisplayChance")) or tonumber(crystal:GetAttribute("CrystalChance")),
	}
end
InventoryService.ExtraFromCrystal = extraFromCrystal

--------------------------------------------------------------------------------
-- v9: СНАРЯЖЕНИЕ (динамит, сундуки) В ИНВЕНТАРЕ
-- Хранится по-прежнему в data.Gear (GearService), слоты рюкзака НЕ тратит,
-- но показывается в сетке и кладётся в хотбар под Uid "gear:<Key>".
--------------------------------------------------------------------------------
-- v12: первой в списке — УПАКОВКА ТЕЛЕЖКИ (Config.CartPackage.GearKey).
-- Она лежит в том же data.Gear, что динамит и сундуки, и благодаря этому
-- получает слот в рюкзаке/хотбаре, иконку и перетаскивание бесплатно — см.
-- CartService (раздел "ВЛАДЕНИЕ ТЕЛЕЖКОЙ И УПАКОВКА").
local GEAR_ORDER = { "CartPackage", "Dynamite", "Dynamite_Medium", "Dynamite_Mega", "Chest_Legendary", "Chest_Epic", "Chest_Rare", "Chest_Common" }
-- Зелья торговца (Config.Potions) — тоже снаряжение: в инвентаре, без ячеек.
for _, potionKey in (Config.Potions and Config.Potions.Order) or {} do
	table.insert(GEAR_ORDER, potionKey)
end
-- v18: эссенции мутаций из жеод (Essence_<Мутация>), от редких к частым.
for _, essenceKey in require(ReplicatedStorage.Shared.DropTables).AllEssenceKeys() do
	table.insert(GEAR_ORDER, essenceKey)
end
local GEAR_PREFIX = "gear:"

local function gearStacks(data)
	local list = {}
	local gear = data and data.Gear
	if type(gear) ~= "table" then return list end
	for _, key in GEAR_ORDER do
		local count = math.max(0, math.floor(tonumber(gear[key]) or 0))
		if count > 0 then
			table.insert(list, { Uid = GEAR_PREFIX .. key, Gear = key, Count = count })
		end
	end
	-- v14: тотемы, декор и реликвии — тоже снаряжение (см. BaseDecorService).
	-- Порядок: реликвии, тотемы (старшие тиры выше), декор.
	local extra = {}
	for key, value in gear do
		local count = math.max(0, math.floor(tonumber(value) or 0))
		if count > 0 and typeof(key) == "string"
			and (key:match("^Relic:") or key:match("^Totem_") or key:match("^Decor_"))
		then
			table.insert(extra, { Uid = GEAR_PREFIX .. key, Gear = key, Count = count })
		end
	end
	local function rank(key)
		if key:match("^Relic:") then return 0 end
		if key:match("^Totem_Shrine_") then return 50 end -- v4: святилища — сразу после реликвий
		if key:match("^Totem_") then return 100 - (tonumber(key:match("_T(%d+)$")) or 0) end
		return 200
	end
	table.sort(extra, function(a, b)
		local ra, rb = rank(a.Gear), rank(b.Gear)
		if ra ~= rb then return ra < rb end
		return a.Gear < b.Gear
	end)
	for _, stack in extra do table.insert(list, stack) end
	return list
end

--------------------------------------------------------------------------------
-- ХОТБАР ССЫЛАЕТСЯ НА СТОПКИ ПО UID, А НЕ ПО ИНДЕКСУ
--
-- ЗДЕСЬ БЫЛА КОРНЕВАЯ ПРИЧИНА "инвентарь и хотбар будто не связаны".
--
-- Хотбар хранил ИНДЕКС стопки в массиве рюкзака. Это ссылка, которая
-- живёт ровно до первого изменения массива — а меняется он постоянно
-- (подобрал, продал, переставил, стопка кончилась). Каждое такое
-- изменение приходилось руками пересчитывать во всех слотах, и любая
-- пропущенная ветка означала, что слот показывает чужой предмет или
-- пустоту.
--
-- Хуже того, индексная таблица слотов ({[2] = 5}) — это РАЗРЕЖЕННЫЙ
-- числовой словарь, а документация Roblox прямо требует передавать через
-- RemoteEvent либо сплошной массив, либо словарь СО СТРОКОВЫМИ ключами,
-- без дыр. Числовые ключи при этом ещё и превращаются в строки по дороге.
-- То есть ссылка портилась и при хранении, и при пересылке.
--
-- Теперь у каждой стопки есть СОБСТВЕННЫЙ неизменный Uid, хотбар хранит
-- именно его, а на клиент уезжает ПЛОТНЫЙ МАССИВ из HotbarSlots строк
-- (пустой слот = ""). Плотный массив строк — единственная форма, которая
-- переживает сериализацию без сюрпризов. Перестановки и удаления в
-- рюкзаке больше вообще не трогают хотбар: Uid не меняется, что бы ни
-- случилось с порядком.
--------------------------------------------------------------------------------
local function ensureUid(stack)
	if not stack then return nil end
	if type(stack.Uid) ~= "string" or stack.Uid == "" then
		stack.Uid = HttpService:GenerateGUID(false)
	end
	return stack.Uid
end

-- Хотбар в виде плотного массива строк длиной HotbarSlots.
local function hotbarOf(data)
	local raw = data.Hotbar
	local slots = Config.Inventory.HotbarSlots
	local normalized = table.create(slots, "")
	for i = 1, slots do
		normalized[i] = ""
	end
	if type(raw) == "table" then
		for key, value in raw do
			local index = tonumber(key)
			-- Строковые Uid берём как есть; числа — это ссылки СТАРОГО
			-- формата (индексы), восстановить их уже нельзя, поэтому слот
			-- просто освобождается. Разовая потеря раскладки хотбара при
			-- переходе — приемлемо, предметы при этом никуда не деваются.
			if index and index >= 1 and index <= slots and type(value) == "string" then
				normalized[index] = value
			end
		end
	end
	-- ЧИСТКА МЁРТВЫХ ССЫЛОК — ЭТО И БЫЛ БАГ "РУДА НЕ ПОПАДАЕТ В ХОТБАР".
	-- Когда стопка кончалась (сдали в тележку, выбросили, подарили), её
	-- Uid оставался в слоте. Клиент рисовал такой слот пустым, но сервер
	-- считал его ЗАНЯТЫМ (putInFirstFreeHotbarSlot ищет строго ""). После
	-- первой же сдачи руды в тележку все 6 слотов забивались мёртвыми Uid,
	-- и вся новая руда уходила только в рюкзак. Теперь слот, чей Uid не
	-- находится в рюкзаке (или повторяется), считается пустым.
	local backpack = data.Backpack
	if type(backpack) == "table" then
		local alive = {}
		for _, stack in backpack do
			if type(stack) == "table" and type(stack.Uid) == "string" and (stack.Count or 0) > 0 then
				alive[stack.Uid] = true
			end
		end
		for _, gearStack in gearStacks(data) do
			alive[gearStack.Uid] = true
		end
		local seen = {}
		for i = 1, slots do
			local uid = normalized[i]
			if uid ~= "" and (not alive[uid] or seen[uid]) then
				normalized[i] = ""
			elseif uid ~= "" then
				seen[uid] = true
			end
		end
	end
	data.Hotbar = normalized
	return normalized
end

-- Найти стопку и её индекс по Uid.
local function findByUid(backpack, uid)
	if type(uid) ~= "string" or uid == "" or not backpack then return nil, nil end
	for index, stack in backpack do
		if stack.Uid == uid then return stack, index end
	end
	return nil, nil
end

local function putInFirstFreeHotbarSlot(player, stack)
	local data = Services.DataService:GetGeodeData(player)
	if not (data and stack) then return end
	local uid = type(stack) == "string" and stack or ensureUid(stack)
	local hotbar = hotbarOf(data)
	for _, assigned in hotbar do
		if assigned == uid then return end -- уже лежит в каком-то слоте
	end
	for slot = 1, Config.Inventory.HotbarSlots do
		if hotbar[slot] == "" then
			hotbar[slot] = uid
			return
		end
	end
end

-- Есть ли КУДА положить ещё хоть один предмет: либо свободный слот, либо
-- недозаполненная стопка. Проверять ТОЛЬКО число слотов недостаточно —
-- при забитых слотах игрок всё ещё может докидывать в уже существующую
-- стопку той же руды, и такой подбор нельзя блокировать.
function InventoryService:HasAnyRoom(player)
	if self:HasInfinitePouch(player) then return true end
	local backpack = backpackOf(player)
	if not backpack then return false end
	if #backpack < self:GetSlotCount(player) then return true end
	for _, stack in backpack do
		if stack.Count < Config.Inventory.StackSize then return true end
	end
	return false
end

function InventoryService:CountItems(player)
	local backpack = backpackOf(player)
	if not backpack then return 0 end
	local total = 0
	for _, stack in backpack do
		total += stack.Count
	end
	return total
end

--------------------------------------------------------------------------------
-- ДОБАВЛЕНИЕ / УДАЛЕНИЕ
--------------------------------------------------------------------------------
-- Влезет ли ОДИН кусок именно этой руды (та же логика, что в AddOre, но
-- без изменений). HasAnyRoom на это не годится: "есть неполная стопка
-- угля" не значит, что влезет железо.
function InventoryService:CanAddOre(player, oreKey, variant, mutations, smelted, gigantic)
	local backpack = backpackOf(player)
	if not backpack then return false end
	if #backpack < self:GetSlotCount(player) then return true end
	for _, stack in backpack do
		if sameStack(stack, oreKey, variant, mutations, smelted, gigantic) and stack.Count < Config.Inventory.StackSize then
			return true
		end
	end
	return false
end

-- Возвращает true, если поместилось. Сначала досыпает в существующую
-- стопку (пока не упрётся в StackSize), потом заводит новую — если есть
-- свободный слот.
function InventoryService:AddOre(player, oreKey, variant, mutations, value, count, smelted, extra)
	local backpack = backpackOf(player)
	if not backpack then return false end
	extra = type(extra) == "table" and extra or {}
	local gigantic = extra.Gigantic == true
	count = count or 1
	local stackSize = Config.Inventory.StackSize
	local slotCount = self:GetSlotCount(player)

	-- ПРИОРИТЕТ — ХОТБАР (по прямому запросу). Сначала досыпаем в
	-- подходящие стопки, которые УЖЕ стоят в хотбаре, и только потом — в
	-- лежащие в глубине рюкзака. Раньше бралась первая по порядку
	-- массива, и руда могла уйти в стопку в рюкзаке при такой же стопке
	-- прямо на хотбаре.
	local profile = Services.DataService:GetGeodeData(player)
	local inHotbar = {}
	if profile then
		for _, uid in hotbarOf(profile) do
			if uid ~= "" then inHotbar[uid] = true end
		end
	end
	local ordered = {}
	for _, stack in backpack do
		if stack.Uid and inHotbar[stack.Uid] then table.insert(ordered, stack) end
	end
	for _, stack in backpack do
		if not (stack.Uid and inHotbar[stack.Uid]) then table.insert(ordered, stack) end
	end

	for _, stack in ordered do
		if sameStack(stack, oreKey, variant, mutations, smelted, gigantic) and stack.Count < stackSize then
			putInFirstFreeHotbarSlot(player, stack)
			local room = stackSize - stack.Count
			local moved = math.min(room, count)
			stack.Count += moved
			count -= moved
			if count <= 0 then
				self:Sync(player)
				return true
			end
		end
	end

	while count > 0 do
		if #backpack >= slotCount then
			-- НЕ синкаем: на этом пути ничего не изменилось. Раньше Sync
			-- здесь был, и при полном рюкзаке цикл подбора (раз в 0.08с на
			-- каждый лежащий рядом кусок) спамил RemoteEvent'ами без конца.
			return false -- рюкзак полон, остаток НЕ теряется — вызывающий решает, что с ним делать
		end
		local moved = math.min(stackSize, count)
		table.insert(backpack, {
			Ore = oreKey,
			Variant = variant,
			Mutations = mutations,
			Value = value,
			Count = moved,
			Smelted = smelted == true or nil,
			Gigantic = gigantic or nil,
			Tier = tonumber(extra.Tier),
			Chance = tonumber(extra.Chance),
		})
		ensureUid(backpack[#backpack])
		putInFirstFreeHotbarSlot(player, backpack[#backpack])
		count -= moved
	end
	self:Sync(player)
	return true
end

-- silent = не слать Sync (для массовых операций — синкнуть один раз в конце).
function InventoryService:RemoveAt(player, index, count, silent)
	local backpack = backpackOf(player)
	local stack = backpack and backpack[index]
	if not stack then return nil end
	count = math.min(count or stack.Count, stack.Count)
	stack.Count -= count
	local removed = {
		Ore = stack.Ore, Variant = stack.Variant,
		Mutations = stack.Mutations, Value = stack.Value, Count = count,
		Smelted = stack.Smelted,
		Gigantic = stack.Gigantic, Tier = stack.Tier, Chance = stack.Chance,
	}
	if stack.Count <= 0 then
		table.remove(backpack, index)
		-- Хотбар держит ИНДЕКСЫ стопок — после удаления они съезжают, поэтому
		-- чиним ссылки, иначе слот покажет чужой предмет.
		-- Хотбар НЕ пересчитываем: он ссылается на Uid, а не на индекс.
		-- Стопка кончилась — её Uid просто перестаёт находиться, и слот
		-- рисуется пустым. Раньше здесь шла ручная переиндексация всех
		-- слотов, и каждая её ошибка означала чужой предмет в слоте.
	end
	if not silent then
		self:Sync(player)
	end
	return removed
end

local function cartForPlayer(player)
	local cartService = Services.CartService
	if not cartService then return nil end
	local held = cartService:GetHeldCart(player)
	if held then return held end
	local owned = cartService:GetOwnedCart(player)
	if owned and owned.HolderUserId == nil then return owned end
	return nil
end

local function cartStack(crystal)
	return {
		Ore = crystal:GetAttribute("CrystalOre"),
		Variant = crystal:GetAttribute("CrystalVariant") or 1,
		Mutations = crystal:GetAttribute("Mutations"),
		Value = crystal:GetAttribute("CrystalValue") or 0,
		Count = 1,
		Smelted = crystal:GetAttribute("Smelted") == true or nil,
		Gigantic = crystal:GetAttribute("Gigantic") == true or nil,
	}
end

function InventoryService:GetCartSnapshot(player)
	local cart = cartForPlayer(player)
	if not cart then return { Items = {}, Capacity = 0, Tier = 0, Carrying = false } end
	local items = {}
	for _, crystal in cart.Crystals do
		table.insert(items, cartStack(crystal))
	end
	return {
		Items = items,
		Capacity = cart.Capacity,
		Tier = cart.Tier,
		Carrying = cart.HolderUserId == player.UserId,
	}
end

function InventoryService:TransferToCart(player, index, count, skipSync)
	local cart = cartForPlayer(player)
	if not cart or (cart.HolderUserId ~= nil and cart.HolderUserId ~= player.UserId) then return false end
	count = math.clamp(tonumber(count) or 1, 1, 64)
	local backpack = backpackOf(player)
	local stack = backpack and backpack[index]
	if not stack or #cart.Crystals >= cart.Capacity then return false end
	local moved = math.min(count, stack.Count, cart.Capacity - #cart.Crystals)
	local transferred = 0
	for _ = 1, moved do
		local info = Config.OreByKey[stack.Ore]
		local variant = Config.OreVariants[stack.Variant or 1]
		if not info then break end
		local crystal = stack.Smelted and PlaceholderFactory.OreIngot(info, variant) or PlaceholderFactory.OreCrystal(info, variant)
		crystal:SetAttribute("CrystalOre", stack.Ore)
		crystal:SetAttribute("CrystalVariant", stack.Variant or 1)
		crystal:SetAttribute("Mutations", stack.Mutations)
		crystal:SetAttribute("CrystalValue", stack.Value or 0)
		if stack.Smelted then crystal:SetAttribute("Smelted", true) end
		local handPosition
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then handPosition = root.Position + Vector3.new(0, 1.1, 0.8) end
		if not Services.CartService:AddCrystal(cart, crystal, false, handPosition, true) then
			crystal:Destroy()
			break
		end
		stack.Count -= 1
		transferred += 1
	end
	if stack.Count <= 0 then table.remove(backpack, index) end
	if not skipSync then self:Sync(player) end
	-- true — только если реально что-то переехало (раньше true возвращался
	-- и когда тележка отказала на первом же куске).
	return transferred > 0
end

-- Односторонняя сдача выбранной руды из рук в ближайшую собственную тележку.
function InventoryService:DepositHeldOre(player, uidOrIndex)
	-- Клиент шлёт Uid; индекс поддержан только ради совместимости со
	-- старыми вызовами внутри сервера.
	local index = uidOrIndex
	if typeof(uidOrIndex) == "string" then
		local _, found = findByUid(backpackOf(player), uidOrIndex)
		index = found
	end
	if typeof(index) ~= "number" then return false end
	if typeof(index) ~= "number" then return false end
	local cart = Services.CartService:GetDepositCart(player, Config.Cart.DepositDistance)
	if not cart then return false end
	local backpack = backpackOf(player)
	local stack = backpack and backpack[index]
	if not stack then return false end
	local deposited = {
		Ore = stack.Ore,
		Variant = stack.Variant or 1,
		Mutations = stack.Mutations,
		Value = stack.Value or 0,
	}
	if not self:TransferToCart(player, index, 1, true) then return false end
	inventoryRemote:FireClient(player, "Deposited", deposited, cart.Root.Position)
	self:Sync(player)
	return true
end

--------------------------------------------------------------------------------
-- РУДА В РУКАХ — РЕПЛИЦИРУЕМЫЙ ФАКТ
--
-- Раньше "держу руду" знал ТОЛЬКО тот клиент, который её взял: модель
-- создавалась в его собственном workspace и никуда не реплицировалась,
-- поэтому остальные игроки видели человека с пустыми руками.
--
-- Сделано по образцу тележки (см. CartService:Attach → атрибут
-- HolderUserId на модели тележки): сервер выставляет на ИГРОКЕ атрибуты
-- с описанием куска, они реплицируются всем, и каждый клиент сам строит
-- себе копию руды и поднимает держателю руки (см.
-- client/OreCarryPose.client.lua). Ровно та же схема, что у хвата за
-- тележку: сервер владеет ФАКТОМ, клиенты — картинкой.
--------------------------------------------------------------------------------
function InventoryService:SetHeldOre(player, uid)
	if not (player and player.Parent) then return false end

	local function clear()
		player:SetAttribute("HeldOreUid", nil)
		player:SetAttribute("HeldOre", nil)
		player:SetAttribute("HeldOreVariant", nil)
		player:SetAttribute("HeldOreMutations", nil)
		player:SetAttribute("HeldOreSmelted", nil)
		player:SetAttribute("HeldOreValue", nil)
		player:SetAttribute("HeldOreGigantic", nil)
		player:SetAttribute("HeldOreTier", nil)
	end

	if uid == nil then
		clear()
		return true
	end
	if typeof(uid) ~= "string" then return false end
	-- v9: с телегой в руках руду взять нельзя (руки заняты).
	if player:GetAttribute("CarryingCart") == true then
		clear()
		if Services.NotifyService then
			Services.NotifyService:Show(player, "Hands busy — drop the cart first", { Icon = "Cart", Duration = 1.5 })
		end
		return false
	end

	local backpack = backpackOf(player)
	local stack = findByUid(backpack, uid)
	if not stack then
		-- Индекс не указывает ни на что (стопка кончилась, клиент отстал
		-- на один Sync) — это не ошибка, просто руки пустые.
		clear()
		return false
	end

	-- В руке может быть что-то одно: снаряжение убираем.
	if Services.GearService and (player:GetAttribute("HeldGear") or "") ~= "" then
		pcall(Services.GearService.Unequip, Services.GearService, player)
	end
	player:SetAttribute("HeldOreUid", uid)
	player:SetAttribute("HeldOre", stack.Ore)
	player:SetAttribute("HeldOreVariant", stack.Variant or 1)
	player:SetAttribute("HeldOreMutations", stack.Mutations or "")
	player:SetAttribute("HeldOreSmelted", stack.Smelted == true or nil)
	-- v3: цена куска для надписи над головой (вариация/мутации/ребёрт/слиток уже внутри).
	player:SetAttribute("HeldOreValue", tonumber(stack.Value) or 0)
	player:SetAttribute("HeldOreGigantic", stack.Gigantic == true or nil)
	player:SetAttribute("HeldOreTier", tonumber(stack.Tier))
	return true
end

--------------------------------------------------------------------------------
-- ПЕРЕТАСКИВАНИЕ (Satchel-style drag & drop)
--
-- Клиент присылает только НАМЕРЕНИЕ ("переставь стопку 3 на место 7",
-- "поменяй местами слоты хотбара 2 и 5"). Порядок предметов — это чистая
-- косметика, экономику он не трогает, но всё равно валидируется здесь:
-- клиент может прислать любые числа, включая дробные и отрицательные.
--------------------------------------------------------------------------------

-- Перестановка в рюкзаке по Uid. Хотбар при этом НЕ трогается вообще:
-- он ссылается на Uid, а порядок массива на Uid не влияет. Раньше здесь
-- жил пересчёт всех слотов (remapIndexAfterMove) — целый класс багов,
-- которого больше нет как явления.
function InventoryService:ReorderBackpack(player, fromUid, toUid)
	local backpack = backpackOf(player)
	if not backpack or #backpack < 2 then return false end
	local _, fromIndex = findByUid(backpack, fromUid)
	local _, toIndex = findByUid(backpack, toUid)
	if not fromIndex then return false end
	if not toIndex then toIndex = #backpack end
	if fromIndex == toIndex then return false end

	local stack = table.remove(backpack, fromIndex)
	table.insert(backpack, toIndex, stack)
	self:Sync(player)
	return true
end

function InventoryService:SwapHotbar(player, slotA, slotB)
	if typeof(slotA) ~= "number" or typeof(slotB) ~= "number" then return false end
	slotA, slotB = math.floor(slotA), math.floor(slotB)
	local maxSlot = Config.Inventory.HotbarSlots
	if slotA < 1 or slotA > maxSlot or slotB < 1 or slotB > maxSlot or slotA == slotB then
		return false
	end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	local hotbar = hotbarOf(data)
	hotbar[slotA], hotbar[slotB] = hotbar[slotB], hotbar[slotA]
	self:Sync(player)
	return true
end

--------------------------------------------------------------------------------
-- ПОДБОР НАСТУПАНИЕМ
--------------------------------------------------------------------------------
-- Единая точка правды "куда попадёт руда": тележка в руках → тележка,
-- иначе → рюкзак. Вызывается и подборщиком ниже, и CartService.
-- v10: пасс Ore Magnet увеличивает радиус подбора (руда «летит» к игроку —
-- полёт уже есть у подбора, см. CrystalService:PickupToInventory).
local function pickupRadiusFor(player)
	local monetization = Services.MonetizationService
	if monetization and monetization.GetPickupRadius then
		return monetization:GetPickupRadius(player)
	end
	return Config.Inventory.PickupRadius
end

local function tutorialCount(player, key)
	if Services.TutorialService then
		pcall(function() Services.TutorialService:Count(player, key, 1) end)
	end
end

function InventoryService:TryPickup(player, crystal)
	local heldCart = Services.CartService and Services.CartService:GetHeldCart(player)
	if heldCart and #heldCart.Crystals < heldCart.Capacity then
		local ok, root = pcall(CrystalUtil.GetRoot, crystal)
		local added = Services.CartService:AddCrystal(heldCart, crystal, false, ok and root and root.Position or nil) == true
		if added then tutorialCount(player, "OrePickedUp") end -- v20.36: шаг «собери руду»
		return added
	end

	local added = self:AddOre(
		player,
		crystal:GetAttribute("CrystalOre"),
		crystal:GetAttribute("CrystalVariant") or 1,
		crystal:GetAttribute("Mutations"),
		crystal:GetAttribute("CrystalValue") or 0,
		1,
		crystal:GetAttribute("Smelted") == true,
		extraFromCrystal(crystal)
	)
	if added then
		crystal:Destroy()
		tutorialCount(player, "OrePickedUp")
	end
	return added
end

--------------------------------------------------------------------------------
-- СМЕРТЬ: выпадает 25% случайного лута
--------------------------------------------------------------------------------
function InventoryService:DropOnDeath(player)
	local backpack = backpackOf(player)
	if not backpack or #backpack == 0 then return end
	local total = self:CountItems(player)
	local limit = Config.Inventory.DeathDropMaxItems or 5
	local toDrop = math.clamp(math.floor(total * Config.Inventory.DeathDropFraction), 0, limit)
	if toDrop <= 0 then return end

	-- v10: РУДА РЕАЛЬНО ВЫПАДАЕТ НА ЗЕМЛЮ (до DeathDropMaxItems штук,
	-- случайных из рюкзака), лежит, крутится и ждёт, пока её подберут —
	-- раньше она просто исчезала из инвентаря.
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local origin = hrp and hrp.Position or nil

	local dropped = 0
	for _ = 1, toDrop do
		if #backpack == 0 then break end
		local index = math.random(1, #backpack)
		local removed = self:RemoveAt(player, index, 1, true) -- silent: один Sync в конце
		dropped += 1
		if removed and origin and Services.CrystalService then
			local ok, crystal = pcall(Services.CrystalService.CreateFromStack, Services.CrystalService, removed)
			if ok and crystal then
				local angle = math.random() * math.pi * 2
				crystal:PivotTo(CFrame.new(origin + Vector3.new(0, 2.5, 0)))
				Services.CrystalService:MakeLoose(
					crystal,
					Vector3.new(math.cos(angle), 0, math.sin(angle)) * (8 + math.random() * 6) + Vector3.new(0, 14, 0),
					player.UserId,
					character,
					player.UserId
				)
				-- Крутится на месте, пока лежит (видно, что это подбираемый предмет).
				local root = crystal:IsA("Model") and (crystal.PrimaryPart or crystal:FindFirstChildWhichIsA("BasePart")) or crystal
				if root and root:IsA("BasePart") then
					task.delay(1.2, function()
						if root.Parent then
							root.AssemblyLinearVelocity = Vector3.zero
							root.AssemblyAngularVelocity = Vector3.new(0, Config.Inventory.DeathDropSpinSpeed or 2.5, 0)
						end
					end)
				end
			end
		end
	end
	self:Sync(player)
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("YOU DROPPED %d ITEMS"):format(dropped), { Duration = 3 })
	end
end

--------------------------------------------------------------------------------
-- КИРКИ: переключение между открытыми тирами + скины с мелкими баффами
--------------------------------------------------------------------------------
-- Открытым считается ЛЮБОЙ тир не выше купленного по прокачке — игрок и
-- так их все "проходил", а возможность вернуться на низкий тир это просто
-- косметика/выбор стиля, не эксплойт.
function InventoryService:GetMaxPickaxeTier(player)
	return Services.DataService:GetTiers(player).Pickaxe or 1
end

function InventoryService:GetEquippedPickaxeTier(player)
	local data = Services.DataService:GetGeodeData(player)
	local maxTier = self:GetMaxPickaxeTier(player)
	local chosen = data and data.EquippedPickaxeTier or 0
	if chosen == 0 or chosen > maxTier then
		return maxTier -- 0 = "всегда лучшая", и страховка, если тир понизился после ребёрта
	end
	return chosen
end

function InventoryService:EquipPickaxe(player, tier, skinName)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	local maxTier = self:GetMaxPickaxeTier(player)
	if tier and tier ~= 0 then
		if tier < 1 or tier > maxTier then return false end -- нельзя надеть неоткрытый тир
		data.EquippedPickaxeTier = tier
	end
	if skinName then
		-- Скин должен быть реально разблокирован (см. SkinService) — иначе
		-- любой мог бы прислать себе Void-скин с его баффом.
		local owned = skinName == "Default"
		if not owned and Services.SkinService then
			local ok, result = pcall(Services.SkinService.OwnsSkin, Services.SkinService, player, skinName)
			owned = ok and result == true
		end
		if owned then
			data.EquippedPickaxeSkin = skinName
		end
	end
	-- Перевыдаём Tool, иначе в руках останется старая кирка/старый скин:
	-- RefreshPickaxe сам снимает прежнюю, выдаёт новую и возвращает её в
	-- руки, если она была экипирована.
	if Services.CombatService then
		local okRefresh, err = pcall(Services.CombatService.RefreshPickaxe, Services.CombatService, player)
		if not okRefresh then warn("[InventoryService] RefreshPickaxe упал:", err) end
	end
	-- Скин мог поменять бонус скорости (см. Config.PickaxeSkinBuffs) —
	-- пересчитываем WalkSpeed сразу, а не до следующего события.
	if Services.CartService and Services.CartService.RecomputeWalkSpeed then
		pcall(Services.CartService.RecomputeWalkSpeed, Services.CartService, player)
	end
	self:Sync(player)
	return true
end

-- Суммарный бафф от текущего скина (см. Config.PickaxeSkinBuffs).
-- Возвращает таблицу множителей-ДОБАВОК: { Damage = 0.05, ... } = +5%.
function InventoryService:GetSkinBuffs(player)
	-- v8: баффы/дебаффы НАСТОЯЩЕГО скина кирки (SkinService, EquippedSkins.
	-- Pickaxe) из Config.SkinBuffs. Старые Bronze…Void остаются запасным
	-- вариантом для легаси-поля EquippedPickaxeSkin.
	local data = Services.DataService:GetGeodeData(player)
	local skinId = data and data.EquippedSkins and data.EquippedSkins.Pickaxe or ""
	if skinId ~= "" and Config.SkinBuffs and Config.SkinBuffs[skinId] then
		return Config.SkinBuffs[skinId]
	end
	local legacy = data and data.EquippedPickaxeSkin or "Default"
	return Config.PickaxeSkinBuffs[legacy] or Config.PickaxeSkinBuffs.Default
end

--------------------------------------------------------------------------------
-- ДАРЕНИЕ (зажать на игроке предмет из руки)
--------------------------------------------------------------------------------
function InventoryService:GiftFromSlot(player, targetPlayer, stackIndex)
	if player == targetPlayer then return false end
	if not (targetPlayer and targetPlayer.Parent) then return false end

	-- Дистанция проверяется НА СЕРВЕРЕ — клиент мог бы прислать любую цель.
	local fromRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local toRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not (fromRoot and toRoot) then return false end
	if (fromRoot.Position - toRoot.Position).Magnitude > Config.Inventory.GiftMaxDistance then return false end

	local backpack = backpackOf(player)
	local stack = backpack and backpack[stackIndex]
	if not stack then return false end

	-- Сначала проверяем, поместится ли у получателя — иначе предмет
	-- пропал бы у дарителя и не появился у цели.
	local targetSlots = self:GetSlotCount(targetPlayer)
	local targetBackpack = backpackOf(targetPlayer)
	if not targetBackpack then return false end
	local canFit = #targetBackpack < targetSlots
	if not canFit then
		for _, targetStack in targetBackpack do
			if sameStack(targetStack, stack.Ore, stack.Variant, stack.Mutations, stack.Smelted, stack.Gigantic)
				and targetStack.Count < Config.Inventory.StackSize then
				canFit = true
				break
			end
		end
	end
	if not canFit then
		if Services.NotifyService then
			Services.NotifyService:Show(player, "THEIR BACKPACK IS FULL", { Duration = 2.5 })
		end
		return false
	end

	local removed = self:RemoveAt(player, stackIndex, 1)
	if not removed then return false end
	self:AddOre(targetPlayer, removed.Ore, removed.Variant, removed.Mutations, removed.Value, 1, removed.Smelted, removed)
	if Services.NotifyService then
		Services.NotifyService:Show(targetPlayer, ("%s GIFTED YOU %s"):format(player.DisplayName, removed.Ore or "ORE"), { Duration = 3 })
		Services.NotifyService:Show(player, ("GIFTED TO %s"):format(targetPlayer.DisplayName), { Duration = 2.5 })
	end
	return true
end

--------------------------------------------------------------------------------
-- СИНХРОНИЗАЦИЯ С КЛИЕНТОМ
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- ВСЯ РУДА ПЕРЕЛИВАЕТСЯ В ТЕЛЕЖКУ (по прямому запросу — "когда игрок
-- подходит на нужную дистанцию к тележке, вся руда переливается в
-- тележку, а не только одна, которая в руках").
--
-- Раньше сдавалась ТОЛЬКО стопка в руках, и только по запросу клиента.
-- Теперь это решает сервер: игрок у своей тележки (та же проверка, что
-- была — CartService:GetDepositCart, дистанция Config.Cart.DepositDistance)
-- → по одному куску каждые CartAutoDepositInterval секунд, пока в
-- тележке есть место и у игрока есть руда. Поштучно — чтобы это
-- выглядело как поток, а не как мгновенное исчезновение рюкзака.
--
-- Порядок: сначала то, что лежит в глубине рюкзака, потом хотбар, потом
-- руда в руках HandCarry (подобранная чужая). Продать руду теперь можно
-- ТОЛЬКО тележкой (см. BankService, Config.Bank.HandSellEnabled), поэтому
-- вся руда игрока должна уметь в неё попасть.
--------------------------------------------------------------------------------
function InventoryService:_depositOneToCart(player, cart)
	local backpack = backpackOf(player)
	local profile = Services.DataService:GetGeodeData(player)

	if backpack and #backpack > 0 then
		local inHotbar = {}
		if profile then
			for _, uid in hotbarOf(profile) do
				if uid ~= "" then inHotbar[uid] = true end
			end
		end
		-- Кандидаты по порядку: сначала глубина рюкзака, потом хотбар. Если
		-- стопку перелить нельзя (например, руды с таким ключом больше нет в
		-- Config), пробуем следующую — одна битая стопка не должна
		-- блокировать перелив всего остального.
		local order = {}
		for index, stack in backpack do
			if not (stack.Uid and inHotbar[stack.Uid]) then table.insert(order, index) end
		end
		for index, stack in backpack do
			if stack.Uid and inHotbar[stack.Uid] then table.insert(order, index) end
		end
		for _, index in order do
			local stack = backpack[index]
			if stack and (stack.Count or 0) > 0 and Config.OreByKey[stack.Ore] then
				local deposited = {
					Ore = stack.Ore,
					Variant = stack.Variant or 1,
					Mutations = stack.Mutations,
					Value = stack.Value or 0,
					Smelted = stack.Smelted,
				}
				local uid = stack.Uid
				if self:TransferToCart(player, index, 1, true) then
					inventoryRemote:FireClient(player, "Deposited", deposited, cart.Root.Position)
					-- Стопка в руках кончилась → руки пустеют и у остальных
					-- игроков (атрибуты реплицируются), не дожидаясь клиента.
					if uid and player:GetAttribute("HeldOreUid") == uid and not findByUid(backpackOf(player), uid) then
						self:SetHeldOre(player, nil)
					end
					self:Sync(player)
					return true
				end
				-- Тележка отказала (заполнилась) — дальше пробовать нечего.
				if #cart.Crystals >= cart.Capacity then return false end
			end
		end
	end

	-- Руда в руках HandCarry — у неё нет своей стопки, собираем кусок.
	local hands = Services.HandCarryService
	if hands and hands.TakeOne and hands:HasOre(player) then
		local entry = hands:TakeOne(player)
		if not entry then return false end
		local tier = math.clamp(math.floor(tonumber(entry.Tier) or 1), 1, #Config.MineTiers)
		local value = tonumber(entry.Value) or 0
		-- Чужая (украденная) руда сохраняет свой бонус — раньше он
		-- начислялся при продаже из рук, а продажи из рук больше нет.
		if entry.OwnerUserId ~= nil and entry.OwnerUserId ~= player.UserId then
			value = math.floor(value * (Config.HandCarry.StolenOreMultiplier or 1) + 0.5)
		end
		local tierInfo = Config.MineTiers[tier]
		local showcase = tierInfo and tierInfo.Ores and (tierInfo.Ores[4] or tierInfo.Ores[1])
		local crystal = PlaceholderFactory.Crystal(tier)
		crystal:SetAttribute("CrystalTier", tier)
		crystal:SetAttribute("CrystalValue", value)
		crystal:SetAttribute("CrystalPoints", entry.Points or 0)
		if showcase and showcase.Key then
			crystal:SetAttribute("CrystalOre", showcase.Key)
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = root and (root.Position + Vector3.new(0, 1.6, 0)) or nil
		if not Services.CartService:AddCrystal(cart, crystal, false, from, true) then
			crystal:Destroy()
			-- Не влезло — возвращаем обратно в руки, ничего не теряем.
			if hands.PutBack then hands:PutBack(player, entry) end
			return false
		end
		self:Sync(player)
		return true
	end
	return false
end

-- ПРЕСТИЖ: ВСЯ РУДА ИЗ ИНВЕНТАРЯ ПРОПАДАЕТ (по прямому запросу).
-- Рюкзак, хотбар, руда в руках (и та, что держит персонаж, и HandCarry).
-- Кирки не трогаем — они живут отдельно (PickaxeTier/EquippedPickaxe), их
-- сбрасывает сам ребёрт. Стопка без поля Ore (на будущее — не руда)
-- остаётся на месте.
function InventoryService:ClearAllOre(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return 0 end
	local removed = 0
	local backpack = data.Backpack
	if type(backpack) == "table" then
		for index = #backpack, 1, -1 do
			local stack = backpack[index]
			if type(stack) == "table" and stack.Ore ~= nil then
				removed += tonumber(stack.Count) or 0
				table.remove(backpack, index)
			end
		end
	end
	-- v4: из хотбара убираем ТОЛЬКО руду. Снаряжение (тотемы, декор,
	-- реликвии, динамит, зелья, сундуки — Uid "gear:…") остаётся на своих
	-- слотах: престиж их не сбрасывает.
	local slots = Config.Inventory.HotbarSlots
	local kept = table.create(slots, "")
	local current = type(data.Hotbar) == "table" and data.Hotbar or {}
	for i = 1, slots do
		local uid = current[i]
		kept[i] = (type(uid) == "string" and uid:sub(1, #GEAR_PREFIX) == GEAR_PREFIX) and uid or ""
	end
	data.Hotbar = kept

	self:SetHeldOre(player, nil)
	local hands = Services.HandCarryService
	if hands and hands.TakeOne then
		while hands:HasOre(player) do
			if not hands:TakeOne(player) then break end
			removed += 1
		end
	end
	self:Sync(player)
	return removed
end

-- Для плавильни (IslandService): найти стопку по Uid и снять с неё ОДИН
-- кусок. Возвращает снятый кусок (таблица, как у RemoveAt) или nil.
function InventoryService:TakeOneByUid(player, uid)
	local backpack = backpackOf(player)
	local stack, index = findByUid(backpack, uid)
	if not (stack and index) then return nil end
	local removed = self:RemoveAt(player, index, 1, true)
	if removed and player:GetAttribute("HeldOreUid") == uid and not findByUid(backpackOf(player), uid) then
		self:SetHeldOre(player, nil)
	end
	self:Sync(player)
	return removed
end

function InventoryService:GetStackByUid(player, uid)
	return (findByUid(backpackOf(player), uid))
end

-- v20.22: сундук-хранилище на базе (BaseDecorService). Снять ВСЮ стопку
-- по Uid — таблица, как у RemoveAt, или nil.
function InventoryService:TakeStackByUid(player, uid)
	local backpack = backpackOf(player)
	local stack, index = findByUid(backpack, uid)
	if not (stack and index) then return nil end
	local removed = self:RemoveAt(player, index, stack.Count, true)
	if removed and player:GetAttribute("HeldOreUid") == uid then
		self:SetHeldOre(player, nil)
	end
	self:Sync(player)
	return removed
end

-- Сколько кусков ЭТОЙ руды влезет в рюкзак (досыпать в стопки + свободные
-- ячейки). AddOre на это количество гарантированно проходит целиком.
function InventoryService:RoomFor(player, stack)
	local backpack = backpackOf(player)
	if not (backpack and stack) then return 0 end
	local stackSize = Config.Inventory.StackSize
	local slots = self:GetSlotCount(player)
	if slots == math.huge then return math.huge end
	local room = math.max(0, slots - #backpack) * stackSize
	for _, other in backpack do
		if sameStack(other, stack.Ore, stack.Variant, stack.Mutations, stack.Smelted, stack.Gigantic) then
			room += math.max(0, stackSize - other.Count)
		end
	end
	return room
end

-- v9: GearService зовёт при изменении снаряжения. Новое — сразу в
-- свободный слот хотбара (как руда), затем обычный Sync.
function InventoryService:OnGearChanged(player, key, added)
	if added and added > 0 and typeof(key) == "string" then
		putInFirstFreeHotbarSlot(player, GEAR_PREFIX .. key)
	end
	self:Sync(player)
end

function InventoryService:Sync(player)
	if not (inventoryRemote and player and player.Parent) then return end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	local slots = self:GetSlotCount(player)
	local backpack = data.Backpack or {}
	-- Гарантируем Uid у каждой стопки перед отправкой: клиент адресует
	-- предметы ТОЛЬКО по нему.
	for _, stack in backpack do
		ensureUid(stack)
	end
	inventoryRemote:FireClient(player, "Sync", {
		Backpack = backpack,
		Cart = self:GetCartSnapshot(player),
		Hotbar = hotbarOf(data), -- ПЛОТНЫЙ массив строк-Uid; "" = пустой слот
		Gear = gearStacks(data), -- v9: снаряжение, слоты не тратит
		Slots = slots == math.huge and -1 or slots, -- -1 = безлимит (RemoteEvent не умеет math.huge)
		PickaxeTier = self:GetEquippedPickaxeTier(player),
		PickaxeMaxTier = self:GetMaxPickaxeTier(player),
		PickaxeSkin = data.EquippedPickaxeSkin or "Default",
	})
end

--------------------------------------------------------------------------------
-- НАСТРОЙКА ИГРОКА
--
-- Вызывается из Main.server.lua ПОСЛЕ загрузки профиля — ровно как у
-- остальных сервисов (CombatService:SetupPlayer и т.д.). Раньше сервис
-- вешал собственный Players.PlayerAdded прямо в Init, и это ломалось
-- дважды: (1) игрок, уже находящийся в игре к моменту Init (обычный
-- случай при запуске в Studio), не получал ни хук смерти, ни первый
-- Sync; (2) Sync мог уйти РАНЬШЕ загрузки профиля и вернуть пустой
-- инвентарь. Main вызывает нас в правильный момент и для уже
-- подключённых игроков тоже.
--------------------------------------------------------------------------------
function InventoryService:SetupPlayer(player)
	local function hookCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.Died:Connect(function()
				-- Руки очищаем ПЕРВЫМ делом: иначе труп (и заново заспавненный
				-- персонаж) остался бы с поднятыми руками и рудой над головой,
				-- которой в рюкзаке уже нет.
				self:SetHeldOre(player, nil)
				local ok, err = pcall(function() self:DropOnDeath(player) end)
				if not ok then warn("[InventoryService] DropOnDeath упал:", err) end
			end)
		end
		task.defer(function() self:Sync(player) end)
	end

	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	self:Sync(player)
end

--------------------------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ
--------------------------------------------------------------------------------
function InventoryService:Init(services)
	Services = services

	inventoryRemote = Instance.new("RemoteEvent")
	inventoryRemote.Name = "InventoryRequest"
	inventoryRemote.Parent = ReplicatedStorage.Shared

	-- ЗАЩИТА ОТ СПАМА REMOTE'АМИ. Раньше любой клиент мог гнать
	-- "Sync"/"Gift"/"DepositHeldOre" сотнями в секунду: каждый Sync — это
	-- сериализация всего рюкзака и FireClient, то есть бесплатная для
	-- атакующего и дорогая для сервера операция. Ограничиваем по типу
	-- действия, а не общим счётчиком, чтобы поток перетаскиваний (их
	-- бывает много и они дешёвые) не блокировал редкие дорогие действия.
	local lastAction = {} -- [userId] = { [action] = os.clock() }
	local ACTION_COOLDOWN = {
		Sync = 0.25,
		Gift = 0.5,
		DepositHeldOre = 0.15,
		SetHotbar = 0.05,
		SwapHotbar = 0.05,
		ReorderBackpack = 0.05,
		EquipPickaxe = 0.15,
		Hold = 0.05,
		DropHeld = 0.2,
	}
	local function throttled(player, action)
		local cooldown = ACTION_COOLDOWN[action]
		if not cooldown then return true end -- неизвестное действие — режем
		local bucket = lastAction[player.UserId]
		if not bucket then
			bucket = {}
			lastAction[player.UserId] = bucket
		end
		local now = os.clock()
		if bucket[action] and now - bucket[action] < cooldown then
			return true
		end
		bucket[action] = now
		return false
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player.UserId] = nil
	end)

	inventoryRemote.OnServerEvent:Connect(function(player, action, a, b)
		if typeof(action) ~= "string" then return end
		if throttled(player, action) then return end
		local ok, err = pcall(function()
			if action == "SetHotbar" then
				-- a = номер слота, b = индекс стопки (или nil, чтобы очистить)
				local data = Services.DataService:GetGeodeData(player)
				if not data then return end
				local hotbar = hotbarOf(data)
				if typeof(a) == "number" and a >= 1 and a <= Config.Inventory.HotbarSlots then
					-- b = Uid стопки (строка) либо nil, чтобы очистить слот.
					hotbar[math.floor(a)] = (typeof(b) == "string" and b) or ""
					self:Sync(player)
				end
			elseif action == "EquipPickaxe" then
				self:EquipPickaxe(player, typeof(a) == "number" and a or nil, typeof(b) == "string" and b or nil)
			elseif action == "SwapHotbar" then
				-- a, b = номера слотов хотбара (перетаскивание слот↔слот)
				self:SwapHotbar(player, a, b)
			elseif action == "ReorderBackpack" then
				-- a = откуда, b = куда (перетаскивание внутри сетки)
				self:ReorderBackpack(player, a, b)
			elseif action == "Gift" then
				-- a = целевой игрок, b = индекс стопки. Проверяем, что это
				-- РЕАЛЬНО Player: клиент может прислать любой Instance, и
				-- дальше по коду обращение к .Character у, скажем, Part
				-- просто молча вернуло бы nil — лучше отсечь сразу.
				if typeof(b) == "string" and typeof(a) == "Instance" and a:IsA("Player") then
					local _, giftIndex = findByUid(backpackOf(player), b)
					if giftIndex then self:GiftFromSlot(player, a, giftIndex) end
				end
			elseif action == "DropHeld" then
				-- a = Uid стопки. Снимаем ОДИН кусок и просим MineService
				-- швырнуть его по дуге — дальше он ничем не отличается от
				-- руды, выпавшей из шахты.
				if typeof(a) == "string" then
					local backpack = backpackOf(player)
					local stack, index = findByUid(backpack, a)
					if stack and index and Services.MineService and Services.CrystalService then
						local removed = self:RemoveAt(player, index, 1, true)
						if removed then
							local ok, crystal = pcall(function()
								return Services.CrystalService:CreateFromStack(removed)
							end)
							if ok and crystal then
								Services.MineService:ThrowOreToGround(player, crystal)
							end
						end
						-- Руки освобождаем в любом случае: стопка ушла.
						self:SetHeldOre(player, nil)
						self:Sync(player)
					end
				end
			elseif action == "Hold" then
				-- a = индекс стопки в руках, либо nil = руки пустые.
				self:SetHeldOre(player, typeof(a) == "string" and a or nil)
			elseif action == "DepositHeldOre" then
				self:DepositHeldOre(player, a)
			elseif action == "Sync" then
				self:Sync(player)
			end
		end)
		if not ok then warn("[InventoryService] Обработка действия", action, "упала:", err) end
	end)


	-- ПОДБОР НАСТУПАНИЕМ. Один общий цикл на всех игроков — дешевле, чем
	-- Touched на каждом куске руды, и не зависит от того, успел ли кусок
	-- получить коллизию после приземления.
	RunService.Heartbeat:Connect(function(dt)
		pickupClock += dt
		if pickupClock < Config.Inventory.PickupCooldown then return end
		pickupClock = 0

		local folder = workspace:FindFirstChild("MineGroundOre")
		if not folder then return end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			-- Если девать руду некуда (рюкзак полон И тележки в руках нет),
			-- даже не перебираем лежащие куски: раньше это каждый тик
			-- прогоняло весь цикл впустую и дёргало AddOre по кругу.
			local heldCart = root and Services.CartService and Services.CartService:GetHeldCart(player)
			local cartHasRoom = heldCart and #heldCart.Crystals < heldCart.Capacity
			local backpackHasRoom = root and self:HasAnyRoom(player)
			-- v14.3: после выхода из шахты куча не летит в игрока, пока он
			-- сам не отошёл от точки появления (MineService ставит MineExitPos).
			local exitPos = root and player:GetAttribute("MineExitPos")
			if exitPos and (root.Position - exitPos).Magnitude >= (Config.MineExpedition.ExitMoveThreshold or 3) then
				player:SetAttribute("MineExitPos", nil)
				exitPos = nil
			end
			local fullRadius = root and pickupRadiusFor(player) or 0
			local dropRadius = fullRadius > Config.Inventory.PickupRadius
				and (Config.MineExpedition.DropPickupRadiusMagnet or 9)
				or (Config.MineExpedition.DropPickupRadius or 4.5)
			dropRadius = math.min(dropRadius, fullRadius)
			if root and (cartHasRoom or backpackHasRoom) then
				for _, crystal in folder:GetChildren() do
					local mineDrop = crystal:GetAttribute("MineDrop") == true
					if mineDrop and exitPos then continue end
					-- Подбирает ТОЛЬКО владелец выброса — чужую кучу не унести.
					-- Свою руду с участка — только владелец; выброшенную руками
					-- (PublicDrop) — кто угодно, в том числе другие игроки.
					local mine = crystal:GetAttribute("GroundOreOwner") == player.UserId
					local public = crystal:GetAttribute("PublicDrop") == true

					-- Тот, кто выбросил кусок, пару секунд не может поднять его
					-- обратно: он стоит ровно на месте броска, и без паузы руда
					-- всасывалась бы мгновенно. Остальных это не касается.
					local cooling = crystal:GetAttribute("DropOwnerUserId") == player.UserId
						and os.time() < (crystal:GetAttribute("DropOwnerCooldownUntil") or 0)

					-- Только полностью улёгшаяся руда (PickupReady ставит
					-- MineService, когда приземление доиграно), не во время
					-- катсцены (CutsceneScaled) и не пока она садится обратно
					-- к обычному размеру (ShrinkingBack) — иначе полёт к
					-- игроку и эти анимации писали бы размер/позицию
					-- одновременно. PickupRetryAt — пауза после неудачной
					-- попытки (не влезла в рюкзак).
					local ready = crystal:GetAttribute("Landed") == true
						and crystal:GetAttribute("PickupReady") == true
						and crystal:GetAttribute("CutsceneScaled") ~= true
						and crystal:GetAttribute("ShrinkingBack") ~= true
						and crystal:GetAttribute("InventoryPickupInProgress") ~= true
						and os.clock() >= (crystal:GetAttribute("PickupRetryAt") or 0)
					if (mine or public) and not cooling and ready then
						local ok, crystalRoot = pcall(CrystalUtil.GetRoot, crystal)
						if ok and crystalRoot and crystalRoot.Parent
							and (crystalRoot.Position - root.Position).Magnitude <= (mineDrop and dropRadius or fullRadius) then
							pcall(function()
								if Services.CrystalService then
									Services.CrystalService:PickupToInventory(player, crystal)
								else
									self:TryPickup(player, crystal)
								end
							end)
						end
					end
				end
			end
		end
	end)

	-- Перелив всей руды в тележку, когда игрок рядом (см. _depositOneToCart).
	local depositClock = 0
	RunService.Heartbeat:Connect(function(dt)
		depositClock += dt
		if depositClock < (Config.Inventory.CartAutoDepositInterval or 0.08) then return end
		depositClock = 0
		if not Services.CartService then return end
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("EconomyTransactionLocked") == true then continue end
			local ok, err = pcall(function()
				local cart = Services.CartService:GetDepositCart(player, Config.Cart.DepositDistance)
				if cart and not cart.Selling and cart.Root and cart.Root.Parent then
					self:_depositOneToCart(player, cart)
				end
			end)
			if not ok then
				warn("[InventoryService] Перелив в тележку упал:", err)
			end
		end
	end)
end

return InventoryService
