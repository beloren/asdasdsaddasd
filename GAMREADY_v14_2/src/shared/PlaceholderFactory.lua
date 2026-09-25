--------------------------------------------------------------------------------
-- PlaceholderFactory
-- Единственное место, где создаются модели.
--
-- КОНТРАКТ ЗАМЕНЫ МОДЕЛЕЙ (без изменения кода):
-- Положи реальную модель в ReplicatedStorage/Assets с нужным именем —
-- фабрика будет клонировать её вместо плейсхолдера.
--
--   Crystal_Tier1..8   → BasePart (или Model с PrimaryPart/частью "Root" —
--                         любое содержимое внутри допустимо, см. CrystalUtil)
--   Cart_Tier1..10     → Model, обязателен PrimaryPart "Root" (пол тележки).
--                         Высота крепления к игроку — по умолчанию
--                         статичное число (Config.Cart.FollowOffset), но
--                         можно настроить САМОМУ: положи в модель Part
--                         "AttachPoint" и подвинь мышкой в Studio туда,
--                         где тележка должна "держаться" — её локальная
--                         высота относительно Root используется НАПРЯМУЮ,
--                         без вычислений (см. CartService:Attach).
--                         Разворот (какая сторона тележки обращена к
--                         игроку) — по умолчанию общий угол на все тиры
--                         (Config.Cart.HolderSideRotation), но тоже можно
--                         настроить ИМЕННО под эту модель: положи Part
--                         "FacingPoint" в направлении, которое должно
--                         "смотреть" на игрока — код сам разворачивает
--                         тележку на этот угол, ничего вычислять не нужно.
--                         Обе — чисто ориентиры, никогда не участвуют в
--                         физике. Необязательно: Part "Hitbox" — область,
--                         по которой реально можно попасть киркой по
--                         тележке (см. CombatService:findVictim); нет её —
--                         считается только центр Root. Необязательно:
--                         "LeftHandGrip"/"RightHandGrip" — точки, к которым
--                         "прилипают" руки игрока, пока держит тележку (см.
--                         CustomCartUI.client.lua); нет их — клиент сам бьёт
--                         лучом от плеча каждой руки в сторону тележки и
--                         берёт точку реального попадания по геометрии —
--                         работает "из коробки" даже без единого маркера.
--   Mine_Tier1..8      → Model, обязателен PrimaryPart (та часть, что должна
--                         касаться земли — см. PlotService:_buildMine, её
--                         нижний край подгоняется к полу участка автоматически)
--                         и Part "Zone" (зона парковки тележки).
--                         Необязательно: "OreDropPoint" — откуда руда
--                         визуально "падает" в тележку (см. MineService/
--                         CartService); нет её — код использует точку над
--                         Zone по умолчанию.
--   Pickaxe_Tier1..8   → Tool с Handle
--   Bank               → Model, обязательны "SellZone" и "Building".
--                         Необязательно: Part "MerchantSpot" — где стоит
--                         торговец (точка на ЗЕМЛЕ; старое имя "SlimeSpot"
--                         тоже читается); Part "SellTarget" — куда влетает
--                         проданная руда (нет — середина "Building").
--   BankMerchant       → Model торговца банка (см. Config.Merchant). Пивот —
--                         у ног, лицом по -Z (к покупателям). Необязательно:
--                         Part "PromptAnchor" (где висит кнопка "Shop") и
--                         Part "Head" (над ним вешается табло курса/таймера).
--   UpgradeShopNPC     → Model, обязателен PrimaryPart "Torso", часть "Head" с
--                         дочерним BillboardGui "gui" → TextLabel "name",
--                         "arrow", "dialog" (диалог в стиле Fisch/Grow a
--                         Garden — см. CustomCartUI.client.lua) — продавец
--                         прокачки, заменил три отдельных пьедестала
--   RebirthNPC         → Model, обязателен PrimaryPart "Torso" (на него вешается ProximityPrompt)
--   SprintVFX          → BasePart (или Model с PrimaryPart/частью "Root", как у
--                         Crystal — см. CrystalUtil) — партиклэмиттер уже должен
--                         лежать ВНУТРИ этой модели/части, код его не создаёт и
--                         не настраивает, только сам ставит деталь под ЗАДНЮЮ
--                         часть КАЖДОЙ тележки (любого тира, плейсхолдер или
--                         свой ассет), см. CartService. "Задняя" сторона
--                         определяется тем же маркером "FacingPoint" (зеркально)
--                         или явным своим маркером "SprintVFXPoint" внутри
--                         модели тележки, если он есть.
--   PlotTemplate       → Model, обязателен PrimaryPart "PlotPad" (пол участка) и
--                         маркеры-BasePart: "MineMarker", "PillarMarker",
--                         "CartSpawnMarker", "PlayerSpawnMarker", "RebirthMarker" —
--                         их CFrame (позиция И поворот) определяет, где именно на
--                         участке всё стоит. Клонируется один раз на каждый участок
--                         (см. PlotService), сам билдер расставляет маркеры как хочет.
--                         Поворот можно не крутить руками — деталь с тем же именем
--                         и суффиксом "Look" (например "MineMarkerLook") задаёт
--                         направление взгляда вместо вращения самого маркера.
--                         Необязательный "LeaderboardMarker" задаёт место блока
--                         глобальных досок (без него используется край PlotPad).
--   BankSellVFX        → BasePart ИЛИ Model (контракт как у SprintVFX) — на 2-3
--                         сек появляется НАД тележкой, которую только что
--                         полностью распродали (см. BankService), сам
--                         удаляется через Config.BankSellVfx.Duration.
--   Coin               → BasePart ИЛИ Model (контракт как у SprintVFX) — мини-
--                         монетка без коллизии, крутится на месте, потом
--                         улетает к игроку (тоже BankService).
--   PickaxeHitVFX      → BasePart ИЛИ Model (контракт как у SprintVFX) — разовая
--                         вспышка на месте удара киркой (см. CombatService),
--                         сам удаляется через Config.Combat.HitVfxDuration.
--   swing             → ParticleEmitter — один burst в центре игрока при
--                         каждом замахе; число частиц задаёт Attribute EmitCount.
--   RespawnButton      → BasePart ИЛИ Model (контракт как у SprintVFX) —
--                         физическая кнопка спавна новой тележки на участке
--                         (см. CartService:SetupRespawnButton). ProximityPrompt
--                         вешается на возвращённый Root и получает
--                         Style = Custom — тот же кастомный вид промпта, что
--                         и у "взять тележку" (см. CustomCartUI.client.lua,
--                         он реагирует на ЛЮБОЙ Custom-промпт в игре, отдельно
--                         ничего подключать не нужно).
--   LeaderboardBoards → Model с PrimaryPart и тремя BasePart:
--                         MoneyBoard, RebirthBoard, CartDamageBoard. Код сам
--                         создаёт SurfaceGui и клонирует модель на каждую базу.
--
-- ShieldVfx (см. PlaceholderFactory.ShieldVfx ниже) — VFX-точка щита,
-- висит приваренной над ГОЛОВОЙ ДЕРЖАТЕЛЯ (CombatService), а не отдельным ассетом
-- под конкретным NPC/тележкой — можно переопределить своей моделью так же,
-- как и остальные простые VFX (BankSellVFX, PickaxeHitVFX, Coin).
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей

-- Защита от рассинхрона (см. тот же приём в BuildUIAssets.lua/CustomCartUI.client.lua) —
-- если Config.lua ещё старой версии без Config.NpcBillboard, подставляем
-- те же значения по умолчанию, что заданы в самом Config.lua.
Config.NpcBillboard = Config.NpcBillboard or {}
Config.NpcBillboard.UpgradeShopNPC = Config.NpcBillboard.UpgradeShopNPC or { Height = 1.55, SizeWidth = 240, SizeHeight = 90 }
Config.NpcBillboard.ShopNPC = Config.NpcBillboard.ShopNPC or { Height = 1.55, SizeWidth = 240, SizeHeight = 90 }
Config.NpcBillboard.RebirthNPC = Config.NpcBillboard.RebirthNPC or { Height = 3, SizeWidth = 4.2, SizeHeight = 1.0 }

local PlaceholderFactory = {}

function PlaceholderFactory.ShiftNpcHats(npc, localZOffset)
	local pivot = npc:GetPivot()
	local delta = pivot:VectorToWorldSpace(Vector3.new(0, 0, localZOffset or 0))
	local parts = {}
	local seen = {}
	for _, descendant in npc:GetDescendants() do
		local lowerName = descendant.Name:lower()
		local isHatContainer = descendant:IsA("Accessory")
			or ((descendant:IsA("Model") or descendant:IsA("BasePart")) and lowerName:find("hat", 1, true) ~= nil)
		if isHatContainer then
			if descendant:IsA("BasePart") then
				if not seen[descendant] then seen[descendant] = true; table.insert(parts, descendant) end
			else
				for _, part in descendant:GetDescendants() do
					if part:IsA("BasePart") and not seen[part] then
						seen[part] = true
						table.insert(parts, part)
					end
				end
			end
		end
	end
	for _, part in parts do part.CFrame += delta end
end

