--------------------------------------------------------------------------------
-- CrystalService
-- Кристаллы — физические объекты. Стоимость и тир лежат в атрибутах
-- самого Part'а, поэтому кристалл самодостаточен: в чьей бы тележке он
-- ни оказался, банк заплатит именно его цену.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)
local MutationRoll = require(ReplicatedStorage.Shared.MutationRoll)

local CrystalService = {}

local Services = nil
local looseFolder = nil
-- [player.UserId] = {model, model, ...} — украденные жеоды, приваренные на
-- спину (см. _flyToBack), пока не сброшены достижением банка
-- (BankService:Start вызывает ClearStolenGeodeVisuals) или смертью персонажа
-- (вместе с character уничтожаются автоматически, но запись тут тоже чистим).
local stolenGeodeVisuals = {}

local function colorHex(color)
	return ("%02X%02X%02X"):format(
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function clearStolenVisuals(player)
	local list = stolenGeodeVisuals[player.UserId]
	for _, model in list or {} do
		if model and model.Parent then model:Destroy() end
	end
	stolenGeodeVisuals[player.UserId] = nil
end

-- Личный ценник кристалла: виден, пока кристалл летит/лежит и ещё
-- не приземлился в тележку (CartService снимает его при посадке).
-- Формат "x{тир} · ${цена}" — икс всегда виден отдельно от денег,
-- чтобы было понятно: чем реже руда, тем выше множитель.
-- Если у модели (реальный Studio-ассет Crystal_TierN, не плейсхолдер)
-- уже есть свой BillboardGui "PriceGui" с TextLabel внутри — используем
-- его как есть (шрифт/размер остаются авторскими), просто пишем текущий
-- текст/цвет. Иначе строим плейсхолдер сами.
-- oreInfo — конкретная выпавшая руда (Config.OreChain-запись, НЕ
-- Config.MineTiers[tier]), chanceFraction — итоговая (руда-в-тире × мутация,
-- если есть) вероятность ДОЛЕЙ (0.05 = 1/20). mutationName — имя мутации
-- (или nil), см. ТЗ: "IRON 1/20" без мутации, "IRON SOAKED\n1/60" с ней
-- (две строки).
-- По атрибутам куска восстанавливает всё, что нужно ценнику: запись руды
-- из Config.OreChain, вариацию (I/II/III) и подпись мутаций. Нужна там,
-- где под рукой только сам кусок (MakeLoose), а не данные его ролла.
local function resolveOreInfo(crystal, tierFallback)
	local oreInfo = Config.OreByKey[crystal:GetAttribute("CrystalOre")]
	if not oreInfo then
		-- Старый кусок без CrystalOre — берём "витринную" руду его тира
		-- (у Config.MineTiers[tier] есть те же DisplayName/Color).
		local tier = tonumber(tierFallback or crystal:GetAttribute("CrystalTier")) or 1
		oreInfo = Config.MineTiers[math.clamp(math.floor(tier), 1, #Config.MineTiers)] or Config.OreChain[1]
	end
	return oreInfo
end

local function mutationLabelFor(crystal)
	local raw = crystal:GetAttribute("Mutations")
	if type(raw) ~= "string" or raw == "" then return nil end
	local names = {}
	for _, id in string.split(raw, ",") do
		local mutation = Config.Mutations[id]
		if mutation and mutation.DisplayName then
			table.insert(names, mutation.DisplayName)
		end
	end
	return #names > 0 and table.concat(names, " ") or nil
end

local function attachPriceGui(crystal, oreInfo, value, chanceFraction, mutationName, variantInfo)
	-- ЗАЩИТА ОТ СТАРОЙ СИГНАТУРЫ. Раньше сюда вторым аргументом приходил
	-- НОМЕР ТИРА (так до сих пор звал MakeLoose), а функция уже ждала
	-- запись руды — отсюда "attempt to index number with 'Color'" на
	-- каждом выбитом/выпавшем куске. Теперь число/пустое значение
	-- превращается в запись руды по атрибутам самого куска.
	if type(oreInfo) ~= "table" or typeof(oreInfo.Color) ~= "Color3" then
		oreInfo = resolveOreInfo(crystal, type(oreInfo) == "number" and oreInfo or nil)
	end
	if type(chanceFraction) ~= "number" then chanceFraction = 0 end
	if oreInfo.Junk then
		variantInfo = nil -- v17: у мусора нет вариаций I/II/III
		crystal:SetAttribute("Junk", true)
	end
	value = tonumber(value) or 0
	local nameColor = oreInfo.Color:Lerp(Color3.new(1, 1, 1), 0.72)
	local incomeColor = Color3.fromRGB(95, 255, 130)
	local oddsColor = Color3.fromRGB(255, 225, 130)
	local oneInN = chanceFraction > 0 and math.max(1, math.round(1 / chanceFraction)) or 0
	-- Вариация (I/II/III, см. Config.OreVariants) приписывается к имени
	-- руды: "IRON II". Вариация 1 тоже подписывается — иначе игрок не
	-- поймёт, что бывают другие, и будет считать "IRON" и "IRON III"
	-- разными рудами, а не вариациями одной.
	local baseName = variantInfo and (oreInfo.DisplayName .. " " .. variantInfo.DisplayName) or oreInfo.DisplayName
	local nameLine = mutationName
		and ("%s <font color=\"#%s\">%s</font>"):format(baseName, colorHex(Color3.fromRGB(255, 160, 60)), mutationName:upper())
		or baseName
	-- ШАНС ПОКАЗЫВАЕМ, ТОЛЬКО ЕСЛИ ОН ЕСТЬ.
	--
	-- Раньше строка жёстко содержала "1/%d", и при chanceFraction = 0
	-- (кусок, выброшенный игроком из рюкзака — он уже был раскрыт когда-то,
	-- и заново разыгрывать его шанс нечем) на табличке печаталось "1/0".
	-- Это не просто некрасиво: "1/0" читается как настоящая вероятность и
	-- вводит в заблуждение. Теперь при нулевом шансе строка с шансом
	-- просто не выводится, остаются имя и цена.
	local oddsSegment = oneInN > 0
		and ('<font color="#%s">1/%d</font>  '):format(colorHex(oddsColor), oneInN)
		or ""
	local text = ('<font color="#%s">%s</font>\n%s<font color="#%s">$%s</font>'):format(
		colorHex(nameColor),
		nameLine:upper(),
		oddsSegment,
		colorHex(incomeColor),
		NumberFormat.abbreviate(value)
	)

	local root = CrystalUtil.GetRoot(crystal)
	local gui = crystal:FindFirstChild("PriceGui", true) -- recursive: авторский PriceGui может лежать где угодно внутри Model
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel")

	if not gui or not label then
		if gui then
			gui:Destroy() -- нашли BillboardGui, но без TextLabel внутри — пересоберём с нуля
		end
		gui = Instance.new("BillboardGui")
		gui.Name = "PriceGui"
		gui.Size = UDim2.new(4.4, 0, 1.2, 0)
		gui.StudsOffset = Vector3.new(0, 2.2, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 100
		gui.DistanceStep = 0 -- фиксированный размер на экране
		gui.Adornee = root -- важно для Model-кристаллов: без Adornee биллборд не знает, где висеть
		gui.Parent = root

		label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.TextScaled = true
		label.TextStrokeColor3 = Color3.fromRGB(20, 20, 25)
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end

	gui.Size = UDim2.new(4.4, 0, 1.2, 0)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 100
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	label.TextStrokeTransparency = 0
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	return label
end

--------------------------------------------------------------------------------
-- РУДА НИ С КЕМ НЕ СТАЛКИВАЕТСЯ (по прямому запросу — "коллизии у руды
-- быть не должно").
--
-- Раньше лежащая руда после приземления получала CanCollide = true (см.
-- flyOre в MineService), а выбитая (MakeLoose) — тоже, и о куски
-- спотыкались игроки, в них упиралась тележка, куча толкалась сама с
-- собой.
--
--   • Руда НА ЗЕМЛЕ (workspace.MineGroundOre) заанкорена и висит в воздухе
--     на ховере — ей коллизия не нужна вообще: CanCollide = false у ВСЕХ
--     деталей куска.
--   • Выбитая руда (LooseCrystals) падает ФИЗИКОЙ — без коллизии с миром
--     она провалилась бы сквозь пол. Поэтому она в своей группе "Ore",
--     которая сталкивается ТОЛЬКО с миром (Default): не с игроками
--     (CartCarrier — в эту группу CartService кладёт всех персонажей), не
--     с тележками (Cart), не с гоблинами и не сама с собой.
--   • Касание (Touched → подбор выбитой руды) от этого не ломается: оно
--     зависит от CanTouch, а не от столкновений.
--------------------------------------------------------------------------------
local ORE_COLLISION_GROUP = "Ore"

local function ensureOreCollisionGroup()
	local PhysicsService = game:GetService("PhysicsService")
	for _, name in { ORE_COLLISION_GROUP, "Cart", "CartCarrier", "Goblins" } do
		pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
	end
	for _, other in { ORE_COLLISION_GROUP, "Cart", "CartCarrier", "Goblins" } do
		pcall(function() PhysicsService:CollisionGroupSetCollidable(ORE_COLLISION_GROUP, other, false) end)
	end
end

local function applyOreCollision(instance, noCollideAtAll)
	if not instance:IsA("BasePart") then return end
	instance.CollisionGroup = ORE_COLLISION_GROUP
	if noCollideAtAll then
		instance.CanCollide = false
	end
end

-- Следит за папкой: всё, что в неё попадает (и всё, что потом меняет
-- CanCollide у лежащих кусков), приводится к правилу выше.
local function watchOreFolder(folder, noCollideAtAll)
	for _, descendant in folder:GetDescendants() do
		applyOreCollision(descendant, noCollideAtAll)
	end
	folder.DescendantAdded:Connect(function(descendant)
		applyOreCollision(descendant, noCollideAtAll)
		if noCollideAtAll and descendant:IsA("BasePart") then
			-- Кто-то (старый код, ассет) включит коллизию обратно —
			-- выключаем, пока кусок лежит в этой папке.
			descendant:GetPropertyChangedSignal("CanCollide"):Connect(function()
				if descendant.CanCollide and descendant:IsDescendantOf(folder) then
					descendant.CanCollide = false
				end
			end)
		end
	end)
end

function CrystalService:Init(services)
	Services = services
	-- v14.4: remote эффекта подбора создаётся СРАЗУ. Раньше он появлялся
	-- только при первом подборе, а клиент ждал его 60 сек и выключался —
	-- поэтому анимации подбора не было видно вовсе.
	self:_ensurePickupFx()
	looseFolder = Instance.new("Folder")
	looseFolder.Name = "LooseCrystals"
	looseFolder.Parent = workspace

	ensureOreCollisionGroup()
	watchOreFolder(looseFolder, false)
	local groundFolder = workspace:FindFirstChild("MineGroundOre")
	if not groundFolder then
		groundFolder = Instance.new("Folder")
		groundFolder.Name = "MineGroundOre"
		groundFolder.Parent = workspace
	end
	watchOreFolder(groundFolder, true)
	Players.PlayerRemoving:Connect(function(player)
		clearStolenVisuals(player)
	end)
	local function hookPlayer(player)
		player.CharacterAdded:Connect(function() clearStolenVisuals(player) end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do hookPlayer(player) end
end

-- Независимые роллы каждой мутации (могут комбинироваться) — возвращает
-- список ID выпавших мутаций (в порядке Config.Mutations.Order) и итоговый
-- множитель цены (произведение всех сработавших Multiplier).
-- Удача игрока: чем больше ребёртов и выше тир шахты, тем выше шансы РЕДКИХ
-- мутаций (см. Config.Mutations.LuckBonus). Для руды без владельца (miner =
-- nil) удача нулевая — брать её неоткуда.
local function luckFor(miner)
	if not miner then return 0 end
	local ok, luck = pcall(function()
		return MutationRoll.LuckFor(
			Services.DataService:GetRebirths(miner),
			Services.DataService:GetTiers(miner).Mine
		)
	end)
	luck = ok and luck or 0
	-- Временный бафф "х2 удача" из жеод (см. ТЗ и BuffService) — ДОБАВКА,
	-- а не множитель: на низких тирах базовая удача близка к нулю,
	-- умножать там нечего (см. подробный комментарий в BuffService.lua).
	if Services.BuffService then
		luck += Services.BuffService:GetBonus(miner, "Luck")
	end
	-- Мелкий бафф удачи от надетого скина кирки (см. Config.PickaxeSkinBuffs).
	-- Как и бафф из жеод — ДОБАВКА, а не множитель: на низких тирах базовая
	-- удача близка к нулю, умножать там нечего.
	if Services.InventoryService then
		local okSkin, buffs = pcall(Services.InventoryService.GetSkinBuffs, Services.InventoryService, miner)
		if okSkin and buffs and buffs.Luck then
			luck += buffs.Luck
		end
	end
	return luck
end

-- Строка вида "5%"/"2.5%"/"0.30%" — процент с разумной точностью в
-- зависимости от порядка величины (чтобы редкие мутации не округлялись до
-- невидимого "0%"). Используется и для одной мутации, и для произведения
-- шансов нескольких сразу (см. announceMutations ниже).
--
-- КОМБИНИРОВАННЫЙ шанс НЕСКОЛЬКИХ мутаций сразу может быть на порядки
-- меньше шанса любой из них по отдельности (перемножение вероятностей) —
-- раньше фиксированные 2 знака после запятой на таких значениях реально
-- округляли текст до "0.00%", хотя шанс был ненулевым. Теперь точность
-- растёт вместе с тем, насколько маленькое число (максимум 4 знака —
-- дальше просто "<0.0001%", не расползаясь в нечитаемую простыню цифр).
local function formatChancePercent(fraction)
	local percent = fraction * 100
	if percent <= 0 then return "0%" end
	if percent >= 1 then
		return ("%.0f%%"):format(percent)
	elseif percent >= 0.1 then
		return ("%.1f%%"):format(percent)
	elseif percent >= 0.01 then
		return ("%.2f%%"):format(percent)
	elseif percent >= 0.001 then
		return ("%.3f%%"):format(percent)
	elseif percent >= 0.0001 then
		return ("%.4f%%"):format(percent)
	end
	return "<0.0001%"
end

-- Сообщение в чат про находку — вынесено отдельно, чтобы им пользовались и
-- мутации руды, и находка жеоды, и новый скин (см. вызовы ниже и в
-- GeodeService.lua). segments — как у AnnounceService:Broadcast.
local function announceFind(segments)
	if not Services.AnnounceService then return end
	Services.AnnounceService:Broadcast(nil, nil, segments)
end

--------------------------------------------------------------------------------
-- ФИЛЬТР "ЧТО ИЗ МУТАЦИЙ ВООБЩЕ ПОПАДАЕТ В ЧАТ"
--
-- Раньше фильтра не было вовсе: КАЖДАЯ выпавшая мутация печаталась всем.
-- При текущих шансах мутирует 43% всей руды, а шахта выдаёт кусок раз в
-- 1.2-1.7 сек — на сервере из 8 человек это несколько сообщений В СЕКУНДУ.
-- Редкая находка при этом ничем не выделялась: она тонула ровно в том же
-- потоке, что и Mossy. Вау-эффект существует только там, где сообщение
-- редкое, поэтому теперь их два порядка меньше — см. подробности и посчитанные
-- цифры в Config.Mutations.AnnounceSingleMinIndex.
--
-- ВАЖНО: фильтр влияет ТОЛЬКО на печать в чат. Сама мутация, её множитель
-- цены, визуал и запись в книгу коллекции (MutationBookService) работают
-- как работали — игрок ничего не теряет, просто сервер молчит.
--------------------------------------------------------------------------------

-- Позиция мутации в Config.Mutations.Order = её редкость (список идёт от
-- частых к редким). Отдельного поля "уровень редкости" в конфиге нет, и
-- заводить его не нужно: порядок и так единственный источник правды, на
-- который опираются и ролл, и книга, и выбор "самой редкой" в сообщении.
local mutationRarityIndex = {}
for index, id in Config.Mutations.Order do
	mutationRarityIndex[id] = index
end

-- Кулдаун ОБЩИЙ НА ВЕСЬ СЕРВЕР, а не на игрока: игрока раздражает поток
-- сообщений в чате как таковой, и неважно, восемь человек его создали или
-- один. os.clock() (а не os.time()) — нужна дробная точность, кулдаун
-- измеряется секундами.
local lastMutationAnnounceAt = -math.huge

local function shouldAnnounceMutations(mutations)
	local cfg = Config.Mutations
	local count = #mutations
	if count == 0 then return false end

	-- Самая редкая из выпавших. mutations приходит уже отсортированным по
	-- Order (MutationRoll.Roll идёт по нему), поэтому последняя = самая
	-- редкая — но полагаться на это молча нельзя: если однажды порядок
	-- ролла поменяется, фильтр начнёт врать. Считаем максимум явно.
	local rarest = 0
	for _, id in mutations do
		local index = mutationRarityIndex[id] or 0
		if index > rarest then rarest = index end
	end

	local singleMin = tonumber(cfg.AnnounceSingleMinIndex) or 0
	local comboMin = tonumber(cfg.AnnounceComboMinIndex) or 0
	local passesRarity
	if count >= 2 then
		-- Порог для СОЧЕТАНИЙ намеренно мягче одиночного: две мутации на
		-- одном куске — уже само по себе событие. Но порог всё равно есть,
		-- иначе в чат полетело бы "Mossy + Rusty", а это 1.2% всей руды.
		passesRarity = rarest >= comboMin
	else
		passesRarity = rarest >= singleMin
	end
	if not passesRarity then return false end

	-- ТОП-НАХОДКИ ПРОХОДЯТ ВСЕГДА. Celestial/Eclipsed — это то самое
	-- событие, ради которого весь механизм и нужен; проглотить его из-за
	-- того, что секундой раньше кто-то нашёл Prismatic, было бы обиднее
	-- любого спама.
	local bypass = tonumber(cfg.AnnounceBypassCooldownIndex)
	if bypass and rarest >= bypass then
		lastMutationAnnounceAt = os.clock()
		return true
	end

	-- Жёсткий потолок частоты поверх шансов: тир шахты и число игроков
	-- влияют на поток руды напрямую, и без него полный сервер на T10 снова
	-- превратил бы чат в ленту.
	local cooldown = math.max(0, tonumber(cfg.AnnounceGlobalCooldown) or 0)
	local now = os.clock()
	if now - lastMutationAnnounceAt < cooldown then
		return false
	end
	lastMutationAnnounceAt = now
	return true
end

-- miner (опционально) — игрок, чья шахта добыла кристалл: его множитель
-- ребёртов ЗАПЕКАЕТСЯ в цену. Кристалл самодостаточен: укравший получит
-- ровно эту цену, свой множитель вор не применяет.
-- luckBonus (опционально, см. MineService — копится за мини-игру "дуга")
-- — прокидывается напрямую в Config.RollOreForTier, слегка наклоняя
-- шансы этого конкретного куска к более редким слотам тира.
-- Воссоздать кусок руды из УЖЕ СУЩЕСТВУЮЩЕЙ стопки рюкзака (см.
-- InventoryService, действие "DropHeld"). В отличие от Create ничего НЕ
-- роллит: руда, вариация, мутации и цена уже определены — их надо просто
-- вернуть в мир ровно такими, какими игрок их нёс. Любой ролл здесь был
-- бы дырой в экономике: выбросил и подобрал — получил новую руду.
function CrystalService:CreateFromStack(stack)
	if type(stack) ~= "table" then return nil end
	local oreInfo = Config.OreByKey[stack.Ore]
	if not oreInfo then return nil end
	local variantInfo = Config.OreVariants[stack.Variant or 1] or Config.OreVariants[1]
	local smelted = stack.Smelted == true
	local crystal = smelted and PlaceholderFactory.OreIngot(oreInfo, variantInfo) or PlaceholderFactory.OreCrystal(oreInfo, variantInfo)

	crystal:SetAttribute("CrystalOre", oreInfo.Key)
	crystal:SetAttribute("CrystalName", oreInfo.DisplayName .. (smelted and " Ingot" or ""))
	if smelted then crystal:SetAttribute("Smelted", true) end
	-- v9: пещера-источник и честный шанс едут вместе с куском (и в слиток).
	if tonumber(stack.Tier) then
		crystal:SetAttribute("CrystalTier", tonumber(stack.Tier))
		crystal:SetAttribute("CrystalRarity", Config.OreRarityFor and Config.OreRarityFor(oreInfo.Key, tonumber(stack.Tier)) or oreInfo.Rarity)
	end
	if tonumber(stack.Chance) then
		crystal:SetAttribute("CrystalChance", tonumber(stack.Chance))
		crystal:SetAttribute("CrystalDisplayChance", tonumber(stack.Chance))
	end
	crystal:SetAttribute("CrystalVariant", variantInfo.Variant)
	crystal:SetAttribute("CrystalValue", stack.Value or oreInfo.CrystalValue)
	crystal:SetAttribute("CrystalPoints", oreInfo.Points)

	-- Мутации переносим как ЯРЛЫК и как визуал, но НЕ пересчитываем цену:
	-- множитель уже запечён в stack.Value при первом появлении куска.
	local mutations = stack.Mutations or ""
	if mutations ~= "" then
		crystal:SetAttribute("Mutations", mutations)
		local root = CrystalUtil.GetRoot(crystal)
		local ids = string.split(mutations, ",")
		local partGroups = MutationVisuals.SplitPartsForMutations(crystal, #ids)
		for index, id in ids do
			if Config.Mutations[id] then
				pcall(function()
					MutationVisuals.Apply(crystal, id, root, partGroups and partGroups[index])
				end)
			end
		end
	end

	-- chanceFraction = 0, а НЕ nil.
	--
	-- ЗДЕСЬ БЫЛА ПРИЧИНА "выброшенная руда просто исчезает". attachPriceGui
	-- первым делом делает `chanceFraction > 0`, а сравнение nil с числом —
	-- это ошибка. Она улетала в pcall обработчика "DropHeld", кусок не
	-- создавался, а стопка к тому моменту УЖЕ была снята с рюкзака: руда
	-- пропадала, ничего не вылетало и подбирать было нечего.
	-- Ноль означает "шанс не показываем" — ровно то, что и нужно: кусок
	-- уже был раскрыт когда-то, печатать "1/N" повторно незачем.
	attachPriceGui(
		crystal,
		-- Слиток подписывается "IRON INGOT" — копия записи руды с другим
		-- именем, сама запись в Config не трогается.
		smelted and setmetatable({ DisplayName = oreInfo.DisplayName .. " Ingot" }, { __index = oreInfo }) or oreInfo,
		stack.Value or oreInfo.CrystalValue,
		tonumber(stack.Chance) or 0,
		mutations ~= "" and mutations or nil,
		variantInfo
	)
	-- v9: GIGANTIC сохраняется (×1.5 и значок) — и у руды, и у слитка.
	if stack.Gigantic == true and Services and Services.MineService and Services.MineService._markAsGigantic then
		pcall(Services.MineService._markAsGigantic, Services.MineService, crystal)
		local badge = crystal:FindFirstChild("GiganticBadge", true)
		local priceGui = crystal:FindFirstChild("PriceGui", true)
		if badge and priceGui then badge.Enabled = priceGui.Enabled end
	end
	return crystal
end

-- v17: кусок МУСОРА (Config.Junk). Без мутаций, вариаций, книги
-- коллекции; цена — фиксированная копеечная (или 0).
function CrystalService:CreateJunk(junkInfo, tier)
	if type(junkInfo) == "string" then junkInfo = Config.JunkByKey[junkInfo] end
	if not junkInfo then return nil end
	local crystal = PlaceholderFactory.Junk(junkInfo)
	local value = math.max(0, math.floor(tonumber(junkInfo.Value) or 0))
	local chance = tonumber(junkInfo.Chance) or 0
	crystal:SetAttribute("Junk", true)
	crystal:SetAttribute("CrystalOre", junkInfo.Key)
	crystal:SetAttribute("CrystalName", junkInfo.DisplayName)
	crystal:SetAttribute("CrystalTier", tonumber(tier) or 1)
	crystal:SetAttribute("CrystalRarity", "Common")
	crystal:SetAttribute("CrystalVariant", 1)
	crystal:SetAttribute("CrystalValue", value)
	crystal:SetAttribute("CrystalPoints", 0)
	crystal:SetAttribute("CrystalChance", chance)
	crystal:SetAttribute("CrystalDisplayChance", chance)
	attachPriceGui(crystal, junkInfo, value, 0, nil, nil)
	return crystal
end

-- source (v17): "Mine" (по умолчанию) | "Boulder" — откуда кусок; от этого
-- зависит шанс мусора (Config.Junk.Chance).
function CrystalService:Create(tier, miner, luckBonus, source)
	local junk = Config.RollJunk and Config.RollJunk(source or "Mine")
	if junk then
		local junkCrystal = self:CreateJunk(junk, tier)
		if junkCrystal then return junkCrystal end
	end
	-- РУДА v2: тир задаёт ПУЛ из 4 возможных руд (см. Config.MineTiers[tier]
	-- .Ores/.Weights), конкретная руда роллится здесь, на каждый кусок
	-- отдельно — так и выпадает "IRON 1/20" на одном камне и "COAL 1/2" на
	-- соседнем из той же кучи.
	-- v8: перк Luck + бафф Luck скина — наклон ролла к редким слотам пещеры.
	if miner and Services.PrestigeService then
		local ok, stat = pcall(Services.PrestigeService.Stat, Services.PrestigeService, miner, "Luck")
		if ok and stat and stat ~= 0 then luckBonus = math.max(0, (luckBonus or 0) + stat) end
	end
	-- v10: удача за Robux (пасс 2x Luck, зелье, удача сервера).
	local paidOreLuck, paidMutation = 0, 1
	if Services.MonetizationService and Services.MonetizationService.GetLuckBoost then
		local okLuck, oreBoost, mutationBoost = pcall(Services.MonetizationService.GetLuckBoost, Services.MonetizationService, miner)
		if okLuck then paidOreLuck, paidMutation = oreBoost or 0, mutationBoost or 1 end
	end
	if paidOreLuck > 0 then luckBonus = math.max(0, (luckBonus or 0) + paidOreLuck) end
	local oreInfo, oreChance, _oreSlot, oreRarity = Config.RollOreForTier(tier, luckBonus)
	-- ВАРИАЦИЯ (1/2/3, см. Config.OreVariants) — роллится отдельно поверх
	-- уже выпавшей руды и домножает цену. Шанс перемножается с шансом
	-- самой руды, чтобы надпись "1/N" над камнем оставалась честной.
	local variantInfo, variantChance = Config.RollOreVariant()
	-- v18: амулет MIDAS TOUCH — вариация на ступень выше (I→II→III).
	if miner and source ~= "Paid" and Services.BuffService and Services.BuffService:GetBonus(miner, "MidasTouch") > 0 then
		local upgraded = Config.OreVariants[math.min(#Config.OreVariants, variantInfo.Variant + 1)]
		if upgraded and upgraded ~= variantInfo then
			local total = 0
			for _, v in Config.OreVariants do total += v.Weight end
			variantInfo = upgraded
			variantChance = upgraded.Weight / math.max(1, total)
		end
	end
	oreChance = oreChance * variantChance
	local crystal = PlaceholderFactory.OreCrystal(oreInfo, variantInfo)
	local value = math.floor(oreInfo.CrystalValue * variantInfo.ValueMultiplier + 0.5)
	if miner then
		value = math.floor(value * Services.DataService:GetCrystalMultiplier(miner) + 0.5)
	end

	local points = oreInfo.Points

	-- Мутации роллятся ПРЯМО ТУТ — то есть в момент, когда кусок руды
	-- реально появляется и летит в тележку (см. MineService), без всякого
	-- предупреждения заранее. Множитель запекается в CrystalValue сразу же,
	-- поэтому дальше кристалл остаётся самодостаточным как обычно — вор,
	-- укравший мутировавшую руду, получит ровно её (уже повышенную) цену.
	local luck = luckFor(miner)
	local weatherBoosts = Services.WeatherService and Services.WeatherService:GetActiveBoosts()
	if miner and Services.BaseDecorService then weatherBoosts = Services.BaseDecorService:MergeMutationBoosts(miner, weatherBoosts) end
	-- v8: перк Mutations + бафф Mutation скина — множитель шанса мутаций.
	local mutationPotion = nil
	if miner and Services.PrestigeService then
		local ok, stat = pcall(Services.PrestigeService.Stat, Services.PrestigeService, miner, "Mutation")
		if ok and stat and stat ~= 0 then mutationPotion = math.max(0.1, 1 + stat) end
	end
	if paidMutation ~= 1 then mutationPotion = (mutationPotion or 1) * paidMutation end
	local mutations, mutationMultiplier = MutationRoll.Roll(luck, weatherBoosts, mutationPotion)
	-- v18: амулет MUTATION MAGNET — следующие N руд гарантированно с мутацией
	-- (мутация роллится обычным броском с сильным перекосом, редкость честная).
	if miner and source ~= "Paid" and #mutations == 0 and Services.BuffService
		and Services.BuffService:GetBonus(miner, "MutationMagnet") >= 1 then
		-- Одна мутация, выбранная по её реальному шансу (частые — чаще).
		local total, weights = 0, {}
		for _, id in Config.Mutations.Order do
			local info = Config.Mutations[id]
			if info and (tonumber(info.Chance) or 0) > 0 and not info.EventOnly then
				local ok, w = pcall(MutationRoll.EffectiveChance, id, luck, weatherBoosts and weatherBoosts[id])
				w = ok and tonumber(w) or tonumber(info.Chance) or 0
				weights[id] = w
				total += w
			end
		end
		local pick = math.random() * total
		local chosen = Config.Mutations.Order[1]
		for _, id in Config.Mutations.Order do
			local w = weights[id]
			if w then
				pick -= w
				if pick <= 0 then chosen = id break end
			end
		end
		mutations, mutationMultiplier = MutationRoll.ForceInclude(mutations, mutationMultiplier, chosen)
		Services.BuffService:Consume(miner, "MutationMagnet", 1)
	end
	-- ТОЛЬКО во время Solar Eclipse (см. Config.WeatherEvents.SolarEclipse.
	-- ForcedMutationChance) — часть руды получает Eclipsed НАПРЯМУЮ, минуя
	-- обычный бросок, чтобы самый редкий ивент ощущался кардинально иначе.
	local forcedMutation = Services.WeatherService and Services.WeatherService:GetForcedMutation()
	if forcedMutation then
		mutations, mutationMultiplier = MutationRoll.ForceInclude(mutations, mutationMultiplier, forcedMutation)
	end
	-- v4: святилища на базе — каждая N-я руда с гарантированной мутацией.
	if miner and Services.BaseDecorService and Services.BaseDecorService.TickShrines then
		local ok, due = pcall(Services.BaseDecorService.TickShrines, Services.BaseDecorService, miner)
		if ok and due then
			for _, mutationId in due do
				mutations, mutationMultiplier = MutationRoll.ForceInclude(mutations, mutationMultiplier, mutationId)
			end
		end
	end
	if mutationMultiplier > 1 then
		value = math.floor(value * mutationMultiplier + 0.5)
	end

	crystal:SetAttribute("CrystalTier", tier)
	crystal:SetAttribute("CrystalOre", oreInfo.Key)
	crystal:SetAttribute("CrystalRarity", oreRarity or Config.OreRarityFor(oreInfo.Key, tier)) -- v3: редкость по слоту пещеры
	crystal:SetAttribute("CrystalName", oreInfo.DisplayName)
	crystal:SetAttribute("CrystalVariant", variantInfo.Variant) -- 1/2/3, см. Config.OreVariants
	crystal:SetAttribute("CrystalValue", value)
	crystal:SetAttribute("CrystalPoints", points) -- отдельная шкала для комбо тележки, см. CartService
	crystal:SetAttribute("CrystalChance", oreChance) -- честный шанс ЭТОЙ руды в этом тире (без мутации)

	local displayChance = oreChance -- дальше домножим на шанс мутации, если она есть
	local mutationLabel = nil

	if #mutations > 0 then
		-- Раньше список мутаций использовался ТОЛЬКО для одноразового
		-- анонса в чат — на самом инстансе кристалла нигде не сохранялся.
		-- Нужен клиенту для превью руды в тележке (см. OrePreviewHud.client.lua).
		crystal:SetAttribute("Mutations", table.concat(mutations, ","))
		local root = CrystalUtil.GetRoot(crystal)
		local names = {}
		local combinedChance = 1
		-- Чередование деталей между мутациями при комбинации нескольких —
		-- по прямому запросу, см. MutationVisuals.SplitPartsForMutations.
		local partGroups = MutationVisuals.SplitPartsForMutations(crystal, #mutations)
		for index, id in mutations do
			MutationVisuals.Apply(crystal, id, root, partGroups and partGroups[index])
			table.insert(names, Config.Mutations[id].DisplayName)
			-- ФАКТИЧЕСКИЙ шанс этого игрока, а не базовый из конфига: шансы
			-- редких мутаций растут от ребёртов и тира шахты, и печатать в
			-- чат базовое число значило бы врать игроку. Раскрытие реальных
			-- вероятностей — требование Roblox к Random Item Generator'ам.
			combinedChance *= MutationRoll.EffectiveChance(id, luck, weatherBoosts and weatherBoosts[id])
			if miner and Services.MutationBookService then
				Services.MutationBookService:RecordFound(miner, tier, id)
			end
		end
		displayChance = oreChance * combinedChance -- ТЗ: "IRON SOAKED 1/60" — итоговый (руда × мутация) шанс
		mutationLabel = table.concat(names, " ")
		if miner and shouldAnnounceMutations(mutations) then
			-- "{name} found a rare Frozen/Molten/Radiant ore! (5% chance)"
			-- Если сработало НЕСКОЛЬКО мутаций сразу (они умеют
			-- комбинироваться) — множественное число и ОБЩИЙ (перемноженный)
			-- шанс именно этой комбинации: "found rare Frozen + Molten ores!
			-- (0.10% combined chance)". Раскрытие шансов — по политике
			-- Roblox о честных Random Item Generator'ах (та же логика, что и
			-- у панели "i" с шансами жеод).
			local rarestId = mutations[#mutations] -- Order идёт от частой к редкой
			local multiple = #mutations > 1
			announceFind({
				{ Text = ("%s found %s "):format(miner.DisplayName, multiple and "rare" or "a rare"), Color = Color3.new(1, 1, 1) },
				{ Text = table.concat(names, " + "), Color = Config.Mutations[rarestId].Color },
				{ Text = (" %s ("):format(multiple and "ores" or "ore"), Color = Color3.new(1, 1, 1) },
				{ Text = formatChancePercent(combinedChance) .. (multiple and " combined chance" or " chance"), Color = Color3.fromRGB(200, 200, 200) },
				{ Text = ")!", Color = Color3.new(1, 1, 1) },
			})
			-- ЛИЧНОЕ УВЕДОМЛЕНИЕ (Toast, opts.Viewport) — ДОПОЛНИТЕЛЬНО к
			-- чату: тот же принцип, что и у редкой находки на валуне (см.
			-- RockService.lua) — 3D-превью ИМЕННО этой руды+мутации вместо
			-- плоской иконки. Это основной источник мутаций в игре (обычная
			-- добыча), поэтому именно здесь отсутствие личного тоста
			-- было заметнее всего.
			if Services.NotifyService then
				Services.NotifyService:Show(miner, ("RARE DROP: <font color=\"#%s\">%s</font> <font color=\"#6FE3FF\">%s</font> (<font color=\"#FFD966\">%s</font>)"):format(
					colorHex(Config.Mutations[rarestId].Color), table.concat(names, " + "),
					Config.MineTiers[tier].DisplayName, formatChancePercent(combinedChance)
				), {
					Icon = "Crystal",
					Duration = 3.5,
					RichText = true,
					Viewport = { Tier = tier, MutationId = rarestId },
				})
			end
		end
	end

	crystal:SetAttribute("CrystalDisplayChance", displayChance) -- v9: переживает рюкзак/печь
	-- v9: книга коллекции по руде (+ маленькая награда за новое).
	if miner and Services.MutationBookService and Services.MutationBookService.RecordOre then
		pcall(Services.MutationBookService.RecordOre, Services.MutationBookService, miner, oreInfo.Key, mutations)
	end
	local priceLabel = attachPriceGui(crystal, oreInfo, value, displayChance, mutationLabel, variantInfo)
	if #mutations > 0 then
		MutationVisuals.StyleOverheadLabel(priceLabel, mutations, oreInfo.Color)
	end

	return crystal
end

--------------------------------------------------------------------------------
-- Выбитый кристалл: физически разлетается по дороге (см. CombatService для
-- гарантированно-наружной траектории). Первые Config.Crystal.PickupLockoutTime
-- секунд его может подобрать КТО УГОДНО, КРОМЕ владельца — микро-стан (см.
-- CombatService) и так не даёт жертве сразу среагировать, а этот таймер
-- следит, чтобы она не подобрала свою же выбитую руду вперёд вора, даже если
-- как-то умудрилась дотянуться. После истечения таймера всё как обычно:
--   • ВЛАДЕЛЕЦ (ownerUserId — тот, у кого выбили/кто уронил при смерти) —
--     летит в тележку, если есть место, иначе в руки.
--   • ЛЮБОЙ ДРУГОЙ игрок — ТОЛЬКО в руки (см. HandCarryService), даже если
--     у него пустая тележка рядом: грабёж чужой добычи ограничен вместимостью
--     рук по тиру кирки, а не тем, насколько велика его собственная тележка.
--
-- noCollideWith (опционально) — источник выброса: Model тележки или Model
-- персонажа жертвы (лучше целиком, не один Part — см. ниже почему), либо
-- одиночный BasePart. На время KnockoutEjectNoCollideTime коллизия с ним
-- отключена, чтобы кристалл гарантированно улетал НАРУЖУ, а не
-- застревал/пружинил в его геометрии, пока источник ещё в движении.
--------------------------------------------------------------------------------
-- justDroppedByUserId (опционально) — см. фикс "выбил руду из вора — вор не
-- должен тут же поднять её обратно": ЭТО СОВСЕМ НЕ ТО ЖЕ САМОЕ, что
-- ownerUserId выше. ownerUserId — кто ИЗНАЧАЛЬНО намайнил/владеет куском (и
-- кому этот кусок в итоге должен вернуться), а justDroppedByUserId — кто
-- ФИЗИЧЕСКИ только что нёс его в руках/на спине и был ударом лишён его
-- ПРЯМО СЕЙЧАС. Если вор украл чужую руду и ему же выбили её ударом,
-- ownerUserId — это ОКРАДЕННЫЙ (не вор), поэтому старая проверка
-- isOwnerPickup для вора всегда была false — и вор мог тут же подобрать
-- собственное только что выбитое обратно, сводя удар на нет. Теперь
-- ЭТОТ КОНКРЕТНЫЙ игрок (кто уронил) отдельно заблокирован на тот же
-- Config.Crystal.PickupLockoutTime, независимо от того, "владелец" он или нет.
function CrystalService:MakeLoose(crystal, velocity, ownerUserId, noCollideWith, justDroppedByUserId)
	local root = CrystalUtil.GetRoot(crystal)

	crystal:SetAttribute("Loose", true)
	if ownerUserId ~= nil then
		crystal:SetAttribute("OwnerUserId", ownerUserId)
	end
	crystal:SetAttribute("JustDroppedByUserId", justDroppedByUserId)
	root.Anchored = false
	root.CanCollide = true
	root.Massless = false
	crystal.Parent = looseFolder
	if crystal:GetAttribute("IsGeode") ~= true then
		-- Шанс 0 = строку "1/N" не печатаем: кусок уже был раскрыт раньше,
		-- его ролл тут неизвестен (тот же приём, что в CreateFromStack).
		attachPriceGui(
			crystal,
			resolveOreInfo(crystal),
			crystal:GetAttribute("CrystalValue") or 0,
			0,
			mutationLabelFor(crystal),
			Config.OreVariants[crystal:GetAttribute("CrystalVariant") or 1] or Config.OreVariants[1]
		)
	end
	if velocity then
		root.AssemblyLinearVelocity = velocity
	end

	if noCollideWith then
		-- Если передали целую Model (тележка/персонаж жертвы) — отключаем
		-- коллизию со ВСЕМИ её физическими частями, не только с одной: иначе
		-- кристалл всё ещё мог зацепиться за стенку/колесо тележки, приваренные
		-- к Root отдельными Part'ами, и застрять точно так же, как раньше.
		local parts = {}
		if noCollideWith:IsA("Model") then
			for _, descendant in noCollideWith:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(parts, descendant)
				end
			end
		else
			table.insert(parts, noCollideWith)
		end
		for _, part in parts do
			local ejectNoCollide = Instance.new("NoCollisionConstraint")
			ejectNoCollide.Part0 = root
			ejectNoCollide.Part1 = part
			ejectNoCollide.Parent = root
			game:GetService("Debris"):AddItem(ejectNoCollide, Config.Combat.KnockoutEjectNoCollideTime)
		end
	end

	-- Визуальный таймер блокировки — белое свечение, гаснущее ровно к концу
	-- PickupLockoutTime, чтобы было понятно, ПОЧЕМУ подбор владельцем пока
	-- не срабатывает (вору эта подсказка ни на что не влияет — он и так может
	-- забрать сразу).
	local lockHighlight = Instance.new("Highlight")
	local geodeType = crystal:GetAttribute("GeodeType")
	local geodeInfo = geodeType and Config.Geodes.Types[geodeType]
	lockHighlight.FillColor = geodeInfo and geodeInfo.Color or Color3.new(1, 1, 1)
	lockHighlight.FillTransparency = 0.5
	lockHighlight.OutlineColor = geodeInfo and geodeInfo.Color or Color3.new(1, 1, 1)
	lockHighlight.OutlineTransparency = 0.2
	lockHighlight.Parent = crystal
	TweenService:Create(
		lockHighlight,
		TweenInfo.new(Config.Crystal.PickupLockoutTime, Enum.EasingStyle.Linear),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	):Play()
	game:GetService("Debris"):AddItem(lockHighlight, Config.Crystal.PickupLockoutTime + 0.1)

	local lockedUntil = os.clock() + Config.Crystal.PickupLockoutTime
	local picked = false
	local connection
	connection = root.Touched:Connect(function(hit)
		if picked then
			return
		end
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player and character and character.Parent then
			player = Players:GetPlayerFromCharacter(character.Parent) -- аксессуары
		end
		if not player then
			return
		end

		local owner = crystal:GetAttribute("OwnerUserId")
		local isOwnerPickup = (owner == nil) or (owner == player.UserId)

		local justDroppedBy = crystal:GetAttribute("JustDroppedByUserId")
		if justDroppedBy ~= nil and justDroppedBy == player.UserId and os.clock() < lockedUntil then
			return -- он же только что уронил этот кусок ударом — не подбирать мгновенно обратно (см. комментарий у MakeLoose)
		end

		if isOwnerPickup and os.clock() < lockedUntil then
			return -- владельцу нужно сначала прийти в себя — вор может забрать сразу, он и так уже забрал
		end

		if crystal:GetAttribute("IsGeode") == true then
			local cart = Services.CartService:GetCartWithGeodeSpaceFor(player, root.Position)
			if cart then
				picked = true
				connection:Disconnect()
				Sfx.play(isOwnerPickup and "CrystalPickup" or "CrystalStolenPickup", root)
				self:_flyToCart(crystal, cart)
				return
			end
			-- БАГ, КОТОРЫЙ ЧИНИМ: раньше, если рядом не было тележки с местом
			-- (типичный случай для вора — он гоняет за чужими тележками пешком,
			-- налегке, своей рядом обычно нет), функция просто ничего не
			-- делала и return'илась — жеоду нельзя было поднять ВООБЩЕ, она
			-- просто лежала нетронутой, пока не сгорит по таймеру
			-- (Config.Crystal.LooseLifetime). У обычной руды в этом случае
			-- есть запасной вариант — в руки (HandCarryService, см. ниже).
			-- Жеоды в руки не помещаются (иначе их пришлось бы ещё и продавать
			-- оттуда, а BankService/HandCarryService этого не умеют), поэтому
			-- запасной вариант — сразу зачислить жеоду в постоянное хранилище
			-- подобравшего, как будто он уже донёс её до банка. Работает и для
			-- вора без тележки, и для владельца, если его собственная тележка
			-- далеко/занята. Приваривается на спину на пару секунд (см.
			-- _flyToBack) — иначе зачисление незаметно и выглядит так, будто
			-- ничего не подобралось.
			local geodeType = crystal:GetAttribute("GeodeType") or "Stone"
			picked = true
			connection:Disconnect()
			Sfx.play(isOwnerPickup and "CrystalPickup" or "CrystalStolenPickup", root)
			self:_flyToBack(player, crystal, geodeType)
			return -- geodes never enter the ordinary hand inventory
		end

		if isOwnerPickup and Services.InventoryService then
			-- Собственная руда всегда сначала попадает в Backpack. Тележка
			-- получает её позже отдельным односторонним переносом у игрока.
			if self:PickupToInventory(player, crystal) then
				picked = true
				connection:Disconnect()
				return
			end
		end

		-- Не владелец (грабит чужое) ИЛИ владельцу некуда в тележку —
		-- пробуем в руки, если есть место по тиру кирки (см. HandCarryService).
		-- Не грабится в PvP, зато без комбо-множителя при продаже.
		if Services.HandCarryService and Services.HandCarryService:HasSpace(player) then
			picked = true
			connection:Disconnect()
			self:_flyToHand(player, crystal, owner ~= nil and owner ~= player.UserId)
			return
		end

		-- Некуда класть вообще — остаётся лежать для других (или сгорит по таймеру)
	end)

	task.delay(Config.Crystal.LooseLifetime, function()
		if not picked and crystal.Parent == looseFolder then
			connection:Disconnect()
			crystal:Destroy()
		end
	end)
end

-- Подбор в Backpack с двухфазным полётом: короткий подъём над игроком,
-- затем красивое втягивание в грудь. Атрибут защищает от двойного подбора
-- одновременно через Touched и InventoryService.HeartBeat.
local homeToTarget
function CrystalService:PickupToInventory(player, crystal)
	if not (player and crystal and crystal.Parent) then return false end
	if crystal:GetAttribute("InventoryPickupInProgress") == true then return false end

	-- ЗАРАНЕЕ проверяем, влезет ли ИМЕННО этот кусок. Раньше проверка была
	-- только "есть ли в рюкзаке хоть какое-то место" (HasAnyRoom): стопка
	-- угля с местом есть → летит железо → AddOre отказывает (слоты
	-- заняты). Кусок успевал сжаться до 10% и уйти в fail → MakeLoose,
	-- а тот падал с ошибкой attachPriceGui. Итог — "маленькие кубики",
	-- которые больше никто не подбирает.
	local inventory = Services.InventoryService
	if inventory and inventory.CanAddOre and not inventory:CanAddOre(
		player,
		crystal:GetAttribute("CrystalOre"),
		crystal:GetAttribute("CrystalVariant") or 1,
		crystal:GetAttribute("Mutations"),
		crystal:GetAttribute("Smelted") == true
	) then
		return false
	end

	crystal:SetAttribute("InventoryPickupInProgress", true)

	local root = CrystalUtil.GetRoot(crystal)
	if not root then
		crystal:SetAttribute("InventoryPickupInProgress", nil)
		return false
	end

	-- v14.3: ПОДБОР КАК У МОНЕТОК. Раньше сервер сам тащил кусок к игроку
	-- покадрово (на пинге это дёргалось). Теперь руда засчитывается СРАЗУ,
	-- а красивый полёт — подпрыгнуть, на миг зависнуть, магнитом в игрока,
	-- искры и «дзынь» по нарастающей — рисует клиент (OrePickupFx.client).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if player.Parent ~= Players or not humanoid or humanoid.Health <= 0 then
		crystal:SetAttribute("InventoryPickupInProgress", nil)
		return false
	end
	local added = inventory:AddOre(
		player,
		crystal:GetAttribute("CrystalOre"),
		crystal:GetAttribute("CrystalVariant") or 1,
		crystal:GetAttribute("Mutations"),
		crystal:GetAttribute("CrystalValue") or 0,
		1,
		crystal:GetAttribute("Smelted") == true,
		inventory.ExtraFromCrystal and inventory.ExtraFromCrystal(crystal) or nil
	)
	if not added then
		crystal:SetAttribute("InventoryPickupInProgress", nil)
		crystal:SetAttribute("PickupRetryAt", os.clock() + 2)
		return false
	end
	self:_sendPickupFx(player, crystal, root)
	crystal:Destroy()
	return true
end

-- Копия куска для клиентского эффекта подбора. Кладём её на пару секунд в
-- ReplicatedStorage (оттуда клиент её клонирует и сразу «роняет» в
-- полёт), а сам кусок в мире уничтожается сразу.
local pickupFxFolder = nil
local pickupFxRemote = nil
local pickupFxSerial = 0
function CrystalService:_ensurePickupFx()
	if pickupFxRemote then return end
	pickupFxRemote = ReplicatedStorage.Shared:FindFirstChild("OrePickupFx") or Instance.new("RemoteEvent")
	pickupFxRemote.Name = "OrePickupFx"
	pickupFxRemote.Parent = ReplicatedStorage.Shared
	pickupFxFolder = ReplicatedStorage:FindFirstChild("OrePickupFxTemplates") or Instance.new("Folder")
	pickupFxFolder.Name = "OrePickupFxTemplates"
	pickupFxFolder.Parent = ReplicatedStorage
end

function CrystalService:_sendPickupFx(player, crystal, root)
	self:_ensurePickupFx()
	local position = root.Position
	local ok, copy = pcall(function()
		-- Клонируется только то, у чего Archivable = true — включаем всем
		-- частям, иначе копия приходила бы пустой.
		crystal.Archivable = true
		for _, d in crystal:GetDescendants() do d.Archivable = true end
		return crystal:Clone()
	end)
	if ok and copy then
		for _, d in copy:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt")
				or d:IsA("Sound") or d:IsA("BodyMover") or d:IsA("Constraint") and not d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
		pickupFxSerial += 1
		copy.Name = ("Fx%d_%d"):format(player.UserId, pickupFxSerial)
		copy.Parent = pickupFxFolder
		Debris:AddItem(copy, 4)
		pickupFxRemote:FireClient(player, copy, position, copy.Name)
	else
		pickupFxRemote:FireClient(player, nil, position, nil)
	end
end

-- root двигается физически (Position/CFrame/Touched/Anchored), а любые
-- декоративные части внутри Model (партиклы, доп. геометрия) едут вместе с
-- ним автоматически, если приварены к нему через WeldConstraint — тот же
-- принцип, каким Wall/Wheel едут с Root у тележки (см. PlaceholderFactory.Cart).
-- ИСПРАВЛЕНИЕ БАГА "не долетает до двигающегося игрока": раньше все три
-- функции ниже (_flyToHand/_flyToBack/_flyToCart) считали целевую точку
-- ОДИН РАЗ в начале и твинили к ней как к неподвижной — игрок, шевельнувшийся
-- за время полёта (0.35 сек, Config.Crystal.PickupTweenTime — на обычной
-- скорости ходьбы это несколько стадов, больше на спринте), видел, как
-- предмет прилетает туда, где он СТОЯЛ, а не туда, где он СЕЙЧАС. Здесь
-- цель пересчитывается КАЖДЫЙ КАДР (getTarget вызывается заново), поэтому
-- полёт всегда "доводит" до актуальной позиции, даже если она движется.
-- Кривая интерполяции — та же самая Quad-Out, что была у TweenInfo,
-- просто применяется вручную кадр за кадром: eased = 1 - (1-alpha)^2.
homeToTarget = function(root, duration, getTarget, onArrive)
	local startPosition = root.Position
	local startTime = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not root.Parent then
			connection:Disconnect()
			return
		end
		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 2
		local target = getTarget() or root.Position
		root.Position = startPosition:Lerp(target, eased)
		if alpha >= 1 then
			connection:Disconnect()
			onArrive()
		end
	end)
end

function CrystalService:_flyToHand(player, crystal, fromOtherPlayer)
	local root = CrystalUtil.GetRoot(crystal)
	root.Anchored = true
	root.CanCollide = false
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local function getTarget()
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		return hrp and (hrp.Position + Vector3.new(0, 1.2, 0.9))
	end
	homeToTarget(root, Config.Crystal.PickupTweenTime, getTarget, function()
		if player.Parent ~= Players or player.Character ~= character or not humanoid or humanoid.Health <= 0 then
			if crystal.Parent then
				root.Anchored = false
				self:MakeLoose(crystal, nil)
			end
		elseif Services.HandCarryService:TryPickup(player, crystal) then
			Sfx.play(fromOtherPlayer and "CrystalStolenPickup" or "CrystalPickup", root)
			crystal:Destroy() -- дальше это просто запись в стеше, не физический объект
			if fromOtherPlayer and Services.NotifyService then Services.NotifyService:ShowBankTrailOnce(player, "Hand") end
		else
			-- пока летел — место в руках закончилось (race): остаётся лежать на земле
			root.Anchored = false
			self:MakeLoose(crystal, nil)
		end
	end)
end

-- Как _flyToHand, только жеода в итоге зачисляется НАПРЯМУЮ в постоянное
-- хранилище (GeodeService:AddGeodeDirectly — нет тележки, класть некуда), а
-- не в стеш рук. После зачисления модель не пропадает — привариваем её на
-- спину, чтобы было видно, ЧТО именно подобрали (иначе само зачисление в
-- хранилище снаружи никак не видно); живёт, пока жив этот персонаж.
function CrystalService:_flyToBack(player, crystal, geodeType)
	local root = CrystalUtil.GetRoot(crystal)
	root.Anchored = true
	root.CanCollide = false
	local character = player.Character
	local function getTarget()
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		return hrp and (hrp.Position + Vector3.new(0, 1.4, 0.9))
	end
	local transactionId = HttpService:GenerateGUID(false)
	homeToTarget(root, Config.Crystal.PickupTweenTime, getTarget, function()
		-- НАЙДЕННАЯ ПРИЧИНА "прилетела и тут же открепилась, пропала":
		-- AddGeodeDirectly использует ОБЩУЮ экономическую блокировку игрока
		-- (EconomyTransactionLocked — та же, что у продажи в банке, апгрейдов,
		-- ребёрта и т.п.). Если в момент подбора игрок как раз завершает
		-- какую-то ДРУГУЮ экономическую операцию, блокировка ещё держится,
		-- зачисление проваливается с первой попытки — а раньше код тут же
		-- сдавался и ронял жеоду обратно физикой на землю. Обычно такая
		-- блокировка держится доли секунды, так что вместо немедленной
		-- капитуляции пробуем ещё несколько раз с небольшой паузой.
		local credited = false
		local pendingSave = false
		for _ = 1, 20 do
			if not player.Parent then
				break -- игрок вышел, пока ждали — дальше зачислять/крепить некому
			end
			-- ВНИМАНИЕ, ТОНКОЕ МЕСТО: раньше тут стояло
			--   local granted, status = Services.GeodeService and Services.GeodeService:AddGeodeDirectly(...)
			-- и это МОЛЧА ломало защиту от дюпа ниже. В Lua/Luau оператор
			-- `and` обрезает множественный возврат до ОДНОГО значения, так
			-- что `status` был всегда nil, а проверка `status == "Pending"`
			-- не срабатывала никогда. Последствие ровно то, от которого
			-- защищается ветка `if pendingSave` ниже: при подвисшем
			-- сохранении жеода уже лежит в профиле, но код уходил в
			-- MakeLoose и ронял на землю ВТОРУЮ физическую копию.
			-- Раскладываем на явные строки — множественный возврат доходит целиком.
			local granted, status = false, nil
			if Services.GeodeService then
				granted, status = Services.GeodeService:AddGeodeDirectly(player, geodeType, transactionId)
			end
			if granted then
				credited = true
				break
			end
			if status == "Pending" then pendingSave = true end
			task.wait(0.15)
		end
		if not credited then
			if pendingSave then
				-- The idempotent mutation is already in the profile and may be
				-- committed by autosave; never restore a second physical copy.
				crystal:Destroy()
				return
			end
			-- Не получилось зачислить даже за ~3 секунды попыток (сбой
			-- сохранения или что-то более серьёзное) — оставляем лежать на
			-- земле, как раньше делала вся функция при отсутствии тележки,
			-- вместо того чтобы тихо потерять жеоду.
			root.Anchored = false
			self:MakeLoose(crystal, nil)
			return
		end
		-- Зачислена по-настоящему — дальше чисто декоративный довесок.
		local liveCharacter = player.Character
		local liveHrp = liveCharacter and liveCharacter:FindFirstChild("HumanoidRootPart")
		if not liveHrp then
			crystal:Destroy()
			return
		end
		local backCFrame = liveHrp.CFrame * CFrame.new(0, 0.2, 0.8)
		crystal:PivotTo(backCFrame * CFrame.Angles(0, math.rad(90), 0))
		local parts = crystal:GetDescendants()
		if crystal:IsA("BasePart") then
			table.insert(parts, crystal)
		end
		for _, descendant in parts do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = liveHrp
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
		crystal.Parent = liveCharacter
		local list = stolenGeodeVisuals[player.UserId]
		if not list then
			list = {}
			stolenGeodeVisuals[player.UserId] = list
		end
		table.insert(list, crystal)
		-- НЕ ставим Debris-таймер: жеода уже реально зачислена в хранилище
		-- (see выше), так что дальше это чисто декоративная деталь на спине.
		-- Раньше она сама пропадала через фиксированное время — выглядело как
		-- баг ("она пропадает"), хотя по факту всё зачислилось честно. Теперь
		-- висит на спине, пока не сработает ОДНО из двух:
		--  1) игрок дойдёт до банка (см. ClearStolenGeodeVisuals, вызывается
		--     из BankService:Start для любого игрока в зоне продажи — это и
		--     есть "сдал" в понимании игрока);
		--  2) персонаж умрёт/респавнится — модель приварена прямо внутрь
		--     character, поэтому уничтожится вместе с ним автоматически,
		--     просто саму запись в таблице тоже чистим (см. ниже).
	end)
end

-- Убирает с игрока ВСЕ жеоды, приваренные на спину после подбора без тележки
-- (см. _flyToBack) — вызывается BankService, когда игрок физически доходит
-- до банка: жеода в хранилище уже давно зачислена, так что тут только
-- декоративная уборка "визуально сдал".
function CrystalService:ClearStolenGeodeVisuals(player)
	clearStolenVisuals(player)
end

function CrystalService:_flyToCart(crystal, cart)
	local root = CrystalUtil.GetRoot(crystal)
	root.Anchored = true
	root.CanCollide = false
	local function getTarget()
		return cart.Root and (cart.Root.Position + Vector3.new(0, 3, 0))
	end
	homeToTarget(root, Config.Crystal.PickupTweenTime, getTarget, function()
		root.Anchored = false
		local added
		if crystal:GetAttribute("IsGeode") == true then
			added = Services.CartService:AddGeode(cart, crystal, true)
		else
			added = Services.CartService:AddCrystal(cart, crystal, true)
		end
		if not added then
			-- пока летел — место закончилось: остаётся лежать на земле
			self:MakeLoose(crystal, nil)
		end
	end)
end

return CrystalService
