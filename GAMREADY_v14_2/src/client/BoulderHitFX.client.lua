--------------------------------------------------------------------------------
-- BoulderHitFX (LocalScript) v19 — ВАЛУНЫ: ПЛАШКА ХП, ЦИФРЫ УРОНА, ВИНЬЕТКА.
--
-- 1. ПЛАШКА ХП (стиль The Forge) над каждым валуном: тёмная подложка с тонкой
--    рамкой, имя слева, «640 HP» справа, под ними полоса. Полоса сразу
--    падает, а белый «хвост» урона плавно догоняет её. Цвет — от зелёного к
--    красному. Видна рядом с камнем (ShowDistance) или HitShowSeconds после
--    удара, плавно проявляется и гаснет. При ударе плашка вздрагивает.
-- 2. ЦИФРА УРОНА на камне — белая на полупрозрачной чёрной подложке,
--    выскакивает из точки удара с «пружинкой», поднимается и тает.
--    PERFECT — крупнее, жёлтая, с подписью; динамит — оранжевая;
--    добивание — ещё и красная плашка «BREAK!».
-- 3. ВИНЬЕТКА по краям экрана на каждый удар: лёгкая белая, у PERFECT —
--    золотистая, у добивания — чуть сильнее (Config.BoulderHitFx.Vignette).
--
-- Сервер (RockService) шлёт BoulderHitFx: (модель, урон, оценка, добит?, точка).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local CFG = Config.BoulderHitFx or {}
if CFG.Enabled == false then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- v19.1: шрифт как во всей игре (FredokaOne), без чёрных подложек — только обводка.
local NAME_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local NUMBER_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local INK = Color3.fromRGB(10, 8, 18)

local function textStroke(label, thickness, color)
	local s = Instance.new("UIStroke")
	s.Color = color or INK
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
	return s
