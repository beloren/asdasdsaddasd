--------------------------------------------------------------------------------
-- OreCarryPose (LocalScript) — руда НАД ГОЛОВОЙ и поднятые руки.
--
-- ЭТО ТА ЖЕ СИСТЕМА, ЧТО И ХВАТ ЗА ТЕЛЕЖКУ (см. CustomCartUI, блок "ХВАТ ЗА
-- ТЕЛЕЖКУ (R6 IK)"), перенесённая на руду один в один по принципу:
--
--   1) Поза руки — это НЕ свойство детали руки, а `Motor6D.Transform`,
--      который Animator переписывает КАЖДЫЙ КАДР. Поэтому мы не трогаем
--      риг вообще: ни клонов, ни новых суставов, ни правок C0/C1. Каждый
--      кадр в `RunService.Stepped` (он идёт СРАЗУ ПОСЛЕ записи аниматора)
--      мы перезаписываем Transform штатных Left/Right Shoulder своим.
--      Аниматор пишет своё — мы пишем поверх, позже. Утечка анимации
--      невозможна по построению.
--
--   2) ВИДНО ВСЕМ. Transform не реплицируется, поэтому этот код крутится
--      на КАЖДОМ клиенте для КАЖДОГО держателя, а не только для себя.
--      Тележка ищется по атрибуту `HolderUserId`; руда — по атрибутам
--      `HeldOre`/`HeldOreVariant`/`HeldOreMutations` НА ИГРОКЕ, которые
--      ставит сервер (InventoryService:SetHeldOre).
--
-- ОТЛИЧИЕ ОТ ТЕЛЕЖКИ — РУКИ НЕ РАСТЯГИВАЮТСЯ (по прямому запросу "можно
-- даже чтобы они не растягивались"). У тележки длина руки каждый кадр
-- подгонялась под расстояние до точки хвата, чтобы кончик математически
-- совпал с ней. Здесь `Size` руки НЕ трогается вообще: рука просто
-- разворачивается вверх, а руда висит над головой сама. Поэтому и
-- восстанавливать при отпускании нечего — Transform аниматор перепишет
-- уже в следующем кадре.
--
-- Руду каждый клиент строит СЕБЕ САМ и держит в workspace без физики
-- (Anchored, CanCollide = false, CanQuery = false), позиционируя её каждый
-- кадр от головы. Сварка не нужна и вредна: WeldConstraint потянул бы за
-- собой физическую сборку персонажа.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)

-- Насколько высоко над головой висит руда и как широко разведены руки.
local HEAD_CLEARANCE = 1.5   -- студ от верха головы до низа руды
local GRIP_SPREAD = 0.75     -- разнос точек, куда целятся левая и правая рука
local SHOULDER_WIDEN = 0.65  -- тот же вынос плеча, что и у тележки (ARM_SHOULDER_WIDEN_STUDS)
local MAX_ORE_SIZE = 2.2     -- крупную руду ужимаем, иначе она закрывает пол-экрана
local SPIN_DEGREES_PER_SECOND = 45 -- медленное вращение руды над головой
-- v17: ПЛАВНЫЕ ПЕРЕХОДЫ. Руки поднимаются к руде и опускаются обратно не
-- мгновенно, а смешиваются с позой аниматора (ходьба/стойка) за это время.
local BLEND_IN_SECONDS = (Config.Animations and Config.Animations.PoseBlendIn) or 0.22
local BLEND_OUT_SECONDS = (Config.Animations and Config.Animations.PoseBlendOut) or 0.25