-- Поиск идёт СНАЧАЛА среди прямых детей Assets (как было), и только потом
-- рекурсивно по всей папке. Раньше был только первый вариант, поэтому любой
-- ассет, положенный в подпапку (Assets/VFX/MutationVFX_Electric — как их
-- обычно и раскладывают, чтобы не превращать Assets в свалку), просто не
-- находился, и код молча уходил на плейсхолдер.
local function findAsset(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local asset = assets:FindFirstChild(name) or assets:FindFirstChild(name, true)
	return asset and asset:Clone() or nil
end

-- Достаёт именно Attachment из того, что лежит в Assets под нужным именем.
--
-- ЗАЧЕМ: раньше во всех VFX-функциях стоял жёсткий
--     assert(asset:IsA("Attachment"), "... must be an Attachment")
-- и это была главная причина "VFX не воспроизводятся". В Studio голый
-- Attachment неудобно копировать и перетаскивать, поэтому его почти всегда
-- заворачивают в Part/Model/Folder — и тогда assert БРОСАЛ ошибку. В
-- MutationVisuals вызов обёрнут в pcall, так что ошибка гасилась молча и
-- эффект просто не появлялся, без единой строчки в консоли.
--
-- Теперь принимается всё разумное:
--   • сам Attachment                     → берётся как есть
--   • Part/Model/Folder с Attachment'ом  → достаётся первый вложенный
--   • Part/Model с ParticleEmitter'ами
--     БЕЗ Attachment'а                   → эмиттеры переносятся в новый
--                                          Attachment (самый частый случай,
--                                          когда эффект собирали прямо на
--                                          детали)
local function extractVfxAttachment(asset, assetName)
	if not asset then return nil end
	if asset:IsA("Attachment") then
		return asset
	end

	local nested = asset:FindFirstChildWhichIsA("Attachment", true)
	if nested then
		nested.Parent = nil
		asset:Destroy()
		return nested
	end

	local emitters = {}
	for _, descendant in asset:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("PointLight")
			or descendant:IsA("SpotLight") or descendant:IsA("Beam") then
			table.insert(emitters, descendant)
		end
	end
	if #emitters > 0 then
		local attachment = Instance.new("Attachment")
		attachment.Name = assetName
		for _, emitter in emitters do
			emitter.Parent = attachment
		end
		asset:Destroy()
		return attachment
	end

	warn(("[PlaceholderFactory] ReplicatedStorage/Assets/%s найден, но внутри нет ни Attachment, ни ParticleEmitter — использую плейсхолдер. Положи туда Attachment с эмиттерами (или Part/Model, внутри которого они есть)."):format(assetName))
	asset:Destroy()
	return nil
end

-- Готовит клонированный VFX-Attachment к использованию: сбрасывает
-- позицию/ориентацию в ноль (иначе сохранённое в Studio мировое смещение
-- уносит частицы в сторону от кристалла) и, если попросили, включает
-- эмиттеры. resetPivot = false для эффектов, где смещение задумано автором.
local function prepareVfxAttachment(attachment, resetPivot)
	if not attachment then return nil end
	if resetPivot ~= false then
		attachment.CFrame = CFrame.new()
	end
	return attachment
end

local function newPart(props)
	local part = Instance.new("Part")
	if props.Shape then
		part.Shape = props.Shape -- Shape строго до Size
	end
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Shape" then
			part[key] = value
		end
	end
	return part
end

--------------------------------------------------------------------------------
-- КРИСТАЛЛ: Neon Cube. Тир = цвет + размер (богатство видно глазами).
--
-- Размер считается ОТНОСИТЕЛЬНО шага сетки тележки (Config.CartSlots.Cell),
-- а не фиксированным числом — раньше кристалл тира 8 (1.872 студ) был
-- физически КРУПНЕЕ самой ячейки (1.8 студ), гарантированно задевал соседей
-- в сетке (z-fighting/наложение текстур). Теперь верхняя граница диапазона
-- (MaxFactor) заведомо меньше клетки с запасом, плюс небольшой случайный
-- разброс на каждый экземпляр ("один чуть меньше, другой чуть больше") —
-- и даже в худшем случае (максимальный тир + максимальный разброс) кристалл
-- всё равно не достаёт до соседней ячейки.
--------------------------------------------------------------------------------
local CRYSTAL_MIN_STUDS = 0.85 -- тир 1
local CRYSTAL_MAX_STUDS = 1.45 -- тир 8 — с запасом меньше клетки (1.8), даже с разбросом ниже
local CRYSTAL_SIZE_VARIANCE = 0.08 -- ±8% случайно на КАЖДЫЙ кристалл — и плейсхолдер, и свой ассет

-- ±8% от текущего размера — единая точка правды для "разброса", чтобы
-- одинаковые кристаллы (плейсхолдер ИЛИ твой собственный ассет) в соседних
-- ячейках сетки тележки не были 100% идентичны и не мерцали текстурами при
-- точном совпадении граней друг с другом.
local function randomVarianceFactor()
	return 1 + (math.random() * 2 - 1) * CRYSTAL_SIZE_VARIANCE
end

local function crystalSize(tier)
	local info = Config.MineTiers[tier]
	local minInfoSize = Config.MineTiers[1].Size
	local maxInfoSize = Config.MineTiers[#Config.MineTiers].Size
	local t = (info.Size - minInfoSize) / (maxInfoSize - minInfoSize)
	local base = CRYSTAL_MIN_STUDS + t * (CRYSTAL_MAX_STUDS - CRYSTAL_MIN_STUDS)
	return base * randomVarianceFactor()
end

function PlaceholderFactory.Crystal(tier)
	-- Visual assets follow gameplay tiers directly: Tier 1 uses Crystal_Tier1,
	-- Tier 2 uses Crystal_Tier2, and so on through the available Tier 9.
	local asset = findAsset("Crystal_Tier" .. tier)
	if asset then
		-- Никогда не возвращаем исходник из ReplicatedStorage: каждый кристалл
		-- должен быть отдельным экземпляром. Для многочастных ассетов (особенно
		-- Tier 8) также фиксируем все части на одном Root, иначе при физическом
		-- спавне модель распадается и выглядит как набор отдельных фрагментов.
		asset = asset:Clone()
		-- Свой ассет — БАЗОВЫЙ размер трогать нельзя (билдер сам его выбрал,
		-- под свою сетку/масштаб), но лёгкий случайный разброс ±8% вокруг
		-- него всё равно применяем — Model:ScaleTo масштабирует ВСЮ модель
		-- целиком относительно размера "как было при вставке" (не копится
		-- от вызова к вызову), для одиночного Part — просто множим Size.
		local variance = randomVarianceFactor()
		if asset:IsA("Model") then
			local root = asset.PrimaryPart or asset:FindFirstChild("Root", true)
			if root and root:IsA("BasePart") then
				asset.PrimaryPart = root
				for _, descendant in asset:GetDescendants() do
					if descendant:IsA("BasePart") and descendant ~= root then
						descendant.Anchored = false
						descendant.Massless = true
						local weld = Instance.new("WeldConstraint")
						weld.Name = "CrystalRootWeld"
						weld.Part0 = root
						weld.Part1 = descendant
						weld.Parent = root
					end
				end
			end
			asset:ScaleTo(variance)
		elseif asset:IsA("BasePart") then
			asset.Size = asset.Size * variance
		end
		return asset
	end
	local info = Config.MineTiers[tier]
	return newPart({
		Name = "Crystal",
		Size = Vector3.one * crystalSize(tier), -- crystalSize уже включает свой ±8% разброс
		Color = info.Color,
		Material = Enum.Material.Neon,
		Anchored = false,
	})
end

-- НОВОЕ: конкретная руда из Config.OreChain (18 видов, см. Config.lua —
-- "РУДА v2"), а не просто "тир". Ищет билдерский ассет "Crystal_<Key>"
-- (например "Crystal_Iron", "Crystal_Singularity") — ИМЕННО так их нужно
-- называть в билдере/ReplicatedStorage.Assets, чтобы получить свою модель
-- на каждую руду вместо общего плейсхолдера. Никогда не возвращает
-- оригинал — всегда :Clone().
--
-- ВАЖНО (см. ТЗ "учитывай что это меши, мутацию так просто не сделать"):
-- если хочешь красить меши под мутации/редкость по маске, а не сплошным
-- цветом — используй SurfaceAppearance/MeshPart.TextureID с отдельной
-- ColorMap на мутацию, ПРОСТОЙ .Color на MeshPart игнорирует текстуру
-- целиком. Подробности и рабочий пример — см. src/shared/MutationVisuals.lua
-- (там уже решена ровно эта проблема для мутаций).
--------------------------------------------------------------------------------
-- v17: МУСОР (Config.Junk). Свой ассет — Assets.Junk_<Key> (сам ключ уже
-- начинается с "Junk_", то есть ищется ровно имя ключа). Иначе —
-- плейсхолдер из нескольких деталей: кость, осколки, камень, банка, утка.
-- Формат как у руды: Model с PrimaryPart "Root", остальное приварено.
--------------------------------------------------------------------------------
local function junkModel(oreInfo)
	local model = Instance.new("Model")
	model.Name = "Crystal"
	local function piece(name, shape, size, color, material, offset)
		local part = newPart({
			Name = name, Shape = shape, Size = size, Color = color,
			Material = material or Enum.Material.SmoothPlastic, Anchored = false,
		})
		part.CFrame = offset or CFrame.new()
		part.Parent = model
		return part
	end
	local key = oreInfo.Key
	local root
	if key == "Junk_DogBone" then
		local bone = Color3.fromRGB(240, 232, 210)
		root = piece("Root", Enum.PartType.Cylinder, Vector3.new(1.4, 0.32, 0.32), bone)
		for _, x in { -0.7, 0.7 } do
			for _, z in { -0.16, 0.16 } do
				piece("Knob", Enum.PartType.Ball, Vector3.new(0.42, 0.42, 0.42), bone, nil, CFrame.new(x, 0, z))
			end
		end
	elseif key == "Junk_AncientShards" then
		local clay = Color3.fromRGB(150, 175, 170)
		root = piece("Root", Enum.PartType.Block, Vector3.new(0.7, 0.18, 0.55), clay, Enum.Material.Slate)
		piece("Shard", Enum.PartType.Wedge, Vector3.new(0.18, 0.5, 0.45), clay:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Slate, CFrame.new(0.35, 0.2, 0.1) * CFrame.Angles(0, 0.6, 0.3))
		piece("Shard", Enum.PartType.Wedge, Vector3.new(0.16, 0.4, 0.5), Color3.fromRGB(190, 120, 80), Enum.Material.Slate, CFrame.new(-0.3, 0.16, -0.15) * CFrame.Angles(0.3, -0.8, 0))
	elseif key == "Junk_ColaCan" then
		root = piece("Root", Enum.PartType.Cylinder, Vector3.new(0.95, 0.55, 0.55), Color3.fromRGB(200, 30, 40), Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90)))
		piece("Lid", Enum.PartType.Cylinder, Vector3.new(0.06, 0.5, 0.5), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
		piece("Stripe", Enum.PartType.Cylinder, Vector3.new(0.2, 0.56, 0.56), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)))
	elseif key == "Junk_RubberDuck" then
		local yellow = Color3.fromRGB(255, 215, 40)
		root = piece("Root", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), yellow)
		piece("Head", Enum.PartType.Ball, Vector3.new(0.55, 0.55, 0.55), yellow, nil, CFrame.new(0, 0.5, -0.25))
		piece("Beak", Enum.PartType.Wedge, Vector3.new(0.3, 0.12, 0.25), Color3.fromRGB(255, 130, 30), nil, CFrame.new(0, 0.46, -0.6) * CFrame.Angles(0, math.pi, 0))
		for _, x in { -0.14, 0.14 } do
			piece("Eye", Enum.PartType.Ball, Vector3.new(0.09, 0.09, 0.09), Color3.fromRGB(20, 20, 20), nil, CFrame.new(x, 0.6, -0.48))
		end
		piece("Tail", Enum.PartType.Wedge, Vector3.new(0.3, 0.3, 0.25), yellow, nil, CFrame.new(0, 0.25, 0.45))
	else -- Junk_Rock и всё неизвестное
		root = piece("Root", Enum.PartType.Ball, Vector3.new(0.95, 0.75, 0.85), oreInfo.Color or Color3.fromRGB(125, 120, 115), Enum.Material.Slate)
		piece("Chip", Enum.PartType.Block, Vector3.new(0.45, 0.35, 0.4), (oreInfo.Color or Color3.fromRGB(125, 120, 115)):Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Slate, CFrame.new(0.3, 0.15, 0.1) * CFrame.Angles(0.4, 0.5, 0.2))
	end
	model.PrimaryPart = root
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Name = "CrystalRootWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
	return model
end

function PlaceholderFactory.Junk(oreInfo)
	local asset = findAsset(oreInfo.Key)
	if asset then
		if asset:IsA("Model") then
			local root = asset.PrimaryPart or asset:FindFirstChild("Root", true) or asset:FindFirstChildWhichIsA("BasePart", true)
			if root and root:IsA("BasePart") then
				asset.PrimaryPart = root
				for _, descendant in asset:GetDescendants() do
					if descendant:IsA("BasePart") and descendant ~= root then
						descendant.Anchored = false
						descendant.Massless = true
						local weld = Instance.new("WeldConstraint")
						weld.Name = "CrystalRootWeld"
						weld.Part0 = root
						weld.Part1 = descendant
						weld.Parent = root
					end
				end
			end
		end
		return asset
	end
	return junkModel(oreInfo)
end

