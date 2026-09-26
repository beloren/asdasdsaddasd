--------------------------------------------------------------------------------
-- CartService
-- Тележка — центральный объект игры.
--   • Пока в руках — физически ДОГОНЯЕТ игрока через AlignPosition/
--     AlignOrientation (см. Attach ниже), а не жёстко приварена — небольшой
--     реальный люфт при резких движениях, без бокового заноса.
--   • Коллизия с игроками отключена ПОСТОЯННО и ГЛОБАЛЬНО через отдельную
--     коллизионную группу PhysicsService (CART_COLLISION_GROUP не
--     сталкивается с PLAYER_COLLISION_GROUP, см. константы ниже) — тележка
--     никогда не толкает ни держателя, ни случайных игроков, ни в руках,
--     ни стоя на земле. При этом с миром (землёй/стенами, группа "Default")
--     тележка сталкивается как обычно — иначе ей нечем держаться на
--     рельефе, и она проваливается под карту на резких движениях (прыжок).
--   • Игрок поворачивается ОГРАНИЧЕННО, пока держит полную тележку —
--     AutoRotate выключен, целевой поворот считается вручную (ограниченная
--     угловая скорость от заполнения), но применяется к персонажу через
--     AlignOrientation-констрейнт, а не прямой записью CFrame — так поворот
--     не конфликтует с внутренней физикой Humanoid и не дёргается при
--     репликации другим игрокам. Тележка, будучи жёстко приваренной,
--     автоматически следует за уже ограниченным поворотом.
--   • "Тяжесть" гружёной тележки передаётся через замедление WalkSpeed
--     (applySpeed), а не через физическую инерцию самой тележки.
--   • Прыгать с тележкой в руках можно, но с откатом (см. JumpConn в
--     Attach/Detach ниже, Config.Cart.JumpCooldown) — не полный запрет,
--     иначе прыжок при жёсткой Motor6D-сборке с игроком выглядел криво.
--   • Кристаллы визуально складываются в сетку слотов — богатство видно без UI.
--   • После смерти держателя остаётся на земле; взять может ЛЮБОЙ игрок (угон).
--   • Вырвать тележку из рук живого игрока нельзя — только убить.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
Config.Cart = Config.Cart or {}
Config.Cart.ButtonOffset = Config.Cart.ButtonOffset or Vector3.new(5, -0.5, 0)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local CartPlacement = require(ReplicatedStorage.Shared.CartPlacement)

local CartService = {}

-- КОЛЛИЗИОННЫЕ ГРУППЫ ("физика в разных мирах" для тележки и игроков).
-- Раньше держатель "не проваливался" сквозь свою тележку тем, что у ВСЕХ
-- частей тележки на время удержания просто выключался CanCollide целиком —
-- то есть тележка переставала сталкиваться и с игроками, И С МИРОМ
-- ОДНОВРЕМЕННО. Это и было причиной "тележка падает сквозь землю на
-- прыжке": она физическая (Anchored=false, её держит на месте только
-- упругая AlignPosition-привязка к игроку), а столкновений с реальной
-- землёй/рельефом у неё не было вообще — на резком скачке HRP вверх
-- (прыжок) тележка на мгновение проседала ниже привязки и, не встречая
-- пола, проваливалась под карту, пока констрейнт её не утаскивал следом.
--
-- Правильное решение — не трогать CanCollide вообще, а развести тележку и
-- игроков по РАЗНЫМ коллизионным группам: тележка (CART_COLLISION_GROUP)
-- продолжает нормально сталкиваться с миром (землёй/стенами/рельефом —
-- они всегда в группе "Default") — падать сквозь пол ей больше физически
-- нечем, а вот с группой ИГРОКОВ (PLAYER_COLLISION_GROUP) столкновения
-- между этими двумя группами выключены раз и навсегда на уровне
-- PhysicsService — тележка никогда не толкает и не расталкивает ни
-- держателя, ни случайных прохожих, ни во время переноски, ни стоя на
-- земле. Никакого точечного NoCollisionConstraint/сохранения-восстановления
-- CanCollide на время Attach/Detach больше не нужно — правило действует
-- постоянно и одинаково для всех тележек и всех игроков.
local CART_COLLISION_GROUP = "Cart"
local PLAYER_COLLISION_GROUP = "CartCarrier"

local function ensureCollisionGroups()
	-- pcall — RegisterCollisionGroup кидает ошибку, если группа уже
	-- зарегистрирована (например, повторный старт сервиса в Studio при
	-- live-редактировании) — тогда просто ничего не делаем, группа и так есть.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CART_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end)
	-- Обе группы остаются коллидируемыми со всем ОСТАЛЬНЫМ (в частности,
	-- с "Default", где живут Terrain/бейсплейт/стены участков) — выключаем
	-- столкновение ТОЛЬКО друг с другом.
	PhysicsService:CollisionGroupSetCollidable(CART_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
end

-- Переносит персонажа игрока в PLAYER_COLLISION_GROUP — целиком, включая
-- части, которые реплицируются/подгружаются позже (аксессуары, R15-доп.
-- детали) — поэтому подписываемся на DescendantAdded, а не проходим по
-- дереву один раз.
local function applyPlayerCollisionGroup(character)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end)
end

local function hookPlayerCollisionGroup(player)
	player.CharacterAdded:Connect(function(character)
		applyPlayerCollisionGroup(character)
		-- НОВОЕ. Тот же класс бага, что и застревание на спавне: на респавне
		-- никто не применял к свежему персонажу рассчитанную скорость, и он
		-- получал стандартные роблоксовые WalkSpeed = 16 вместо
		-- Config.Cart.BaseWalkSpeed = 14 (она намеренно снижена) — вместе с
		-- потерей бонуса за ребёрты и, что важнее, вместе с потерей
		-- замедления от руды в руках и от тележки. То есть после каждой
		-- смерти игрок бегал не с той скоростью, пока что-нибудь случайно не
		-- дёргало пересчёт.
		-- Ждём кадр: Humanoid в момент CharacterAdded уже есть, но
		-- RefreshSpeed читает и сопутствующее состояние (руки/тележка).
		task.defer(function()
			if player.Parent and player.Character == character then
				local ok, err = pcall(function()
					CartService:RefreshSpeed(player)
				end)
				if not ok then
					warn("[CartService] Не удалось применить скорость на респавне для", player.Name, ":", err)
				end
			end
		end)
	end)
	if player.Character then
		applyPlayerCollisionGroup(player.Character)
	end
end

local Services = nil
local carts = {}       -- [Model] = data
local ownerIndex = {}  -- [userId] = data (тележка, созданная для игрока)
local holderIndex = {} -- [userId] = data (тележка в руках игрока)
-- УСТАРЕЛО (v12): кулдаун кнопки "Заспавить тележку". Самой кнопки больше
-- нет (тележка ставится из упаковки), поле оставлено пустым, чтобы не
-- ломать возможные внешние ссылки; ни один путь кода его не читает.
local lastManualRespawn = {}

local DROP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Позиция и высота ценника — от них считается позиция комбо-карточки
-- (см. updateComboLabel), чтобы она всегда сидела вплотную НАД ценой,
-- независимо от того, какого она сейчас размера (стадии). ВАЖНО: должны
-- быть объявлены ДО updateComboLabel/findOrBuildValueGui — Lua-замыкание
-- видит только локальные переменные, объявленные ВЫШЕ по тексту файла;
-- объявление ниже места использования резолвится в nil (не в ошибку
-- компиляции, а в рантайм-краш при первом же обращении).
local VALUE_OFFSET_Y = 8
local VALUE_HEIGHT = 0.95

-- НОВОЕ (см. ТЗ "переписать систему механики сбора руды" — сбор руды с
-- земли наездом тележки). Радиус в стадах, на котором тележка "подбирает"
-- кусок руды, лежащий на земле после выброса из шахты (см. MineService:
-- _ejectOre — та же папка workspace.MineGroundOre, тот же атрибут
-- GroundOreOwner). Специально пошире габаритов тележки — иначе игрок
-- должен целиться колесом ровно в камень.
local GROUND_ORE_PICKUP_RADIUS = 7
local GROUND_ORE_FOLDER_NAME = "MineGroundOre"
local COMBO_GAP = 0.35 -- зазор между низом комбо-карточки и верхом ценника