local function smoothstep(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- [player] = { Left, Right, Torso, LeftLocal, RightLocal, Weight } —
-- руки, которые плавно опускаются после того, как руду убрали.
local releasing = {}

-- [player] = { Model, Root, Left = armState, Right = armState, Key = "<ore>|<variant>|<mut>" }
local rigs = {}

--------------------------------------------------------------------------------
-- ГЕОМЕТРИЯ (скопировано из CustomCartUI — намеренно, чтобы поза читалась
-- ровно так же, как при хвате за тележку)
--------------------------------------------------------------------------------
local function aimBasis(worldDirection)
	local yAxis = -worldDirection.Unit
	local reference = math.abs(yAxis:Dot(Vector3.yAxis)) > 0.99 and Vector3.zAxis or Vector3.yAxis
	local xAxis = reference:Cross(yAxis)
	if xAxis.Magnitude < 1e-5 then
		xAxis = Vector3.xAxis
	end
	xAxis = xAxis.Unit
	local zAxis = xAxis:Cross(yAxis).Unit
	return xAxis, yAxis, zAxis
end

local function buildArmState(character, torso, side)
	local motor = torso:FindFirstChild(side .. " Shoulder")
	local arm = character:FindFirstChild(side .. " Arm")
	if not (motor and motor:IsA("Motor6D") and arm and arm:IsA("BasePart")) then
		return nil
	end
	local c0Position = motor.C0.Position
	local anchorLocal = Vector3.new(
		c0Position.X + (c0Position.X >= 0 and 1 or -1) * SHOULDER_WIDEN,
		c0Position.Y,
		c0Position.Z
	)
	return { Motor = motor, Arm = arm, AnchorLocal = anchorLocal }
end

-- Один кадр одной руки. В отличие от тележки Size НЕ трогаем — рука
-- сохраняет свою настоящую длину и просто смотрит вверх, на точку хвата.
local function updateArm(armState, torsoCFrame, targetWorldPosition, weight)
	if not (armState and armState.Arm.Parent and armState.Motor.Parent) then return end
	weight = weight or 1
	local shoulderWorld = torsoCFrame:PointToWorldSpace(armState.AnchorLocal)
	local direction = targetWorldPosition - shoulderWorld
	local distance = direction.Magnitude
	if distance < 0.05 then return end

	-- Центр руки — на полруки от плеча вдоль направления на цель. Верхний
	-- торец остаётся точно в плече, кончик уходит вверх настолько,
	-- насколько рука длинная. До руды он может не достать — и не должен.
	local sizeY = armState.Arm.Size.Y
	local dirUnit = direction / distance
	local xAxis, yAxis, zAxis = aimBasis(direction)
	local desiredArmCFrame = CFrame.fromMatrix(shoulderWorld + dirUnit * (sizeY / 2), xAxis, yAxis, zAxis)

	local motor = armState.Motor
	-- Из Part1 = Part0 * C0 * Transform * C1⁻¹ следует
	-- Transform = C0⁻¹ * Part0.CFrame⁻¹ * desiredPart1 * C1.
	local target = motor.C0:Inverse() * torsoCFrame:Inverse() * desiredArmCFrame * motor.C1
	-- v17: смешиваем с тем, что аниматор записал в этом кадре.
	motor.Transform = weight >= 1 and target or motor.Transform:Lerp(target, smoothstep(weight))
end

--------------------------------------------------------------------------------
-- МОДЕЛЬ РУДЫ
--------------------------------------------------------------------------------
-- v12: УПАКОВКА ТЕЛЕЖКИ носится ровно как руда — над головой, с той же
-- позой рук. Сервер (GearService:Equip) ставит на игрока атрибут
-- HeldCartPackage = тир тележки; здесь он превращается в такой же ключ
-- рига, как у руды, поэтому вся остальная механика (пересборка при смене,
-- удаление при отпускании, видимость у ВСЕХ клиентов) работает без единой
-- дополнительной строчки. Тир входит в ключ — апгрейд тележки, лежащей в
-- упаковке, сам пересоберёт коробку с новой надписью.
local function heldPackageTier(plr)
	local tier = tonumber(plr:GetAttribute("HeldCartPackage"))
	if not tier or tier < 1 then return nil end
	return math.floor(tier)
end

-- ЗЕЛЬЕ (Config.Potions) держится ровно как руда и коробка тележки —
-- над головой поднятыми руками. Сервер (GearService:Equip) ставит на игрока
-- атрибут HeldPotion = ключ зелья.
local function heldPotion(plr)
	local key = plr:GetAttribute("HeldPotion")
	if not key or key == "" then return nil end
	if not (Config.Potions and Config.Potions.Types[key]) then return nil end
	return key
end

local function heldKey(plr)
	local potion = heldPotion(plr)
	if potion then
		return "potion|" .. potion
	end
	local packageTier = heldPackageTier(plr)
	if packageTier then
		return "cartpackage|" .. tostring(packageTier)
	end
	local ore = plr:GetAttribute("HeldOre")
	if not ore then return nil end
	return ("%s|%s|%s|%s|%s|%s"):format(
		tostring(ore),
		tostring(plr:GetAttribute("HeldOreVariant") or 1),
		tostring(plr:GetAttribute("HeldOreMutations") or ""),
		tostring(plr:GetAttribute("HeldOreSmelted") == true),
		tostring(plr:GetAttribute("HeldOreValue") or 0),
		tostring(plr:GetAttribute("MineTier") or 1)
	) .. "|" .. tostring(plr:GetAttribute("HeldOreGigantic") == true)
end

-- Коробка упаковки: та же подготовка, что у руды (без физики, без запросов
-- лучом), плюс подпись с тиром — чтобы и владелец, и окружающие видели,
-- ЧТО именно человек несёт.
local function buildPackageModel(plr, tier)
	local ok, model = pcall(PlaceholderFactory.CartPackage, tier)
	if not ok or not model then return nil, nil end

	local root = model:IsA("Model")
		and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
		or model
	if not root then
		model:Destroy()
		return nil, nil
	end
	if model:IsA("Model") then model.PrimaryPart = root end

	for _, d in (model:IsA("Model") and model:GetDescendants() or { model }) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end

	if model:IsA("Model") then
		local _, size = model:GetBoundingBox()
		local biggest = math.max(size.X, size.Y, size.Z)
		if biggest > MAX_ORE_SIZE then
			pcall(function() model:ScaleTo(model:GetScale() * MAX_ORE_SIZE / biggest) end)
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HeldCartPackage"
	billboard.Size = UDim2.new(4.6, 0, 1.1, 0)
	billboard.StudsOffset = Vector3.new(0, Config.Inventory.HeldRarityBillboardHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Adornee = root
	billboard.Parent = root

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "CART PACKAGE"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	title.TextStrokeTransparency = 0
	title.Parent = billboard

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.fromScale(1, 0.45)
	subtitle.Position = UDim2.fromScale(0, 0.55)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.TextScaled = true
	subtitle.Text = ("LV %d"):format(tier)
	subtitle.TextColor3 = Color3.fromRGB(120, 230, 255)
	subtitle.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	subtitle.TextStrokeTransparency = 0
	subtitle.Parent = billboard

	model.Name = "HeldCartPackageVisual_" .. plr.UserId
	model.Parent = workspace
	return model, root
end

-- Колба зелья: стеклянный шар, светящаяся жидкость цвета зелья, горлышко,
-- пробка и блик. Первая деталь (стекло) — корень для позы рук.
local function buildPotionModel(plr, key)
	local info = Config.Potions.Types[key]
	local color = info.Color or Color3.fromRGB(200, 120, 255)
	local model = Instance.new("Model")
	local function piece(name, shape, size, partColor, material, transparency, offset)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Size = size
		part.Color = partColor
		part.Material = material
		part.Transparency = transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = offset
		part.Parent = model
		return part
	end
	local glassColor = Color3.fromRGB(220, 240, 255)
	local root, liquid
	if info.Charm then
		-- v18: АМУЛЕТ из сундука — золотой диск с камнем цвета амулета.
		local gold = Color3.fromRGB(255, 196, 60)
		root = piece("Disc", Enum.PartType.Cylinder, Vector3.new(0.25, 1.4, 1.4), gold, Enum.Material.Metal, 0, CFrame.Angles(0, math.rad(90), 0))
		piece("Rim", Enum.PartType.Cylinder, Vector3.new(0.3, 1.1, 1.1), Color3.fromRGB(200, 140, 30), Enum.Material.Metal, 0, CFrame.Angles(0, math.rad(90), 0))
		liquid = piece("Gem", Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), color, Enum.Material.Neon, 0, CFrame.new(0, 0, -0.18))
		piece("Loop", Enum.PartType.Cylinder, Vector3.new(0.12, 0.4, 0.4), gold, Enum.Material.Metal, 0, CFrame.new(0, 0.82, 0) * CFrame.Angles(0, math.rad(90), 0))
	else
		root = piece("Glass", Enum.PartType.Ball, Vector3.new(1.35, 1.35, 1.35), glassColor, Enum.Material.Glass, 0.45, CFrame.new())
		liquid = piece("Liquid", Enum.PartType.Ball, Vector3.new(1, 1, 1), color, Enum.Material.Neon, 0.1, CFrame.new(0, -0.1, 0))
		piece("Neck", Enum.PartType.Cylinder, Vector3.new(0.45, 0.44, 0.44), glassColor, Enum.Material.Glass, 0.4, CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)))
		piece("Cork", Enum.PartType.Cylinder, Vector3.new(0.3, 0.48, 0.48), Color3.fromRGB(150, 95, 55), Enum.Material.Wood, 0, CFrame.new(0, 1.08, 0) * CFrame.Angles(0, 0, math.rad(90)))
		piece("Shine", Enum.PartType.Ball, Vector3.new(0.22, 0.22, 0.22), Color3.new(1, 1, 1), Enum.Material.Neon, 0.2, CFrame.new(-0.34, 0.3, -0.44))
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 7
	light.Brightness = 0.9
	light.Parent = liquid
	model.PrimaryPart = root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HeldPotion"
	billboard.Size = UDim2.new(4.6, 0, 0.9, 0)
	billboard.StudsOffset = Vector3.new(0, Config.Inventory.HeldRarityBillboardHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Adornee = root
	billboard.Parent = root
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = (info.Icon and (info.Icon .. " ") or "") .. (info.DisplayName or key):upper()
	title.TextColor3 = color
	title.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	title.TextStrokeTransparency = 0
	title.Parent = billboard

	model.Name = "HeldPotionVisual_" .. plr.UserId
	model.Parent = workspace
	return model, root
end

local function buildOreModel(plr)
	local potion = heldPotion(plr)
	if potion then
		return buildPotionModel(plr, potion)
	end
	local packageTier = heldPackageTier(plr)
	if packageTier then
		return buildPackageModel(plr, packageTier)
	end
	local oreKey = plr:GetAttribute("HeldOre")
	local info = oreKey and Config.OreByKey[oreKey]
	if not info then return nil, nil end
	local variant = Config.OreVariants[plr:GetAttribute("HeldOreVariant") or 1]
	-- Слиток из плавильни (см. IslandService) держится в руках слитком.
	local builder = plr:GetAttribute("HeldOreSmelted") == true and PlaceholderFactory.OreIngot or PlaceholderFactory.OreCrystal
	local ok, model = pcall(builder, info, variant)
	if not ok or not model then return nil, nil end

	local root = model:IsA("Model")
		and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
		or model
	if not root then
		model:Destroy()
		return nil, nil
	end
	if model:IsA("Model") then model.PrimaryPart = root end

	-- v9: в руках — ТОТ ЖЕ визуал мутаций, что и на земле (оболочки,
	-- материалы, частицы, мерцание). Раньше мутации были только текстом.
	local heldMutations = plr:GetAttribute("HeldOreMutations") or ""
	if heldMutations ~= "" then
		local ids = string.split(heldMutations, ",")
		local groups = nil
		pcall(function() groups = MutationVisuals.SplitPartsForMutations(model, #ids) end)
		for index, id in ids do
			if Config.Mutations and Config.Mutations[id] then
				pcall(MutationVisuals.Apply, model, id, root, groups and groups[index])
			end
		end
	end
	local gigantic = plr:GetAttribute("HeldOreGigantic") == true

	for _, d in (model:IsA("Model") and model:GetDescendants() or { model }) do
		if d:IsA("BasePart") then
			-- Никакой физики: это чисто визуальная копия у КАЖДОГО клиента
			-- своя. Неанкоренная деталь начала бы падать, а CanQuery = true
			-- ломал бы лучи хвата за тележку и подбор руды.
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end

	-- Крупные куски ужимаем, чтобы руда над головой не перекрывала обзор.
	if model:IsA("Model") then
		local _, size = model:GetBoundingBox()
		local biggest = math.max(size.X, size.Y, size.Z)
		local limit = gigantic and MAX_ORE_SIZE * 1.5 or MAX_ORE_SIZE
		if biggest > limit then
			pcall(function() model:ScaleTo(model:GetScale() * limit / biggest) end)
		end
	end

	-- Ярлык редкости над рудой — раньше его вешал InventoryUI, и видел
	-- его только сам держатель. Теперь он строится здесь, а значит виден
	-- ВСЕМ: остальные игроки читают, что человек несёт, не подходя вплотную.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HeldRarity"
	billboard.Size = UDim2.new(4.6, 0, 1.7, 0) -- выше: теперь три строки, а не одна
	billboard.StudsOffset = Vector3.new(0, Config.Inventory.HeldRarityBillboardHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Adornee = root
	billboard.Parent = root

	-- ТРИ СТРОКИ РАЗНОГО ВЕСА вместо одной свалки текста:
	--   1) мутации  — САМЫМ МЕЛКИМ, сверху (их может не быть вовсе);
	--   2) название + вариация — крупно, белым;
	--   3) редкость — её собственным цветом.
	-- Раньше всё это было одним TextLabel с "\n", поэтому размер строк
	-- совпадал, а редкость красилась вместе с названием — прочитать
	-- иерархию было невозможно.
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local function makeLine(order, height, text, color, stroke)
		local line = Instance.new("TextLabel")
		line.LayoutOrder = order
		line.Size = UDim2.new(1, 0, height, 0)
		line.BackgroundTransparency = 1
		line.Font = Enum.Font.FredokaOne
		line.TextScaled = true
		line.Text = text
		line.TextColor3 = color
		line.TextStrokeColor3 = stroke or Color3.fromRGB(10, 10, 14)
		line.TextStrokeTransparency = 0
		line.Parent = billboard
		return line
	end

	local mutations = plr:GetAttribute("HeldOreMutations") or ""
	-- v3 (Ж2): редкость — по слоту руды в ТЕКУЩЕЙ пещере держателя.
	local rarity = (Config.OreRarityFor and Config.OreRarityFor(oreKey, plr:GetAttribute("HeldOreTier") or plr:GetAttribute("MineTier"))) or info.Rarity or ""
	local rarityColor = (Config.RarityColors and Config.RarityColors[rarity])
		or Color3.fromRGB(200, 200, 200)

	if mutations ~= "" then
		-- Мутации перечисляем через запятую человекочитаемо и мелко: это
		-- приписка к предмету, а не его имя.
		local parts = {}
		for _, id in string.split(mutations, ",") do
			local mutation = Config.Mutations and Config.Mutations[id]
			table.insert(parts, ((mutation and mutation.DisplayName) or id):upper())
		end
		makeLine(1, 0.22, table.concat(parts, " + "), Color3.fromRGB(255, 205, 120))
	end

	if gigantic then
		makeLine(0, 0.2, "GIGANTIC", Color3.fromRGB(255, 215, 60))
	end

	-- Вариация — часть имени предмета, поэтому в одной строке с названием.
	local variantName = variant and variant.DisplayName or nil
	local title = info.DisplayName
	if variantName and variantName ~= "" then
		title = title .. " " .. variantName
	end
	makeLine(2, 0.42, title, Color3.fromRGB(255, 255, 255))
	-- v3: вместо слова редкости — ЦЕНА куска, покрашенная в цвет редкости.
	local heldValue = tonumber(plr:GetAttribute("HeldOreValue")) or 0
	if heldValue > 0 then
		makeLine(3, 0.34, "$" .. NumberFormat.abbreviate(heldValue), rarityColor)
	else
		makeLine(3, 0.3, rarity:upper(), rarityColor)
	end

	model.Name = "HeldOreVisual_" .. plr.UserId
	model.Parent = workspace
	return model, root
end

local function stopRig(plr, fadeArms)
	local rig = rigs[plr]
	if not rig then return end
	rigs[plr] = nil
	if rig.Model and rig.Model.Parent then
		rig.Model:Destroy()
	end
	-- v17: руки не «падают» в ту же секунду — плавно опускаются.
	if fadeArms and rig.Torso.Parent and rig.LastLeft and rig.LastRight then
		local torsoCFrame = rig.Torso.CFrame
		releasing[plr] = {
			Left = rig.Left, Right = rig.Right, Torso = rig.Torso,
			LeftLocal = torsoCFrame:PointToObjectSpace(rig.LastLeft),
			RightLocal = torsoCFrame:PointToObjectSpace(rig.LastRight),
			Weight = rig.Blend or 1,
		}
	end
	-- Transform НЕ восстанавливаем: аниматор перепишет его уже в следующем
	-- кадре сам. Size мы не трогали, восстанавливать тоже нечего.
end

local function startRig(plr)
	local character = plr.Character
	local torso = character and character:FindFirstChild("Torso")
	local head = character and character:FindFirstChild("Head")
	-- R6-риг. На R15 ("UpperTorso"/"RightUpperArm") этой позы нет — тихо
	-- не включаем, как и хват за тележку: остальная игра не страдает.
	if not (torso and head) then return end

	local left = buildArmState(character, torso, "Left")
	local right = buildArmState(character, torso, "Right")
	if not (left and right) then return end

	local model, root = buildOreModel(plr)
	if not model then return end

	-- Если руки ещё опускались после прошлой руды — подхватываем с того же
	-- места, а не с нуля.
	local fading = releasing[plr]
	releasing[plr] = nil
	rigs[plr] = {
		Model = model,
		Root = root,
		Head = head,
		Torso = torso,
		Left = left,
		Right = right,
		Key = heldKey(plr),
		Blend = fading and fading.Torso == torso and fading.Weight or 0,
	}
end

--------------------------------------------------------------------------------
-- СИНХРОНИЗАЦИЯ "КТО ЧТО ДЕРЖИТ"
--------------------------------------------------------------------------------
local function reconcile(plr)
	local wanted = heldKey(plr)
	local rig = rigs[plr]
	if not wanted then
		stopRig(plr, true)
		return
	end
	-- Ключ поменялся (взяли другую руду) — пересобираем только модель,
	-- руки остаются поднятыми (без «опустил-поднял»).
	if rig and rig.Key ~= wanted then
		local model, root = buildOreModel(plr)
		if model then
			if rig.Model and rig.Model.Parent then rig.Model:Destroy() end
			rig.Model, rig.Root, rig.Key = model, root, wanted
			return
		end
		stopRig(plr, true)
		rig = nil
	end
	if not rig then
		startRig(plr)
	end
end

local function watch(plr)
	plr:GetAttributeChangedSignal("HeldOre"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldOreVariant"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldOreMutations"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldOreSmelted"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldOreValue"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldOreGigantic"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("MineTier"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldCartPackage"):Connect(function() reconcile(plr) end)
	plr:GetAttributeChangedSignal("HeldPotion"):Connect(function() reconcile(plr) end)
	plr.CharacterAdded:Connect(function()
		-- Новый персонаж — старые ссылки на Torso/Motor6D мертвы. Ждём,
		-- пока риг соберётся, и пересобираем позу, если руда всё ещё в руках.
		stopRig(plr)
		task.delay(0.6, function() reconcile(plr) end)
	end)
	plr.CharacterRemoving:Connect(function() stopRig(plr); releasing[plr] = nil end)
	reconcile(plr)
end

for _, plr in Players:GetPlayers() do
	watch(plr)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(plr) stopRig(plr); releasing[plr] = nil end)