function PlaceholderFactory.OreCrystal(oreInfo, variantInfo)
	if oreInfo and oreInfo.Junk then
		return PlaceholderFactory.Junk(oreInfo)
	end
	-- Сперва ищем ассет КОНКРЕТНОЙ вариации ("Crystal_Iron_V3", см.
	-- Config.OreVariants — "это всё будут меши в будущем"), и только если
	-- его нет — общий ассет руды ("Crystal_Iron"). Так можно добавлять
	-- меши вариаций по одному, не ломая руды, у которых их ещё нет.
	local asset = variantInfo and findAsset("Crystal_" .. oreInfo.Key .. "_V" .. tostring(variantInfo.Variant))
	if not asset then
		asset = findAsset("Crystal_" .. oreInfo.Key)
	end
	local variantScale = variantInfo and variantInfo.SizeScale or 1
	if asset then
		asset = asset:Clone()
		local variance = randomVarianceFactor() * variantScale
		if asset:IsA("Model") then
			local root = asset.PrimaryPart or asset:FindFirstChild("Root", true)
			if root and root:IsA("BasePart") then
				asset.PrimaryPart = root
				for _, descendant in asset:GetDescendants() do
					if descendant:IsA("BasePart") and descendant ~= root then
						descendant.Anchored = false
						descendant.Massless = true
						local weld = Instance.new("WeldConstraint")
						weld.Name = "CrystalRootWeld"
						weld.Part0 = root
						weld.Part1 = descendant
						weld.Parent = root
					end
				end
			end
			asset:ScaleTo(variance)
		elseif asset:IsA("BasePart") then
			asset.Size = asset.Size * variance
		end
		return asset
	end
	return newPart({
		Name = "Crystal",
		Size = Vector3.one * oreInfo.Size * variantScale * (0.92 + math.random() * 0.16),
		Color = oreInfo.Color,
		Material = Enum.Material.Neon,
		Anchored = false,
	})
end

-- СЛИТОК ИЗ ПЛАВИЛЬНИ (см. IslandService / Config.Islands.Smelter).
-- Ищет ассет "Ingot_<Key>" (своя модель слитка на конкретную руду), потом
-- общий "Ingot" (перекрашивается в цвет руды — детали с атрибутом
-- KeepColor = true не трогаются), иначе — плейсхолдер: металлический
-- брусок цвета руды. Формат результата тот же, что у OreCrystal (BasePart
-- или Model с PrimaryPart/Root, остальное приварено), поэтому слиток
-- ездит в тележке, лежит на земле и продаётся ровно как обычная руда.
local function weldToRoot(asset)
	local root = asset.PrimaryPart or asset:FindFirstChild("Root", true)
	if not (root and root:IsA("BasePart")) then return end
	asset.PrimaryPart = root
	for _, descendant in asset:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			descendant.Anchored = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Name = "CrystalRootWeld"
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = root
		end
	end
end

function PlaceholderFactory.OreIngot(oreInfo, variantInfo)
	local variantScale = variantInfo and variantInfo.SizeScale or 1
	local asset = findAsset("Ingot_" .. oreInfo.Key)
	local recolor = false
	if not asset then
		asset = findAsset("Ingot")
		recolor = asset ~= nil
	end
	if asset then
		local variance = randomVarianceFactor() * variantScale
		local function paint(part)
			if recolor and part:IsA("BasePart") and part:GetAttribute("KeepColor") ~= true then
				part.Color = oreInfo.Color
			end
		end
		if asset:IsA("Model") then
			for _, descendant in asset:GetDescendants() do paint(descendant) end
			weldToRoot(asset)
			asset:ScaleTo(variance)
		elseif asset:IsA("BasePart") then
			paint(asset)
			asset.Size = asset.Size * variance
		end
		return asset
	end
	local scale = (oreInfo.Size or 1) * variantScale * (0.95 + math.random() * 0.1)
	return newPart({
		Name = "Crystal",
		Size = Vector3.new(1.4, 0.55, 0.75) * scale,
		Color = oreInfo.Color:Lerp(Color3.new(1, 1, 1), 0.12),
		Material = Enum.Material.Foil,
		Reflectance = 0.15,
		Anchored = false,
	})
end

-- НПС ОСТРОВОВ в центре мира (см. IslandService). Свой ассет —
-- "IslandKeeperNPC" в Assets (Model с PrimaryPart), иначе плейсхолдер в
-- стиле ShopNPC, только другого цвета и с другой подписью.
function PlaceholderFactory.IslandKeeperNPC()
	local asset = findAsset("IslandKeeperNPC")
	if asset and asset:IsA("Model") and asset.PrimaryPart then
		return asset, true
	end
	if asset then asset:Destroy() end
	local model = PlaceholderFactory.ShopNPC()
	model.Name = "IslandKeeperNPC"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Torso" or part.Name == "Arm") then
			part.Color = Color3.fromRGB(70, 170, 120)
		end
	end
	local nameLabel = model:FindFirstChild("name", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = Config.Islands and Config.Islands.KeeperName or "Island Keeper"
		nameLabel.TextColor3 = Color3.fromRGB(140, 255, 190)
	end
	return model, false
end

-- СВОЙ МАКЕТ ОСТРОВА (имя — Config.Islands.Definitions[id].Model, по
-- умолчанию "Island_Anvil" и т.д.) — или nil, тогда остров строит
-- IslandService сам.
function PlaceholderFactory.Island(assetName)
	local asset = findAsset(tostring(assetName))
	if asset and asset:IsA("Model") and asset.PrimaryPart then
		return asset
	end
	if asset then
		warn(("[PlaceholderFactory] Assets/%s должен быть Model с назначенным PrimaryPart — строю остров-плейсхолдер."):format(tostring(assetName)))
		asset:Destroy()
	end
	return nil
end

-- СВОЯ МОДЕЛЬ ПЛАВИЛЬНИ ("Smelter") — или nil (плейсхолдер строит IslandService).
-- Свой вид на каждый уровень — "Smelter_Level<N>", иначе общий "Smelter".
function PlaceholderFactory.Smelter(level)
	local asset = (level and findAsset("Smelter_Level" .. tostring(level))) or findAsset("Smelter")
	if asset and asset:IsA("Model") and (asset.PrimaryPart or asset:FindFirstChild("Root", true)) then
		asset.PrimaryPart = asset.PrimaryPart or asset:FindFirstChild("Root", true)
		return asset
	end
	if asset then asset:Destroy() end
	return nil
end

function PlaceholderFactory.Geode(geodeType)
	local asset = findAsset("Geode_" .. geodeType)
	if asset then
		assert(asset:IsA("BasePart") or asset:IsA("Model"), "Geode asset must be a BasePart or Model")
		if asset:IsA("Model") then assert(asset.PrimaryPart or asset:FindFirstChild("Root", true), "Geode model requires PrimaryPart or Root") end
		return asset
	end
	local info = Config.Geodes.Types[geodeType] or Config.Geodes.Types.Stone
	local geode = newPart({
		Name = "Geode_" .. geodeType,
		Size = Vector3.new(1.65, 1.65, 1.65),
		Color = info.Color,
		Material = Enum.Material.Slate,
		Anchored = false,
	})
	local light = Instance.new("PointLight")
	light.Color = info.Color
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = geode
	return geode
end

-- Burst shown when a geode is first added to a mining cart. Replace the
-- `GeodeCartVFX` asset without changing the service that triggers it.
function PlaceholderFactory.GeodeCartVFX()
	local asset = findAsset("GeodeCartVFX")
	if asset then
		if asset:IsA("BasePart") then return asset, asset end
		local root = asset:IsA("Model") and (asset.PrimaryPart or asset:FindFirstChild("Root"))
		assert(root, "GeodeCartVFX must be a BasePart or Model with PrimaryPart/Root")
		return asset, root
	end
	local part = newPart({
		Name = "GeodeCartVFX",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
	})
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "PlaceholderGeodeCartBurst"
	burst.Color = ColorSequence.new(Color3.fromRGB(95, 210, 255), Color3.fromRGB(255, 255, 255))
	burst.LightEmission = 1
	burst.Lifetime = NumberRange.new(0.55, 1.1)
	burst.Speed = NumberRange.new(4, 9)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Acceleration = Vector3.new(0, 4, 0)
	burst.Rate = 0
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Parent = part
	return part, part
end

function PlaceholderFactory.CollectionOre(oreId)
	local asset = findAsset("CollectionOre_" .. oreId)
	if asset then
		assert(asset:IsA("BasePart") or asset:IsA("Model"), "Collection ore asset must be a BasePart or Model")
		if asset:IsA("Model") then
			local root = asset.PrimaryPart or asset:FindFirstChild("Root", true)
			assert(root and root:IsA("BasePart"), "Collection ore model requires a BasePart PrimaryPart or Root")
			-- Normalize imported assets so every consumer uses the same pivot/root,
			-- including models such as CollectionOre_Eclipse with nested Root parts.
			asset.PrimaryPart = root
		end
		return asset
	end
	local info = Config.Geodes.Ores[oreId] or Config.Geodes.Ores.Quartz
	return newPart({
		Name = "CollectionOre_" .. oreId,
		Size = Vector3.new(2.3, 3.6, 2.3),
		Color = info.Color,
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
	})
end

function PlaceholderFactory.GeodeBuilding()
	local asset = findAsset("GeodeBuilding")
	if asset then
		assert(asset:IsA("Model") and (asset.PrimaryPart or asset:FindFirstChild("Root", true)), "GeodeBuilding must be a Model with PrimaryPart or Root")
		assert(asset:FindFirstChild("Crusher", true) and asset:FindFirstChild("Crusher", true):IsA("BasePart"), "GeodeBuilding requires a Crusher BasePart")
		return asset
	end
	return nil
end

function PlaceholderFactory.GeodePodium()
	local asset = findAsset("GeodePodium")
	if asset then
		assert(asset:IsA("BasePart") or (asset:IsA("Model") and (asset.PrimaryPart or asset:FindFirstChild("Root", true))), "GeodePodium must be a BasePart or Model with PrimaryPart/Root")
		return asset
	end
	return nil
end

function PlaceholderFactory.GeodeSafe()
	local asset = findAsset("GeodeSafe")
	if asset then
		assert(asset:IsA("BasePart") or (asset:IsA("Model") and (asset.PrimaryPart or asset:FindFirstChild("Root", true))), "GeodeSafe must be a BasePart or Model with PrimaryPart/Root")
		return asset
	end
	return nil
end

--------------------------------------------------------------------------------
-- ТЕЛЕЖКА: Model из кубов. Размер пола выводится из сетки слотов.
--------------------------------------------------------------------------------
function PlaceholderFactory.Cart(tier)
	local asset = findAsset("Cart_Tier" .. tier)
	if asset then
		return asset
	end

	local slots = Config.CartSlots
	local innerX = slots.Cols * slots.Cell
	local innerZ = slots.Rows * slots.Cell
	local wallHeight = 1.4

	local model = Instance.new("Model")
	model.Name = "Cart"

	local root = newPart({
		Name = "Root",
		Size = Vector3.new(innerX + 1, 0.6, innerZ + 1),
		Color = Color3.fromRGB(96, 72, 48),
		Anchored = false,
	})
	root.CFrame = CFrame.new()
	root:SetAttribute("DailyColorable", true)
	root.Parent = model
	model.PrimaryPart = root

	local function attachPart(part, offset)
		if part.Name == "Wall" then part:SetAttribute("DailyColorable", true) end
		part.Anchored = false
		part.CFrame = root.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end

	local wallColor = Color3.fromRGB(122, 92, 62)
	local wallY = 0.3 + wallHeight / 2

	for _, zSign in { -1, 1 } do
		attachPart(
			newPart({ Name = "Wall", Size = Vector3.new(innerX + 1, wallHeight, 0.35), Color = wallColor }),
			CFrame.new(0, wallY, zSign * (innerZ / 2 + 0.35))
		)
	end
	for _, xSign in { -1, 1 } do
		attachPart(
			newPart({ Name = "Wall", Size = Vector3.new(0.35, wallHeight, innerZ + 1), Color = wallColor }),
			CFrame.new(xSign * (innerX / 2 + 0.35), wallY, 0)
		)
	end

	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			attachPart(
				newPart({
					Name = "Wheel",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.4, 1.4, 1.4),
					Color = Color3.fromRGB(40, 40, 40),
					CanCollide = false,
				}),
				CFrame.new(xSign * (innerX / 2 + 0.7), -0.1, zSign * (innerZ / 2 - 0.6))
			)
		end
	end

	-- LeftHandGrip/RightHandGrip — маркеры хвата рук (см.
	-- CustomCartUI.client.lua) — на ближней к игроку стороне (та же, что
	-- определяет FacingPoint/дефолт HolderSideRotation — локальный -X при
	-- 90°, см. CartService:Attach). В своём ассете Cart_TierN можно положить
	-- одноимённые Part куда угодно — эти дефолтные только для плейсхолдера.
	local gripY = wallY + 0.35
	for _, side in { { Name = "LeftHandGrip", Z = -0.9 }, { Name = "RightHandGrip", Z = 0.9 } } do
		attachPart(
			newPart({ Name = side.Name, Size = Vector3.new(0.3, 0.3, 0.3), Transparency = 1, CanCollide = false }),
			CFrame.new(-(innerX / 2 + 0.5), gripY, side.Z)
		)
	end

	return model