end
local WHITE = Color3.new(1, 1, 1)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function tween(object, seconds, goal, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function healthColor(ratio)
	if ratio > 0.6 then
		return Color3.fromRGB(110, 215, 90):Lerp(Color3.fromRGB(235, 200, 60), (1 - ratio) / 0.4)
	elseif ratio > 0.3 then
		return Color3.fromRGB(235, 200, 60):Lerp(Color3.fromRGB(230, 90, 60), (0.6 - ratio) / 0.3)
	end
	return Color3.fromRGB(215, 55, 55)
end

local function isBoulder(model)
	return model:IsA("Model") and (model:GetAttribute("IsRubbleBoulder") == true or model.Name == "RubbleBoulder")
end

local function boulderName(model)
	local custom = model:GetAttribute("DisplayName")
	if typeof(custom) == "string" and custom ~= "" then return custom end
	local tier = tonumber(model:GetAttribute("Tier")) or 1
	local names = CFG.DisplayNames or {}
	local name = names[math.clamp(tier, 1, math.max(1, #names))] or "Boulder"
	if model:GetAttribute("GoldenBoulder") == true then return "Golden " .. name end
	if model:GetAttribute("Elite") == true then return "Elite " .. name end
	return name
end

--------------------------------------------------------------------------------
-- 1. ПЛАШКА ХП
--------------------------------------------------------------------------------
local plates = {} -- [model] = record

local function buildPlate(model)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then return nil end
	local ok, boundsCFrame, boundsSize = pcall(function() return model:GetBoundingBox() end)
	if not ok then return nil end
	local top = boundsCFrame.Position + Vector3.new(0, boundsSize.Y / 2 + 1.1, 0)

	local gui = Instance.new("BillboardGui")
	gui.Name = "BoulderPlate"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(236, 46)
	gui.StudsOffsetWorldSpace = top - root.Position
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = CFG.MaxDistance or 70
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	-- v19.5: обычный Frame вместо CanvasGroup — CanvasGroup внутри
	-- BillboardGui на части устройств не рисуется вообще (плашки пропадали).
	-- Показ/скрытие — через BillboardGui.Enabled + «пружинка» масштаба.
	local group = Instance.new("Frame")
	group.Name = "Plate"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.new(1, -6, 1, -6)
	group.BackgroundTransparency = 1
	group.Parent = gui
	local popScale = Instance.new("UIScale")
	popScale.Name = "Pop"
	popScale.Parent = group
	gui.Enabled = false

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(10, 4)
	name.Size = UDim2.new(0.62, -10, 0, 20)
	name.FontFace = NAME_FONT
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = WHITE
	name.Text = boulderName(model)
	name.Parent = group
	textStroke(name, 2)

	local hp = Instance.new("TextLabel")
	hp.Name = "HP"
	hp.BackgroundTransparency = 1
	hp.AnchorPoint = Vector2.new(1, 0)
	hp.Position = UDim2.new(1, -10, 0, 5)
	hp.Size = UDim2.new(0.38, -10, 0, 17)
	hp.FontFace = NAME_FONT
	hp.TextScaled = true
	hp.TextXAlignment = Enum.TextXAlignment.Right
	hp.TextColor3 = WHITE
	hp.Parent = group
	textStroke(hp, 2)

	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -7)
	back.Size = UDim2.new(1, -20, 0, 7)
	back.BackgroundColor3 = Color3.fromRGB(38, 36, 42)
	back.BorderSizePixel = 0
	back.Parent = group
	corner(back, 4)
	local barStroke = Instance.new("UIStroke")
	barStroke.Color = INK
	barStroke.Thickness = 1.5
	barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barStroke.Parent = back
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = WHITE
	trail.BackgroundTransparency = 0.1
	trail.BorderSizePixel = 0
	trail.Parent = back
	corner(trail, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 4)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 190, 190))
	shine.Parent = fill

	local record = {
		Model = model, Gui = gui, Group = group, Hp = hp, Fill = fill, Trail = trail, Root = root,
		ShownUntil = 0, Visible = false, TrailToken = 0,
	}
	local function refresh(animate)
		local health = math.max(0, tonumber(model:GetAttribute("Health")) or 0)
		local maxHealth = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 1)
		local ratio = math.clamp(health / maxHealth, 0, 1)
		hp.Text = NumberFormat.abbreviate(math.ceil(health)) .. " HP"
		fill.BackgroundColor3 = healthColor(ratio)
		if animate then
			tween(fill, 0.12, { Size = UDim2.fromScale(ratio, 1) })
			record.TrailToken += 1
			local token = record.TrailToken
			task.delay(0.28, function()
				if token == record.TrailToken and trail.Parent then
					tween(trail, 0.45, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				end
			end)
		else
			fill.Size = UDim2.fromScale(ratio, 1)
			trail.Size = UDim2.fromScale(ratio, 1)
		end
		if health <= 0 then record.ShownUntil = 0 end
	end
	record.Refresh = refresh
	refresh(false)
	record.Connections = {
		model:GetAttributeChangedSignal("Health"):Connect(function() refresh(true) end),
		model:GetAttributeChangedSignal("MaxHealth"):Connect(function() refresh(false) end),
		model:GetAttributeChangedSignal("Tier"):Connect(function() name.Text = boulderName(model) end),
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				local r = plates[model]
				if r then
					for _, c in r.Connections do c:Disconnect() end
					r.Gui:Destroy()
					plates[model] = nil
				end
			end
		end),
	}
	return record
end

local function track(model)
	if plates[model] or not isBoulder(model) then return end
	plates[model] = false -- ждём атрибуты
	task.spawn(function()
		local deadline = os.clock() + 8
		while model.Parent and (model:GetAttribute("MaxHealth") == nil or not (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))) and os.clock() < deadline do
			task.wait(0.1)
		end
		if not model.Parent then plates[model] = nil return end
		local record = buildPlate(model)
		plates[model] = record or nil
	end)
end

for _, d in workspace:GetDescendants() do
	if d:IsA("Model") and isBoulder(d) then track(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		if isBoulder(d) then track(d) end
		-- Атрибут может приехать позже самой модели.
		if d:GetAttribute("IsRubbleBoulder") == nil then
			local conn
			conn = d:GetAttributeChangedSignal("IsRubbleBoulder"):Connect(function()
				conn:Disconnect()
				track(d)
			end)
			task.delay(5, function() if conn.Connected then conn:Disconnect() end end)
		end
	end
end)