--------------------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ
--
-- Именно Stepped, а не RenderStepped: Stepped идёт ПОСЛЕ того, как Animator
-- записал свой Transform в суставы, поэтому наша запись оказывается
-- последней в кадре и побеждает. В RenderStepped мы писали бы ДО аниматора
-- и он затирал бы позу — ровно та ошибка, на которую напоролись прошлые
-- версии хвата за тележку.
--------------------------------------------------------------------------------
local reconcileClock = 0

RunService.Stepped:Connect(function(_, dt)
	-- Раз в секунду сверяем "кто держит" с "какие риги активны" — ловит
	-- стриминг, позднюю репликацию персонажа и пропущенные сигналы. Та же
	-- страховка, что и RECONCILE_INTERVAL у тележки.
	reconcileClock += dt
	if reconcileClock >= 1 then
		reconcileClock = 0
		for _, plr in Players:GetPlayers() do
			reconcile(plr)
		end
	end

	for plr, rig in rigs do
		local character = plr.Character
		if not (character and rig.Head.Parent and rig.Torso.Parent and rig.Model.Parent) then
			stopRig(plr)
		else
			local head = rig.Head
			local torsoCFrame = rig.Torso.CFrame

			-- Руда строго над головой, без наклона по тангажу/крену: берём
			-- только рыскание торса, иначе на прыжке и склонах кусок
			-- заваливался бы вместе с телом.
			local look = torsoCFrame.LookVector * Vector3.new(1, 0, 1)
			local yaw = look.Magnitude > 1e-4
				and CFrame.lookAt(Vector3.zero, look.Unit).Rotation
				or CFrame.identity

			local orePosition = head.Position + Vector3.yAxis * (head.Size.Y / 2 + HEAD_CLEARANCE)
			-- МЕДЛЕННОЕ ВРАЩЕНИЕ. Угол копим сами и крутим ВОКРУГ СВОЕЙ ОСИ
			-- поверх рыскания торса, а не подменяем им поворот: иначе руда
			-- перестала бы следовать за разворотом игрока и "плавала" бы
			-- относительно него.
			rig.Spin = (rig.Spin or 0) + dt * SPIN_DEGREES_PER_SECOND
			if rig.Spin >= 360 then rig.Spin -= 360 end
			local oreCFrame = CFrame.new(orePosition) * yaw * CFrame.Angles(0, math.rad(rig.Spin), 0)
			if rig.Model:IsA("Model") then
				rig.Model:PivotTo(oreCFrame)
			else
				rig.Root.CFrame = oreCFrame
			end

			-- Точки, куда тянутся руки: чуть ниже руды и разведены в
			-- стороны — получается поза "держу над головой", а не "тяну
			-- обе руки в одну точку".
			-- РУКИ НЕ КРУТЯТСЯ ВМЕСТЕ С РУДОЙ. Точки хвата берём из рыскания корпуса
			-- (yaw), а НЕ из oreCFrame: в oreCFrame теперь входит вращение руды,
			-- и руки ездили бы по кругу следом за ней. Крутиться должна только
			-- руда, руки — стоять.
			local rightVector = (CFrame.new(orePosition) * yaw).RightVector
			local gripCentre = orePosition - Vector3.yAxis * 0.25
			rig.Blend = math.min(1, (rig.Blend or 1) + dt / BLEND_IN_SECONDS)
			rig.LastLeft = gripCentre - rightVector * GRIP_SPREAD
			rig.LastRight = gripCentre + rightVector * GRIP_SPREAD
			updateArm(rig.Left, torsoCFrame, rig.LastLeft, rig.Blend)
			updateArm(rig.Right, torsoCFrame, rig.LastRight, rig.Blend)
		end
	end

	-- v17: плавное опускание рук после того, как руду убрали.
	for plr, fade in releasing do
		fade.Weight -= dt / BLEND_OUT_SECONDS
		if fade.Weight <= 0 or not fade.Torso.Parent or rigs[plr] then
			releasing[plr] = nil
		else
			local torsoCFrame = fade.Torso.CFrame
			updateArm(fade.Left, torsoCFrame, torsoCFrame:PointToWorldSpace(fade.LeftLocal), fade.Weight)
			updateArm(fade.Right, torsoCFrame, torsoCFrame:PointToWorldSpace(fade.RightLocal), fade.Weight)
		end
	end
end)