end

--------------------------------------------------------------------------------
-- УПАКОВКА ТЕЛЕЖКИ (v12) — то, что игрок получает при покупке/апгрейде
-- тележки и носит НАД ГОЛОВОЙ, как руду, пока не поставит (см.
-- CartService/CartPlacement.client.lua).
--
-- КОНТРАКТ ЗАМЕНЫ МОДЕЛИ (ничего в коде менять не нужно):
--   CartPackage_Tier1..9 → своя коробка ИМЕННО под этот тир (необязательно);
--   CartPackage          → одна общая коробка на все тиры;
--   нет ни того, ни другого → код строит картонный ящик-плейсхолдер ниже.
-- Формат — как у Crystal: голый BasePart ЛИБО Model с PrimaryPart/деталью
-- "Root". Всё внутри (наклейки, верёвки, партиклы) сохраняется как есть.
--------------------------------------------------------------------------------
function PlaceholderFactory.CartPackage(tier)
	local asset = findAsset("CartPackage_Tier" .. tostring(tier)) or findAsset("CartPackage")
	if asset then
		return asset
	end

	local model = Instance.new("Model")
	model.Name = "CartPackage"

	local root = newPart({
		Name = "Root",
		Size = Vector3.new(2.2, 2.0, 2.2),
		Color = Color3.fromRGB(168, 124, 78),
		Material = Enum.Material.Wood,
	})
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	-- Две «ленты» крест-накрест: коробка читается как упаковка, а не как
	-- просто ящик, даже на маленьком размере над головой.
	local function strap(sizeVector, offset)
		local part = newPart({
			Name = "Strap",
			Size = sizeVector,
			Color = Color3.fromRGB(228, 196, 130),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		part.CFrame = root.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
		return part
	end
	strap(Vector3.new(0.35, 2.06, 2.26), CFrame.new())
	strap(Vector3.new(2.26, 2.06, 0.35), CFrame.new())

	return model
end

--------------------------------------------------------------------------------
-- SPRINT VFX: деталь под задней частью тележки. Партиклэмиттер уже лежит
-- ВНУТРИ самого ассета "SprintVFX" — код его не создаёт и не настраивает,
-- только ставит деталь на место (см. CartService). Фолбэк-плейсхолдер (пока
-- своего ассета нет) — со своим простым эмиттером, чтобы не было пусто.
-- Поддерживает тот же контракт, что и Crystal: голый BasePart ИЛИ Model с
-- PrimaryPart/частью "Root".
--------------------------------------------------------------------------------
function PlaceholderFactory.SprintVFX()
	local asset = findAsset("SprintVFX")
	if asset then
		if asset:IsA("BasePart") then
			return asset
		end
		local root = asset.PrimaryPart or asset:FindFirstChild("Root")
		assert(root, "SprintVFX-Model обязан иметь PrimaryPart/часть 'Root': " .. asset:GetFullName())
		return asset, root -- Model возвращается целиком (Parent = model тележки), root — точка крепления/партикла
	end

	local part = newPart({
		Name = "SprintVFX",
		Size = Vector3.new(0.6, 0.6, 0.6),
		Transparency = 1, -- сам плейсхолдер невидим — виден только партикл на нём
		Anchored = false,
		CanCollide = false,
	})

	local placeholderParticle = Instance.new("ParticleEmitter")
	placeholderParticle.Name = "PlaceholderSprintParticle" -- временно, до реального ассета SprintVFX — см. комментарий выше
	placeholderParticle.Color = ColorSequence.new(Color3.fromRGB(210, 195, 170))
	placeholderParticle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	placeholderParticle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1.6),
	})
	placeholderParticle.Lifetime = NumberRange.new(0.35, 0.6)
	placeholderParticle.Speed = NumberRange.new(1, 2.5)
	placeholderParticle.SpreadAngle = Vector2.new(35, 35)
	placeholderParticle.Rate = 24
	placeholderParticle.LightEmission = 0
	placeholderParticle.Parent = part

	return part
end

-- Общий резолвер для простых "BasePart ИЛИ Model с PrimaryPart/'Root'"
-- ассетов (тот же контракт, что у SprintVFX/Crystal) — чтобы не повторять
-- одну и ту же проверку в каждой из фабрик ниже. buildPlaceholder вызывается,
-- только если своего ассета с именем `name` нет — САМ плейсхолдер тоже может
-- вернуть либо голый BasePart, либо Model (см. RespawnButton ниже).
local function resolveSimpleAsset(name, buildPlaceholder)
	local asset = findAsset(name)
	if not asset then
		asset = buildPlaceholder()
	end
	if asset:IsA("BasePart") then
		return asset, asset
	end
	local root = asset.PrimaryPart or asset:FindFirstChild("Root")
	assert(root, name .. " (Model) обязан иметь PrimaryPart/часть 'Root': " .. asset:GetFullName())
	return asset, root
end

--------------------------------------------------------------------------------
-- BANK SELL VFX: разовая вспышка над тележкой, которую только что полностью
-- распродали (см. BankService) — плейсхолдер сам себя удаляет не отсюда,
-- вызывающий код (BankService) ставит Debris по Config.BankSellVfx.Duration.
--------------------------------------------------------------------------------
function PlaceholderFactory.BankSellVFX()
	return resolveSimpleAsset("BankSellVFX", function()
		local part = newPart({
			Name = "BankSellVFX",
			Size = Vector3.new(0.5, 0.5, 0.5),
			Transparency = 1,
			Anchored = true,
			CanCollide = false,
		})
		local burst = Instance.new("ParticleEmitter")
		burst.Name = "PlaceholderSellBurst" -- временно, до реального ассета BankSellVFX
		burst.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 255, 210))
		burst.LightEmission = 1
		burst.Lifetime = NumberRange.new(0.6, 1.1)
		burst.Speed = NumberRange.new(4, 9)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Acceleration = Vector3.new(0, 6, 0)
		burst.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(1, 0),
		})
		burst.Rate = 0
		burst.Parent = part
		burst:Emit(30)
		return part
	end)
end