--------------------------------------------------------------------------------
-- Слот i → CFrame относительно Root. Кристаллы растут слоями вверх:
-- полная тележка видна издалека — это и есть "интерфейс" богатства.
--------------------------------------------------------------------------------
local function slotOffset(data, index)
	local cell = Config.CartSlots.Cell
	local cols = Config.CartSlots.Cols
	local rows = Config.CartSlots.Rows
	local perLayer = cols * rows

	local layer = math.floor((index - 1) / perLayer)
	local rem = (index - 1) % perLayer
	local cx = rem % cols
	local cz = math.floor(rem / cols)

	-- Небольшой случайный разброс от идеального узла сетки — по прямому
	-- запросу ("немного ближе друг к другу или дальше, чтобы было
	-- реалистично"): без этого руда лежала идеально ровными рядами,
	-- как на конвейере, а не так, будто её действительно вывалили в
	-- тележку. ±18% ячейки — заметно на глаз, но соседние камни всё ещё
	-- не пересекаются заметно и не вылезают за борт тележки.
	local jitterRange = cell * 0.18
	local jitterX = (math.random() * 2 - 1) * jitterRange
	local jitterZ = (math.random() * 2 - 1) * jitterRange

	local x = (cx - (cols - 1) / 2) * cell + jitterX
	local z = (cz - (rows - 1) / 2) * cell + jitterZ
	local y = data.Root.Size.Y / 2 + cell / 2 + layer * cell

	-- Случайный поворот на 0/90/180/270° вокруг вертикали — чисто визуальное
	-- разнообразие (одинаковые кристаллы не лежат все строго одинаково),
	-- запекается прямо в целевой CFrame слота, поэтому фиксируется в сварке
	-- (weld.C0 = target) навсегда, а не крутится каждый раз заново.
	local spin = math.random(0, 3) * 90

	-- НАКЛОН ЛЁЖКИ. Раньше поворот был ТОЛЬКО вокруг вертикали, поэтому
	-- каждый кусок стоял идеально прямо — куча выглядела разложенной, а не
	-- сваленной. Особенно бросалось в глаза после АФК: там куски приезжают
	-- мгновенно (instant), все разом и все ровные.
	--
	-- Наклон запекается в ЦЕЛЕВОЙ CFrame слота, а значит действует на ОБА
	-- пути — и на мгновенную выдачу после АФК, и на обычный подбор руками:
	-- лежат они теперь одинаково естественно. ±14° хватает, чтобы куча
	-- читалась как наваленная, и мало, чтобы куски не протыкали друг друга
	-- и не торчали за борт.
	local tiltX = math.rad((math.random() * 2 - 1) * 14)
	local tiltZ = math.rad((math.random() * 2 - 1) * 14)
	return CFrame.new(x, y, z)
		* CFrame.Angles(0, math.rad(spin), 0)
		* CFrame.Angles(tiltX, 0, tiltZ)
end

local function updateGeodeLabel(data)
	local count = #data.Geodes
	data.Model:SetAttribute("GeodeCount", count)
end

-- Пока тележка свободна — виден кастомный промпт "Взять тележку".
-- Пока её несут — промпт ПОЛНОСТЬЮ выключен (не мигает при ходьбе);
-- отпустить можно только через экранную подсказку + клавишу (см. src/client).
local function updatePrompt(data)
	local free = data.HolderUserId == nil
	data.Prompt.Enabled = free
	data.Prompt.ActionText = "Take Cart"
	data.Prompt:SetAttribute("OwnerUserId", data.OwnerUserId)
	data.Prompt:SetAttribute("Stealable", data.Stealable == true)
end

--------------------------------------------------------------------------------
-- КОМБО-МНОЖИТЕЛЬ: зависит от % заполнения тележки НАПРЯМУЮ — начинается,
-- только когда тележка ощутимо заполнена (не с пустой/почти пустой).
-- Ценность руды (Points) работает как ускоритель: чем ценнее в среднем
-- груз, тем МЕНЬШЕГО % заполнения достаточно для того же множителя —
-- effectiveFill = rawFill × (среднийPoints / ComboReferencePoints).
--------------------------------------------------------------------------------
local function comboMultiplier(data)
	local count = #data.Crystals
	local rawFill = data.Capacity > 0 and (count / data.Capacity) or 0
	if rawFill < Config.Cart.ComboMinFill then
		return 1
	end

	local avgPoints = count > 0 and (data.PointsSum / count) or 0
	-- v3: по умолчанию комбо зависит только от заполнения (см. Config.Cart.ComboUseOreQuality).
	local qualityBoost = Config.Cart.ComboUseOreQuality == false and 1 or (avgPoints / Config.Cart.ComboReferencePoints)
	local effectiveFill = rawFill * qualityBoost

	local best = 1
	for _, step in Config.Cart.ComboThresholds do
		if effectiveFill >= step.Fill then
			best = step.Multiplier
		else
			break -- пороги отсортированы по возрастанию
		end
	end
	return best
end

-- Общая ценность добычи — видна всем над тележкой (богатый = мишень).
-- Уже умножена на ВСЕ множители, что реально применяются при продаже
-- (см. BankService:_sell — это ТА ЖЕ цепочка, 1:1): комбо-множитель
-- заполнения, cash-пассы, рефералка, бонус слайма банка. Раньше здесь
-- был только комбо-множитель — надпись над тележкой систематически
-- занижала реальную выплату для всех, у кого куплен cash-пасс или
-- прокачан слайм, показывая цифру меньше той, что реально падала на
-- баланс при продаже.
local function updateValueLabel(data)
	local multiplier = comboMultiplier(data)
	local total = data.ValueSum * multiplier

	local holder = data.HolderUserId and Players:GetPlayerByUserId(data.HolderUserId)
	if holder then
		if Services.MonetizationService then
			total *= Services.MonetizationService:GetCashMultiplier(holder) * Services.MonetizationService:GetReferralMultiplier(holder)
		end
		-- Курс биржи торговца × замороженный бонус слайма — та же цепочка,
		-- что в BankService:_sell, иначе подпись врала бы о выплате.
		if Services.MerchantService then
			total *= Services.MerchantService:GetSellMultiplier(holder)
		end
	end
	total = math.min(math.floor(total + 0.5), Config.Economy.MaxCurrency)

	data.ValueLabel.Text = "$" .. NumberFormat.abbreviate(total)
	local hasValue = data.ValueSum > 0
	data.ValueLabel.Visible = hasValue
	data.ValueGui.Enabled = hasValue -- иначе пустая золотая "таблетка" продолжала бы висеть без цифр
end

-- Курс биржи сменился (MerchantService:_newCycle) — пересчитать подписи
-- стоимости на всех тележках.
function CartService:RefreshAllValueLabels()
	for _, data in self:GetAllCarts() do
		if data.ValueLabel then
			pcall(updateValueLabel, data)
		end
	end
end

local function updateComboLabel(data)
	local multiplier = comboMultiplier(data)
	local active = multiplier > 1 -- x1 никого не впечатляет — комбо показываем, только когда реально есть чем похвастаться

	data.ComboGui.Enabled = active
	if not active then
		if data.ComboTween then
			data.ComboTween:Cancel()
			data.ComboTween = nil
		end
		data.ComboSoundPlayed = false
		return
	end

	-- Раньше было "COMBO x{число}" на карточке — теперь просто "X{число}"
	-- голым текстом, без слова COMBO и без фона.
	data.ComboLabel.Text = (multiplier == math.floor(multiplier))
		and ("X%d"):format(multiplier)
		or ("X" .. (("%.2f"):format(multiplier):gsub("0+$", ""):gsub("%.$", "")))

	-- Визуальная "лига": чем больше множитель, тем крупнее текст — видно
	-- издалека, кого стоит грабить (раньше так же рос размер карточки).
	local stage = Config.Cart.ComboVisualStages[1]
	for _, candidate in Config.Cart.ComboVisualStages do
		if multiplier >= candidate.MinMultiplier then
			stage = candidate
		else
			break
		end
	end
	data.ComboGui.Size = stage.Size
	data.ComboGui.StudsOffset = Vector3.new(0, VALUE_OFFSET_Y + VALUE_HEIGHT / 2 + COMBO_GAP + stage.Size.Y.Scale / 2, 0)

	if stage.Gradient then
		-- Только самая верхняя лига (Радуга) — крутящийся радужный градиент
		-- прямо на буквах (TextColor3 в этом режиме роли не играет, гасим в
		-- белый на всякий случай, чтобы не подсвечивал градиент оттенком).
		data.ComboGradient.Color = stage.Gradient
		data.ComboGradient.Enabled = true
		data.ComboLabel.TextColor3 = Color3.new(1, 1, 1)
		if not data.ComboTween then
			data.ComboTween = TweenService:Create(
				data.ComboGradient,
				TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
				{ Rotation = 360 }
			)
			data.ComboTween:Play()
		end
	else
		-- Остальные лиги — сплошной цвет прямо в тексте, без градиента.
		data.ComboGradient.Enabled = false
		data.ComboLabel.TextColor3 = stage.Color
		if data.ComboTween then
			data.ComboTween:Cancel()
			data.ComboTween = nil
		end
	end

	if not data.ComboSoundPlayed then
		data.ComboSoundPlayed = true
		Sfx.play("ComboActivate", data.Root)
	end
end

-- Замедление от груза: линейно от % заполнения. Макс. просадка зависит от
-- разницы тиров Тележка-Шахта — тележка круче шахты (запас прочности) везёт
-- легче, шахта круче тележки (руда не по силам) — тяжелее.
-- ЕДИНЫЙ расчёт скорости игрока: база → нагрузка тележки (если несёт,
-- см. Config.Cart) → груз в руках (если есть, см. Config.HandCarry) →
-- микро-стан (если активен, см. CombatService) полностью перебивает
-- результат нулём. Единая точка правды — вызывается и отсюда (когда
-- меняется наполнение тележки), и из HandCarryService (когда меняется
-- груз в руках), и из CombatService (когда микро-стан заканчивается),
-- чтобы эти три источника замедления не спорили друг с другом через
-- прямые перезаписи WalkSpeed.
--------------------------------------------------------------------------------
-- РАЗГОН ПРИ ДОЛГОЙ ХОДЬБЕ (см. Config.Sprint)
-- Состояние на игрока: сколько он уже двигается без остановки и какая доля
-- бонуса набрана сейчас. Считается НА СЕРВЕРЕ по humanoid.MoveDirection —
-- оно реплицируется с клиента само, отдельный ремоут не нужен, и клиент не
-- может просто "объявить" себя бегущим.
--------------------------------------------------------------------------------
local sprintState = {} -- [player] = { Moving, Idle, Factor }

local function sprintFactor(player)
	local state = sprintState[player]
	return state and state.Factor or 0
end

local function recomputeWalkSpeed(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if Services.CombatService and Services.CombatService:IsStunned(player) then
		humanoid.WalkSpeed = 0
		return
	end

	local cfg = Config.Cart
	local baseWithGamepass = cfg.BaseWalkSpeed
	if Services.MonetizationService then
		baseWithGamepass = baseWithGamepass * Services.MonetizationService:GetSpeedMultiplier(player) -- геймпасс Speed Boost — множитель к БАЗЕ, замедление от груза ниже всё равно применяется поверх
	end
	-- Мелкий бафф скорости от надетого скина кирки (см.
	-- Config.PickaxeSkinBuffs). Применяется к БАЗЕ, поэтому замедление от
	-- гружёной тележки ниже всё равно считается поверх — скин не
	-- отменяет "тяжесть" груза, просто чуть поднимает потолок.
	if Services.InventoryService then
		local okSkin, buffs = pcall(Services.InventoryService.GetSkinBuffs, Services.InventoryService, player)
		if okSkin and buffs and buffs.Speed then
			baseWithGamepass *= (1 + buffs.Speed)
		end
	end
	-- v8: перк Swift Feet.
	if Services.PrestigeService then
		baseWithGamepass *= (1 + Services.PrestigeService:PerkBonus(player, "Speed"))
	end
	local rebirthBonus = Services.DataService:GetRebirths(player) * Config.Rebirth.SpeedBonusPerRebirth
	local normalSpeed = baseWithGamepass + rebirthBonus -- обычная ходьба БЕЗ тележки — полный бонус ребёртов, как раньше

	local data = holderIndex[player.UserId]
	local speed
	if data then
		-- Скорость с тележкой ФИКСИРОВАННАЯ (см. Config.Cart.FixedCartSpeed) —
		-- НЕ зависит от заполнения тележки и от разницы тиров Cart/Mine
		-- (раньше зависела от обоих, и полная тележка у новичка резала
		-- скорость больше чем вдвое — по фидбеку это отталкивало игроков
		-- на самом старте). Геймпасс Speed Boost по-прежнему множит именно
		-- эту базу, а небольшой процент от обычной скорости ходьбы
		-- (Config.Rebirth.CartSpeedBonusPercent) даёт прокачке/ребёртам
		-- смысл и с тележкой в руках, просто без резкого замедления.
		local gamepassMultiplier = baseWithGamepass / cfg.BaseWalkSpeed
		speed = (cfg.FixedCartSpeed * gamepassMultiplier) + (normalSpeed * Config.Rebirth.CartSpeedBonusPercent)
	else
		speed = normalSpeed
	end

	if Services.HandCarryService then
		local handCount = Services.HandCarryService:GetCount(player)
		if handCount > 0 then
			local handSlowdown = math.min(handCount * Config.HandCarry.SlowdownPerItem, Config.HandCarry.MaxSlowdown)
			speed = speed * (1 - handSlowdown)
		end
	end

	-- Разгон применяется ПОСЛЕДНИМ, поверх остальных модификаторов: он
	-- ускоряет ровно ту скорость, с которой игрок сейчас идёт, включая
	-- замедление от руды в руках.
	local cfgSprint = Config.Sprint
	if cfgSprint and cfgSprint.Enabled ~= false then
		if data == nil or cfgSprint.ApplyWhileHoldingCart then
			speed = speed * (1 + (cfgSprint.SpeedBonus or 0) * sprintFactor(player))
		end
	end

	humanoid.WalkSpeed = speed
end

-- Обёртка для call-сайтов, у которых уже есть `data` тележки под рукой
-- (изменение наполнения и т.п.) — просто резолвит игрока и зовёт общий расчёт.
local function applySpeed(data)
	if data.HolderUserId == nil then
		return
	end
	local holder = Players:GetPlayerByUserId(data.HolderUserId)
	if holder then
		recomputeWalkSpeed(holder)
	end
end

-- Показывает/прячет обводку (Highlight) на модели тележки — чисто
-- декоративная, реального игрового эффекта (сама защита от урона) это не
-- касается, она считается отдельно в CombatService по атрибуту Protected.
-- VFX щита теперь висит над головой держателя, а не над тележкой — см.
-- CombatService. Цвет — золото, если у ДЕРЖАТЕЛЯ (не обязательно владельца —
-- ворованную тележку тоже может тащить владелец GoldenShield) есть геймпасс
-- GoldenShield, иначе обычный зелёный (Config.Protection.Color); проверяется
-- заново при КАЖДОМ включении — пасс, купленный посреди переноски, красится
-- сразу же, без пересоздания тележки.
local function setShieldVisible(data, visible, holder)
	if visible and holder then
		local useVip = Services.MonetizationService and Services.MonetizationService:HasGoldenShield(holder)
		data.ShieldHighlight.OutlineColor = useVip and Config.GamePasses.CartGuard.OutlineColor or Config.Protection.Color
	end
	data.ShieldHighlight.Enabled = visible
end

--------------------------------------------------------------------------------
-- АНИМАЦИЯ ПЕРЕТАСКИВАНИЯ: пока тележка в руках, подменяем штатные Idle/Walk
-- персонажа на свои (Priority.Action — перебивают дефолтную анимацию).
-- Переключение — по событию Humanoid.Running (2 состояния: стоит/идёт).
--------------------------------------------------------------------------------
local dragAnimState = {} -- [userId] = { Tracks = {Idle=,Walk=}, Current=, Connection= }

local function loadCartAnimTrack(animator, assetId)
	if not assetId or assetId == "rbxassetid://0" then
		return nil -- плейсхолдер не задан — просто не проигрываем
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = assetId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	return track
end

local function startDragAnimation(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return
	end

	local tracks = {
		Idle = loadCartAnimTrack(animator, Config.Animations.CartIdle),
		Walk = loadCartAnimTrack(animator, Config.Animations.CartWalk),
	}
	if not (tracks.Idle or tracks.Walk) then
		return -- оба ID — плейсхолдеры, играть нечего
	end

	local state = { Tracks = tracks, Current = nil }

	local function switchTo(track)
		if state.Current == track then
			return
		end
		local blend = (Config.Animations and tonumber(Config.Animations.CartBlend)) or 0.32 -- v17
		if state.Current then
			state.Current:Stop(blend)
		end
		state.Current = track
		if track then
			track:Play(blend)
		end
	end

	state.Connection = humanoid.Running:Connect(function(speed)
		if speed > 0.5 and tracks.Walk then
			switchTo(tracks.Walk)
		else
			switchTo(tracks.Idle)
		end
	end)
	switchTo(tracks.Idle) -- стартовое состояние (стоит на месте)

	dragAnimState[player.UserId] = state
end

local function stopDragAnimation(player)
	local state = dragAnimState[player.UserId]
	if not state then
		return
	end
	dragAnimState[player.UserId] = nil
	if state.Connection then
		state.Connection:Disconnect()
	end
	for _, track in state.Tracks do
		if track then
			track:Stop((Config.Animations and tonumber(Config.Animations.CartBlend)) or 0.32) -- v17
		end
	end
end

--------------------------------------------------------------------------------
-- МЕДЛЕННЫЕ ПОВОРОТЫ: чем полнее тележка, тем медленнее держатель может
-- развернуться — резко крутнуться с полной тележкой не получится. Даже у
-- пустой тележки есть небольшое "стопорное" сопротивление (MaxTurnRate
-- заметно ниже мгновенного) — ощущается, что в руках реально что-то есть.
-- AutoRotate выключен на время переноски, целевой yaw считается вручную
-- с ограниченной угловой скоростью (Config.Cart.MaxTurnRate/MinTurnRate) —
-- но применяется к персонажу НЕ прямой записью CFrame (это конфликтует с
-- внутренней физикой Humanoid и даёт дёрганое движение при репликации), а
-- через AlignOrientation-констрейнт (data.TurnAlign) — физический движок
-- сам плавно доворачивает HRP к посчитанной цели в общем солвере вместе с
-- обычным движением персонажа. Тележка приварена к HRP через Motor6D — ей
-- НЕ нужно отдельно управлять поворотом, она следует автоматически.
--------------------------------------------------------------------------------
local holderYaw = {} -- [userId] = текущий целевой yaw держателя, радианы

local function yawOf(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function setSprintVfx(data, enabled)
	if data.SprintVfxOn == enabled then
		return -- уже в нужном состоянии — не долбим .Enabled/.Playing каждый кадр без надобности
	end
	data.SprintVfxOn = enabled
	for _, particle in data.SprintParticles do
		particle.Enabled = enabled
	end
	if data.RollSound then
		if enabled then data.RollSound:Play() else data.RollSound:Stop() end
	end
end

local function limitTurning(data, dt)
	local holder = Players:GetPlayerByUserId(data.HolderUserId)
	local character = holder and holder.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not data.TurnAlign then
		setSprintVfx(data, false)
		return
	end

	local moveDirection = humanoid.MoveDirection
	local isMoving = moveDirection.Magnitude > 0.05
	setSprintVfx(data, isMoving) -- пыль сзади только пока тележку реально везут (а не просто стоят с ней)
	local currentYaw = holderYaw[data.HolderUserId] or yawOf(hrp.CFrame)

	if isMoving then
		local targetYaw = math.atan2(-moveDirection.X, -moveDirection.Z)
		local fill = math.clamp(#data.Crystals / data.Capacity, 0, 1)
		local cfg = Config.Cart
		local turnRate = cfg.MaxTurnRate - fill * (cfg.MaxTurnRate - cfg.MinTurnRate)

		local diff = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi -- в [-pi, pi]
		local maxStep = turnRate * dt
		currentYaw = currentYaw + math.clamp(diff, -maxStep, maxStep)
	end

	holderYaw[data.HolderUserId] = currentYaw
	-- Не трогаем hrp.CFrame напрямую — просто двигаем цель констрейнта,
	-- дальше её физически "дотягивает" AlignOrientation.
	data.TurnAlign.CFrame = CFrame.Angles(0, currentYaw, 0)
	-- Тележка в этот же физический шаг сама подтянется вслед за hrp — она
	-- жёстко приварена к нему через Motor6D (см. Attach), отдельного кода
	-- для её позиционирования/поворота не требуется.
end

-- Тележка остаётся физической и сталкивается с миром, но получает небольшую
-- вертикальную помощь, когда отстаёт от follow-anchor из-за низкого выступа.
-- Три пары горизонтальных лучей (лево/центр/право) отличают ступень от
-- высокой стены: препятствие должно быть внизу, а сверху путь обязан быть
-- свободен. Поэтому помощь срабатывает и при зацепе только одним колесом.
local function assistCartTraversal(data)
	local holder = Players:GetPlayerByUserId(data.HolderUserId)
	local character = holder and holder.Character
	local anchor = data.FollowAnchor
	local root = data.Root
	if not character or not anchor or not root.Parent then
		return
	end

	local toAnchor = anchor.Position - root.Position
	local horizontal = Vector3.new(toAnchor.X, 0, toAnchor.Z)
	local horizontalDistance = horizontal.Magnitude
	local now = os.clock()

	-- Ошибка между Root и follow-anchor — та же самая лишняя дистанция,
	-- которую визуально растягивают IK-руки. Если она долго остаётся большой,
	-- тележка действительно не догоняет игрока. Два небольших импульса за
	-- один эпизод помогают соскочить с края, но не позволяют ползти по башне.
	if horizontalDistance >= Config.Cart.StuckDistance then
		data.StuckSince = data.StuckSince or now
		local canBoost = now - data.StuckSince >= Config.Cart.StuckDelay
			and now >= (data.NextStuckBoost or 0)
			and (data.StuckBoostCount or 0) < Config.Cart.StuckMaxBoosts
		if canBoost then
			data.StuckBoostCount = (data.StuckBoostCount or 0) + 1
			data.NextStuckBoost = now + Config.Cart.StuckBoostCooldown
			local velocity = root.AssemblyLinearVelocity
			if velocity.Y < Config.Cart.StuckBoostVelocity then
				local deltaVelocity = Config.Cart.StuckBoostVelocity - velocity.Y
				root:ApplyImpulse(Vector3.new(0, deltaVelocity * root.AssemblyMass, 0))
			end
		end
	elseif horizontalDistance < Config.Cart.StuckDistance * 0.6 then
		data.StuckSince = nil
		data.StuckBoostCount = 0
		data.NextStuckBoost = 0
	end

	if horizontalDistance < Config.Cart.ClimbMinFollowLag then
		data.ClimbUntil = 0
		return
	end

	if now >= (data.NextClimbProbe or 0) then
		data.NextClimbProbe = now + Config.Cart.ClimbProbeInterval
		local direction = horizontal.Unit
		local probeDistance = math.min(horizontalDistance + 0.5, Config.Cart.ClimbProbeDistance)
		local bottomY = root.Position.Y - data.RootToBottom
		local centerOrigin = Vector3.new(root.Position.X, bottomY + 0.35, root.Position.Z)
		local lateral = Vector3.new(-direction.Z, 0, direction.X)
		local halfProbeWidth = math.clamp(math.max(root.Size.X, root.Size.Z) * 0.35, 0.75, 2.5)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { data.Model, character, anchor }
		params.RespectCanCollide = true
		params.CollisionGroup = CART_COLLISION_GROUP

		local climbableObstacle = false
		for _, side in { -1, 0, 1 } do
			local lowOrigin = centerOrigin + lateral * halfProbeWidth * side
			local highOrigin = lowOrigin + Vector3.new(0, Config.Cart.ClimbMaxHeight, 0)
			local lowHit = workspace:Raycast(lowOrigin, direction * probeDistance, params)
			local highHit = workspace:Raycast(highOrigin, direction * probeDistance, params)
			if lowHit and not highHit then
				climbableObstacle = true
				break
			end
		end
		local targetIsSlightlyHigher = toAnchor.Y > 0.3 and toAnchor.Y <= Config.Cart.ClimbMaxHeight + 0.5
		if climbableObstacle or targetIsSlightlyHigher then
			data.ClimbUntil = now + Config.Cart.ClimbProbeInterval * 2.5
		end
	end

	if now < (data.ClimbUntil or 0) then
		local velocity = root.AssemblyLinearVelocity
		if velocity.Y < Config.Cart.ClimbSpeed then
			local deltaVelocity = Config.Cart.ClimbSpeed - velocity.Y
			root:ApplyImpulse(Vector3.new(0, deltaVelocity * root.AssemblyMass, 0))
		end
	end
end

-- Тележка гоблина не является частью его физической сборки. Она отдельно
-- заанкорена и визуально следует за корнем гоблина серверным обновлением.
local function followGoblinCart(data)
	local carrier = data.GoblinCarrier
	local carrierRoot = carrier and carrier.Model and carrier.Model.PrimaryPart
	if not carrierRoot or not data.Model.Parent then
		return
	end
	local rootToPivot = data.Root.CFrame:ToObjectSpace(data.Model:GetPivot())
	data.Model:PivotTo(carrierRoot.CFrame * data.GoblinCarryOffset * rootToPivot)
end

--------------------------------------------------------------------------------

-- Публичная обёртка вокруг recomputeWalkSpeed (см. выше) — нужна
-- BuffService, чтобы моментально применить/снять временный бафф скорости
-- из жеод (см. ТЗ "х2 скорость"), не дожидаясь следующего естественного
-- пересчёта (взял/бросил тележку и т.п.).
function CartService:RecomputeWalkSpeed(player)
	recomputeWalkSpeed(player)
end

function CartService:Init(services)
	Services = services

	ensureCollisionGroups()
	Players.PlayerAdded:Connect(hookPlayerCollisionGroup)
	for _, player in Players:GetPlayers() do
		hookPlayerCollisionGroup(player)
	end

	-- Пока тележка в руках, ProximityPrompt полностью выключен (не мигает
	-- при ходьбе) — отпустить можно только по клавише через экранную
	-- подсказку (src/client).
	--
	-- lastDropAttempt — защита от спама (см. тот же приём в UpgradeService.lua).
	local lastDropAttempt = {}
	local dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "DropCartRequest"
	dropRemote.Parent = ReplicatedStorage.Shared
	dropRemote.OnServerEvent:Connect(function(player)
		local now = os.clock()
		local last = lastDropAttempt[player.UserId]
		if last and now - last < 0.15 then
			return
		end
		lastDropAttempt[player.UserId] = now

		local held = holderIndex[player.UserId]
		if held then
			self:Detach(held) -- сервер сам проверяет владение — клиенту нечего подделывать
		end
	end)

	--------------------------------------------------------------------------
	-- v12: ПОСТАНОВКА ТЕЛЕЖКИ ИЗ УПАКОВКИ.
	--
	-- Клиент (CartPlacement.client.lua) рисует зелёный/красный предпросмотр и
	-- присылает сюда ТОЛЬКО точку, куда целится игрок. Все решения —
	-- есть ли упаковка, не стоит ли уже тележка, годится ли место, каким
	-- боком развернуть — принимает сервер, заново, через тот же общий модуль
	-- CartPlacement, которым клиент считал превью. Подделать клиенту нечего:
	-- максимум он пришлёт "неправильную" точку и получит отказ.
	--------------------------------------------------------------------------
	local lastPlaceAttempt = {}
	local placeRemote = Instance.new("RemoteEvent")
	placeRemote.Name = "PlaceCartRequest"
	placeRemote.Parent = ReplicatedStorage.Shared
	CartService.PlaceRemote = placeRemote
	placeRemote.OnServerEvent:Connect(function(player, position)
		local now = os.clock()
		local last = lastPlaceAttempt[player.UserId]
		if last and now - last < (Config.CartPackage.PlaceCooldown or 0.6) then
			return
		end
		lastPlaceAttempt[player.UserId] = now
		if typeof(position) ~= "Vector3" then
			return
		end
		self:PlaceCartFromPackage(player, position)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPlaceAttempt[player.UserId] = nil
		lastDropAttempt[player.UserId] = nil
	end)
end

function CartService:Start()
	-- Тележка упала в бездну → пересоздать пустую на участке владельца
	-- РАЗГОН ПРИ ДОЛГОЙ ХОДЬБЕ (см. Config.Sprint и sprintFactor выше).
	-- Отдельный Heartbeat, а не общий с limitTurning: тот работает по
	-- тележкам, а этот — по игрокам, и им нужны разные наборы данных.
	if Config.Sprint and Config.Sprint.Enabled ~= false then
		local cfg = Config.Sprint
		RunService.Heartbeat:Connect(function(delta)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local state = sprintState[player]
					if not state then
						state = { Moving = 0, Idle = 0, Factor = 0 }
						sprintState[player] = state
					end

					-- Оглушение сбрасывает разгон полностью: после удара
					-- игрок должен разгоняться заново, иначе бег превращался
					-- бы в способ убежать от последствий драки без потерь.
					local stunned = Services.CombatService and Services.CombatService:IsStunned(player)
					local moving = not stunned and humanoid.MoveDirection.Magnitude > 0.1

					if moving then
						state.Idle = 0
						state.Moving += delta
					else
						state.Idle += delta
						-- Короткая заминка (упёрся в угол, прыгнул, сменил
						-- направление) разгон не сбрасывает.
						if state.Idle >= (cfg.StopGraceSeconds or 0.3) then
							state.Moving = 0
						end
					end

					-- Цель: 1, если уже набегали больше BuildUpSeconds, иначе 0.
					-- Сам множитель едет к цели за RampSeconds, а не щёлкает —
					-- резкий скачок скорости ощущается как рывок камеры.
					local target = state.Moving >= (cfg.BuildUpSeconds or 3) and 1 or 0
					local step = delta / math.max(0.05, cfg.RampSeconds or 0.8)
					local previous = state.Factor
					if state.Factor < target then
						state.Factor = math.min(target, state.Factor + step)
					elseif state.Factor > target then
						state.Factor = math.max(target, state.Factor - step)
					end

					-- WalkSpeed трогаем, только когда множитель реально
					-- изменился: recomputeWalkSpeed каждый кадр на каждого
					-- игрока — это лишняя работа на ровном месте.
					if math.abs(state.Factor - previous) > 0.001 then
						recomputeWalkSpeed(player)
					end
				else
					sprintState[player] = nil
				end
			end
		end)
	end

	-- pcall ВНУТРИ цикла, а не снаружи: это `while true` в task.spawn, и
	-- любая незакрытая ошибка убивает поток НАВСЕГДА — до конца жизни
	-- сервера упавшие в бездну тележки перестали бы восстанавливаться, молча
	-- и для всех игроков сразу. Уронить итерацию есть чем: data.Root может
	-- оказаться уже уничтоженным, а SpawnCartFor кидает assert на кривой
	-- пользовательской модели Cart_TierN (см. _buildCart).
	task.spawn(function()
		while true do
			task.wait(3)
			local ok, err = pcall(function()
				local fallen = {}
				for _, data in carts do
					if not data.PaidFillPendingSave and not data.GeodeSavePending
						and not data.GoblinStolen and data.Root.Parent and data.Root.Position.Y < -60 then
						table.insert(fallen, data)
					end
				end
				for _, data in fallen do
					local owner = Players:GetPlayerByUserId(data.OwnerUserId)
					self:_destroy(data)
					-- v12: новой тележки больше НЕ появляется само собой — игрок
					-- получает обратно упаковку и ставит её сам, там, где захочет
					-- (см. OnCartLost).
					if owner and owner.Parent then
						self:OnCartLost(owner, "fell")
					end
				end
			end)
			if not ok then
				warn("[CartService] Проход по упавшим тележкам упал (цикл продолжает работать):", err)
			end
		end
	end)

	-- Свободная тележка (никто не держит), которую не трогали дольше
	-- Config.Cart.DespawnIdleTime — уничтожается полностью, груз внутри
	-- теряется. Если это была ТЕКУЩАЯ тележка игрока — тут же спавнится
	-- пустая новая на его базе (SpawnCartFor вернёт уже существующую, если
	-- эта успела осиротеть — например, игрок сам нажал "заспавить новую",
	-- пока эту несли/бросили — тогда лишней тележки не появится).
	-- Тот же случай, что и с циклом упавших тележек выше: без pcall одна
	-- ошибка навсегда отключает уборку простаивающих тележек, и они
	-- копятся в мире до конца сессии сервера.
	task.spawn(function()
		while true do
			task.wait(5)
			local ok, err = pcall(function()
				local now = os.clock()
				local idle = {}
				for _, data in carts do
					local atOwnerBase = self:IsAtOwnerBase(data)
					if not data.PaidFillPendingSave and not data.GeodeSavePending
						and not data.GoblinStolen and data.HolderUserId == nil
						and not atOwnerBase and now - data.LastActivityTime > Config.Cart.DespawnIdleTime then
						table.insert(idle, data)
					end
				end
				for _, data in idle do
					local owner = Players:GetPlayerByUserId(data.OwnerUserId)
					self:_destroy(data)
					if owner and owner.Parent then
						self:OnCartLost(owner, "idle")
					end
				end
			end)
			if not ok then
				warn("[CartService] Проход по простаивающим тележкам упал (цикл продолжает работать):", err)
			end
		end
	end)

	-- Поворот держателя и небольшая помощь тележке на низких препятствиях.
	-- Основное следование по-прежнему выполняют AlignPosition/Orientation.
	RunService.Heartbeat:Connect(function(dt)
		for _, data in carts do
			if data.GoblinStolen then
				followGoblinCart(data)
			elseif data.HolderUserId ~= nil then
				limitTurning(data, dt)
				assistCartTraversal(data)
			end
		end
	end)

	-- НОВОЕ: подбор руды с земли наездом тележки (см. ТЗ "переделать
	-- систему механики сбора руды"). Руда, выброшенная шахтой (см.
	-- MineService:_ejectOre), лежит в workspace.MineGroundOre с атрибутами
	-- GroundOreOwner (UserId владельца участка) и Landed (true — только
	-- приземлившуюся и уже "раскрытую" руду можно подбирать, пока кусок
	-- ещё летит по дуге — трогать его нельзя). Не каждый Heartbeat — раз в
	-- GROUND_ORE_PICKUP_INTERVAL секунд достаточно для честного подбора и
	-- ощутимо дешевле при большом количестве кусков на земле разом.
	local groundOrePickupClock = 0
	RunService.Heartbeat:Connect(function(dt)
		groundOrePickupClock += dt
		if groundOrePickupClock < 0.1 then return end
		groundOrePickupClock = 0

		local folder = workspace:FindFirstChild(GROUND_ORE_FOLDER_NAME)
		if not folder then return end

		for _, data in carts do
			if data.HolderUserId ~= nil and data.Root and data.Root.Parent and #data.Crystals < data.Capacity then
				-- v14.3: пока держатель не отошёл от точки выхода из шахты
				-- (MineExitPos), руду из шахты тележкой тоже не собираем.
				local holder = Players:GetPlayerByUserId(data.HolderUserId)
				local holderJustExited = holder and holder:GetAttribute("MineExitPos") ~= nil
				for _, crystal in folder:GetChildren() do
					if #data.Crystals >= data.Capacity then break end
					if holderJustExited and crystal:GetAttribute("MineDrop") == true then continue end
					-- Те же условия готовности, что у подбора ногами (см.
					-- InventoryService): не во время катсцены (руда ещё
					-- увеличена), не пока садится к обычному размеру, не пока
					-- её уже тянет к игроку в рюкзак.
					if crystal:GetAttribute("GroundOreOwner") == data.OwnerUserId
						and crystal:GetAttribute("Landed") == true
						and crystal:GetAttribute("PickupReady") == true
						and crystal:GetAttribute("CutsceneScaled") ~= true
						and crystal:GetAttribute("ShrinkingBack") ~= true
						and crystal:GetAttribute("InventoryPickupInProgress") ~= true
						and os.clock() >= (crystal:GetAttribute("PickupRetryAt") or 0) then -- v14: лут валуна пару секунд не подбирается
						local ok, root = pcall(CrystalUtil.GetRoot, crystal)
						if ok and root and root.Parent and (root.Position - data.Root.Position).Magnitude <= GROUND_ORE_PICKUP_RADIUS then
							local dropPos = root.Position
							CartService:AddCrystal(data, crystal, false, dropPos)
						end
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- СОЗДАНИЕ
--------------------------------------------------------------------------------

-- Общая ценность добычи над тележкой — раньше тёмная капсула с золотой
-- обводкой, теперь (как и комбо-текст выше) просто голый текст без фона:
-- зелёный с чёрной обводкой. Если у модели (реальный Studio-ассет
-- Cart_TierN, не плейсхолдер) уже есть свой BillboardGui "ValueGui" с
-- TextLabel внутри — переиспользуем его как есть (шрифт/цвет/размер/фон
-- остаются авторскими), просто пишем в него актуальный текст. Иначе строим
-- плейсхолдер сами.
local function findOrBuildValueGui(root)
	local gui = root:FindFirstChild("ValueGui", true)
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
	if gui and label then
		WorldUi.Restyle(label, "Number", true)
		gui.Size = UDim2.new(3.6, 0, VALUE_HEIGHT, 0)
		return gui, label
	end
	if gui then
		warn("[CartService] Найден ValueGui, но без TextLabel внутри - пересобираю плейсхолдер:", gui:GetFullName())
		gui:Destroy() -- нашли BillboardGui, но без TextLabel внутри — пересоберём с нуля
	end

	gui = Instance.new("BillboardGui")
	gui.Name = "ValueGui"
	gui.Size = UDim2.new(3.6, 0, VALUE_HEIGHT, 0)
	gui.StudsOffset = Vector3.new(0, VALUE_OFFSET_Y, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.DistanceStep = 0 -- фиксированный размер на экране
	gui.Parent = root

	label = WorldUi.Text(nil, "Text", "Number")
	label.Name = "ValueLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(60, 220, 90)
	label.Parent = gui

	return gui, label
end

-- Комбо-множитель: раньше это была растущая карточка с градиентным фоном,
-- теперь просто голый текст "X{число}" над тележкой без фона/рамки — цвет
-- текста меняется по "лигам" (см. Config.Cart.ComboVisualStages), а самая
-- верхняя лига (Радуга) вместо сплошного цвета крутит радужный градиент
-- прямо на буквах. Тот же принцип переиспользования: если модель уже несёт
-- свой BillboardGui "ComboGui" с TextLabel и UIGradient внутри — используем
-- их как есть, иначе строим плейсхолдер.
local function findOrBuildComboGui(root)
	local gui = root:FindFirstChild("ComboGui", true)
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
	local gradient = label and (label:FindFirstChildWhichIsA("UIGradient") or (label.Parent and label.Parent:FindFirstChildWhichIsA("UIGradient")))
	if gui and label and gradient then
		return gui, label, gradient
	end
	if gui then
		warn("[CartService] Найден ComboGui, но не хватает частей (TextLabel и/или UIGradient на нём/родителе) - пересобираю плейсхолдер:", gui:GetFullName())
		gui:Destroy() -- не хватает частей — пересоберём с нуля
	end

	gui = Instance.new("BillboardGui")
	gui.Name = "ComboGui"
	gui.Size = UDim2.new(3.6, 0, 0.95, 0)
	gui.StudsOffset = Vector3.new(0, VALUE_OFFSET_Y + VALUE_HEIGHT / 2 + COMBO_GAP + 0.95 / 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400 -- дальше, чем обычные надписи (220) — это сигнал для всей карты
	gui.DistanceStep = 0 -- фиксированный размер на экране
	gui.Enabled = false
	gui.Parent = root

	label = WorldUi.Text(nil, "Text", "Number")
	label.Name = "ComboLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui

	-- Enabled=false по умолчанию — включается только на верхней "радужной"
	-- лиге (см. updateComboLabel); на остальных лигах цвет буквам задаёт
	-- обычный TextColor3 напрямую, без градиента.
	gradient = Instance.new("UIGradient")
	gradient.Enabled = false
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
		ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 0)),
		ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 170, 255)),
		ColorSequenceKeypoint.new(0.84, Color3.fromRGB(140, 0, 255)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
	})
	gradient.Parent = label

	return gui, label, gradient
end

--------------------------------------------------------------------------------
-- ВЛАДЕНИЕ ТЕЛЕЖКОЙ И УПАКОВКА (v12)
--
-- Тележка больше НЕ выдаётся при заходе и НЕ спавнится кнопкой. Есть ровно
-- три состояния, и игрок всегда находится в одном из них:
--
--   1. НЕ КУПЛЕНА (CartUnlocked = false). Тележки нет, упаковки нет.
--      Покупается у НПС прокачки за 0 (см. UpgradeService → UnlockFirstCart).
--   2. КУПЛЕНА, НЕ ПОСТАВЛЕНА. В рюкзаке лежит УПАКОВКА
--      (data.Gear[Config.CartPackage.GearKey] = 1). Взял в руки — она
--      поднимается над головой, включается предпросмотр места.
--   3. КУПЛЕНА И ПОСТАВЛЕНА. Тележка в мире (ownerIndex), упаковки нет.
--
-- ИНВАРИАНТ (_syncPackageInvariant): 2 и 3 взаимно исключают друг друга —
-- двух тележек или тележки + упаковки одновременно быть не может. Именно он
-- заменил старую кнопку "Spawn New": потерял тележку (бездна, деспавн по
-- простою) — упаковка возвращается сама.
--
-- ПОЧЕМУ УПАКОВКА ХРАНИТСЯ В data.Gear, А НЕ ОТДЕЛЬНЫМ ПОЛЕМ. Там же лежат
-- динамит и сундуки, а значит предмет БЕСПЛАТНО получает: слот в рюкзаке и
-- хотбаре, иконку, перетаскивание, сохранение в профиле и готовую цепочку
-- "клик по слоту → Equip → предмет в руках" (см. GearService/InventoryService).
-- Отдельное поле потребовало бы дублировать весь этот UI с нуля.
--
-- ТИР УПАКОВКА НЕ ХРАНИТ. Тележка собирается по ТЕКУЩЕМУ тиру игрока в
-- момент постановки — поэтому апгрейд тележки, лежащей в упаковке, не
-- требует вообще ничего делать с предметом: следующая постановка сама
-- построит новый тир (см. UpgradeOwnedCart).
--------------------------------------------------------------------------------

local function packageKey()
	return (Config.CartPackage and Config.CartPackage.GearKey) or "CartPackage"
end

local function profileOf(player)
	-- GetGeodeData отдаёт весь профиль целиком (историческое имя, см. DataService).
	return Services.DataService and Services.DataService:GetGeodeData(player) or nil
end

function CartService:IsCartUnlocked(player)
	local data = profileOf(player)
	return data ~= nil and data.CartUnlocked == true
end

function CartService:HasDeployedCart(player)
	return ownerIndex[player.UserId] ~= nil
end

function CartService:GetPackageCount(player)
	local data = profileOf(player)
	local gear = data and data.Gear
	return math.max(0, math.floor(tonumber(gear and gear[packageKey()]) or 0))
end

-- Реплицируемые атрибуты для клиента: по ним рисуется предпросмотр
-- (CartPlacement.client.lua), карточка магазина и подсказки.
function CartService:_refreshCartAttributes(player)
	if not player.Parent then return end
	player:SetAttribute("CartUnlocked", self:IsCartUnlocked(player))
	player:SetAttribute("CartPackageCount", self:GetPackageCount(player))
	player:SetAttribute("CartDeployed", self:HasDeployedCart(player))
	player:SetAttribute("CartTier", Services.DataService:GetTiers(player).Cart)
end

-- Выдать упаковку (если её ещё нет). Возвращает true, если предмет реально
-- появился. Счёт всегда 0 или 1 — вторая тележка игроку не положена.
function CartService:GrantPackage(player, reason)
	if not self:IsCartUnlocked(player) then
		return false
	end
	if self:HasDeployedCart(player) then
		return false -- тележка уже стоит в мире, упаковка была бы второй тележкой
	end
	if self:GetPackageCount(player) > 0 then
		return false
	end
	if Services.GearService then
		Services.GearService:AddGear(player, packageKey(), 1)
	else
		local data = profileOf(player)
		if not data then return false end
		data.Gear = data.Gear or {}
		data.Gear[packageKey()] = 1
	end
	self:_refreshCartAttributes(player)
	if Services.NotifyService and reason ~= "silent" then
		local text = reason == "upgrade" and "📦 New cart package - place it anywhere!"
			or reason == "unlock" and "📦 Cart package! Take it in hand and place your cart."
			or "📦 Your cart package is back - place it again!"
		Services.NotifyService:Show(player, text, { Icon = "Cart" })
	end
	return true
end

function CartService:ConsumePackage(player)
	if self:GetPackageCount(player) <= 0 then
		return false
	end
	if Services.GearService then
		Services.GearService:AddGear(player, packageKey(), -1)
		-- AddGear сам снимает предмет с руки, когда счёт дошёл до нуля.
	else
		local data = profileOf(player)
		if data and data.Gear then data.Gear[packageKey()] = 0 end
	end
	player:SetAttribute("HeldCartPackage", nil)
	self:_refreshCartAttributes(player)
	return true
end

-- Первая (бесплатная) покупка тележки — зовётся из UpgradeService.
function CartService:UnlockFirstCart(player)
	local data = profileOf(player)
	if not data then return false end
	if data.CartUnlocked == true then
		return false
	end
	data.CartUnlocked = true
	self:_refreshCartAttributes(player)
	self:GrantPackage(player, "unlock")
	if Services.TutorialService then
		pcall(function() Services.TutorialService:SetFlag(player, "CartUnlocked", true) end)
	end
	task.spawn(function() Services.DataService:SaveProfile(player) end)
	return true
end

-- Тележка исчезла НЕ по воле игрока (упала в бездну, сгорела по таймеру
-- простоя) — возвращаем упаковку. Задержка нужна, чтобы это не выглядело
-- как мгновенная телепортация тележки обратно и чтобы игрок успел понять,
-- что именно произошло.
function CartService:OnCartLost(player, reason)
	if not (player and player.Parent) then return end
	if not self:IsCartUnlocked(player) then return end
	self:_refreshCartAttributes(player)
	local delay = tonumber(Config.CartPackage.RestoreDelay) or 8
	task.delay(delay, function()
		if not player.Parent then return end
		-- За это время игрок мог поставить/поднять другую тележку — тогда
		-- возврат уже не нужен (инвариант).
		if self:HasDeployedCart(player) then return end
		self:GrantPackage(player, reason == "upgrade" and "upgrade" or "restore")
	end)
end

-- Приводит игрока к инварианту: куплена тележка → ровно одно из
-- "стоит в мире" / "лежит упаковкой". Зовётся на заходе и после любой
-- потери/постановки.
function CartService:_syncPackageInvariant(player)
	if not self:IsCartUnlocked(player) then
		self:_refreshCartAttributes(player)
		return
	end
	if self:HasDeployedCart(player) then
		if self:GetPackageCount(player) > 0 and Services.GearService then
			Services.GearService:AddGear(player, packageKey(), -self:GetPackageCount(player))
		end
	elseif self:GetPackageCount(player) < 1 then
		self:GrantPackage(player, "silent")
	end
	self:_refreshCartAttributes(player)
end

-- Зовётся из Main вместо прежнего SpawnCartFor.
--
-- МИГРАЦИЯ СТАРЫХ ПРОФИЛЕЙ. До v12 тележка была у всех и всегда, поля
-- CartUnlocked в сейве не существовало — после обновления такой игрок
-- остался бы без тележки и был бы вынужден "покупать" её заново. Поэтому
-- любой профиль, в котором есть хоть какой-то прогресс (купленный апгрейд,
-- ребёрт, пройденный гайд, заметное время в игре), считается уже владеющим
-- тележкой. Реально новый игрок (всё по нулям) проходит нормальный путь:
-- купить за 0 → получить упаковку.
function CartService:SetupPlayer(player)
	local data = profileOf(player)
	if not data then return end
	-- Игрок ВНУТРИ обучения v7 мигрировать не должен: он получает
	-- тележку на шаге GetCart. Раньше условие PlayTimeSeconds > 120 молча
	-- выдавало упаковку новичку, перезашедшему посреди пролога, — и шаг
	-- «возьми тележку у торговца» вёл к торговцу, у которого её уже нет.
	local inTutorial = player:GetAttribute("NeedsTutorial") == true
	if data.CartUnlocked ~= true and not inTutorial then
		local hadProgress = (tonumber(data.CartIndex) or 0) > 0
			or (tonumber(data.MineIndex) or 0) > 0
			or (tonumber(data.PickaxeIndex) or 0) > 0
			or (tonumber(data.Rebirths) or 0) > 0
			or (tonumber(data.TutorialVersion) or 0) > 0
			or (tonumber(data.PlayTimeSeconds) or 0) > 120
		if hadProgress then
			data.CartUnlocked = true
		end
	end
	self:_syncPackageInvariant(player)
end

--------------------------------------------------------------------------------
-- ПОСТАНОВКА ИЗ УПАКОВКИ
--------------------------------------------------------------------------------

-- "НАДУВАНИЕ": тележка появляется крошечной и резко раздувается до полного
-- размера с перелётом. Пока идёт анимация, модель заанкорена (иначе
-- физика начала бы её толкать в промежуточных размерах), ценник/комбо и
-- промпт выключены — их показываем уже готовой тележке.
--
-- Почему не TweenService: масштаб модели — это не свойство инстанса, а
-- метод Model:ScaleTo, твинить его напрямую нечем. Шаг руками по кадрам
-- Heartbeat — ровно то же самое, но без лишней обвязки; анимация разовая
-- и короткая (~0.4 сек), на производительность не влияет.
-- ОСЕДАНИЕ НА НЕРОВНОЙ ЗЕМЛЕ.
--
-- Тележка ставится НЕ впритык к земле, а с зазором (Config.CartPackage
-- .GroundGap) — иначе на любой кочке колесо оказывалось бы утоплено в
-- геометрии, и место приходилось бы запрещать. Зазор решает это: тележка
-- просто падает последние сантиметры сама.
--
-- Единственный побочный эффект — на склоне или ступеньке падающую тележку
-- может завалить набок. Поэтому на время падения к ней цепляется временный
-- AlignOrientation, который держит ВЕРТИКАЛЬ (поворот вокруг Y свободен:
-- тележка сохраняет ту сторону, которой её поставили лицом к игроку) и
-- снимается через Settle.Seconds. Дальше она живёт обычной физикой.
function CartService:_settleUpright(data)
	local settle = (Config.CartPackage and Config.CartPackage.Settle) or {}
	local seconds = tonumber(settle.Seconds) or 1.6
	local root = data and data.Root
	if seconds <= 0 or not (root and root.Parent) then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "SettleAttachment"
	attachment.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "SettleAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.Responsiveness = tonumber(settle.Responsiveness) or 35
	align.MaxTorque = math.huge
	-- Цель — текущий разворот тележки без наклонов: только рыскание.
	local _, yaw = root.CFrame:ToEulerAnglesYXZ()
	align.CFrame = CFrame.Angles(0, yaw, 0)
	align.Parent = root

	task.delay(seconds, function()
		if align.Parent then align:Destroy() end
		if attachment.Parent then attachment:Destroy() end
	end)
end

function CartService:_playInflate(data, onComplete)
	local cfg = Config.CartPackage.Inflate or {}
	local startScale = math.clamp(tonumber(cfg.StartScale) or 0.12, 0.01, 0.9)
	local duration = math.max(0.05, tonumber(cfg.Duration) or 0.42)
	local overshoot = math.max(1, tonumber(cfg.Overshoot) or 1.12)
	local settle = math.max(0, tonumber(cfg.SettleDuration) or 0.16)

	local model = data.Model
	if not (model and model.Parent) then return end

	local restore = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			restore[descendant] = descendant.Anchored
			descendant.Anchored = true
		end
	end
	local prompt = data.Prompt
	local promptWasEnabled = prompt and prompt.Enabled
	if prompt then prompt.Enabled = false end
	local valueWasEnabled = data.ValueGui and data.ValueGui.Enabled
	local comboWasEnabled = data.ComboGui and data.ComboGui.Enabled
	if data.ValueGui then data.ValueGui.Enabled = false end
	if data.ComboGui then data.ComboGui.Enabled = false end

	local pivot = model:GetPivot()
	local baseScale = model:GetScale()

	local function setScale(factor)
		if not model.Parent then return false end
		local ok = pcall(function()
			model:ScaleTo(baseScale * factor)
			-- ScaleTo масштабирует относительно пивота, но пивот при этом
			-- может уехать на доли стада из-за округлений — держим тележку
			-- ровно там, где её поставили.
			model:PivotTo(pivot)
		end)
		return ok
	end

	if not setScale(startScale) then
		for part, anchored in restore do
			if part.Parent then part.Anchored = anchored end
		end
		return
	end

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration and model.Parent do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			local t = math.clamp(elapsed / duration, 0, 1)
			-- Ease-out: быстро в начале, мягко в конце — коробка именно
			-- "лопается" в тележку, а не плавно вырастает.
			local eased = 1 - (1 - t) ^ 3
			setScale(startScale + (overshoot - startScale) * eased)
		end
		-- Перелёт оседает обратно в честную единицу.
		local settleElapsed = 0
		while settleElapsed < settle and model.Parent do
			local dt = RunService.Heartbeat:Wait()
			settleElapsed += dt
			local t = math.clamp(settleElapsed / settle, 0, 1)
			setScale(overshoot + (1 - overshoot) * t)
		end
		setScale(1)

		for part, anchored in restore do
			if part.Parent then part.Anchored = anchored end
		end
		-- Тележку отпустили в воздухе (Config.CartPackage.GroundGap) — даём
		-- ей сесть, не завалившись набок на неровности.
		self:_settleUpright(data)
		if prompt and prompt.Parent then prompt.Enabled = promptWasEnabled ~= false end
		if data.ValueGui and data.ValueGui.Parent then data.ValueGui.Enabled = valueWasEnabled ~= false end
		if data.ComboGui and data.ComboGui.Parent then data.ComboGui.Enabled = comboWasEnabled == true end
		if data.Root and data.Root.Parent then
			pcall(function() data.Root:SetNetworkOwnershipAuto() end)
		end
		-- Всё, что кладёт в тележку ГРУЗ, обязано ждать конца анимации:
		-- слоты кристаллов считаются от размера Root (см. AddCrystal), а
		-- во время надувания он временно меньше настоящего.
		if onComplete then
			task.spawn(onComplete)
		end
	end)
end

-- Главная точка входа постановки. position — куда целился игрок (пришла с
-- клиента, ей самой по себе НЕ доверяем: всё пересчитывается заново).
function CartService:PlaceCartFromPackage(player, position)
	if not self:IsCartUnlocked(player) then
		return false, "No cart yet"
	end
	if self:GetPackageCount(player) <= 0 then
		return false, "No package"
	end
	if self:HasDeployedCart(player) then
		-- Инвариант нарушить нельзя: упаковка и тележка одновременно
		-- существовать не должны. Если это всё-таки случилось — чиним.
		self:_syncPackageInvariant(player)
		return false, "You already have a cart"
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (hrp and humanoid and humanoid.Health > 0) then
		return false, "No character"
	end

	-- Модель строим СРАЗУ, но пока не в workspace: проверке нужны её
	-- настоящие габариты и маркер FacingPoint (у пользовательских моделей
	-- Cart_TierN они какие угодно), а не средние числа из конфига.
	local tier = Services.DataService:GetTiers(player).Cart
	local probe = PlaceholderFactory.Cart(tier)
	local probeRoot = probe:FindFirstChild("Root") or probe.PrimaryPart
	if not probeRoot then
		probe:Destroy()
		warn(("[CartService] У модели Cart_Tier%d нет детали 'Root' - поставить тележку нельзя."):format(tier))
		return false, "Broken cart model"
	end
	probe.PrimaryPart = probeRoot

	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	local ok, reason, placement = CartPlacement.Validate({
		Position = position,
		PlayerPosition = hrp.Position,
		Model = probe,
		Root = probeRoot,
		Pad = plot and plot.Pad or nil,
		IgnoreList = CartPlacement.DefaultIgnoreList({ probe }),
	})
	probe:Destroy()

	if not ok or not placement then
		if Services.NotifyService then
			Services.NotifyService:Show(player, reason or "Can't place the cart here", { Icon = "Cart" })
		end
		return false, reason
	end

	local built, data = pcall(function()
		return self:_buildCart(player, { CFrame = placement })
	end)
	if not built or not data then
		warn(("[CartService] Не удалось поставить тележку для %s: %s"):format(player.Name, tostring(data)))
		return false, "Cart build failed"
	end

	self:ConsumePackage(player)
	self:_refreshCartAttributes(player)
	Sfx.play("CartDrop", data.Root)

	self:_playInflate(data, function()
		-- v12: офлайн-руда не могла высыпаться на заходе — тележки тогда
		-- ещё не существовало. Она ждала именно этого момента и падает в
		-- уже раздувшуюся тележку (см. ReturnScreenService).
		if Services.ReturnScreenService and Services.ReturnScreenService.ApplyPendingOfflineFill then
			pcall(Services.ReturnScreenService.ApplyPendingOfflineFill, Services.ReturnScreenService, player, data)
		end
	end)
	-- Шаг обучения «получи тележку» закрывается именно ПОСТАНОВКОЙ, а не
	-- покупкой: между ними лежит вся механика упаковки и превью, ради
	-- которой шаг и существует. Купить и не поставить — значит не понять
	-- её совсем.
	if Services.TutorialService then
		pcall(function() Services.TutorialService:SetFlag(player, "CartDeployed", true) end)
	end
	return true
end

--------------------------------------------------------------------------------

-- Возвращает существующую тележку игрока или строит новую. options —
-- необязательная таблица { CFrame = куда поставить, Inflate = анимация }.
-- Без options тележка встаёт на парковку участка, как раньше (этим путём
-- пользуются апгрейд и ребёрт, которым место уже известно).
function CartService:SpawnCartFor(player, options)
	local existing = ownerIndex[player.UserId]
	if existing then
		return existing
	end
	return self:_buildCart(player, options)
end

-- Всегда строит НОВУЮ тележку для игрока, даже если у него уже есть
-- активная. Старая удаляется СРАЗУ, если она не украдена (свободна или в
-- руках самого владельца) — груз в ней в этом случае теряется. Если её
-- несёт ЧУЖОЙ игрок (украдена) — не трогаем вообще: просто перестаёт быть
-- "текущей" (ownerIndex переуказывается на новую) и рано или поздно сама
-- сгорит по таймеру простоя (см. Start), когда вор её бросит и не тронет.
function CartService:ForceNewCart(player, options)
	local existing = ownerIndex[player.UserId]
	if existing and (existing.PaidFillPendingSave or existing.GeodeSavePending) then
		return existing -- оплаченный груз ещё фиксируется в DataStore; не даём уничтожить его
	end
	if existing then
		local stolen = existing.GoblinStolen
			or (existing.HolderUserId ~= nil and existing.HolderUserId ~= player.UserId)
		if not stolen then
			-- Свободна или в руках самого владельца — удаляем сразу
			-- (_destroy сам отцепит от рук, если владелец её как раз несёт).
			self:_destroy(existing)
		end
		-- Украдена (в руках чужого игрока) — НЕ трогаем вообще, см. шапку
		-- функции и README: она осиротеет (перестанет быть "текущей") и
		-- сама сгорит по таймеру простоя, когда вор её бросит и не тронет.
	end
	return self:_buildCart(player, options)
end

--------------------------------------------------------------------------------
-- ФИЗИЧЕСКАЯ КНОПКА "Заспавить тележку" УДАЛЕНА (v12).
--
-- Раньше у парковки стояла нажимная кнопка "Spawn New" с трёхминутным
-- кулдауном и отсчётом над ней (CartService:SetupRespawnButton, вызывалась
-- из PlotService). Теперь тележка появляется ТОЛЬКО из упаковки, которую
-- игрок ставит сам, где хочет, — а потерянная тележка возвращается
-- упаковкой автоматически (см. OnCartLost выше). Кнопка стала лишней
-- сущностью, дублирующей упаковку, и удалена целиком.
--
-- Маркер "CartButtonMarker" в шаблонах участков и ассет "RespawnButton"
-- больше не используются — их можно удалить из моделей, но оставленные на
-- месте они ничего не ломают (код к ним просто не обращается).
--------------------------------------------------------------------------------

function CartService:_buildCart(player, options)
	local tier = Services.DataService:GetTiers(player).Cart
	local model = PlaceholderFactory.Cart(tier)
	local root = model:FindFirstChild("Root") or model.PrimaryPart
	assert(root, "У модели тележки обязан быть PrimaryPart 'Root'")
	model.PrimaryPart = root

	-- v12: МЕСТО ПОСТАНОВКИ. options.CFrame приходит от постановки из
	-- упаковки (PlaceCartFromPackage — там место уже проверено и повёрнуто
	-- лицом к игроку). Без него — старое поведение: парковка участка. Им
	-- пользуются апгрейд на месте и ребёрт, у которых место уже известно.
	options = options or {}
	local plot = Services.PlotService:GetPlot(player)
	model:PivotTo(options.CFrame or (plot and plot.CartSpawnCFrame) or CFrame.new(0, 5, 40))

	model.Name = "Cart_" .. player.Name
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Tier", tier)
	player:SetAttribute("CartTier", tier)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("SkinBaseTransparency", descendant.Transparency)
			-- Нулевая упругость: столкновение со стеной гасится, а не
			-- отскакивает рывком (актуально, когда тележка стоит свободно
			-- или брошена — под держателем её физику ведёт не она сама).
			descendant.CustomPhysicalProperties = PhysicalProperties.new(
				0.4, -- Density
				0.3, -- Friction
				0,   -- Elasticity
				1,   -- FrictionWeight
				1    -- ElasticityWeight
			)
			-- Своя коллизионная группа (см. константы вверху файла) — тележка
			-- по-прежнему нормально сталкивается с землёй/стенами (группа
			-- "Default"), но никогда не толкает и не расталкивает игроков.
			descendant.CollisionGroup = CART_COLLISION_GROUP
			-- Корпус тележки (стены/пол/колёса) "прозрачен" для рейкаста
			-- мыши — иначе он перехватывал наведение/клик РАНЬШЕ, чем луч
			-- долетал до руды, лежащей внутри (см. OrePreviewHud.client.lua) —
			-- превью работало, только когда руда уже вылетела в открытое
			-- пространство. Куски руды добавляются ПОЗЖЕ этого цикла (см.
			-- AddCrystal) и сохраняют свой обычный CanQuery = true.
			descendant.CanQuery = false
		end
	end

	-- "AttachPoint" (высота крепления), "FacingPoint" (какая сторона
	-- обращена к игроку) и "Bottom" (старый декоративный маркер с прошлых
	-- версий) — все, если есть в модели, чисто ориентиры: сами никогда не
	-- участвуют в физике.
	for _, markerName in { "AttachPoint", "FacingPoint", "Bottom", "LeftHandGrip", "RightHandGrip" } do
		local marker = model:FindFirstChild(markerName, true)
		if marker and marker:IsA("BasePart") then
			marker.CanCollide = false
			marker.CanQuery = false
			marker.Massless = true
			if markerName == "LeftHandGrip" or markerName == "RightHandGrip" then
				marker.Anchored = false
				local weld = marker:FindFirstChild("GripMarkerWeld")
				if not weld then
					weld = Instance.new("WeldConstraint")
					weld.Name = "GripMarkerWeld"
					weld.Part0 = root
					weld.Part1 = marker
					weld.Parent = marker
				end
			end
		end
	end

	-- Высота физического низа относительно Root нужна нижнему лучу
	-- карабканья. Невидимые маркеры не учитываем; если автор положил Bottom,
	-- он остаётся самым точным источником для модели любой формы.
	local rootToBottom
	local bottomMarker = model:FindFirstChild("Bottom", true)
	if bottomMarker and bottomMarker:IsA("BasePart") then
		rootToBottom = math.max(0.1, root.Position.Y - bottomMarker.Position.Y)
	else
		local physicalBottom = math.huge
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.CanCollide then
				local cf = descendant.CFrame
				local size = descendant.Size
				local halfWorldHeight = math.abs(cf.RightVector.Y) * size.X * 0.5
					+ math.abs(cf.UpVector.Y) * size.Y * 0.5
					+ math.abs(cf.LookVector.Y) * size.Z * 0.5
				physicalBottom = math.min(physicalBottom, descendant.Position.Y - halfWorldHeight)
			end
		end
		rootToBottom = physicalBottom < math.huge and math.max(0.1, root.Position.Y - physicalBottom) or root.Size.Y * 0.5
	end

	-- ПОСАДКА НА ЗЕМЛЮ. Выше стоит model:PivotTo(plot.CartSpawnCFrame), а
	-- пивот модели — это её PrimaryPart, то есть Root. Значит на маркер
	-- парковки ставился ЦЕНТР Root, а весь корпус ниже него оказывался под
	-- маркером. Парковочная площадка лежит всего в 0.9 студа под маркером
	-- (см. PlotService: parkingPad.CFrame = CartSpawnCFrame * CFrame.new(0,
	-- -0.9, 0)), поэтому у любой модели, где rootToBottom > 0.9, низ тележки
	-- оказывался НИЖЕ уровня земли.
	--
	-- У мелких тиров rootToBottom маленький (0.3-0.6), тележку просто выталкивало
	-- физикой, и никто не замечал. У тиров 9-10 модели заметно крупнее,
	-- rootToBottom больше — тележка спавнилась утопленной в землю, солвер
	-- не мог её вытолкнуть, и она намертво застревала. Это и есть баг
	-- "тележки 9-10 тира не двигаются".
	--
	-- Чиним универсально, а не подгонкой числа под конкретный тир: ищем
	-- реальный пол лучом вниз и ставим тележку так, чтобы её физический низ
	-- стоял на полу с небольшим зазором. Формула работает для модели любого
	-- размера, в том числе для будущих тиров и кастомных ассетов.
	do
		local GROUND_CLEARANCE = 0.15
		local pivot = model:GetPivot()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		-- Модель ещё не в Workspace (model.Parent = workspace ниже), но
		-- исключаем её явно — на случай, если порядок когда-нибудь поменяют.
		params.FilterDescendantsInstances = { model }
		params.RespectCanCollide = true

		-- Луч начинаем ВЫШЕ маркера, чтобы поймать пол даже если сама точка
		-- парковки оказалась внутри геометрии.
		local origin = pivot.Position + Vector3.new(0, 12, 0)
		local hit = workspace:Raycast(origin, Vector3.new(0, -60, 0), params)

		local targetBottomY
		if hit then
			targetBottomY = hit.Position.Y + GROUND_CLEARANCE
		else
			-- Пол не найден (маркер висит над пустотой/стримингом ещё не
			-- подгрузило) — консервативный запасной вариант: считаем полом
			-- уровень парковочной площадки, то есть 0.9 студа под маркером.
			targetBottomY = pivot.Position.Y - 0.9 + GROUND_CLEARANCE
		end

		local currentBottomY = root.Position.Y - rootToBottom
		local lift = targetBottomY - currentBottomY
		-- Опускать тележку не нужно никогда: если она уже стоит выше пола,
		-- её штатно опустит физика. Поднимаем только когда она утоплена.
		if lift > 0 then
			model:PivotTo(pivot + Vector3.new(0, lift, 0))
		end
	end

	-- SPRINT VFX: партиклэмиттер уже лежит ВНУТРИ самого ассета "SprintVFX"
	-- (ReplicatedStorage/Assets) — код его не трогает и не настраивает,
	-- только ставит саму деталь под ЗАДНЮЮ часть тележки, где "зад" —
	-- сторона, ПРОТИВОПОЛОЖНАЯ той, что обращена к игроку (см. Attach ниже,
	-- там та же логика для FacingPoint). Явный маркер "SprintVFXPoint" в
	-- своей модели — высший приоритет (положи Part туда, где должен быть
	-- эффект, как с AttachPoint/FacingPoint). Без маркеров — тот же дефолт,
	-- что и у HolderSideRotation: узкая сторона (локальный -X) смотрит на
	-- игрока, значит зад — локальный +X, считается прямо от размера Root
	-- (работает для ЛЮБОЙ модели без лишней настройки).
	-- Доп. разворот на 180° по Y — ассет "смотрит" не в ту сторону как есть,
	-- без этого пыль летела вперёд, а не назад по ходу движения.
	local sprintParticles = {}
	do
		local backLocalOffset
		local vfxMarker = model:FindFirstChild("SprintVFXPoint", true)
		if vfxMarker and vfxMarker:IsA("BasePart") then
			backLocalOffset = root.CFrame:PointToObjectSpace(vfxMarker.Position)
			vfxMarker.CanCollide = false
			vfxMarker.CanQuery = false
			vfxMarker.Massless = true
		else
			local facingPoint = model:FindFirstChild("FacingPoint", true)
			if facingPoint and facingPoint:IsA("BasePart") then
				local frontOffset = root.CFrame:PointToObjectSpace(facingPoint.Position)
				backLocalOffset = Vector3.new(-frontOffset.X, -(root.Size.Y / 2), -frontOffset.Z)
			else
				backLocalOffset = Vector3.new(root.Size.X / 2 + 0.4, -(root.Size.Y / 2), 0)
			end
		end

		local sprintAsset, sprintRoot = PlaceholderFactory.SprintVFX()
		sprintRoot = sprintRoot or sprintAsset -- BasePart-ветка возвращает только одно значение (сам себе и root)

		local placement = root.CFrame * CFrame.new(backLocalOffset) * CFrame.Angles(0, math.rad(180), 0)
		if sprintAsset:IsA("Model") then
			sprintAsset.PrimaryPart = sprintRoot
			sprintAsset:PivotTo(placement)
		else
			sprintAsset.CFrame = placement
		end
		sprintAsset.Parent = model

		sprintRoot.Anchored = false
		sprintRoot.CanCollide = false
		sprintRoot.CanQuery = false
		sprintRoot.Massless = true

		local sprintWeld = Instance.new("WeldConstraint")
		sprintWeld.Part0 = root
		sprintWeld.Part1 = sprintRoot
		sprintWeld.Parent = sprintRoot

		-- Работает, только пока тележку реально везут (см. Heartbeat-цикл в
		-- Start, тот же, что и ограничение поворота) — выключен по умолчанию.
		for _, descendant in sprintAsset:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
				table.insert(sprintParticles, descendant)
			end
		end
	end

	-- Зелёная обводка (Highlight) прямо на модели тележки, видна, только
	-- пока ДЕРЖАТЕЛЬ защищён (Config.Protection/CombatService). Сам VFX
	-- щита теперь висит НАД ГОЛОВОЙ ДЕРЖАТЕЛЯ, а не над тележкой — см.
	-- CombatService (там же и точно такая же обводка на персонаже).
	local cartHighlight = Instance.new("Highlight")
	cartHighlight.Name = "ProtectionHighlight"
	cartHighlight.FillTransparency = 1 -- только контур, без подсветки объёма
	cartHighlight.OutlineColor = Config.Protection.Color
	cartHighlight.OutlineTransparency = 0
	cartHighlight.Enabled = false
	cartHighlight.Adornee = model
	cartHighlight.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = ""
	prompt.ActionText = "GRAB CART"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = Config.Cart.PickupHoldDuration
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.ClickablePrompt = true -- можно кликнуть прямо по тележке мышью/тапом, не только держать E
	prompt.Style = Enum.ProximityPromptStyle.Custom -- свой вид рисует src/client (LocalScript)
	-- По прямому запросу — первое приближение к своей тележке рисуется
	-- ЗАМЕТНЕЕ (падает сверху), клиент сам определяет "это первый раз"
	-- через атрибут NeedsTutorial/CarryingCart и возвращает обычный вид
	-- сразу после первого взятия.
	prompt:SetAttribute("PromptKind", "CartGrab")
	prompt.Parent = root

	local valueGui, valueLabel = findOrBuildValueGui(root)
	local comboGui, comboLabel, comboGradient = findOrBuildComboGui(root)
	local obsoleteGeodeGui = root:FindFirstChild("GeodeGui", true)
	if obsoleteGeodeGui then obsoleteGeodeGui:Destroy() end

	local data = {
		Model = model,
		Root = root,
		OwnerUserId = player.UserId,
		Tier = tier,
		-- v8: + перк Cart Space.
		Capacity = Config.CartTiers[tier].Capacity + (Services.PrestigeService and math.floor(Services.PrestigeService:PerkBonus(player, "CartSpace")) or 0),
		Crystals = {},
		Geodes = {},
		-- Гарантированная жеода в первой тележке новичка. Раньше слот
		-- роллился в диапазоне Config.Tutorial.RequiredCartLoad — поля,
		-- которое существовало только ради шага "жди 12 капель" из
		-- прежнего гайда. Капель больше нет, шага тоже (см.
		-- Config.Tutorial.Steps), поэтому отсчитываем от РЕАЛЬНОЙ
		-- вместимости тележки: смысл тот же ("где-то в первой партии"),
		-- но число больше не может разойтись с самой тележкой.
		TutorialGeodeSlot = Services.DataService:IsTutorialRequired(player)
			and Random.new(player.UserId + math.floor(os.clock() * 1000)):NextInteger(1, math.max(1, Config.CartTiers[tier].Capacity))
			or nil,
		TutorialDropsGenerated = 0,
		TutorialGeodeGenerated = false,
		CrystalParticleCache = {}, -- [crystal] = {{Parent=part, Templates={ParticleEmitter-клоны, неактивные, только на хранение}}, ...} — см. "ОПТИМИЗАЦИЯ ПАРТИКЛОВ РУДЫ" ниже
		ValueSum = 0,
		PointsSum = 0, -- живая сумма Points кристаллов в тележке — двигает комбо-множитель
		ValueLabel = valueLabel,
		ValueGui = valueGui,
		ComboGui = comboGui,
		ComboLabel = comboLabel,
		ComboGradient = comboGradient,
		ComboTween = nil,
		HolderUserId = nil,
		Selling = false,
		Prompt = prompt,
		Motor = nil,     -- Motor6D, приваривающий Root к HRP держателя
		TurnAttachment = nil, -- Attachment на HRP для AlignOrientation-поворота
		TurnAlign = nil,      -- AlignOrientation, ограничивающий скорость поворота
		DiedConn = nil,
		ShieldHighlight = cartHighlight,
		SprintParticles = sprintParticles, -- список ParticleEmitter'ов пыли — вкл/выкл по факту движения, см. Start/limitTurning
		SprintVfxOn = false, -- текущее состояние (чтобы не долбить .Enabled каждый кадр без надобности)
		RollSound = Sfx.createLoop("CartRoll", root), -- зацикленный звук качения — тот же вкл/выкл, что и у пыли (см. setSprintVfx)
		ProtectionConn = nil, -- подписка на Protected держателя — живёт, пока тележка в руках
		JumpConn = nil,       -- StateChanged-подписка для отката прыжка (см. Attach)
		RootToBottom = rootToBottom,
		NextClimbProbe = 0,
		ClimbUntil = 0,
		StuckSince = nil,
		StuckBoostCount = 0,
		NextStuckBoost = 0,
		-- Угнать чужую тележку МОЖНО только пока она "в игре" после смерти
		-- владельца (см. Detach(data, true) в обработчике Humanoid.Died ниже).
		-- Просто стоящую/брошенную владельцем тележку чужой игрок взять не
		-- может — Attach() ниже проверяет это перед каждым прикреплением.
		Stealable = false,
		-- ХП ТЕЛЕЖКИ: теперь зависит от ТИРА САМОЙ ТЕЛЕЖКИ (Config.CartTiers[tier].MaxHealth),
		-- а не от игрока — апгрейд тележки делает её объективно живучее.
		-- Урон по держателю ОДИНАКОВО прилетает и по тележке (см.
		-- CombatService:ApplyHit) — добьют тележку до нуля — она сразу теряет
		-- весь груз и открепляется, как будто держатель погиб (см. DamageCart).
		Health = Config.CartTiers[tier].MaxHealth,
		MaxHealth = Config.CartTiers[tier].MaxHealth,
		LastActivityTime = os.clock(), -- сбрасывается при любом взаимодействии — см. Start (таймер деспавна)
	}
	carts[model] = data
	ownerIndex[player.UserId] = data -- переуказывает на новую, если старая ещё существует — та осиротеет
	updatePrompt(data)
	updateValueLabel(data)
	updateComboLabel(data)
	updateGeodeLabel(data)

	prompt.Triggered:Connect(function(triggerer)
		if data.HolderUserId == nil then
			self:Attach(data, triggerer) -- Attach сам решает, можно ли: владелец — всегда, чужой — только если Stealable (см. Detach)
		end
	end)

	Services.SkinService:ApplyCartSkin(player, data)
	model.Parent = workspace
	if Services.QuestService and Services.QuestService:HasDailyCartColor(player) then
		self:ApplyDailyRewardColor(player, data)
	end
	-- v12: "надувание" из упаковки (и при апгрейде на месте) — см. _playInflate.
	if options.Inflate then
		self:_playInflate(data)
	end
	player:SetAttribute("CartDeployed", true)
	player:SetAttribute("CartPackageCount", self:GetPackageCount(player))
	return data
end

--------------------------------------------------------------------------------
-- ПРИКРЕПЛЕНИЕ / ОТКРЕПЛЕНИЕ
--------------------------------------------------------------------------------

function CartService:Attach(data, player)
	if data.HolderUserId ~= nil then
		return false
	end
	if data.GoblinStolen then
		return false
	end
	if data.GeodeSavePending and player.UserId ~= data.OwnerUserId then
		return false
	end
	if player.UserId ~= data.OwnerUserId and not data.Stealable then
		return false -- чужая тележка, не выпавшая после смерти владельца — брать нельзя
	end
	if player:GetAttribute("CarryingCart") then
		return false -- одна тележка в руках
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return false
	end

	-- v12.1: тележку могли схватить, пока она ещё оседает после постановки.
	-- Временный констрейнт вертикали (_settleUpright) обязан уйти ДО того,
	-- как своё выравнивание повесит держатель, иначе два AlignOrientation
	-- тянут один и тот же корпус в разные стороны и тележка дрожит.
	for _, child in data.Root:GetChildren() do
		if child.Name == "SettleAlign" or child.Name == "SettleAttachment" then
			child:Destroy()
		end
	end

	-- По прямому запросу — особый вход промпта ("падает сверху") играет
	-- только на самое первое взятие тележки за игру, дальше промпт
	-- становится обычным навсегда (см. клиентскую проверку этого
	-- атрибута в refreshActivePrompt).
	if not player:GetAttribute("HasEverGrabbedCart") then
		player:SetAttribute("HasEverGrabbedCart", true)
	end

	-- v10: чужой игрок увёз твою тележку с рудой → владельцу предложение
	-- «вернуть 50%» (MonetizationService:RecordLoss).
	if player.UserId ~= data.OwnerUserId and Services.MonetizationService and Services.MonetizationService.RecordLoss then
		local owner = Players:GetPlayerByUserId(data.OwnerUserId or 0)
		if owner then
			local lost = 0
			for _, crystal in data.Crystals or {} do
				if typeof(crystal) == "Instance" then lost += tonumber(crystal:GetAttribute("CrystalValue")) or 0 end
			end
			if lost > 0 then pcall(Services.MonetizationService.RecordLoss, Services.MonetizationService, owner, lost) end
		end
	end

	-- КРЕПЛЕНИЕ: раньше было АБСОЛЮТНО жёстким (Motor6D напрямую держатель↔
	-- тележка). Теперь тележка физически ДОГОНЯЕТ невидимый "идеальный"
	-- якорь, жёстко висящий на игроке (см. ниже) — обычно неотличимо от
	-- прежнего жёсткого крепления, но при резком движении даёт небольшой
	-- реальный люфт (см. Config.Cart.FollowResponsiveness).
	--
	-- ВЫСОТА КРЕПЛЕНИЯ: по умолчанию — статичное число из
	-- Config.Cart.FollowOffset. Но если в модели тележки есть часть
	-- "AttachPoint" — её ЛОКАЛЬНАЯ высота относительно Root ИСПОЛЬЗУЕТСЯ
	-- НАПРЯМУЮ, без какой-либо математики: подвинул деталь мышкой в Studio
	-- выше — тележка держится выше, подвинул ниже — ниже. Никаких проверок
	-- в рантайме, просто то самое число "как есть".
	local base = Config.Cart.FollowOffset
	local offsetY = base.Y
	local attachPoint = data.Model:FindFirstChild("AttachPoint", true)
	if attachPoint and attachPoint:IsA("BasePart") then
		offsetY = data.Root.CFrame:PointToObjectSpace(attachPoint.Position).Y
	end
	local followOffset = CFrame.new(base.X, offsetY, base.Z)

	-- C1 разворачивает саму тележку вокруг её же центра (позиция крепления
	-- при этом не меняется — поворот применяется "на месте"). По умолчанию —
	-- фиксированный угол из Config.Cart.HolderSideRotation (один на все
	-- модели). Но у разных Cart_TierN разная внутренняя ориентация — один
	-- глобальный угол не всегда подходит всем сразу. Поэтому: если в
	-- КОНКРЕТНОЙ модели есть часть "FacingPoint" — направление от Root к
	-- ней (то есть КУДА ты её поставил мышкой в Studio) само определяет,
	-- какая сторона ЭТОЙ тележки должна быть обращена к игроку — без
	-- всякой ручной подгонки угла, независимо от остальных тиров.
	local rotationAngle = math.rad(Config.Cart.HolderSideRotation)
	local facingPoint = data.Model:FindFirstChild("FacingPoint", true)
	if facingPoint and facingPoint:IsA("BasePart") then
		local localOffset = data.Root.CFrame:PointToObjectSpace(facingPoint.Position)
		rotationAngle = -math.atan2(localOffset.X, localOffset.Z)
	end

	-- Пол тележки шире по X (Config.CartSlots.Cols), чем по Z (.Rows) —
	-- без поворота ближней к игроку оказывалась ШИРОКАЯ сторона (за неё
	-- как будто толкаешь, а не тащишь) — это и есть смысл угла по
	-- умолчанию для дефолтного плейсхолдера. C1 переворачивает ориентацию
	-- самой коробки, но НЕ трогает сетку слотов кристаллов — она считается
	-- в локальных координатах Root (slotOffset ниже), которые просто
	-- поворачиваются вместе с ним как единое целое.
	-- ЖЁСТКИЙ "ИДЕАЛЬНЫЙ" ЯКОРЬ: невидимая точка, которая двигается и
	-- крутится СТРОГО вместе с игроком через Motor6D — ровно тем же
	-- способом, каким раньше была жёстко прикреплена сама тележка. Это
	-- "где тележка ДОЛЖНА быть, будь привязка идеальной" — реальная
	-- тележка (Root) ниже физически ДОГОНЯЕТ этот якорь, а не жёстко
	-- совпадает с ним.
	local anchor = Instance.new("Part")
	anchor.Name = "CartFollowAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Massless = true
	anchor.Anchored = false
	anchor.CFrame = hrp.CFrame * followOffset
	anchor.Parent = workspace

	local anchorMotor = Instance.new("Motor6D")
	anchorMotor.Name = "CartFollowAnchorMotor"
	anchorMotor.Part0 = hrp
	anchorMotor.Part1 = anchor
	anchorMotor.C0 = followOffset
	anchorMotor.C1 = CFrame.Angles(0, rotationAngle, 0)
	anchorMotor.Parent = anchor

	-- РЕАЛЬНЫЙ ФИЗИЧЕСКИЙ ЛЮФТ: Root не приварен к якорю жёстко, а физически
	-- ДОГОНЯЕТ его — AlignPosition/AlignOrientation с конечной силой и
	-- отзывчивостью (см. Config.Cart.FollowResponsiveness — там же почему).
	-- При резком движении/повороте тележка на мгновение чуть отстаёт, потом
	-- сама возвращается точно на место.
	local followAttachment = Instance.new("Attachment")
	followAttachment.Name = "CartFollowAttachment"
	followAttachment.Parent = data.Root

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "CartFollowAnchorAttachment"
	anchorAttachment.Parent = anchor

	local followPosition = Instance.new("AlignPosition")
	followPosition.Name = "CartFollowPosition"
	followPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
	followPosition.Attachment0 = followAttachment
	followPosition.Attachment1 = anchorAttachment
	-- Кастомные модели старших тиров могут иметь разную собственную массу.
	-- Силы всегда хватает удерживать и поднимать саму тележку; масса руды
	-- ниже полностью исключается из assembly и на этот расчёт не влияет.
	followPosition.MaxForce = math.max(
		Config.Cart.FollowMaxForce,
		data.Root.AssemblyMass * workspace.Gravity * Config.Cart.FollowForceGravityMultiplier
	)
	followPosition.Responsiveness = Config.Cart.FollowResponsiveness
	followPosition.Parent = data.Root

	local followOrientation = Instance.new("AlignOrientation")
	followOrientation.Name = "CartFollowOrientation"
	followOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	followOrientation.Attachment0 = followAttachment
	followOrientation.Attachment1 = anchorAttachment
	followOrientation.MaxTorque = Config.Cart.FollowRotationMaxTorque
	followOrientation.Responsiveness = Config.Cart.FollowRotationResponsiveness
	followOrientation.Parent = data.Root

	-- Коллизия тележки с игроками (держателем и всеми остальными) уже
	-- постоянно выключена на уровне PhysicsService (см. CART_COLLISION_GROUP/
	-- PLAYER_COLLISION_GROUP вверху файла) — точечных костылей на время
	-- удержания (сохранение/обнуление CanCollide, NoCollisionConstraint)
	-- больше не нужно. Со СТЕНАМИ/ЗЕМЛЁЙ (группа "Default") тележка
	-- продолжает сталкиваться как обычно — иначе ей нечем держаться на
	-- рельефе и она проваливается под карту на резких движениях (прыжок).

	-- МЕДЛЕННЫЕ ПОВОРОТЫ: AlignOrientation на HRP, цель которого каждый
	-- кадр двигает limitTurning с ограниченной скоростью. Двигаем через
	-- констрейнт (физический солвер), а не прямой записью CFrame — так
	-- поворот не конфликтует с внутренней физикой Humanoid и не дёргается
	-- при репликации другим игрокам. Торк/отзывчивость высокие: вся
	-- "медленность" уже заложена в скорости движения самой цели.
	local turnAttachment = Instance.new("Attachment")
	turnAttachment.Name = "TurnAttachment"
	turnAttachment.Parent = hrp

	local turnAlign = Instance.new("AlignOrientation")
	turnAlign.Name = "TurnAlign"
	turnAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turnAlign.Attachment0 = turnAttachment
	turnAlign.CFrame = CFrame.Angles(0, yawOf(hrp.CFrame), 0) -- стартовая цель — текущий поворот
	turnAlign.MaxTorque = Config.Cart.TurnMaxTorque
	turnAlign.Responsiveness = Config.Cart.TurnResponsiveness
	turnAlign.Parent = hrp

	-- ХП тележки — от ЕЁ ТИРА (Config.CartTiers), сбрасывается на полное
	-- при каждом новом захвате — свежая в руках тележка всегда целая, не
	-- "подранная" с прошлого владельца/простоя (см. Health/MaxHealth в _buildCart).
	data.MaxHealth = Config.CartTiers[data.Tier].MaxHealth
	data.Health = data.MaxHealth

	data.HolderUserId = player.UserId
	data.Model:SetAttribute("HolderUserId", player.UserId) -- см. CustomCartUI.client.lua — так КАЖДЫЙ клиент находит тележки держателей для IK-хвата рук
	data.Model:SetAttribute("GripSeed", math.random(1, 2 ^ 30)) -- сидирует рандомный фолбэк точек хвата: все клиенты независимо приходят к ОДНИМ И ТЕМ ЖЕ точкам
	holderIndex[player.UserId] = data
	data.FollowAnchor = anchor
	data.FollowAnchorMotor = anchorMotor
	data.FollowAttachment = followAttachment
	data.FollowPosition = followPosition
	data.FollowOrientation = followOrientation
	data.TurnAttachment = turnAttachment
	data.TurnAlign = turnAlign
	data.DiedConn = humanoid.Died:Connect(function()
		self:Detach(data, true) -- смерть → тележка остаётся на земле, добыча внутри, и теперь её можно угнать
	end)

	-- Тележка вернулась к законному владельцу — снова недоступна для угона,
	-- пока он либо сам её не бросит, либо снова не погибнет с ней в руках.
	if player.UserId == data.OwnerUserId then
		data.Stealable = false
	end
	updatePrompt(data)

	-- Купол защиты — виден, только пока держатель реально защищён; следит
	-- за атрибутом Protected (CombatService) всё время, пока тележка в руках.
	setShieldVisible(data, player:GetAttribute("Protected"), player)
	data.ProtectionConn = player:GetAttributeChangedSignal("Protected"):Connect(function()
		setShieldVisible(data, player:GetAttribute("Protected"), player)
	end)

	startDragAnimation(player) -- подменяет Idle/Walk на "тащит тележку"
	humanoid.AutoRotate = false -- поворотом теперь управляем сами (см. limitTurning)
	-- Прыжок разрешён, но с откатом: как только держатель прыгает, высота/
	-- сила прыжка на Config.Cart.JumpCooldown обнуляется и сама
	-- восстанавливается — не полный запрет, просто не даёт спамить прыжок
	-- с тележкой в руках.
	--
	-- ФИКС "ПРЫЖОК НА ТЕЛЕФОНЕ ПРОПАДАЕТ ПОСЛЕ ОДНОГО ИСПОЛЬЗОВАНИЯ":
	-- раньше здесь дёргался humanoid:SetStateEnabled(Jumping, false/true) —
	-- у Roblox есть известная проблема, что мобильная TouchGui-кнопка
	-- прыжка (штатная, от PlayerModule) может сбиться и перестать
	-- появляться ПОСЛЕ ТОГО, как состояние Jumping было программно
	-- выключено/включено с сервера — клавиатурный прыжок (Space) при этом
	-- продолжает работать, поэтому баг был заметен только на телефонах.
	-- Не трогаем сам HumanoidStateType вообще — вместо этого временно
	-- обнуляем JumpPower/JumpHeight (в зависимости от режима
	-- UseJumpPower), а потом возвращаем как было. Кнопка остаётся штатной
	-- и рабочей на весь оборот кулдауна, просто прыжок ничего не даёт.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	local jumpLocked = false
	local savedJumpPower = humanoid.JumpPower
	local savedJumpHeight = humanoid.JumpHeight
	data.JumpConn = humanoid.StateChanged:Connect(function(_, new)
		if new ~= Enum.HumanoidStateType.Jumping or jumpLocked then
			return
		end
		jumpLocked = true
		local cartVelocity = data.Root.AssemblyLinearVelocity
		if cartVelocity.Y < Config.Cart.FollowJumpVelocity then
			local deltaVelocity = Config.Cart.FollowJumpVelocity - cartVelocity.Y
			data.Root:ApplyImpulse(Vector3.new(0, deltaVelocity * data.Root.AssemblyMass, 0))
		end
		if humanoid.UseJumpPower then
			humanoid.JumpPower = 0
		else
			humanoid.JumpHeight = 0
		end
		task.delay(Config.Cart.JumpCooldown, function()
			jumpLocked = false
			if humanoid.Parent then
				if humanoid.UseJumpPower then
					humanoid.JumpPower = savedJumpPower
				else
					humanoid.JumpHeight = savedJumpHeight
				end
			end
		end)
	end)
	holderYaw[player.UserId] = yawOf(hrp.CFrame) -- стартовый угол — как сейчас смотрит
	Sfx.play("CartTake", data.Root)

	if #data.Crystals > 0 and Services.DataService and Services.NotifyService
		and Services.DataService:MarkHintSeen(player, "LeftBaseWithValuableCart") then
		Services.NotifyService:Show(player, "Other players can knock ore out of your loaded cart - press Shield to protect it!", { Icon = "Alert" })
	end

	player:SetAttribute("CarryingCart", true) -- CombatService заберёт кирку
	-- v9: руки заняты телегой — руда и снаряжение из рук убираются.
	if Services.InventoryService then pcall(Services.InventoryService.SetHeldOre, Services.InventoryService, player, nil) end
	if Services.GearService then pcall(Services.GearService.Unequip, Services.GearService, player) end
	updatePrompt(data)
	applySpeed(data) -- тележка могла быть уже частично полной (угнана после боя)
	return true
end

-- diedDrop = true → тележку уронил умерший держатель: с этого момента её
-- может забрать ЛЮБОЙ игрок (см. Attach), не только владелец. При любой
-- другой причине открепления (ручной сброс, апгрейд тира и т.п.) остаётся
-- как была — владелец её не "теряет".
function CartService:Detach(data, diedDrop)
	local holderId = data.HolderUserId
	if holderId == nil then
		return
	end
	data.HolderUserId = nil
	data.Model:SetAttribute("HolderUserId", nil)
	data.Model:SetAttribute("GripSeed", nil)
	holderIndex[holderId] = nil
	data.NextClimbProbe = 0
	data.ClimbUntil = 0
	data.StuckSince = nil
	data.StuckBoostCount = 0
	data.NextStuckBoost = 0
	if diedDrop then
		data.Stealable = true
	end

	if data.DiedConn then
		data.DiedConn:Disconnect()
		data.DiedConn = nil
	end
	if data.FollowPosition then
		data.FollowPosition:Destroy()
		data.FollowPosition = nil
	end
	if data.FollowOrientation then
		data.FollowOrientation:Destroy()
		data.FollowOrientation = nil
	end
	if data.FollowAttachment then
		data.FollowAttachment:Destroy() -- на Root, который переживает Detach — сам по себе не удалится
		data.FollowAttachment = nil
	end
	if data.FollowAnchorMotor then
		data.FollowAnchorMotor:Destroy()
		data.FollowAnchorMotor = nil
	end
	if data.FollowAnchor then
		data.FollowAnchor:Destroy() -- отдельный Part в workspace, не часть модели тележки — надо убрать явно
		data.FollowAnchor = nil
	end
	if data.TurnAlign then
		data.TurnAlign:Destroy()
		data.TurnAlign = nil
	end
	if data.TurnAttachment then
		data.TurnAttachment:Destroy()
		data.TurnAttachment = nil
	end
	if data.ProtectionConn then
		data.ProtectionConn:Disconnect()
		data.ProtectionConn = nil
	end
	if data.JumpConn then
		data.JumpConn:Disconnect()
		data.JumpConn = nil
	end
	setShieldVisible(data, false) -- тележка больше не под чьей-то защитой, VFX/обводка скрыты
	setSprintVfx(data, false) -- Heartbeat больше не зовёт limitTurning для неё — гасим явно, а не ждём кадр
	Sfx.play("CartDrop", data.Root)

	local holder = Players:GetPlayerByUserId(holderId)
	if holder then
		holder:SetAttribute("CarryingCart", false)
		local character = holder.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			recomputeWalkSpeed(holder) -- груз тележки снят, но руки могли остаться нагружены — не сбрасываем в base вслепую
			humanoid.AutoRotate = true -- обычные повороты снова управляются Humanoid
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) -- тележка сдана — прыжок снова доступен
		end
		stopDragAnimation(holder)
		holderYaw[holderId] = nil
	end
	updatePrompt(data)
	data.LastActivityTime = os.clock() -- с этого момента тележка свободна — начинается отсчёт простоя (см. Start)

	-- После разрыва Motor6D тележка снова отдельная физическая сборка —
	-- явно возвращаем автоматический выбор владельца сети (иначе может
	-- остаться "приписана" клиенту, который её только что нёс).
	pcall(function()
		data.Root:SetNetworkOwnershipAuto()
	end)
end

function CartService:GoblinStealCart(data, carrier)
	if not data or not data.Model or not data.Model.Parent then return false end
	if data.GoblinStolen then return data.GoblinCarrier == carrier end
	if data.HolderUserId ~= nil then self:Detach(data, false) end
	local carrierModel = carrier and carrier.Model
	local carrierRoot = carrierModel and carrierModel.PrimaryPart
	if not carrierRoot then return false end
	data.Stealable = false
	data.GoblinStolen = true
	data.GoblinCarrier = carrier
	data.GoblinPartState = {}
	for _, descendant in data.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			data.GoblinPartState[descendant] = {
				Anchored = descendant.Anchored,
				CanCollide = descendant.CanCollide,
				Massless = descendant.Massless,
			}
			descendant.Anchored = false
			descendant.CanCollide = false
		end
	end

	-- The cart is deliberately independent from the goblin. It is anchored and
	-- positioned by followGoblinCart on the server, so no physical joint can
	-- lift or rotate the NPC.
	local base = Config.Goblins.CarryCartOffset
	local rotationAngle = math.rad(Config.Cart.HolderSideRotation)
	local facingPoint = data.Model:FindFirstChild("FacingPoint", true)
	if facingPoint and facingPoint:IsA("BasePart") then
		local localOffset = data.Root.CFrame:PointToObjectSpace(facingPoint.Position)
		rotationAngle = -math.atan2(localOffset.X, localOffset.Z)
	end
	data.GoblinCarryOffset = base * CFrame.Angles(0, -rotationAngle, 0)
	for _, descendant in data.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	followGoblinCart(data)
	return true
end

function CartService:ReleaseGoblinCart(data)
	if not data or not data.GoblinStolen then return false end
	data.GoblinStolen = false
	data.GoblinCarrier = nil
	data.Stealable = true
	for descendant, properties in data.GoblinPartState or {} do
		if descendant.Parent then
			descendant.Anchored = properties.Anchored
			descendant.CanCollide = properties.CanCollide
			descendant.Massless = properties.Massless
		end
	end
	data.GoblinPartState = nil
	data.GoblinCarryOffset = nil
	pcall(function() data.Root:SetNetworkOwnershipAuto() end)
	return true
end

function CartService:RespawnAfterGoblinSteal(data)
	if not data then return nil end
	local owner = Players:GetPlayerByUserId(data.OwnerUserId)
	-- Stop the independent follow update before consuming the delivered cart.
	if data.GoblinStolen then
		self:ReleaseGoblinCart(data)
	end
	self:_destroy(data)
	-- v12: гоблин утащил тележку к себе в лагерь — новая НЕ появляется сама
	-- на парковке, как раньше. Владелец получает обратно упаковку (с той же
	-- задержкой, что и при любой другой потере) и ставит тележку там, где
	-- захочет. Так кража остаётся ощутимой потерей темпа, но не оставляет
	-- игрока без тележки навсегда.
	if owner and owner.Parent then
		self:OnCartLost(owner, "goblin")
	end
	return nil
end

--------------------------------------------------------------------------------
-- КРИСТАЛЛЫ В ТЕЛЕЖКЕ
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ОПТИМИЗАЦИЯ ПАРТИКЛОВ РУДЫ.
--
-- Полная тележка — это до Capacity кристаллов сразу (у топовых тиров —
-- десятки), и если у ассета руды есть свои ParticleEmitter (блёстки/
-- свечение), одновременно активными могут оказаться под сотню частичных
-- систем — ощутимая просадка FPS, притом что бóльшая часть этих эффектов
-- реально не видна: кристалл либо накрыт другим кристаллом сверху в той же
-- клетке сетки, либо намеренно прорежен для дополнительной экономии.
--
-- ДВА НЕЗАВИСИМЫХ ПРАВИЛА (если хоть одно гасит партикл — партикл выключен):
--   1. НАКРЫТО СВЕРХУ — динамически, по факту: как только в ТОЙ ЖЕ клетке
--      сетки (тот же X/Z) появляется кристалл слоем выше, партиклы кристалла
--      снизу удаляются. Если позже верхний кристалл распродан/выбит —
--      партиклы низа возвращаются (пересоздаются заново из сохранённого
--      шаблона).
--   2. ШАХМАТНОЕ ПРОРЕЖИВАНИЕ — среди кристаллов, которые ничем не накрыты
--      (то есть видны), каждый второй по чётности клетки (cx+cz) всё равно
--      без партиклов — НАВСЕГДА, независимо от того, накрыт он потом или
--      нет (доп. экономия плотности эффектов даже на самом верху).
--
-- Оба правила выводятся из ОДНОГО числа — текущего количества кристаллов в
-- тележке — без сканирования всей тележки на каждое изменение: слои
-- заполняются строго последовательно, "по одной полной клетке за раз",
-- поэтому у кристалла с номером i есть накрывающий сосед в той же клетке
-- ровно тогда, когда кристалл с номером (i + perLayer) уже существует.
-- Проверяем/обновляем только ТУ ОДНУ пару кристаллов, на которую реально
-- повлияло текущее добавление/удаление — O(1), а не обход всей тележки.
--
-- Почему Destroy(), а не Enabled = false: партикл, который сейчас закрыт
-- другим кристаллом, всё равно продолжает симулироваться каждый кадр, если
-- просто выключить видимость — реальной экономии почти нет. Настоящая
-- экономия — убрать сам инстанс ParticleEmitter из дерева. Чтобы потом
-- вернуть НАКРЫТЫЙ (не шахматно-прореженный) кристалл — держим неактивный
-- Clone() каждого его партикла "на хранении" (не в Workspace, ни с чем не
-- взаимодействует, ничего не стоит рантайму) и при необходимости клонируем
-- заново — с точки зрения игрока неотличимо от "включили обратно".
--------------------------------------------------------------------------------

local function crystalGridCell(index)
	local cols = Config.CartSlots.Cols
	local rows = Config.CartSlots.Rows
	local perLayer = cols * rows
	local rem = (index - 1) % perLayer
	local cx = rem % cols
	local cz = math.floor(rem / cols)
	return cx, cz, perLayer
end

-- true → эта клетка сетки навсегда без партиклов, независимо от того,
-- накрыта она сверху или нет (шахматное прореживание).
local function isCheckerCulled(index)
	local cx, cz = crystalGridCell(index)
	return (cx + cz) % 2 ~= 0
end

-- Снимает и прячет "на хранение" все живые ParticleEmitter кристалла,
-- запоминая, к какой именно части они относились (чтобы потом пересоздать
-- в том же месте). Безопасно вызывать повторно — если шаблоны уже сняты
-- (кэш уже есть) или живых эмиттеров нет вовсе — просто ничего не делает.
local function cacheAndDestroyEmitters(data, crystal)
	if data.CrystalParticleCache[crystal] then
		return
	end
	local groups = {}
	for _, descendant in crystal:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local template = descendant:Clone()
			table.insert(groups, { Parent = descendant.Parent, Template = template })
			descendant:Destroy()
		end
	end
	if #groups > 0 then
		data.CrystalParticleCache[crystal] = groups
	end
end

-- Возвращает ранее снятые партиклы кристалла обратно на место (клонами
-- сохранённых шаблонов) — используется, только когда накрывавший сосед
-- сверху исчез. Ничего не делает, если у кристалла нет кэша (партиклов не
-- было вовсе, либо он навсегда прорежен шахматкой — для таких кэш в
-- восстановительной роли никогда не создаётся, см. AddCrystal).
local function restoreEmitters(data, crystal)
	local groups = data.CrystalParticleCache[crystal]
	if not groups then
		return
	end
	for _, group in groups do
		if group.Parent and group.Parent.Parent then -- часть кристалла всё ещё жива
			local clone = group.Template:Clone()
			clone.Parent = group.Parent
		end
	end
	data.CrystalParticleCache[crystal] = nil
end

-- instant = true → без анимации падения (перенос при апгрейде/подборе)
function CartService:AddCrystal(data, crystal, instant, dropWorldPosition, silent)
	if #data.Crystals >= data.Capacity then
		return false -- тележка полна → добыча остановится
	end
	local index = #data.Crystals + 1
	local cargoSlotIndex = #data.Crystals + #data.Geodes + 1
	local root = CrystalUtil.GetRoot(crystal) -- BasePart сам по себе, либо PrimaryPart/"Root" у Model-кристалла

	-- У Model-кристалла одного Massless на PrimaryPart недостаточно: каждая
	-- приваренная декоративная часть входит в массу общей assembly. Обнуляем
	-- физический вес ВСЕХ частей, иначе десятки крупных кристаллов тиров 5–8
	-- перегружают AlignPosition и гасят прыжок тележки.
	if crystal:IsA("BasePart") then
		crystal.Anchored = false
		crystal.CanCollide = false
		crystal.Massless = true
	else
		for _, descendant in crystal:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.Massless = true
			end
		end
	end
	crystal:SetAttribute("Loose", false)
	crystal.Parent = data.Model

	local target = slotOffset(data, cargoSlotIndex)
	local weld = Instance.new("Weld")
	weld.Name = "CrystalWeld"
	weld.Part0 = data.Root
	weld.Part1 = root

	local priceGui = crystal:FindFirstChild("PriceGui", true)

	-- Мировая точка над шахтой (OreDropPoint, см. PlotService/
	-- PlaceholderFactory.Mine) переводится в ЛОКАЛЬНЫЕ координаты Root
	-- тележки один раз, в момент спавна — тележка во время добычи и так
	-- обязана стоять неподвижно в зоне шахты (см. MineService).
	local startLocal = dropWorldPosition and CFrame.new(data.Root.CFrame:PointToObjectSpace(dropWorldPosition))

	if instant then
		weld.C0 = target
		weld.Parent = root
		if priceGui then
			priceGui:Destroy() -- уже "приземлился" (перенос/подбор) — личный ценник больше не нужен
		end
		if not silent then
			Sfx.play("CrystalDrop", data.Root)
		end
	else
		-- ПО ПРЯМОМУ ЗАПРОСУ ("убери ту механику с анчоред, просто
		-- складируй так, чтобы красиво лежали внутри и не пересекались")
		-- — реальная физика (Anchored=false + столкновения) убрана
		-- целиком: непредсказуема без живого теста в Studio и рискует
		-- вытолкнуть кусок из тележки/пересечься с соседним. Вернулись к
		-- детерминированному твину прямо в узел сетки (см. slotOffset —
		-- уже с небольшим случайным разбросом позиции и гарантированным
		-- кувырком при падении, см. ниже) — так куски НИКОГДА не
		-- пересекаются (сетка сама на это рассчитана) и всегда красиво
		-- лежат, при этом ещё и не выглядят полностью одинаковыми
		-- рядами благодаря jitter/спину.
		--
		-- ТУМБЛИНГ ПРИ ПАДЕНИИ (по прямому запросу — "крутились на 90
		-- градусов вокруг себя, чтобы было реалистично"): раньше камень
		-- просто линейно долетал до целевого поворота (target уже включал
		-- случайный 0/90/180/270° спин вокруг вертикали, см. slotOffset,
		-- но старт почти всегда был БЕЗ поворота — startLocal это чистая
		-- позиция без вращения, так что при спине 0° разворота вообще не
		-- было видно). Добавляем гарантированный доп. кувырок вокруг
		-- горизонтальной оси (X или Z, вперёд/назад — не вокруг
		-- вертикали, тот уже занят финальным спином) поверх стартового
		-- поворота — независимо от итогового spin камень теперь ВСЕГДА
		-- заметно кувыркается по пути и точно останавливается в target
		-- (TweenService интерполирует поворот сам, C1 не трогаем).
		local tumbleAxis = math.random(1, 2) == 1 and Vector3.xAxis or Vector3.zAxis
		local tumbleAngle = math.rad(90 * math.random(1, 3)) -- 90/180/270° доп. кувырка
		local fallStart = startLocal or (target + Vector3.new(0, 6, 0))
		weld.C0 = fallStart * CFrame.fromAxisAngle(tumbleAxis, tumbleAngle)
		weld.Parent = root
		local tween = TweenService:Create(weld, DROP_TWEEN, { C0 = target })
		tween.Completed:Connect(function()
			if priceGui then
				priceGui:Destroy()
			end
			Sfx.play("CrystalDrop", data.Root)
		end)
		tween:Play()
	end

	table.insert(data.Crystals, crystal)
	do
		local newIndex = #data.Crystals
		if isCheckerCulled(newIndex) then
			-- Прорежено шахматкой — навсегда, кэш для восстановления не нужен:
			-- эта клетка без партиклов независимо от того, накроют её потом
			-- сверху или нет.
			for _, descendant in crystal:GetDescendants() do
				if descendant:IsA("ParticleEmitter") then
					descendant:Destroy()
				end
			end
		end
		-- Не накрыла ли эта новая руда кого-то снизу в той же клетке сетки?
		local _, _, perLayer = crystalGridCell(newIndex)
		local coveredIndex = newIndex - perLayer
		if coveredIndex >= 1 and not isCheckerCulled(coveredIndex) then
			local coveredCrystal = data.Crystals[coveredIndex]
			if coveredCrystal then
				cacheAndDestroyEmitters(data, coveredCrystal)
			end
		end
	end
	data.ValueSum += crystal:GetAttribute("CrystalValue") or 0
	data.PointsSum += crystal:GetAttribute("CrystalPoints") or 0
	data.LastActivityTime = os.clock() -- добыча/подбор — тележка не простаивает
	updateValueLabel(data)
	updateComboLabel(data)
	applySpeed(data)

	-- "НАКОРМИ СВОЕГО СЛАЙМА" вместо намёка на продажу — по прямому
	-- запросу. Тележка ТОЛЬКО ЧТО стала полностью полной (проверяем ДО
	-- этой капли она полной не была, а теперь — да, иначе подсказка
	-- всплывала бы на каждой последующей капле, которых уже не будет,
	-- раз тележка полна, но на всякий случай — защита от повторов) — и
	-- игрок ещё проходит обучение (см. Config.Tutorial). Подсказка вместо
	-- "иди продавай" явно указывает на слайма — сама продажа И ЕСТЬ
	-- кормление (см. SlimeService/BankService), просто раньше это никак
	-- не подчёркивалось игроку в момент, когда это наиболее уместно.
	if #data.Crystals >= data.Capacity then
		local player = Players:GetPlayerByUserId(data.OwnerUserId)
		if player and Services.DataService:IsTutorialRequired(player) and not data.FullCartTipShown then
			data.FullCartTipShown = true
			if Services.NotifyService then
				Services.NotifyService:Show(player, '<font color="#5CFF8A">CART FULL!</font> Take it to the bank.', { Icon = "Cart", Critical = true })
			end
		end
	end
	-- v20.36: обучение, шаг «загрузи руду в тележку».
	local cartOwner = data.OwnerUserId and Players:GetPlayerByUserId(data.OwnerUserId)
	if cartOwner and Services.TutorialService then
		pcall(function() Services.TutorialService:Count(cartOwner, "OreDepositedToCart", 1) end)
	end
	return true
end

function CartService:AddGeode(data, geode, instant, dropWorldPosition)
	if not data or data.PendingGeodeEvacuationId or #data.Geodes >= Config.Geodes.MaxPerCart then
		return false
	end
	local root = CrystalUtil.GetRoot(geode)
	for _, descendant in geode:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	if geode:IsA("BasePart") then
		geode.Anchored = false
		geode.CanCollide = false
		geode.Massless = true
	end
	geode:SetAttribute("Loose", false)
	geode.Parent = data.Model

	local cargoSlotIndex = #data.Crystals + #data.Geodes + 1
	local target = slotOffset(data, cargoSlotIndex)
	local weld = Instance.new("Weld")
	weld.Name = "GeodeWeld"
	weld.Part0 = data.Root
	weld.Part1 = root
	weld.C0 = dropWorldPosition and CFrame.new(data.Root.CFrame:PointToObjectSpace(dropWorldPosition)) or target
	weld.Parent = root
	if not instant then
		local tween = TweenService:Create(weld, DROP_TWEEN, { C0 = target })
		tween.Completed:Connect(function()
			Sfx.play("CrystalDrop", data.Root)
		end)
		tween:Play()
	else
		weld.C0 = target
		Sfx.play("CrystalDrop", data.Root)
	end
	table.insert(data.Geodes, geode)
	data.LastActivityTime = os.clock()
	updateGeodeLabel(data)
	Sfx.play("GeodeSpawn", data.Root)
	return true
end

function CartService:RemoveGeodes(data, count, allowPendingSave)
	if data.GeodeSavePending and not allowPendingSave then return {} end
	local removed = {}
	for _ = 1, math.max(0, count or 0) do
		local geode = table.remove(data.Geodes)
		if not geode then break end
		local weld = CrystalUtil.GetRoot(geode):FindFirstChild("GeodeWeld")
		if weld then weld:Destroy() end
		table.insert(removed, geode)
	end
	data.LastActivityTime = os.clock()
	updateGeodeLabel(data)
	return removed
end

function CartService:GetGeodeCount(data)
	return data and #data.Geodes or 0
end

-- Снимает последние N кристаллов (сверху вниз) и возвращает их части.
function CartService:RemoveCrystals(data, count)
	if data.PaidFillPendingSave then
		return {} -- продажа/PvP ждут подтверждения consumption оплаченного fill
	end
	local removed = {}
	for _ = 1, count do
		local removedIndex = #data.Crystals -- индекс ДО удаления (всегда последний — снимаем строго сверху)
		local crystal = table.remove(data.Crystals)
		if not crystal then
			break
		end
		local root = CrystalUtil.GetRoot(crystal)
		local weld = root:FindFirstChild("CrystalWeld")
		if weld then
			weld:Destroy()
		end
		data.CrystalParticleCache[crystal] = nil -- сам кристалл уходит целиком — восстанавливать больше нечего

		-- Этот кристалл кого-то накрывал в той же клетке сетки? Раз он ушёл —
		-- сосед снизу (если не прорежен шахматкой навсегда) снова видим —
		-- возвращаем ему партиклы.
		local _, _, perLayer = crystalGridCell(removedIndex)
		local uncoveredIndex = removedIndex - perLayer
		if uncoveredIndex >= 1 and not isCheckerCulled(uncoveredIndex) then
			local uncoveredCrystal = data.Crystals[uncoveredIndex]
			if uncoveredCrystal then
				restoreEmitters(data, uncoveredCrystal)
			end
		end

		data.ValueSum -= crystal:GetAttribute("CrystalValue") or 0
		data.PointsSum -= crystal:GetAttribute("CrystalPoints") or 0
		table.insert(removed, crystal)
	end
	data.ValueSum = math.max(0, data.ValueSum)
	data.PointsSum = math.max(0, data.PointsSum)
	data.LastActivityTime = os.clock()
	updateValueLabel(data)
	updateComboLabel(data)
	applySpeed(data)
	return removed
end

-- PvP v2: снять ОДНУ самую дорогую руду. Сетка слотов привязана к индексу,
-- поэтому самую дорогую сначала меняем местами с верхней (меняются и
-- позиции сварки), а снимаем уже штатно сверху через RemoveCrystals.
function CartService:RemoveMostValuable(data)
	if data.PaidFillPendingSave or #data.Crystals == 0 then
		return {}
	end
	local bestIndex, bestValue = #data.Crystals, -math.huge
	for index, crystal in data.Crystals do
		local value = tonumber(crystal:GetAttribute("CrystalValue")) or 0
		if value > bestValue then
			bestIndex, bestValue = index, value
		end
	end
	local lastIndex = #data.Crystals
	if bestIndex ~= lastIndex then
		local best, top = data.Crystals[bestIndex], data.Crystals[lastIndex]
		local bestWeld = CrystalUtil.GetRoot(best):FindFirstChild("CrystalWeld")
		local topWeld = CrystalUtil.GetRoot(top):FindFirstChild("CrystalWeld")
		if bestWeld and topWeld then
			bestWeld.C0, topWeld.C0 = topWeld.C0, bestWeld.C0
		end
		data.Crystals[bestIndex], data.Crystals[lastIndex] = top, best
	end
	return self:RemoveCrystals(data, 1)
end

function CartService:GetCrystalCount(data)
	return #data.Crystals
end

-- Платное заполнение использует тот же AddCrystal, что и обычная шахта:
-- значения, комбо, визуальные слоты и замедление остаются согласованными.
-- maxCrystals привязан к купленному продукту и не позволяет дешёвому тиру
-- заполнить более дорогую тележку после открытия системного окна покупки.
function CartService:FillInstantly(player, data, maxCrystals, crystalTier)
	if not data or carts[data.Model] ~= data or not data.Model.Parent or data.Selling then
		return false
	end
	if data.OwnerUserId ~= player.UserId and data.HolderUserId ~= player.UserId then
		return false
	end

	local remaining = math.min(data.Capacity - #data.Crystals, maxCrystals)
	if remaining <= 0 then
		return false -- не подтверждаем платную покупку, если шахта успела заполнить тележку раньше receipt
	end
	local mineTier = math.clamp(math.floor(tonumber(crystalTier) or Services.DataService:GetTiers(player).Mine), 1, #Config.MineTiers)
	local initialCount = #data.Crystals
	local added = 0
	local ok, errorMessage = xpcall(function()
		for _ = 1, remaining do
			local crystal = Services.CrystalService:Create(mineTier, player, nil, "Paid") -- v17: в платной заливке мусора нет
			if not self:AddCrystal(data, crystal, true, nil, true) then
				crystal:Destroy()
				break
			end
			added += 1
		end
	end, debug.traceback)
	added = math.max(added, #data.Crystals - initialCount)
	if not ok or added ~= remaining then
		for _, crystal in self:RemoveCrystals(data, added) do crystal:Destroy() end
		if not ok then warn("[CartService] Paid FillInstantly rolled back:", errorMessage) end
		return false
	end
	if added > 0 then
		Sfx.play("CrystalDrop", data.Root)
	end
	return true
end

-- Пересчитать скорость держателя: тиры Mine/Cart могли поменяться без
-- изменения числа кристаллов (например, купили апгрейд шахты), или груз
-- в руках/микро-стан изменились без участия тележки — работает и без неё.
-- v8: перк Cart Space купили — расширяем тележку игрока сразу.
function CartService:RefreshCapacity(player)
	local data = ownerIndex[player.UserId]
	if not data then return end
	local bonus = Services.PrestigeService and math.floor(Services.PrestigeService:PerkBonus(player, "CartSpace")) or 0
	data.Capacity = Config.CartTiers[data.Tier].Capacity + bonus
	if data.Model then data.Model:SetAttribute("Capacity", data.Capacity) end
end

function CartService:RefreshSpeed(player)
	recomputeWalkSpeed(player)
end

-- Публичный alias — используется HandCarryService (груз в руках изменился)
-- и CombatService (микро-стан закончился), см. recomputeWalkSpeed выше.
CartService.RecomputeSpeed = CartService.RefreshSpeed

-- Для BankService: множитель ЗАМОРАЖИВАЕТСЯ на момент начала продажи одной
-- партии, иначе он таял бы на глазах по мере того, как кристаллы продаются.
function CartService:GetComboMultiplier(data)
	return comboMultiplier(data)
end

-- Случайная, но гарантированно горизонтально-разнесённая скорость для
-- содержимого СЛОМАННОЙ тележки (см. DamageCart ниже) — тот же принцип
-- "гарантированно наружу", что и у боевого выбития в CombatService, но
-- локальная копия попроще: тут не нужен no-collide (тележка уже открепляется
-- и её Motor уничтожается раньше, чем кристаллы успевают разлететься).
local function scatterVelocity()
	local angle = math.random() * math.pi * 2
	local speed = math.random(10, 18)
	return Vector3.new(math.cos(angle) * speed, math.random(14, 22), math.sin(angle) * speed)
end

-- ХП тележки зеркалит держателя (см. Attach) — урон по игроку прилетает
-- СЮДА же (см. CombatService:ApplyHit), тем же числом. Дойдёт до нуля —
-- тележка "сломана": весь груз рассыпается по земле (доступен всем,
-- включая владельца, как и любая другая выбитая руда — см. CrystalService),
-- а сама тележка тут же открепляется и становится угоняемой, как будто
-- держатель погиб (Detach(data, true)) — играть без тележки, пока новая
-- не появится/старую не отобьют, тоже часть наказания.
function CartService:DamageCart(cart, amount)
	if not cart or cart.HolderUserId == nil then
		return 0, 0
	end
	-- PaidFillPendingSave проверяется здесь ВМЕСТЕ с GeodeSavePending, как и
	-- во всех остальных местах файла (оба цикла в Start, ForceNewCart,
	-- CanUpgradeOwnedCart). Раньше проверялся только второй флаг, и
	-- получалась рассинхронизация: тележку доводили до нуля здоровья, а
	-- RemoveCrystals ниже при PaidFillPendingSave возвращает пустой список —
	-- тележка "ломалась", но не роняла НИЧЕГО и сохраняла весь груз.
	if cart.GeodeSavePending or cart.PaidFillPendingSave then return 0, 0 end
	local dealt = math.min(cart.Health, math.max(0, amount))
	-- Вычитаем именно dealt, а не сырой amount: для положительного урона это
	-- ровно то же самое, но отрицательный amount больше не ЛЕЧИТ тележку
	-- выше максимума (math.max(0, ...) ограничивал только снизу).
	cart.Health = math.max(0, cart.Health - dealt)
	if cart.Health > 0 then
		Sfx.play("CartDamaged", cart.Root)
		return dealt, 0
	end

	local holderId = cart.HolderUserId
	local crystals = self:RemoveCrystals(cart, #cart.Crystals)
	local droppedCrystalCount = #crystals
	for _, crystal in crystals do
		Services.CrystalService:MakeLoose(crystal, scatterVelocity(), holderId, cart.Model)
	end
	for _, geode in self:RemoveGeodes(cart, #cart.Geodes) do
		Services.CrystalService:MakeLoose(geode, scatterVelocity(), holderId, cart.Model)
	end
	Sfx.play("CartDestroyed", cart.Root)
	Sfx.play("CrystalKnockout", cart.Root)
	self:Detach(cart, true)
	return dealt, droppedCrystalCount
end

--------------------------------------------------------------------------------
-- ЗАПРОСЫ
--------------------------------------------------------------------------------

function CartService:GetHeldCart(player)
	return holderIndex[player.UserId]
end

function CartService:RefreshShieldVisual(player)
	local data = holderIndex[player.UserId]
	if data and data.ShieldHighlight then
		setShieldVisible(data, player:GetAttribute("Protected") == true, player)
	end
end

function CartService:GetOwnedCart(player)
	return ownerIndex[player.UserId]
end

-- Возвращает только собственную тележку, до которой игрок действительно
-- дошёл. Чужие тележки не принимают руду из рюкзака.
function CartService:GetDepositCart(player, maxDistance)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cart = self:GetHeldCart(player) or self:GetOwnedCart(player)
	if not (root and cart and cart.Root and cart.Root.Parent) then return nil end
	if cart.OwnerUserId ~= player.UserId or (cart.HolderUserId ~= nil and cart.HolderUserId ~= player.UserId) then
		return nil
	end
	if #cart.Crystals >= cart.Capacity then return nil end
	if (root.Position - cart.Root.Position).Magnitude > (maxDistance or Config.Cart.DepositDistance) then
		return nil
	end
	return cart
end

function CartService:ApplyDailyRewardColor(player, explicitData)
	local data = explicitData or ownerIndex[player.UserId]
	if not data then return false end
	local color
	for _, reward in Config.Quests.DailyRewards do
		if reward.Kind == "CartColor" then color = reward.Color; break end
	end
	if not color then return false end
	data.Model:SetAttribute("DailyRewardColor", color)
	local colored = false
	for _, descendant in data.Model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("DailyColorable") == true then
			descendant.Color = color
			colored = true
		end
	end
	if not colored then data.Root.Color = color end -- custom carts can tag any visible parts
	return true
end

function CartService:RefreshCartSkin(player)
	local data = ownerIndex[player.UserId]
	if not data then return false end
	Services.SkinService:ApplyCartSkin(player, data)
	return true
end

function CartService:GetAllCarts()
	return carts
end

-- true, если тележка СЕЙЧАС физически стоит на пятачке (Pad) базы своего
-- ВЛАДЕЛЬЦА — используется и авто-деспавном простаивающих тележек (см.
-- Start() выше), и CombatService (нельзя бить/грабить тележку, пока она
-- дома на базе — только когда её кто-то тащит или она брошена/оставлена
-- где-то в мире).
function CartService:IsAtOwnerBase(data)
	local owner = Players:GetPlayerByUserId(data.OwnerUserId)
	local plot = owner and Services.PlotService and Services.PlotService:GetPlot(owner)
	if not (plot and plot.Pad) then
		return false
	end
	local localPosition = plot.Pad.CFrame:PointToObjectSpace(data.Root.Position)
	local half = plot.Pad.Size / 2
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Z) <= half.Z
end

-- Куда игроку класть кристаллы: тележка в руках, иначе своя свободная.
function CartService:GetCartWithSpaceFor(player)
	local held = holderIndex[player.UserId]
	if held and #held.Crystals < held.Capacity then
		return held
	end
	local owned = ownerIndex[player.UserId]
	if owned and owned.HolderUserId == nil and #owned.Crystals < owned.Capacity then
		return owned
	end
	return nil
end

function CartService:GetCartWithGeodeSpaceFor(player, pickupPosition)
	local held = holderIndex[player.UserId]
	if held and #held.Geodes < Config.Geodes.MaxPerCart
		and (not pickupPosition or (held.Root.Position - pickupPosition).Magnitude <= 15) then return held end
	local owned = ownerIndex[player.UserId]
	if owned and owned.HolderUserId == nil and #owned.Geodes < Config.Geodes.MaxPerCart
		and (not pickupPosition or (owned.Root.Position - pickupPosition).Magnitude <= 15) then return owned end
	return nil
end

--------------------------------------------------------------------------------
-- АПГРЕЙД
--------------------------------------------------------------------------------

function CartService:CanUpgradeOwnedCart(player)
	local data = ownerIndex[player.UserId]
	if not data then
		return true
	end
	-- нельзя апгрейдить тележку, которую держит другой игрок (угнана)
	return not data.PaidFillPendingSave and not data.GeodeSavePending and (data.HolderUserId == nil or data.HolderUserId == player.UserId)
end

-- wipeCargo (опционально) — используется РЕБЁРТОМ: груз старой тележки НЕ
-- переносится в новую, а сгорает вместе с ней. Без этого флага (обычный
-- платный апгрейд на пьедестале) груз переносится как раньше — это разное
-- поведение НАМЕРЕННО: апгрейд не должен наказывать за то, что в тележке
-- что-то лежит, а ребёрт обязан обнулять и груз тоже, иначе можно нарочно
-- забить тележку перед ребёртом и тут же отбить якобы "обнулённые" деньги.
function CartService:UpgradeOwnedCart(player, wipeCargo)
	local data = ownerIndex[player.UserId]
	if not data then
		-- v12: ТЕЛЕЖКА НЕ СТОИТ В МИРЕ (лежит упаковкой в рюкзаке ЛИБО
		-- игрок только что купил её впервые). Строить ничего не надо и
		-- НЕЛЬЗЯ — тележка должна появиться только там, где игрок сам её
		-- поставит. Упаковка тир не хранит: следующая постановка соберёт
		-- тележку по уже повышенному тиру. Достаточно убедиться, что
		-- упаковка на руках есть, и сказать игроку, что она обновилась.
		if self:IsCartUnlocked(player) then
			local granted = self:GrantPackage(player, "upgrade")
			if not granted and Services.NotifyService then
				Services.NotifyService:Show(player, "📦 Cart upgraded - place your package to see it!", { Icon = "Cart" })
			end
		end
		self:_refreshCartAttributes(player)
		return true
	end
	if not self:CanUpgradeOwnedCart(player) then
		return false
	end

	local wasHeld = data.HolderUserId == player.UserId
	local pivot = data.Root.CFrame

	local crystals = self:RemoveCrystals(data, #data.Crystals)
	local geodes = self:RemoveGeodes(data, #data.Geodes)
	for _, crystal in crystals do
		crystal.Parent = nil -- спасаем от Destroy старой модели
	end
	for _, geode in geodes do geode.Parent = nil end

	if wasHeld then
		self:Detach(data)
	end
	self:_destroy(data)

	-- СТАРАЯ ТЕЛЕЖКА УЖЕ УНИЧТОЖЕНА, А ГРУЗ ВИСИТ В ВОЗДУХЕ (Parent = nil).
	-- Если построить новую не удастся, игрок останется ВООБЩЕ БЕЗ ТЕЛЕЖКИ, а
	-- снятые кристаллы утекут в память навсегда — их уже никто не удалит.
	-- Сценарий не гипотетический: _buildCart содержит
	-- assert(root, "У модели тележки обязан быть PrimaryPart 'Root'"), и
	-- достаточно положить в Assets свою модель Cart_TierN без детали Root,
	-- что проект прямо предлагает делать. Хуже всего порядок вызовов
	-- снаружи: UpgradeService:_tryBuy СНАЧАЛА списывает деньги и повышает
	-- тир (AddMoney/IncrementBranch), и только ПОТОМ зовёт эту функцию, —
	-- то есть игрок заплатил бы, потерял тележку и получил ошибку.
	local built, newData = pcall(function()
		-- v12: новая тележка встаёт РОВНО НА МЕСТО старой (pivot ниже) и
		-- "надувается" той же анимацией, что и постановка из упаковки —
		-- апгрейд читается как событие, а не как молчаливая подмена
		-- модели. Камеру на неё наводит катсцена продавца
		-- (playUpgradeRevealCamera в CustomCartUI.client.lua).
		-- Inflate здесь НЕ включаем: анимация масштабирует модель, а груз
		-- ниже кладётся в слоты, посчитанные от РАЗМЕРА Root (slotOffset) —
		-- попади перенос груза в середину анимации, кристаллы встали бы по
		-- координатам уменьшенной тележки. Анимацию запускаем уже после
		-- переноса, в самом конце функции.
		return self:SpawnCartFor(player, { CFrame = pivot + Vector3.new(0, 0.5, 0) })
	end)
	if not built or not newData then
		for _, crystal in crystals do crystal:Destroy() end
		for _, geode in geodes do geode:Destroy() end
		warn(("[CartService] Не удалось построить новую тележку для %s при апгрейде: %s. Груз уничтожен, чтобы не утёк. Проверь, что у модели Cart_Tier%d есть деталь 'Root'."):format(
			player.Name, tostring(newData), Services.DataService:GetTiers(player).Cart))
		return false
	end
	newData.Model:PivotTo(pivot + Vector3.new(0, 0.5, 0))

	if wipeCargo then
		for _, crystal in crystals do
			crystal:Destroy() -- ребёрт: груз не переживает сброс, сгорает целиком
		end
		for _, geode in geodes do geode:Destroy() end
	else
		for i = #crystals, 1, -1 do -- восстановить исходный порядок (снимали с конца)
			if not self:AddCrystal(newData, crystals[i], true) then
				crystals[i]:Destroy() -- не влез (даунгрейд) — сгорает
			end
		end
		for i = #geodes, 1, -1 do
			if not self:AddGeode(newData, geodes[i], true) then geodes[i]:Destroy() end
		end
	end
	if wasHeld then
		-- Тележка была в руках — возвращаем её туда же. Анимацию в этом
		-- случае не играем: модель висит на констрейнтах держателя, менять
		-- ей масштаб на лету небезопасно.
		self:Attach(newData, player)
	else
		self:_playInflate(newData)
	end
	self:_refreshCartAttributes(player)
	return true
end

--------------------------------------------------------------------------------
-- ОЧИСТКА
--------------------------------------------------------------------------------

function CartService:CleanupPlayer(player)
	sprintState[player] = nil
	local owned = ownerIndex[player.UserId]
	local deadline = os.clock() + 20
	while owned and owned.PaidFillPendingSave and os.clock() < deadline do
		task.wait(0.1) -- consumption entitlement должен сохраниться до уничтожения runtime-груза
	end
	local held = holderIndex[player.UserId]
	if held then
		self:Detach(held)
	end
	owned = ownerIndex[player.UserId]
	if owned then
		self:_destroy(owned)
	end
end

function CartService:_destroy(data)
	if data.GoblinStolen then
		self:ReleaseGoblinCart(data)
	end
	if data.HolderUserId then
		self:Detach(data)
	end
	carts[data.Model] = nil
	if ownerIndex[data.OwnerUserId] == data then
		ownerIndex[data.OwnerUserId] = nil
		-- v12: сам факт "тележка в мире" читают клиент (предпросмотр
		-- упаковки, карточка магазина) и катсцена апгрейда — обновляем его
		-- в одной точке, через какой бы путь тележка ни исчезла.
		local owner = Players:GetPlayerByUserId(data.OwnerUserId)
		if owner and owner.Parent then
			owner:SetAttribute("CartDeployed", false)
		end
	end
	data.Model:Destroy()
end

return CartService