-- Видимость: рядом или недавно били.
local function setVisible(record, visible)
	if record.Visible == visible then return end
	record.Visible = visible
	local pop = record.Group:FindFirstChild("Pop")
	if visible then
		record.Gui.Enabled = true
		if pop then
			pop.Scale = 0.8
			tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	else
		if pop then
			tween(pop, 0.15, { Scale = 0.8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.delay(0.15, function()
			if not record.Visible then record.Gui.Enabled = false end
		end)
	end
end

task.spawn(function()
	while true do
		task.wait(0.15)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local now = os.clock()
		for model, record in plates do
			if record then
				local alive = (tonumber(model:GetAttribute("Health")) or 0) > 0
				local near = hrp and record.Root.Parent and (record.Root.Position - hrp.Position).Magnitude <= (CFG.ShowDistance or 24)
				setVisible(record, alive and (near or now < record.ShownUntil) or false)
			end
		end
	end
end)

local function jolt(record)
	record.ShownUntil = os.clock() + (CFG.HitShowSeconds or 4)
	setVisible(record, true)
	local group = record.Group
	task.spawn(function()
		for i = 1, 5 do
			local k = 1 - i / 5
			group.Position = UDim2.new(0.5, (math.random() - 0.5) * 8 * k, 0.5, (math.random() - 0.5) * 4 * k)
			task.wait(0.025)
		end
		group.Position = UDim2.fromScale(0.5, 0.5)
	end)
end

--------------------------------------------------------------------------------
-- 2. ЦИФРЫ УРОНА
--------------------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "BoulderDamageNumbers"
fxFolder.Parent = workspace

local GRADE_STYLE = {
	Miss = { Text = Color3.fromRGB(190, 190, 195), Scale = 0.85, Sub = "MISS" },
	Good = { Text = WHITE, Scale = 1 },
	Perfect = { Text = Color3.fromRGB(255, 215, 70), Scale = 1.3, Sub = "PERFECT", Stroke = Color3.fromRGB(255, 190, 40) },
	Dynamite = { Text = Color3.fromRGB(255, 160, 70), Scale = 1.25, Sub = "BOOM", Stroke = Color3.fromRGB(255, 120, 40) },
}

local function numberPlate(parent, textValue, color, strokeColor, size, order)
	-- v19.1: без подложки — цифра с тёмной обводкой, как остальной текст игры.
	local label = Instance.new("TextLabel")
	label.Name = "Number"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size + 6)
	label.LayoutOrder = order or 1
	label.FontFace = NUMBER_FONT
	label.TextSize = size
	label.TextColor3 = color
	label.Text = textValue
	label.Parent = parent
	textStroke(label, size >= 24 and 3 or 2, INK)
	local _ = strokeColor
	return label, label
end

local function showNumber(model, amount, grade, final, hitPoint)
	local position = typeof(hitPoint) == "Vector3" and hitPoint
	if not position then
		local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
		position = ok and (cf.Position + Vector3.new(0, size.Y * 0.35, 0)) or nil
	end
	if not position then return end
	position += Vector3.new((math.random() - 0.5) * 1.6, 0.6 + math.random() * 0.6, (math.random() - 0.5) * 1.6)

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = fxFolder

	local style = GRADE_STYLE[grade] or GRADE_STYLE.Good
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(220, 90)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = anchor
	local holder = Instance.new("Frame") -- v19.5: не CanvasGroup (не рисуется в BillboardGui)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = holder
	local pop = Instance.new("UIScale")
	pop.Scale = 0.35
	pop.Parent = holder

	local size = math.floor(24 * style.Scale)
	numberPlate(holder, "-" .. NumberFormat.abbreviate(amount), style.Text, style.Stroke, size, 1)
	if style.Sub then
		numberPlate(holder, style.Sub, style.Text, nil, 14, 2)
	end
	if final then
		numberPlate(holder, "BREAK!", Color3.fromRGB(255, 90, 80), Color3.fromRGB(255, 70, 60), 20, 0)
	end

	-- Пружинка → подъём → таяние.
	tween(pop, 0.18, { Scale = 1.18 }, Enum.EasingStyle.Back)
	task.delay(0.18, function() tween(pop, 0.14, { Scale = 1 }) end)
	local rise = final and 3 or 2.3
	local duration = final and 1.2 or 0.9
	tween(anchor, duration, { CFrame = CFrame.new(position + Vector3.new(0, rise, 0)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(duration - 0.3, function()
		for _, label in holder:GetDescendants() do
			if label:IsA("TextLabel") then
				tween(label, 0.3, { TextTransparency = 1 })
			elseif label:IsA("UIStroke") then
				tween(label, 0.3, { Transparency = 1 })
			end
		end
	end)
	task.delay(duration + 0.05, function() anchor:Destroy() end)
end

--------------------------------------------------------------------------------
-- 3. ВИНЬЕТКА
--------------------------------------------------------------------------------
-- ФИКС v19.2 «БЕЛАЯ ВИНЬЕТКА ВИСИТ ВСЕГДА». Раньше края лежали в
-- полноэкранной CanvasGroup и гасились её GroupTransparency. Но у
-- CanvasGroup есть предел размера текстуры: на больших экранах (и на
-- слабых устройствах) Roblox рисует её содержимое БЕЗ группы, и
-- GroupTransparency просто игнорируется — белые края были видны всегда.
-- Теперь прозрачность задаётся каждому краю напрямую, а в покое весь
-- ScreenGui выключен (Enabled = false) — показать его «случайно» нечем.
local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "BoulderHitVignette"
vignetteGui.IgnoreGuiInset = true
vignetteGui.ResetOnSpawn = false
vignetteGui.DisplayOrder = 8
vignetteGui.Enabled = false
vignetteGui.Parent = playerGui

-- Четыре края с градиентом «цвет у края → прозрачно к центру».
local edges = {}
for _, spec in {
	{ Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0), Rotation = 90 },
	{ Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.68), Rotation = -90 },
	{ Size = UDim2.fromScale(0.26, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
	{ Size = UDim2.fromScale(0.26, 1), Position = UDim2.fromScale(0.74, 0), Rotation = 180 },
} do
	local edge = Instance.new("Frame")
	edge.BorderSizePixel = 0
	edge.Size = spec.Size
	edge.Position = spec.Position
	edge.BackgroundColor3 = WHITE
	edge.BackgroundTransparency = 1
	edge.Parent = vignetteGui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = spec.Rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge
	table.insert(edges, edge)
end

local vignetteToken = 0
local function flashVignette(kind)
	local settings = CFG.Vignette or {}
	local spec = settings[kind] or settings.Good or { Color = WHITE, Alpha = 0.08 }
	local alpha = math.clamp(tonumber(spec.Alpha) or 0.08, 0, settings.MaxAlpha or 0.10)
	vignetteToken += 1
	local token = vignetteToken
	local seconds = settings.Seconds or 0.12
	-- Только в момент удара: мгновенно вспыхнула и тут же погасла.
	for _, edge in edges do
		edge.BackgroundColor3 = spec.Color or WHITE
		edge.BackgroundTransparency = 1 - alpha
		tween(edge, seconds, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	vignetteGui.Enabled = true
	task.delay(seconds + 0.05, function()
		if token ~= vignetteToken then return end
		vignetteGui.Enabled = false
		for _, edge in edges do edge.BackgroundTransparency = 1 end
	end)
end

--------------------------------------------------------------------------------
-- СОБЫТИЕ УДАРА
--------------------------------------------------------------------------------
local remote = ReplicatedStorage.Shared:WaitForChild("BoulderHitFx", 30)
if remote then
	remote.OnClientEvent:Connect(function(model, amount, grade, final, hitPoint)
		if typeof(model) ~= "Instance" then return end
		amount = tonumber(amount) or 0
		grade = typeof(grade) == "string" and grade or "Good"
		local record = plates[model]
		if record then jolt(record) end
		if amount > 0 then pcall(showNumber, model, amount, grade, final == true, hitPoint) end
		flashVignette(final and "Final" or grade)
	end)
end