--------------------------------------------------------------------------------
-- ЩИТ VFX: висит приваренным НАД ГОЛОВОЙ ДЕРЖАТЕЛЯ (высота — Config.
-- Protection.VfxHeight), включается/выключается вместе с реальной защитой
-- держателя (Config.Protection/CombatService). Контракт как у остальных
-- простых VFX (resolveSimpleAsset выше) — своя "ShieldVfx" (Part ИЛИ Model с
-- PrimaryPart/"Root") в Assets перекрывает плейсхолдер целиком.
--
-- Что внутри — не важно: CombatService включает/выключает ВСЕ ParticleEmitter,
-- какие найдёт внутри модели, рекурсивно. Хочешь конкретную точку эмиссии —
-- добавь Attachment и посади партикл на него (как в плейсхолдере ниже), не
-- обязательно — можно и просто на саму часть.
--------------------------------------------------------------------------------
function PlaceholderFactory.ShieldVfx()
	return resolveSimpleAsset("ShieldVfx", function()
		local part = newPart({
			Name = "ShieldVfx",
			Size = Vector3.new(0.5, 0.5, 0.5),
			Transparency = 1,
			Anchored = false, -- КРИТИЧНО: приваривается WeldConstraint к тележке (см. CartService) — Anchored=true заморозило бы всю тележку целиком
			CanCollide = false,
			CanQuery = false,
		})

		local attachment = Instance.new("Attachment")
		attachment.Name = "ShieldVfxAttachment"
		attachment.Parent = part

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "PlaceholderShieldSparkle" -- временно, до реального ассета ShieldVfx
		sparkle.Color = ColorSequence.new(Config.Protection.Color)
		sparkle.LightEmission = 1
		sparkle.Lifetime = NumberRange.new(0.7, 1.3)
		sparkle.Speed = NumberRange.new(1.5, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 20
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Enabled = false -- вкл/выкл вместе со щитом, см. CartService:_setShieldVisible
		sparkle.Parent = attachment

		return part
	end)
end


--------------------------------------------------------------------------------
-- ЩИТ VFX (VIP) — тот же контракт, что и ShieldVfx выше, но отдельный
-- ассет/плейсхолдер для владельцев геймпасса GoldenShield (Config.GamePasses.
-- GoldenShield): свой ассет `ShieldVfxVIP` в ReplicatedStorage/Assets — тем
-- же PrimaryPart/"Root"-контрактом — перекрывает золотой плейсхолдер ниже,
-- ничего в коде трогать не нужно. См. CombatService — выбирает эту фабрику
-- вместо обычной ShieldVfx для владельцев пасса.
--------------------------------------------------------------------------------
function PlaceholderFactory.ShieldVfxVIP()
	return resolveSimpleAsset("ShieldVfxVIP", function()
		local part = newPart({
			Name = "ShieldVfxVIP",
			Size = Vector3.new(0.5, 0.5, 0.5),
			Transparency = 1,
			Anchored = false, -- см. предупреждение в ShieldVfx выше — тот же принцип
			CanCollide = false,
			CanQuery = false,
		})

		local attachment = Instance.new("Attachment")
		attachment.Name = "ShieldVfxVIPAttachment"
		attachment.Parent = part

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "PlaceholderShieldSparkleVIP" -- временно, до реального ассета ShieldVfxVIP
		sparkle.Color = ColorSequence.new(Config.GamePasses.CartGuard.OutlineColor)
		sparkle.LightEmission = 1
		sparkle.Lifetime = NumberRange.new(0.8, 1.5)
		sparkle.Speed = NumberRange.new(2, 4)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 28 -- чуть плотнее обычного щита — заметно "богаче"
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Enabled = false -- вкл/выкл вместе со щитом, см. CombatService
		sparkle.Parent = attachment

		return part
	end)
end


function PlaceholderFactory.Coin()
	-- Денежный лут должен сохранять квадратную форму независимо от Coin-ассета
	-- в Studio, поэтому для сундуков и валунов создаётся фиксированная деталь.
	return newPart({
		Name = "Coin",
		Shape = Enum.PartType.Block,
		Size = Config.CoinFx.CoinSize,
		Color = Config.CoinFx.CoinColor,
		Material = Enum.Material.Neon,
		Anchored = false,
		CanCollide = false,
	})
end

--------------------------------------------------------------------------------
-- LOOT BOX: коробка, которая ВИЗУАЛЬНО выпадает из валуна/сундука, когда
-- награду нельзя показать предметом (скин и всё в этом духе — то, что
-- существует только в инвентаре). Падает по дуге на землю, подпрыгивает и
-- влетает в игрока — см. GoblinService:spawnChestLoot.
--
-- ЭТО ПЛЕЙСХОЛДЕР — заменяется своей моделью БЕЗ ЕДИНОЙ ПРАВКИ КОДА:
-- положи Model (или BasePart) в ReplicatedStorage/Assets с именем
-- "LootBox". Для Model желательно задать PrimaryPart (или деталь с именем
-- "Root") — за неё код берёт коробку при полёте; если ни того, ни другого
-- нет, будет взята первая попавшаяся BasePart, что тоже работает, просто
-- центр вращения окажется случайным.
--
-- Прежние имена "Box"/"box" тоже принимаются — тот ассет уже искался в
-- GoblinService, и ломать существующие сборки незачем.
--
-- Размер трогать не нужно: код сам масштабирует коробку по её собственным
-- габаритам (см. LOOT_BOX_TARGET_STUDS в GoblinService).
--------------------------------------------------------------------------------
function PlaceholderFactory.LootBox()
	local asset = findAsset("LootBox") or findAsset("Box") or findAsset("box")
	if asset and (asset:IsA("Model") or asset:IsA("BasePart")) then
		asset.Name = "LootBox"
		return asset
	end
	if asset then
		-- Ассет есть, но это не Model/BasePart (например, Folder) —
		-- предупреждаем и уходим на плейсхолдер, а не падаем.
		warn("[PlaceholderFactory] ReplicatedStorage.Assets.LootBox должен быть Model или BasePart — использую плейсхолдер.")
		asset:Destroy()
	end

	local box = Instance.new("Model")
	box.Name = "LootBox"

	local crate = newPart({
		Name = "Root",
		Shape = Enum.PartType.Block,
		Size = Vector3.new(1.6, 1.4, 1.6),
		Color = Color3.fromRGB(150, 100, 55),
		Material = Enum.Material.WoodPlanks,
		Anchored = false,
		CanCollide = false,
	})
	crate.Parent = box
	box.PrimaryPart = crate

	-- Крышка и две перекрещенные ленты — чтобы плейсхолдер читался именно
	-- как "коробка с наградой", а не как безымянный ящик. Всё приварено к
	-- Root: код двигает коробку целиком через PivotTo, но сварка нужна на
	-- случай, если модель когда-нибудь окажется не Anchored.
	for _, spec in {
		{ Name = "Lid", Size = Vector3.new(1.74, 0.22, 1.74), Offset = Vector3.new(0, 0.78, 0), Color = Color3.fromRGB(120, 78, 42), Material = Enum.Material.WoodPlanks },
		{ Name = "RibbonX", Size = Vector3.new(1.7, 1.5, 0.26), Offset = Vector3.new(0, 0.05, 0), Color = Color3.fromRGB(240, 200, 80), Material = Enum.Material.SmoothPlastic },
		{ Name = "RibbonZ", Size = Vector3.new(0.26, 1.5, 1.7), Offset = Vector3.new(0, 0.05, 0), Color = Color3.fromRGB(240, 200, 80), Material = Enum.Material.SmoothPlastic },
	} do
		local piece = newPart({
			Name = spec.Name,
			Shape = Enum.PartType.Block,
			Size = spec.Size,
			Color = spec.Color,
			Material = spec.Material,
			Anchored = false,
			CanCollide = false,
		})
		piece.CFrame = crate.CFrame + spec.Offset
		piece.Parent = box
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = crate
		weld.Part1 = piece
		weld.Parent = piece
	end

	return box
end

--------------------------------------------------------------------------------
-- PICKAXE HIT VFX: разовая вспышка на месте удара киркой (см. CombatService) —
-- вызывающий код ставит Debris по Config.Combat.HitVfxDuration.
--------------------------------------------------------------------------------
function PlaceholderFactory.PickaxeHitVFX()
	local asset = extractVfxAttachment(findAsset("PickaxeHitVFX"), "PickaxeHitVFX")
	if asset then
		return prepareVfxAttachment(asset)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PickaxeHitVFX"
	for _, config in {
		{ Name = "PlaceholderSpark", Texture = "rbxasset://textures/particles/sparkles_main.dds", Count = 18, Speed = NumberRange.new(14, 26), Lifetime = NumberRange.new(0.25, 0.5), Size = NumberSequence.new(0.9, 0) },
		{ Name = "PlaceholderFlash", Texture = "rbxasset://textures/particles/smoke_main.dds", Count = 8, Speed = NumberRange.new(3, 8), Lifetime = NumberRange.new(0.12, 0.25), Size = NumberSequence.new(0.5, 0) },
	} do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = config.Name
		emitter.Texture = config.Texture
		emitter.LightEmission = 1
		emitter.Lifetime = config.Lifetime
		emitter.Speed = config.Speed
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -40, 0)
		emitter.Size = config.Size
		emitter.Rate = 0
		emitter:SetAttribute("EmitCount", config.Count)
		emitter.Parent = attachment
	end
	return attachment
end

-- VFX МУТАЦИЙ (искры, капли, ореол — см. Config.Mutations, Visual =
-- "Particles"). Каждая мутация со своим VfxName получает СВОЙ отдельный
-- плейсхолдер, который заменяется независимо от остальных: положи Attachment
-- с именем MutationVFX_<VfxName> в ReplicatedStorage/Assets — например
-- MutationVFX_Toxic, MutationVFX_Electric, MutationVFX_Eclipsed — и код
-- возьмёт его вместо заготовки. Код только клонирует Attachment и красит
-- эмиттеры в цвет мутации, так что своей версии ничего знать про него не
-- нужно: любые эмиттеры внутри просто заработают.
--
-- ВАЖНО про производительность: в тележке T10 помещается 225 кристаллов, и
-- эмиттеры здесь работают непрерывно (Rate, а не Emit). Поэтому Rate у
-- заготовок держится низким — по несколько частиц в секунду. Если будешь
-- делать свои, помни, что их может оказаться пара десятков в одной тележке.
local MUTATION_VFX_PRESETS = {
	Toxic = {
		{ Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 5, Speed = NumberRange.new(0.4, 1.2),
		  Lifetime = NumberRange.new(0.7, 1.2), Size = NumberSequence.new(0.35, 0), Acceleration = Vector3.new(0, -14, 0),
		  SpreadAngle = Vector2.new(25, 25), LightEmission = 0.4 },
	},
	Electric = {
		{ Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 8, Speed = NumberRange.new(2, 5),
		  Lifetime = NumberRange.new(0.15, 0.35), Size = NumberSequence.new(0.3, 0), Acceleration = Vector3.new(0, 0, 0),
		  SpreadAngle = Vector2.new(180, 180), LightEmission = 1 },
	},
	Eclipsed = {
		{ Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 4, Speed = NumberRange.new(0.2, 0.8),
		  Lifetime = NumberRange.new(1.1, 1.8), Size = NumberSequence.new(0.6, 1.4), Acceleration = Vector3.new(0, 1.5, 0),
		  SpreadAngle = Vector2.new(180, 180), LightEmission = 0 },
	},
}

function PlaceholderFactory.MutationVfx(vfxName)
	local assetName = "MutationVFX_" .. tostring(vfxName)
	-- Имя ищется в нескольких написаниях: игроки кладут ассеты и как
	-- MutationVFX_Electric (по гайду), и как MutationVfx_Electric, и просто
	-- Electric — раньше подходило только первое.
	local asset = extractVfxAttachment(
		findAsset(assetName)
			or findAsset("MutationVfx_" .. tostring(vfxName))
			or findAsset("MutationVFX" .. tostring(vfxName))
			or findAsset(tostring(vfxName)),
		assetName
	)
	if asset then
		return prepareVfxAttachment(asset)
	end
	local preset = MUTATION_VFX_PRESETS[vfxName]
	if not preset then return nil end

	local attachment = Instance.new("Attachment")
	attachment.Name = assetName
	for index, config in preset do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = ("Placeholder%d"):format(index)
		emitter.Texture = config.Texture
		emitter.Rate = config.Rate
		emitter.Speed = config.Speed
		emitter.Lifetime = config.Lifetime
		emitter.Size = config.Size
		emitter.Acceleration = config.Acceleration
		emitter.SpreadAngle = config.SpreadAngle
		emitter.LightEmission = config.LightEmission
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Parent = attachment
	end
	return attachment
end

-- ВОСКЛИЦАТЕЛЬНЫЙ ЗНАК НАД ЦЕЛЬЮ КВЕСТА (см. QuestMarker.client.lua).
-- Контракт тот же, что у остального: положи Model с именем "QuestMarker" в
-- ReplicatedStorage/Assets — код возьмёт её вместо плейсхолдера. Своей
-- модели ничего знать про код не нужно, её просто крутят и покачивают
-- целиком, поэтому подойдёт любая (хоть стрелка, хоть звезда).
--
-- Плейсхолдер — классический "!": столбик и точка под ним. Обе детали
-- Anchored + CanCollide=false + CanQuery=false: знак ЧИСТО декоративный, он
-- не должен ни на что натыкаться, ловить лучи прицела или мешать кликам по
-- объекту, над которым висит.
function PlaceholderFactory.QuestMarker()
	local asset = findAsset("QuestMarker")
	if asset then
		assert(asset:IsA("Model"), "ReplicatedStorage/Assets/QuestMarker must be a Model")
		return asset:Clone(), true -- true = свой ассет, цвет ЕГО, не трогать (см. QuestMarker.client.lua)
	end

	local model = Instance.new("Model")
	model.Name = "QuestMarker"

	local function piece(name, size, offset)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Shape = Enum.PartType.Block
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 215, 90)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(offset)
		part.Parent = model
		return part
	end

	local stem = piece("Stem", Vector3.new(0.45, 1.6, 0.45), Vector3.new(0, 0.55, 0))
	piece("Dot", Vector3.new(0.45, 0.45, 0.45), Vector3.new(0, -0.55, 0))
	model.PrimaryPart = stem
	return model, false -- false = плейсхолдер, можно красить под Config.QuestMarker.Color
end

-- BOULDER BREAK VFX: Attachment с ParticleEmitter'ами — разовая вспышка в
-- центре валуна в момент, когда он лопается (см. RockService:Break).
-- Контракт ровно такой же, как у PickaxeHitVFX выше: положи свой Attachment
-- `BoulderBreakVFX` в ReplicatedStorage/Assets, код сам перекрасит эмиттеры
-- в цвет тира и вызовет Emit по числу из атрибута EmitCount. Плейсхолдер —
-- каменная крошка (тяжёлая, с гравитацией, летит наружу) плюс облако пыли,
-- которое всплывает и тает.
function PlaceholderFactory.BoulderBreakVFX()
	local asset = extractVfxAttachment(
		findAsset("BoulderBreakVFX") or findAsset("BoulderBreakVfx"),
		"BoulderBreakVFX"
	)
	if asset then
		return prepareVfxAttachment(asset)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "BoulderBreakVFX"
	for _, config in {
		{ Name = "PlaceholderRubble", Texture = "rbxasset://textures/particles/sparkles_main.dds", Count = 26, Speed = NumberRange.new(18, 34), Lifetime = NumberRange.new(0.45, 0.8), Size = NumberSequence.new(1.4, 0), Acceleration = Vector3.new(0, -90, 0), LightEmission = 0 },
		{ Name = "PlaceholderDust", Texture = "rbxasset://textures/particles/smoke_main.dds", Count = 16, Speed = NumberRange.new(4, 11), Lifetime = NumberRange.new(0.5, 0.95), Size = NumberSequence.new(2.2, 5), Acceleration = Vector3.new(0, 6, 0), LightEmission = 0.2 },
	} do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = config.Name
		emitter.Texture = config.Texture
		emitter.LightEmission = config.LightEmission
		emitter.Lifetime = config.Lifetime
		emitter.Speed = config.Speed
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = config.Acceleration
		emitter.Size = config.Size
		emitter.Rate = 0
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter:SetAttribute("EmitCount", config.Count)
		emitter.Parent = attachment
	end
	return attachment
end

-- PICKAXE SWING VFX: Attachment с любым количеством ParticleEmitter внутри.
-- Положи Attachment `swing` в ReplicatedStorage/Assets. CombatService
-- клонирует его в центр HumanoidRootPart, перекрашивает эмиттеры цветом тира
-- и вызывает Emit у каждого.
function PlaceholderFactory.PickaxeSwingVFX()
	local asset = extractVfxAttachment(findAsset("swing") or findAsset("Swing"), "swing")
	if asset then
		return prepareVfxAttachment(asset)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "swing"
	for _, config in {
		{ Name = "PlaceholderSwingSpark", Texture = "rbxasset://textures/particles/sparkles_main.dds", Count = 14 },
		{ Name = "PlaceholderSwingFlash", Texture = "rbxasset://textures/particles/smoke_main.dds", Count = 5 },
	} do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = config.Name
		emitter.Texture = config.Texture
		emitter.Lifetime = NumberRange.new(0.18, 0.38)
		emitter.Speed = NumberRange.new(5, 14)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 0
		emitter:SetAttribute("EmitCount", config.Count)
		emitter.Parent = attachment
	end
	return attachment
end

--------------------------------------------------------------------------------
-- RESPAWN BUTTON: физическая кнопка спавна новой тележки на участке (см.
-- CartService:SetupRespawnButton). Контракт как у SprintVFX — плейсхолдер
-- строит классическую "нажимную" кнопку (Base+Cap), т.к. код умеет анимировать
-- её вдавливание используя ЛЮБОЙ возвращённый Root (генерик по CFrame).
--------------------------------------------------------------------------------
function PlaceholderFactory.RespawnButton()
	return resolveSimpleAsset("RespawnButton", function()
		local READY_HEIGHT = 0.5
		local model = Instance.new("Model")
		model.Name = "RespawnButton"

		local base = newPart({
			Name = "Base",
			Size = Vector3.new(3, 1, 3),
			Color = Color3.fromRGB(60, 60, 68),
			Material = Enum.Material.Metal,
			CanCollide = true,
		})
		base.CFrame = CFrame.new(0, 0, 0)
		base.Parent = model

		local cap = newPart({
			Name = "Cap",
			Size = Vector3.new(2.2, READY_HEIGHT, 2.2),
			Color = Color3.fromRGB(90, 200, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		cap.CFrame = base.CFrame * CFrame.new(0, base.Size.Y / 2 + READY_HEIGHT / 2, 0)
		cap.Parent = model

		model.PrimaryPart = cap
		return model
	end)
end

function PlaceholderFactory.Mine(tier)
	local asset = findAsset("Mine_Tier" .. tier)
	if asset then
		return asset
	end
	local info = Config.MineTiers[tier]

	local model = Instance.new("Model")
	model.Name = "Mine"

	local body = newPart({
		Name = "Body",
		Size = Vector3.new(10, 8, 6),
		Color = Color3.fromRGB(120, 120, 125),
		Material = Enum.Material.Slate,
	})
	body.CFrame = CFrame.new()
	body.Parent = model
	model.PrimaryPart = body

	local crest = newPart({
		Name = "Crest",
		Size = Vector3.new(10.5, 1, 6.5),
		Color = info.Color,
		Material = Enum.Material.Neon,
	})
	crest.CFrame = body.CFrame * CFrame.new(0, 4.5, 0)
	crest.Parent = model

	-- Зона парковки тележки: пока тележка стоит здесь — идёт добыча.
	local zone = newPart({
		Name = "Zone",
		Size = Vector3.new(14, 0.4, 12),
		Color = info.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.65,
		CanCollide = false,
	})
	zone.CFrame = body.CFrame * CFrame.new(0, -3.8, 9)
	zone.Parent = model

	-- Откуда руда "падает" в тележку — точка над зоной парковки.
	local dropPoint = newPart({
		Name = "OreDropPoint",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	dropPoint.CFrame = body.CFrame * CFrame.new(0, 3.2, 9)
	dropPoint.Parent = model

	return model
end

--------------------------------------------------------------------------------
-- КИРКА: Tool из двух Part.
--------------------------------------------------------------------------------
function PlaceholderFactory.Pickaxe(tier)
	local asset = findAsset("Pickaxe_Tier" .. tier)
	if asset then
		assert(asset:IsA("Tool"), ("Assets/Pickaxe_Tier%d должен быть Tool"):format(tier))
		-- Assets is a template folder. Never move or rename the template itself:
		-- the first player would otherwise remove it from ReplicatedStorage and
		-- later players would receive a fallback pickaxe.
		asset = asset:Clone()
		-- Вся логика удара уже серверная. Скрипты из импортированного Tool не
		-- нужны и могут сами бесконечно запускать toolbox-анимацию замаха.
		for _, descendant in asset:GetDescendants() do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.CanCollide = false
			end
		end
		asset.Name = "Pickaxe"
		asset.CanBeDropped = false
		return asset
	end
	-- ВАЖНО: сюда попадаем ТОЛЬКО если ReplicatedStorage.Assets.Pickaxe_TierN
	-- не нашёлся ВООБЩЕ (неверный путь/имя, либо Rojo не досинхронизирован).
	-- Тогда код сам строит одноразовый плейсхолдер с СВОИМ тонким Handle —
	-- это НЕ баг скина, а именно отсутствие/ненахождение твоего настоящего
	-- ассета. Если ты настраивал Pickaxe_TierN сам и видишь это предупреждение
	-- — проверь, что модель лежит РОВНО в ReplicatedStorage/Assets (не глубже,
	-- не в другом сервисе) с именем ровно "Pickaxe_Tier<N>".
	warn(("[PlaceholderFactory] Assets/Pickaxe_Tier%d не найден — строю запасной Tool со своим Handle вместо твоего. Скин сядет на ЭТОТ временный Handle, а не на настроенный тобой."):format(tier))
	local scale = Config.PickaxeTiers[tier].Scale

	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -1, 0)

	local handle = newPart({
		Name = "Handle",
		Size = Vector3.new(0.35, 3, 0.35) * scale,
		Color = Color3.fromRGB(110, 80, 50),
		Anchored = false,
		CanCollide = false,
	})
	handle.Parent = tool

	local head = newPart({
		Name = "Head",
		Size = Vector3.new(2.2, 0.45, 0.45) * scale,
		Color = Color3.fromRGB(160, 165, 175),
		Material = Enum.Material.Metal,
		Anchored = false,
		CanCollide = false,
	})
	head.CFrame = handle.CFrame * CFrame.new(0, handle.Size.Y / 2 - 0.2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head
	head.Parent = tool
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then descendant.CanCollide = false end
	end

	return tool
end

--------------------------------------------------------------------------------
-- БАНК: простой блок + золотая зона продажи.
--------------------------------------------------------------------------------
function PlaceholderFactory.Bank()
	local asset = findAsset("Bank")
	if asset then
		return asset
	end

	local model = Instance.new("Model")
	model.Name = "Bank"

	local building = newPart({
		Name = "Building",
		Size = Vector3.new(12, 16, 12),
		Color = Color3.fromRGB(200, 200, 205),
		Material = Enum.Material.Marble,
	})
	building.CFrame = CFrame.new()
	building.Parent = model
	model.PrimaryPart = building

	local roof = newPart({
		Name = "Roof",
		Size = Vector3.new(13, 1, 13),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.Neon,
	})
	roof.CFrame = building.CFrame * CFrame.new(0, 8.5, 0)
	roof.Parent = model

	-- v20.19: ОТДЕЛЬНАЯ квадратная зона продажи перед банком — чтобы к
	-- торговцу можно было подойти, не продавая руду. Торговец — справа от
	-- зоны, за её краем (MerchantSpot). Свою модель банка оформляй так же:
	-- SellZone (квадрат) + MerchantSpot сбоку.
	local ZONE = 18
	local zoneCFrame = building.CFrame * CFrame.new(0, -7.7, 6 + ZONE / 2 + 2)
	local zone = newPart({
		Name = "SellZone",
		Size = Vector3.new(ZONE, 0.6, ZONE),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		CanCollide = false,
	})
	zone.CFrame = zoneCFrame
	zone.Parent = model
	-- Рамка зоны (декор).
	for i, spec in {
		{ Vector3.new(ZONE + 1, 0.8, 0.8), Vector3.new(0, 0.1, ZONE / 2) },
		{ Vector3.new(ZONE + 1, 0.8, 0.8), Vector3.new(0, 0.1, -ZONE / 2) },
		{ Vector3.new(0.8, 0.8, ZONE + 1), Vector3.new(ZONE / 2, 0.1, 0) },
		{ Vector3.new(0.8, 0.8, ZONE + 1), Vector3.new(-ZONE / 2, 0.1, 0) },
	} do
		local edge = newPart({
			Name = "SellZoneEdge" .. i,
			Size = spec[1],
			Color = Color3.fromRGB(255, 170, 30),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
		edge.CFrame = zoneCFrame * CFrame.new(spec[2])
		edge.Parent = model
	end
	local sign = Instance.new("SurfaceGui")
	sign.Name = "SellSign"
	sign.Face = Enum.NormalId.Top
	sign.LightInfluence = 0
	sign.PixelsPerStud = 20
	sign.Parent = zone
	local signText = WorldUi.Text(nil, "Text", "Label")
	signText.Size = UDim2.fromScale(1, 0.3)
	signText.Position = UDim2.fromScale(0, 0.35)
	signText.BackgroundTransparency = 1
	signText.TextScaled = true
	signText.Text = "SELL ORE"
	signText.TextColor3 = Color3.fromRGB(255, 240, 200)
	signText.Parent = sign

	-- Торговец — справа от зоны продажи, за её краем (лавка ~8 студ шириной).
	local merchantSpot = newPart({
		Name = "MerchantSpot",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	merchantSpot.CFrame = zoneCFrame * CFrame.new(ZONE / 2 + 6, -0.3, 0)
	merchantSpot.Parent = model

	return model
end

--------------------------------------------------------------------------------
-- ТОРГОВЕЦ БАНКА (см. Config.Merchant / MerchantService) — плейсхолдер:
-- лавка с полосатым навесом, ящики с рудой на прилавке и крот-торговец в
-- шахтёрской каске за прилавком. Своя модель "BankMerchant" в
-- ReplicatedStorage.Assets подменяет его целиком.
--
-- Система координат: пивот (Root) — на земле, покупатели стоят со стороны
-- -Z. Табло над головой (BillboardGui "MerchantBoard") заполняет клиент:
-- курс и таймер меняются каждую секунду, гонять их с сервера незачем.
--------------------------------------------------------------------------------
function PlaceholderFactory.BankMerchant()
	local asset = findAsset(Config.Merchant and Config.Merchant.AssetName or "BankMerchant")
	local model
	if asset then
		model = asset
	else
		model = Instance.new("Model")
		model.Name = "BankMerchant"

		local root = newPart({ Name = "Root", Size = Vector3.new(1, 0.2, 1), Transparency = 1, CanCollide = false, CanQuery = false })
		root.CFrame = CFrame.new()
		root.Parent = model
		model.PrimaryPart = root

		local WOOD = Color3.fromRGB(150, 95, 55)
		local WOOD_DARK = Color3.fromRGB(105, 62, 35)
		local function piece(props, cf)
			local part = newPart(props)
			part.CFrame = cf
			part.Parent = model
			return part
		end

		-- Прилавок + столешница.
		piece({ Name = "Counter", Size = Vector3.new(8, 3, 2.4), Color = WOOD, Material = Enum.Material.WoodPlanks }, CFrame.new(0, 1.5, -1))
		piece({ Name = "CounterTop", Size = Vector3.new(8.6, 0.35, 2.9), Color = WOOD_DARK, Material = Enum.Material.Wood }, CFrame.new(0, 3.15, -1))
		-- Стойки навеса.
		for _, x in { -3.9, 3.9 } do
			piece({ Name = "Post", Size = Vector3.new(0.45, 7.4, 0.45), Color = WOOD_DARK, Material = Enum.Material.Wood }, CFrame.new(x, 3.7, -2))
			piece({ Name = "Post", Size = Vector3.new(0.45, 7.4, 0.45), Color = WOOD_DARK, Material = Enum.Material.Wood }, CFrame.new(x, 3.7, 2))
		end
		-- Полосатый навес: 6 полос, наклон к покупателям.
		local stripes = 6
		local width = 9.2 / stripes
		for index = 1, stripes do
			local x = -4.6 + width * (index - 0.5)
			piece({
				Name = "Awning", Size = Vector3.new(width, 0.25, 5.4),
				Color = index % 2 == 0 and Color3.fromRGB(245, 245, 240) or Color3.fromRGB(215, 55, 55),
				Material = Enum.Material.Fabric, CanCollide = false,
			}, CFrame.new(x, 7.5, -0.3) * CFrame.Angles(math.rad(-12), 0, 0))
		end
		-- Ящики с рудой на прилавке.
		local oreColors = { Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 190, 60), Color3.fromRGB(190, 90, 255) }
		for index, x in { -2.6, 0, 2.6 } do
			piece({ Name = "Crate", Size = Vector3.new(1.6, 0.8, 1.2), Color = WOOD_DARK, Material = Enum.Material.WoodPlanks }, CFrame.new(x, 3.72, -1.3))
			for n = 1, 3 do
				piece({
					Name = "Ore", Size = Vector3.new(0.45, 0.45, 0.45), Color = oreColors[index],
					Material = Enum.Material.Neon, CanCollide = false,
				}, CFrame.new(x + (n - 2) * 0.45, 4.25, -1.3) * CFrame.Angles(math.rad(20 * n), math.rad(35 * n), 0))
			end
		end

		-- Крот-торговец за прилавком.
		local FUR = Color3.fromRGB(95, 70, 60)
		piece({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2), Color = FUR, Material = Enum.Material.SmoothPlastic, CanCollide = false }, CFrame.new(0, 3.6, 1.1))
		local head = piece({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(2.5, 2.5, 2.5), Color = FUR, Material = Enum.Material.SmoothPlastic, CanCollide = false }, CFrame.new(0, 5.6, 0.9))
		piece({ Name = "Snout", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 0.9, 1.1), Color = Color3.fromRGB(210, 170, 150), Material = Enum.Material.SmoothPlastic, CanCollide = false }, CFrame.new(0, 5.35, -0.25))
		piece({ Name = "Nose", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.45, 0.5), Color = Color3.fromRGB(255, 120, 150), Material = Enum.Material.SmoothPlastic, CanCollide = false }, CFrame.new(0, 5.5, -0.75))
		for _, x in { -0.5, 0.5 } do
			piece({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.32, 0.32, 0.32), Color = Color3.fromRGB(20, 20, 25), Material = Enum.Material.SmoothPlastic, CanCollide = false }, CFrame.new(x, 6.05, -0.18))
			piece({ Name = "Paw", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Color = Color3.fromRGB(210, 170, 150), Material = Enum.Material.SmoothPlastic, CanCollide = false }, CFrame.new(x * 2.6, 3.55, -0.1))
		end
		-- Шахтёрская каска с фонарём.
		piece({ Name = "Helmet", Size = Vector3.new(0.9, 2.3, 2.3), Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.SmoothPlastic, CanCollide = false },
			CFrame.new(0, 6.75, 0.9) * CFrame.Angles(0, 0, math.rad(90)))
		local lamp = piece({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), Color = Color3.fromRGB(255, 250, 200), Material = Enum.Material.Neon, CanCollide = false }, CFrame.new(0, 6.85, -0.35))
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 160)
		light.Range = 10
		light.Brightness = 1.2
		light.Parent = lamp

		-- Кнопка "Shop" — у края прилавка со стороны покупателя.
		piece({ Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, CFrame.new(0, 3, -2.6))
		head.Name = "Head"
	end

	-- Табло курса/таймера — общее и для своей модели, и для плейсхолдера.
	local head = model:FindFirstChild("Head", true) or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if head and not model:FindFirstChild("MerchantBoard", true) then
		-- v20.17: курс руды «ORE x1.00» теперь только здесь, над торговцем у
		-- банка (плашка сверху экрана убрана). Табличка в мире: размер в
		-- стадах + TextScaled, шрифт денег (как подписи тотемов/трофеев).
		local board = Instance.new("BillboardGui")
		board.Name = "MerchantBoard"
		-- v20.19: вдвое крупнее и цветное — название, курс, таймер.
		board.Size = UDim2.fromScale(14, 5.2)
		board.StudsOffset = Vector3.new(0, 6.2, 0)
		board.AlwaysOnTop = true
		board.MaxDistance = 90
		board.DistanceLowerLimit = 8
		board.LightInfluence = 0
		board.Parent = head
		local function line(name, y, height, style, color)
			local label = WorldUi.Text(nil, "Text", style)
			label.Name = name
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, height)
			label.Position = UDim2.fromScale(0, y)
			label.TextScaled = true
			label.TextColor3 = color
			label.Text = ""
			label.Parent = board
			return label
		end
		local title = line("Title", 0, 0.3, "Label", Color3.fromRGB(255, 200, 70))
		title.Text = (Config.Merchant and Config.Merchant.DisplayName or "Ore Merchant"):upper()
		line("Market", 0.31, 0.42, "Label", Color3.fromRGB(120, 255, 120)).RichText = true
		line("Timer", 0.75, 0.25, "LabelSub", Color3.fromRGB(140, 215, 255)).RichText = true
	end
	return model
end

--------------------------------------------------------------------------------
function PlaceholderFactory.RebirthNPC()
	local asset = findAsset("RebirthNPC")
	if asset then
		-- ПО ПРЯМОМУ ЗАПРОСУ: свой ассет из ReplicatedStorage переносится
		-- на маркер КАК ЕСТЬ — со всеми своими скриптами внутри модели,
		-- без снятия аксессуаров и без добавления анимации. Второе
		-- возвращаемое значение (true = "это свой ассет") позволяет
		-- RebirthService:SetupPlot пропустить билборд/сдвиг шляп и
		-- вообще любую дальнейшую обработку — только позиционирование на
		-- маркере, ничего больше.
		return asset, true
	end

	local model = Instance.new("Model")
	model.Name = "RebirthNPC"

	local torso = newPart({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = Color3.fromRGB(150, 90, 220),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	torso.CFrame = CFrame.new()
	torso.Parent = model
	model.PrimaryPart = torso

	local function attach(part, offset)
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = torso.CFrame * offset
		part.Parent = model
	end

	attach(
		newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(255, 224, 189) }),
		CFrame.new(0, 1.6, 0)
	)
	for _, xSign in { -1, 1 } do
		attach(
			newPart({ Name = "Arm", Size = Vector3.new(0.6, 1.8, 0.6), Color = Color3.fromRGB(150, 90, 220) }),
			CFrame.new(xSign * 1.3, -0.1, 0)
		)
		attach(
			newPart({ Name = "Leg", Size = Vector3.new(0.7, 1.8, 0.7), Color = Color3.fromRGB(60, 60, 70) }),
			CFrame.new(xSign * 0.5, -2.9, 0)
		)
	end

	return model
end

--------------------------------------------------------------------------------
-- ПРОДАВЕЦ ПРОКАЧКИ: заменяет три отдельных пьедестала — один NPC,
-- диалог с тремя пунктами (Шахта/Тележка/Кирка), см. UpgradeService и
-- клиентский диалог в CustomCartUI.client.lua.
--------------------------------------------------------------------------------
function PlaceholderFactory.UpgradeShopNPC()
	local asset = findAsset("UpgradeShopNPC")
	if asset then
		-- ПО ПРЯМОМУ ЗАПРОСУ: свой ассет переносится как есть, см.
		-- комментарий в RebirthNPC выше — то же самое здесь.
		return asset, true
	end

	local model = Instance.new("Model")
	model.Name = "UpgradeShopNPC"

	local torso = newPart({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = Color3.fromRGB(90, 170, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	torso.CFrame = CFrame.new()
	torso.Parent = model
	model.PrimaryPart = torso

	local function attach(part, offset)
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = torso.CFrame * offset
		part.Parent = model
		return part
	end

	local head = attach(
		newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(255, 224, 189) }),
		CFrame.new(0, 1.6, 0)
	)
	for _, xSign in { -1, 1 } do
		attach(
			newPart({ Name = "Arm", Size = Vector3.new(0.6, 1.8, 0.6), Color = Color3.fromRGB(90, 170, 90) }),
			CFrame.new(xSign * 1.3, -0.1, 0)
		)
		attach(
			newPart({ Name = "Leg", Size = Vector3.new(0.7, 1.8, 0.7), Color = Color3.fromRGB(60, 60, 70) }),
			CFrame.new(xSign * 0.5, -2.9, 0)
		)
	end

	-- "gui" на Head — тот же контракт, что у диалоговых NPC в Fisch/Grow a
	-- Garden (см. референс DialogModule): name/arrow видны и слегка
	-- покачиваются, пока NPC молчит; dialog появляется и печатается
	-- посимвольно, когда с ним заговорили — вся анимация/тайминг в
	-- CustomCartUI.client.lua, здесь только сами лейблы + обводка.
	local gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.new(0, Config.NpcBillboard.UpgradeShopNPC.SizeWidth, 0, Config.NpcBillboard.UpgradeShopNPC.SizeHeight)
	gui.StudsOffset = Vector3.new(0, Config.NpcBillboard.UpgradeShopNPC.Height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = head

	local function label(name, size, position, color)
		local text = WorldUi.Text(nil, "Text", "Heading")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Size = size
		text.Position = position
		text.TextSize = 30 -- база для масштабатора разрешения, см. CustomCartUI.client.lua
		text.TextColor3 = color
		text.TextWrapped = true
		text.Text = ""
		text.Parent = gui


		return text
	end

	local nameLabel = label("name", UDim2.new(1, 0, 0.4, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(170, 230, 170))
	nameLabel.Text = "Upgrade Shop"

	local arrowLabel = label("arrow", UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.4, 0), Color3.new(1, 1, 1))
	arrowLabel.Text = "" -- v20.9: стрелку-фигуру рисует клиент (NpcNameStyle); символа ▼ в шрифтах нет

	local dialogLabel = label("dialog", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.new(1, 1, 1))
	dialogLabel.Visible = false

	return model
end

--------------------------------------------------------------------------------
-- НПС МАГАЗИНА (Robux) — отдельный от продавца прокачки: тот копит за
-- деньги/тиры, этот продаёт геймпассы/девпродукты за Robux (см.
-- ShopNpcService:SetupPlot, Config.Shop/Config.GamePasses/Config.DevProducts).
-- Тот же билборд-контракт "gui" (name/arrow/dialog), что и у
-- UpgradeShopNPC — просто другой цвет (золото, не зелень) и другая
-- надпись, чтобы визуально отличался ещё до разговора.
--------------------------------------------------------------------------------
function PlaceholderFactory.ShopNPC()
	local asset = findAsset("ShopNPC")
	if asset then
		-- ПО ПРЯМОМУ ЗАПРОСУ: свой ассет переносится как есть, см.
		-- комментарий в RebirthNPC выше — то же самое здесь.
		return asset, true
	end

	local model = Instance.new("Model")
	model.Name = "ShopNPC"

	local torso = newPart({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = Color3.fromRGB(230, 175, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	torso.CFrame = CFrame.new()
	torso.Parent = model
	model.PrimaryPart = torso

	local function attach(part, offset)
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = torso.CFrame * offset
		part.Parent = model
		return part
	end

	local head = attach(
		newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(255, 224, 189) }),
		CFrame.new(0, 1.6, 0)
	)
	for _, xSign in { -1, 1 } do
		attach(
			newPart({ Name = "Arm", Size = Vector3.new(0.6, 1.8, 0.6), Color = Color3.fromRGB(230, 175, 60) }),
			CFrame.new(xSign * 1.3, -0.1, 0)
		)
		attach(
			newPart({ Name = "Leg", Size = Vector3.new(0.7, 1.8, 0.7), Color = Color3.fromRGB(60, 60, 70) }),
			CFrame.new(xSign * 0.5, -2.9, 0)
		)
	end

	-- "gui" на Head — тот же контракт, что у UpgradeShopNPC (см. там же
	-- подробный комментарий): name/arrow видны и покачиваются, пока NPC
	-- молчит, dialog появляется и печатается посимвольно при разговоре.
	local gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.new(0, Config.NpcBillboard.ShopNPC.SizeWidth, 0, Config.NpcBillboard.ShopNPC.SizeHeight)
	gui.StudsOffset = Vector3.new(0, Config.NpcBillboard.ShopNPC.Height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = head

	local function label(name, size, position, color)
		local text = WorldUi.Text(nil, "Text", "Heading")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Size = size
		text.Position = position
		text.TextSize = 30
		text.TextColor3 = color
		text.TextWrapped = true
		text.Text = ""
		text.Parent = gui


		return text
	end

	local nameLabel = label("name", UDim2.new(1, 0, 0.4, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 215, 120))
	nameLabel.Text = "Item Shop"

	local arrowLabel = label("arrow", UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.4, 0), Color3.new(1, 1, 1))
	arrowLabel.Text = "" -- v20.9: стрелку-фигуру рисует клиент (NpcNameStyle); символа ▼ в шрифтах нет

	local dialogLabel = label("dialog", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.new(1, 1, 1))
	dialogLabel.Visible = false

	return model
end

-- НОВОЕ: НПС-шахтёр (см. ТЗ "переписать систему механики сбора руды" —
-- стоит слева от шахты, ведёт игрока внутрь на мини-игру). Ищет свой
-- ассет "MinerNPC" в билдере (Studio-модель ЖЕЛАТЕЛЬНО с Humanoid внутри —
-- тогда MineService сможет проигрывать на нём реальную анимацию ходьбы
-- через Config.MineExpedition.WalkAnimationId; без Humanoid сервис просто
-- будет плавно двигать всю модель твином, без скелетной анимации).
-- isCustom (второе значение) сообщает MineService, что это НЕ плейсхолдер,
-- см. тот же приём в ShopNPC/RebirthNPC выше.
function PlaceholderFactory.MinerNPC()
	local asset = findAsset("MinerNPC")
	if asset then
		return asset, true
	end

	local model = Instance.new("Model")
	model.Name = "MinerNPC"

	local torso = newPart({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = Color3.fromRGB(90, 100, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	torso.CFrame = CFrame.new()
	torso.Parent = model
	model.PrimaryPart = torso

	local function attach(part, offset)
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = torso.CFrame * offset
		part.Parent = model
		return part
	end

	local head = attach(
		newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(255, 224, 189) }),
		CFrame.new(0, 1.6, 0)
	)
	for _, xSign in { -1, 1 } do
		attach(
			newPart({ Name = "Arm", Size = Vector3.new(0.6, 1.8, 0.6), Color = Color3.fromRGB(90, 100, 120) }),
			CFrame.new(xSign * 1.3, -0.1, 0)
		)
		attach(
			newPart({ Name = "Leg", Size = Vector3.new(0.7, 1.8, 0.7), Color = Color3.fromRGB(60, 60, 70) }),
			CFrame.new(xSign * 0.5, -2.9, 0)
		)
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.new(0, Config.NpcBillboard.MinerNPC.SizeWidth, 0, Config.NpcBillboard.MinerNPC.SizeHeight)
	gui.StudsOffset = Vector3.new(0, Config.NpcBillboard.MinerNPC.Height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = head

	local function label(name, size, position, color)
		local text = WorldUi.Text(nil, "Text", "Heading")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Size = size
		text.Position = position
		text.TextSize = 30
		text.TextColor3 = color
		text.TextWrapped = true
		text.Text = ""
		text.Parent = gui


		return text
	end

	local nameLabel = label("name", UDim2.new(1, 0, 0.4, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(180, 220, 255))
	nameLabel.Text = "Miner"

	local arrowLabel = label("arrow", UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.4, 0), Color3.new(1, 1, 1))
	arrowLabel.Text = "" -- v20.9: стрелку-фигуру рисует клиент (NpcNameStyle); символа ▼ в шрифтах нет

	local dialogLabel = label("dialog", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.new(1, 1, 1))
	dialogLabel.Visible = false

	return model, false
end

--------------------------------------------------------------------------------
-- ШАБЛОН УЧАСТКА: сама расстановка "где шахта, где пьедесталы, где спавн
-- тележки" внутри участка — теперь ТОЖЕ настраиваемый плейсхолдер, не
-- зашитые в код смещения. Клонируется ОДИН раз на каждый участок
-- (PlotService:Start), дальше PlotService просто читает CFrame нужных
-- маркеров вместо того, чтобы вычислять их сам.
--
-- Маркеры — обычные BasePart, ориентация (не только позиция) тоже
-- учитывается — например, поворот MineMarker определяет, куда смотрит
-- зона добычи. Сами маркеры невидимы и не мешают ходить (PlotService
-- принудительно скрывает всё, кроме PlotPad, после чтения позиций) —
-- их можно оставлять любыми в Studio, не заботясь о внешнем виде.
--------------------------------------------------------------------------------
function PlaceholderFactory.PlotTemplate()
	local asset = findAsset("PlotTemplate")
	if asset then
		assert(asset:IsA("Model"), "PlotTemplate must be a Model")
		local namedPad = asset:FindFirstChild("PlotPad", true)
		local pad = namedPad and namedPad:IsA("BasePart") and namedPad or asset.PrimaryPart
		assert(pad and pad:IsA("BasePart"), "PlotTemplate requires a BasePart named 'PlotPad'; Part, MeshPart and UnionOperation are supported")
		asset.PrimaryPart = pad
		return asset
	end

	local model = Instance.new("Model")
	model.Name = "PlotTemplate"

	-- Пол участка — те же размер/цвет, что были зашиты в PlotService раньше.
	local pad = newPart({
		Name = "PlotPad",
		Size = Config.World.PlotSize,
		Color = Color3.fromRGB(70, 70, 75),
		CanCollide = true,
	})
	pad.CFrame = CFrame.new(0, 0, 0)
	pad.Parent = model
	model.PrimaryPart = pad

	-- Маркеры-точки — позиция ЛОКАЛЬНО относительно PlotPad. Значения по
	-- умолчанию — те же смещения, что раньше были захардкожены прямо в
	-- PlotService (шахта слева, пьедестал справа, тележка и спавн сзади).
	local function marker(name, cframe)
		local part = newPart({
			Name = name,
			Size = Vector3.new(1, 1, 1),
			Transparency = 1,
			CanCollide = false,
		})
		part.CFrame = pad.CFrame * cframe
		part.Parent = model
		return part
	end

	marker("MineMarker", CFrame.new(-14, 4.5, 0) * CFrame.Angles(0, math.rad(90), 0))
	marker("PillarMarker", CFrame.new(14, 3.5, 0))
	marker("CartSpawnMarker", CFrame.new(0, 1, -14))
	marker("PlayerSpawnMarker", CFrame.new(0, 1, 12))
	marker("RebirthMarker", CFrame.new(0, 3.3, -12))
	-- Необязательный маркер — где стоит кнопка "заспавнить тележку" (см.
	-- CartService:SetupRespawnButton). Позиция по умолчанию — та же, что
	-- раньше была жёстко зашита в код (5 студ вбок от CartSpawnMarker) —
	-- если билдер не переопределит этот маркер сам, поведение не меняется.
	marker("CartButtonMarker", CFrame.new(5, 0.5, -14))

	-- НПС МАГАЗИНА (Robux) — отдельно от продавца прокачки (PillarMarker),
	-- смещён вбок от персонального спавна, чтобы не толкаться с игроком
	-- при возрождении. Необязательный маркер (readMarker(..., true) в
	-- PlotService) — старые/чужие PlotTemplate без него просто не получат
	-- NPC магазина на участке (ShopNpcService сам пропустит спавн).
	marker("ShopMarker", CFrame.new(8, 3.3, 12))
	marker("GeodeBuildingMarker", CFrame.new(-13, 2.5, 13))
	marker("GeodePodiumMarker", CFrame.new(13, 1.5, 13))
	marker("GeodeSafeMarker", CFrame.new(13, 1.5, 7))
	-- Три глобальные доски стоят у дальнего края базы и лицевой стороной
	-- (Front, локальный -Z) смотрят внутрь участка.
	marker("LeaderboardMarker", CFrame.new(0, 0.5, 22))

	return model
end

--------------------------------------------------------------------------------
-- GLOBAL LEADERBOARD BOARDS: one model is cloned at every plot. Builders may
-- replace it with Assets/LeaderboardBoards while keeping the three named parts.
--------------------------------------------------------------------------------
function PlaceholderFactory.LeaderboardBoards()
	local asset = findAsset("LeaderboardBoards")
	if asset then
		assert(asset:IsA("Model") and asset.PrimaryPart, "LeaderboardBoards обязан быть Model с назначенным PrimaryPart")
		return asset
	end

	local model = Instance.new("Model")
	model.Name = "LeaderboardBoards"
	local root = newPart({ Name = "Root", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false })
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local boardInfo = {
		{ "MoneyBoard", -8.5, Color3.fromRGB(255, 211, 75) },
		{ "RebirthBoard", 0, Color3.fromRGB(105, 225, 255) },
		{ "CartDamageBoard", 8.5, Color3.fromRGB(255, 105, 105) },
	}
	for _, info in boardInfo do
		local board = newPart({
			Name = info[1],
			Size = Vector3.new(8, 10, 0.5),
			Color = Color3.fromRGB(24, 26, 32),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		board.CFrame = root.CFrame * CFrame.new(info[2], 5.25, 0)
		board.Parent = model
		local trim = newPart({ Name = "Trim", Size = Vector3.new(8.4, 0.35, 0.7), Color = info[3], Material = Enum.Material.Neon, CanCollide = false })
		trim.CFrame = board.CFrame * CFrame.new(0, 5.15, 0)
		trim.Parent = model
	end
	return model
end

return PlaceholderFactory
