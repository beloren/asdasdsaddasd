--------------------------------------------------------------------------------
-- WorldPrompts (LocalScript) — ПРОМПТЫ ВЗАИМОДЕЙСТВИЯ НА САМИХ ОБЪЕКТАХ.
--
-- Все промпты игры — Style = Custom (стандартный серый Roblox не рисуется).
-- Раньше их показывала ОДНА плашка внизу экрана (CustomCartUI). Теперь
-- каждый видимый промпт — BillboardGui прямо на объекте: тёмный полупрозрачный
-- кружок с клавишей ("E", "X" на геймпаде, палец на телефоне) и подпись
-- действия справа белым с обводкой ("Collect", "Shop", "Talk").
--
-- Показывается ОДИН промпт — лучший: сначала разговор с NPC
-- (PromptKind = "Talk"), затем ближайший. Та же логика, что была у экранной
-- плашки, включая владельца (OwnerUserId) и разрешение на кражу (Stealable).
--
-- АНИМАЦИИ: появление — "пружинка" масштаба + проявление + лёгкий подъём;
-- исчезновение — сжатие и угасание; клик — удар кружка, волна-кольцо и
-- вспышка клавиши; удержание — круговое заполнение обводки по часовой
-- стрелке от 12 часов (у мгновенных промптов кольцо пробегает круг при
-- клике). Под кружком — слабая мягкая тень.
--
-- Удержание (HoldDuration > 0) — кружок заполняется. Телефон: тап по
-- кружку/подписи жмёт промпт (InputHoldBegin/End), ровно как раньше тап по
-- экранной плашке. Выключается Config.UI.WorldPrompts = false.
--
-- Атрибуты промпта (необязательно):
--   PromptOffset (Vector3) — сдвиг билборда от точки промпта, студ;
--   PromptColor = "Blue"   — синий кружок (как у прежней плашки).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)

if Config.UI and Config.UI.WorldPrompts == false then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function tr(text)
	if not text or text == "" then return "" end
	local ok, translated = pcall(Localization.Translate, player.LocaleId, text)
	return ok and translated or text
end

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local CIRCLE = 46
local CIRCLE_COLOR = Color3.fromRGB(25, 25, 25)
local BLUE = Color3.fromRGB(45, 105, 190)

local container = Instance.new("Folder")
container.Name = "WorldPrompts"
container.Parent = playerGui

--------------------------------------------------------------------------------
-- ОДИН БИЛБОРД, ПЕРЕВЕШИВАЕТСЯ НА АКТИВНЫЙ ПРОМПТ
--------------------------------------------------------------------------------
local billboard = Instance.new("BillboardGui")
billboard.Name = "Prompt"
-- Холст с запасом по высоте: волна клика расходится до ~2x кружка и не
-- должна обрезаться краем билборда.
billboard.Size = UDim2.fromOffset(280, math.floor(CIRCLE * 2.4))
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Active = true
billboard.Enabled = false
billboard.Parent = container

local root = Instance.new("TextButton")
root.Name = "Root"
root.Text = ""
root.AutoButtonColor = false
root.BackgroundTransparency = 1
-- Центр билборда — центр кружка: подпись уходит вправо, а сам кружок
-- стоит ровно на точке взаимодействия (как на референсе).
root.AnchorPoint = Vector2.new(0, 0.5)
root.Position = UDim2.new(0.5, -CIRCLE / 2, 0.5, 0)
root.Size = UDim2.new(0.5, CIRCLE / 2, 0, CIRCLE + 8)
root.Parent = billboard

local scale = Instance.new("UIScale")
scale.Parent = root

local function roundCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
	return corner
end

-- Тень: мягкий тёмный круг чуть крупнее кружка, сдвинутый вниз. Край
-- размыт радиальным затуханием (UIGradient по двум осям не бывает, поэтому
-- две вложенные "полутени" разной прозрачности).
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0, CIRCLE / 2, 0.5, 4)
shadow.Size = UDim2.fromOffset(CIRCLE + 8, CIRCLE + 8)
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.88
shadow.ZIndex = 0
shadow.Parent = root
roundCorner(shadow)
local shadowCore = Instance.new("Frame")
shadowCore.Name = "Core"
shadowCore.AnchorPoint = Vector2.new(0.5, 0.5)
shadowCore.Position = UDim2.fromScale(0.5, 0.5)
shadowCore.Size = UDim2.new(1, -6, 1, -6)
shadowCore.BackgroundColor3 = Color3.new(0, 0, 0)
shadowCore.BackgroundTransparency = 0.8
shadowCore.ZIndex = 0
shadowCore.Parent = shadow
roundCorner(shadowCore)

local circle = Instance.new("Frame")
circle.Name = "Circle"
circle.AnchorPoint = Vector2.new(0.5, 0.5)
circle.Position = UDim2.new(0, CIRCLE / 2, 0.5, 0)
circle.Size = UDim2.fromOffset(CIRCLE, CIRCLE)
circle.BackgroundColor3 = CIRCLE_COLOR
circle.BackgroundTransparency = 0.35
circle.ZIndex = 1
circle.Parent = root
roundCorner(circle)
local circleScale = Instance.new("UIScale")
circleScale.Parent = circle

-- КРУГОВОЕ ЗАПОЛНЕНИЕ. Кольцо = обводка круга, к обводке привязан
-- UIGradient "видно одну половину": поворот градиента двигает видимую
-- половину по кругу. Две клип-рамки (правая и левая половины кружка)
-- показывают каждая свой полукруг: правая заполняется при прогрессе
-- 0…0.5 (поворот 0→180°), левая — при 0.5…1 (поворот 180→360°). Итог —
-- сплошная дуга по часовой стрелке от 12 часов.
local RING_THICKNESS = 4
local function ringHalf(name, isRight)
	local clip = Instance.new("Frame")
	clip.Name = name
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Size = UDim2.fromScale(0.5, 1)
	clip.Position = UDim2.fromScale(isRight and 0.5 or 0, 0)
	clip.ZIndex = 3
	clip.Parent = circle
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.new(2, -RING_THICKNESS, 1, -RING_THICKNESS)
	ring.Position = UDim2.new(isRight and -1 or 0, RING_THICKNESS / 2, 0, RING_THICKNESS / 2)
	ring.ZIndex = 3
	ring.Parent = clip
	roundCorner(ring)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = RING_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = isRight and 0 or 180
	gradient.Parent = stroke
	return gradient, stroke
end
local rightGradient, rightStroke = ringHalf("RingRight", true)
local leftGradient, leftStroke = ringHalf("RingLeft", false)

local function setProgress(progress)
	progress = math.clamp(progress, 0, 1)
	rightGradient.Rotation = math.min(progress, 0.5) * 360
	leftGradient.Rotation = 180 + math.max(progress - 0.5, 0) * 360
	local visible = progress > 0.001
	rightStroke.Enabled = visible
	leftStroke.Enabled = visible
end
setProgress(0)

-- Клавиша: скруглённый квадрат с белой рамкой.
local key = Instance.new("TextLabel")
key.Name = "Key"
key.AnchorPoint = Vector2.new(0.5, 0.5)
key.Position = UDim2.fromScale(0.5, 0.5)
key.Size = UDim2.fromOffset(26, 26)
key.BackgroundColor3 = Color3.new(1, 1, 1)
key.BackgroundTransparency = 1
key.FontFace = FONT
key.TextSize = 15
key.TextColor3 = Color3.new(1, 1, 1)
key.Text = "E"
key.ZIndex = 4
key.Parent = circle
local keyCorner = Instance.new("UICorner")
keyCorner.CornerRadius = UDim.new(0, 6)
keyCorner.Parent = key
local keyStroke = Instance.new("UIStroke")
keyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
keyStroke.Color = Color3.new(1, 1, 1)
keyStroke.Thickness = 2
keyStroke.Parent = key

-- Волна при клике — кольцо, расходящееся от кружка.
local ripple = Instance.new("Frame")
ripple.Name = "Ripple"
ripple.AnchorPoint = Vector2.new(0.5, 0.5)
ripple.Position = UDim2.new(0, CIRCLE / 2, 0.5, 0)
ripple.Size = UDim2.fromOffset(CIRCLE, CIRCLE)
ripple.BackgroundTransparency = 1
ripple.ZIndex = 0
ripple.Parent = root
roundCorner(ripple)
local rippleStroke = Instance.new("UIStroke")
rippleStroke.Color = Color3.new(1, 1, 1)
rippleStroke.Thickness = 3
rippleStroke.Transparency = 1
rippleStroke.Parent = ripple

local label = Instance.new("TextLabel")
label.Name = "Action"
label.AnchorPoint = Vector2.new(0, 0.5)
label.Position = UDim2.new(0, CIRCLE + 8, 0.5, 0)
label.Size = UDim2.new(1, -(CIRCLE + 8), 1, 0)
label.BackgroundTransparency = 1
label.FontFace = FONT
label.TextSize = 20
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = ""
label.ZIndex = 2
label.Parent = root
local labelStroke = Instance.new("UIStroke")
labelStroke.Color = Color3.new(0, 0, 0)
labelStroke.Thickness = 2
labelStroke.Transparency = 0.2
labelStroke.Parent = label

-- v18: ВТОРИЧНЫЙ ПРОМПТ на том же объекте (атрибут SecondaryPrompt = true),
-- например «[F] Apply Frozen Essence» под «Choose Ore» у подиума. Показывается
-- мелкой строкой под главным; на телефоне по ней можно тапнуть.
local secondaryButton = Instance.new("TextButton")
secondaryButton.Name = "Secondary"
secondaryButton.AutoButtonColor = false
secondaryButton.AnchorPoint = Vector2.new(0, 0)
secondaryButton.Position = UDim2.new(0, CIRCLE + 8, 0.5, 14)
secondaryButton.Size = UDim2.new(1, -(CIRCLE + 8), 0, 22)
secondaryButton.BackgroundColor3 = Color3.fromRGB(120, 60, 170)
secondaryButton.BackgroundTransparency = 0.15
secondaryButton.FontFace = FONT
secondaryButton.TextSize = 14
secondaryButton.TextColor3 = Color3.new(1, 1, 1)
secondaryButton.TextXAlignment = Enum.TextXAlignment.Left
secondaryButton.AutomaticSize = Enum.AutomaticSize.X
secondaryButton.Visible = false
secondaryButton.ZIndex = 3
secondaryButton.Parent = root
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = secondaryButton
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 6)
	p.PaddingRight = UDim.new(0, 8)
	p.Parent = secondaryButton
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = 1.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Parent = secondaryButton
end
local secondaryPrompt = nil
secondaryButton.Activated:Connect(function()
	local prompt = secondaryPrompt
	if not (prompt and prompt.Parent and prompt.Enabled) then return end
	pcall(function() prompt:InputHoldBegin() end)
	task.delay((prompt.HoldDuration or 0) + 0.05, function()
		pcall(function() prompt:InputHoldEnd() end)
	end)
end)

--------------------------------------------------------------------------------
-- ПРОЗРАЧНОСТЬ ВСЕГО ПРОМПТА ОДНИМ ЧИСЛОМ (для появления/исчезновения)
--------------------------------------------------------------------------------
-- [объект] = { свойство, базовая прозрачность }
local fadeTargets = {
	{ shadow, "BackgroundTransparency", 0.88 },
	{ shadowCore, "BackgroundTransparency", 0.8 },
	{ circle, "BackgroundTransparency", 0.35 },
	{ key, "TextTransparency", 0 },
	{ keyStroke, "Transparency", 0 },
	{ label, "TextTransparency", 0 },
	{ labelStroke, "Transparency", 0.2 },
	{ rightStroke, "Transparency", 0 },
	{ leftStroke, "Transparency", 0 },
}
local alpha = Instance.new("NumberValue")
alpha.Value = 0
local function applyAlpha(value)
	for _, target in fadeTargets do
		local object, property, base = target[1], target[2], target[3]
		object[property] = 1 - value * (1 - base)
	end
end
alpha.Changed:Connect(applyAlpha)
applyAlpha(0)

local visibleToken = 0

local function animateIn()
	visibleToken += 1
	billboard.Enabled = true
	scale.Scale = 0.35
	root.Position = UDim2.new(0.5, -CIRCLE / 2, 0.5, 10)
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(root, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -CIRCLE / 2, 0.5, 0),
	}):Play()
	TweenService:Create(alpha, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 }):Play()
end

local function animateOut()
	visibleToken += 1
	local myToken = visibleToken
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.4 }):Play()
	local fade = TweenService:Create(alpha, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	fade.Completed:Connect(function()
		if myToken == visibleToken then
			billboard.Enabled = false
			billboard.Adornee = nil
		end
	end)
	fade:Play()
end

--------------------------------------------------------------------------------
-- ПОДПИСЬ: единый вид "Grab Cart" / "Взять тележку"
--------------------------------------------------------------------------------
-- Серверные ActionText исторически пишутся кто как (GRAB CART, Take Cart,
-- Shop) — на экране их приводим к одному виду: каждое слово с заглавной.
-- string.lower/upper в Luau работают только с ASCII, поэтому кириллица
-- переводится вручную по кодовым точкам (А–Я ↔ а–я, Ё ↔ ё).
local function lowerCode(code)
	if code >= 65 and code <= 90 then return code + 32 end
	if code >= 0x0410 and code <= 0x042F then return code + 32 end
	if code == 0x0401 then return 0x0451 end
	return code
end
local function upperCode(code)
	if code >= 97 and code <= 122 then return code - 32 end
	if code >= 0x0430 and code <= 0x044F then return code - 32 end
	if code == 0x0451 then return 0x0401 end
	return code
end
local function titleCase(text)
	local ok, result = pcall(function()
		local out = {}
		local startOfWord = true
		for _, code in utf8.codes(text) do
			if code == 32 or code == 45 then
				table.insert(out, code)
				startOfWord = true
			else
				table.insert(out, startOfWord and upperCode(code) or lowerCode(code))
				startOfWord = false
			end
		end
		return utf8.char(table.unpack(out))
	end)
	return ok and result or text
end

--------------------------------------------------------------------------------
-- БЕЛАЯ ОБВОДКА объекта взаимодействия (Highlight), плавно появляется и
-- гаснет. Два экземпляра: пока старый гаснет, новый уже проявляется на
-- следующем объекте. Свой персонаж не обводится (кристалл над головой).
--------------------------------------------------------------------------------
local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "LocalPromptHighlights"
highlightFolder.Parent = workspace

local function newHighlight()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = highlightFolder
	return highlight
end
local highlights = { newHighlight(), newHighlight() }
local currentHighlight = nil
local highlightIndex = 0
local HIGHLIGHT_FILL = 0.88   -- едва заметная белая дымка внутри
local HIGHLIGHT_FADE = 0.25
local MAX_HIGHLIGHT_SIZE = 25 -- студ; крупнее — обводим только деталь с промптом

local function highlightTargetFor(instance)
	if not instance then return nil end
	local character = player.Character
	if character and instance:IsDescendantOf(character) then return nil end
	local part = instance:IsA("BasePart") and instance
		or (instance.Parent and instance.Parent:IsA("BasePart") and instance.Parent)
		or nil
	-- Ближайшая Model над точкой промпта (NPC, тележка, сейф) — если она
	-- размером с объект. Промпт внутри большой модели (сейф в модели
	-- участка) иначе обвёл бы весь участок: тогда — только сама деталь.
	local model = (part or instance):FindFirstAncestorWhichIsA("Model")
	if model and model ~= workspace then
		local ok, size = pcall(function() return model:GetExtentsSize() end)
		if ok and math.max(size.X, size.Y, size.Z) <= MAX_HIGHLIGHT_SIZE then
			return model
		end
	end
	return part
end

local function fadeHighlight(highlight, visible)
	local tween = TweenService:Create(highlight, TweenInfo.new(HIGHLIGHT_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		OutlineTransparency = visible and 0 or 1,
		FillTransparency = visible and HIGHLIGHT_FILL or 1,
	})
	if not visible then
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and highlight ~= currentHighlight then
				highlight.Enabled = false
				highlight.Adornee = nil
			end
		end)
	end
	tween:Play()
end

local function setHighlight(target)
	if currentHighlight and currentHighlight.Adornee == target and target then return end
	if currentHighlight then
		local old = currentHighlight
		currentHighlight = nil
		fadeHighlight(old, false)
	end
	if not target then return end
	-- Попеременно: пока предыдущая обводка гаснет, новая проявляется.
	highlightIndex = highlightIndex % #highlights + 1
	local highlight = highlights[highlightIndex]
	highlight.Adornee = target
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 1
	highlight.Enabled = true
	currentHighlight = highlight
	fadeHighlight(highlight, true)
end

--------------------------------------------------------------------------------
-- ВЫБОР АКТИВНОГО ПРОМПТА
--------------------------------------------------------------------------------
local shown = {} -- [prompt] = inputType
local active = nil        -- ProximityPrompt или VIRTUAL_CART
local activeInput = nil
local holdStarted = nil   -- os.clock() начала удержания
local holdDuration = 0
local sweepStarted = nil  -- быстрый пробег кольца при клике
local SWEEP_TIME = 0.22

-- "Отпустить тележку" — не ProximityPrompt (тележка отпускается клавишей E
-- или кликом, см. CustomCartUI), но выглядеть должна как все промпты:
-- висит на тележке в руках, пока ничего важнее рядом нет.
local VIRTUAL_CART = { ActionText = "RELEASE CART" }
local dropRemote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DropCartRequest", 10)

-- Тележка в руках. Модель кэшируется: полный обход workspace — только
-- когда кэш устарел (другая тележка или её отпустили), а не каждые 0.2 с.
local cartModelCache = nil
local function heldCartPart()
	if player:GetAttribute("CarryingCart") ~= true then
		cartModelCache = nil
		return nil
	end
	local model = cartModelCache
	if not (model and model.Parent and model:GetAttribute("HolderUserId") == player.UserId) then
		model = nil
		for _, candidate in workspace:GetDescendants() do
			if candidate:IsA("Model") and candidate:GetAttribute("HolderUserId") == player.UserId then
				model = candidate
				break
			end
		end
		cartModelCache = model
	end
	return model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) or nil
end
local cachedCartPart = nil

local function canUse(prompt)
	local owner = prompt:GetAttribute("OwnerUserId")
	if not owner or owner == player.UserId then return true end
	return prompt:GetAttribute("Stealable") == true
end

local function worldPosition(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	if parent and parent:IsA("BasePart") then return parent.Position end
	if parent and parent:IsA("Model") then return parent:GetPivot().Position end
	return nil
end

local function currentInputType()
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then return Enum.ProximityPromptInputType.Touch end
	if last.Name:find("Gamepad") then return Enum.ProximityPromptInputType.Gamepad end
	return Enum.ProximityPromptInputType.Keyboard
end

local function keyText(prompt, inputType)
	-- В Enum.ProximityPromptInputType только Keyboard/Gamepad/Touch —
	-- отдельного типа для клика мышью нет (обращение к несуществующему
	-- члену Enum роняет скрипт).
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		if prompt == VIRTUAL_CART then return "X" end
		return (prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	if prompt == VIRTUAL_CART then return "E" end
	local name = prompt.KeyboardKeyCode.Name
	return string.len(name) <= 3 and name or string.sub(name, 1, 3)
end

local function resetFill()
	holdStarted = nil
	sweepStarted = nil
	setProgress(0)
end

local function show(prompt, inputType, fresh)
	local adornee, highlightFrom
	if prompt == VIRTUAL_CART then
		adornee = cachedCartPart
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
		circle.BackgroundColor3 = CIRCLE_COLOR
		highlightFrom = nil -- свою тележку в руках не обводим
	else
		adornee = prompt.Parent
		if adornee and adornee:IsA("Model") then
			adornee = adornee.PrimaryPart or adornee:FindFirstChildWhichIsA("BasePart", true)
		end
		local offset = prompt:GetAttribute("PromptOffset")
		billboard.StudsOffsetWorldSpace = typeof(offset) == "Vector3" and offset or Vector3.zero
		circle.BackgroundColor3 = prompt:GetAttribute("PromptColor") == "Blue" and BLUE or CIRCLE_COLOR
		highlightFrom = prompt.Parent
	end
	billboard.Adornee = adornee
	billboard.MaxDistance = math.huge

	local action = tr(prompt.ActionText)
	if action == "" and prompt ~= VIRTUAL_CART then action = tr(prompt.ObjectText) end
	label.Text = titleCase(action)
	-- v18: вторичный промпт того же объекта.
	secondaryPrompt = nil
	if prompt ~= VIRTUAL_CART and prompt.Parent then
		for _, sibling in prompt.Parent:GetChildren() do
			if sibling ~= prompt and sibling:IsA("ProximityPrompt") and sibling.Enabled
				and sibling:GetAttribute("SecondaryPrompt") == true and canUse(sibling) then
				secondaryPrompt = sibling
				break
			end
		end
	end
	if secondaryPrompt then
		local secondaryKey = inputType == Enum.ProximityPromptInputType.Touch and "👆"
			or keyText(secondaryPrompt, inputType)
		secondaryButton.Text = ("[%s] %s"):format(secondaryKey, titleCase(tr(secondaryPrompt.ActionText)))
		secondaryButton.Visible = true
	else
		secondaryButton.Visible = false
	end
	key.Text = keyText(prompt, inputType)
	key.TextSize = key.Text == "👆" and 18 or 15
	keyStroke.Enabled = key.Text ~= "👆"

	setHighlight(highlightTargetFor(highlightFrom))
	if fresh then animateIn() end
end

local function refresh()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local best, bestInput, bestPriority, bestDistance = nil, nil, -math.huge, math.huge
	for prompt, inputType in shown do
		if prompt.Parent and prompt.Enabled and canUse(prompt) and prompt:GetAttribute("SecondaryPrompt") ~= true then
			local position = worldPosition(prompt)
			local priority = prompt:GetAttribute("PromptKind") == "Talk" and 2 or 1
			local distance = (hrp and position) and (position - hrp.Position).Magnitude or 0
			if priority > bestPriority or (priority == bestPriority and distance < bestDistance) then
				best, bestInput, bestPriority, bestDistance = prompt, inputType, priority, distance
			end
		end
	end
	-- Ничего рядом, а в руках тележка — "Отпустить тележку" на ней самой.
	if not best then
		cachedCartPart = heldCartPart()
		if cachedCartPart then
			best, bestInput = VIRTUAL_CART, currentInputType()
		end
	end
	local changed = best ~= active
	if changed then resetFill() end
	if best then
		-- Новый промпт (или переход на другой объект) — проигрываем
		-- появление; тот же промпт — только обновляем текст/клавишу.
		show(best, bestInput, changed)
	elseif changed and active then
		animateOut()
		setHighlight(nil)
	end
	active = best
	activeInput = bestInput
end

local attributeConnections = {}

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	shown[prompt] = inputType
	if not attributeConnections[prompt] then
		attributeConnections[prompt] = {
			prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh),
			prompt:GetAttributeChangedSignal("Stealable"):Connect(refresh),
			prompt:GetPropertyChangedSignal("ActionText"):Connect(refresh),
			prompt:GetPropertyChangedSignal("Enabled"):Connect(refresh),
		}
	end
	refresh()
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	shown[prompt] = nil
	local connections = attributeConnections[prompt]
	if connections then
		attributeConnections[prompt] = nil
		for _, connection in connections do connection:Disconnect() end
	end
	refresh()
end)

player:GetAttributeChangedSignal("CarryingCart"):Connect(function()
	-- Тележка появляется в руках на кадр позже атрибута — даём ей встать.
	task.defer(refresh)
	task.delay(0.2, refresh)
end)

-- Анимация клика (общая для настоящих промптов и "Отпустить тележку").
local function playClick()
	-- Мгновенный промпт — кольцо коротко пробегает полный круг; после
	-- удержания оно уже полное — держим его полным и гасим, без повтора.
	local wasHolding = holdStarted ~= nil
	holdStarted = nil
	sweepStarted = os.clock() - (wasHolding and SWEEP_TIME or 0)

	circleScale.Scale = 1.28
	TweenService:Create(circleScale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	ripple.Size = UDim2.fromOffset(CIRCLE, CIRCLE)
	rippleStroke.Thickness = 3
	rippleStroke.Transparency = 0.1
	TweenService:Create(ripple, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(CIRCLE * 2.1, CIRCLE * 2.1),
	}):Play()
	TweenService:Create(rippleStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1, Thickness = 1,
	}):Play()

	key.BackgroundTransparency = 0.1
	key.TextColor3 = CIRCLE_COLOR
	TweenService:Create(key, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1),
	}):Play()
end

local function releaseCartNow()
	if active ~= VIRTUAL_CART then return end
	playClick()
	if dropRemote then dropRemote:FireServer() end
end

-- E на клавиатуре отпускает тележку в CustomCartUI; здесь — только
-- анимация клика на её промпте.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or active ~= VIRTUAL_CART then return end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
		playClick()
	end
end)

-- НАЖАТИЕ И УДЕРЖАНИЕ: кружок чуть проседает, кольцо заполняется по кругу.
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	if prompt ~= active then return end
	holdStarted = os.clock()
	holdDuration = math.max(prompt.HoldDuration, 0.05)
	sweepStarted = nil
	TweenService:Create(circleScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.9 }):Play()
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	if prompt ~= active then return end
	holdStarted = nil
	-- Отпустил раньше времени — кольцо быстро "сматывается" обратно.
	TweenService:Create(circleScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end)

-- КЛИК (срабатывание): удар кружка, волна-кольцо, вспышка клавиши.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt == active then playClick() end
end)

-- Кадр: прогресс кольца.
RunService.RenderStepped:Connect(function()
	if not billboard.Enabled then return end
	if holdStarted then
		setProgress((os.clock() - holdStarted) / holdDuration)
	elseif sweepStarted then
		local t = (os.clock() - sweepStarted) / SWEEP_TIME
		if t >= 1.6 then
			sweepStarted = nil
			setProgress(0)
		else
			setProgress(math.min(t, 1))
		end
	elseif rightStroke.Enabled then
		-- Отпустили удержание — дуга плавно убывает к нулю.
		local current = (rightGradient.Rotation / 360) + math.max(0, (leftGradient.Rotation - 180) / 360)
		setProgress(current - 0.08)
	end
end)

-- Тап/клик по билборду жмёт активный промпт (телефон, а также мышь для
-- промптов без ClickablePrompt).
root.InputBegan:Connect(function(input)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		if active == VIRTUAL_CART then
			releaseCartNow()
		else
			active:InputHoldBegin()
		end
	end
end)
root.InputEnded:Connect(function(input)
	if not active or active == VIRTUAL_CART then return end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		active:InputHoldEnd()
	end
end)

-- ПРОМПТЫ ИЗ STUDIO со стандартным стилем тоже переводим на свой вид —
-- локально, до показа (свойство Style на клиенте влияет только на то, как
-- промпт рисуется у этого игрока). Атрибут KeepDefaultStyle = true —
-- оставить стандартный вид Roblox.
local function adopt(instance)
	if instance:IsA("ProximityPrompt") and instance.Style ~= Enum.ProximityPromptStyle.Custom
		and instance:GetAttribute("KeepDefaultStyle") ~= true then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end
for _, instance in workspace:GetDescendants() do adopt(instance) end
workspace.DescendantAdded:Connect(adopt)

-- Ближайший промпт меняется, пока игрок идёт, — пересчёт несколько раз в
-- секунду, а не только на Shown/Hidden.
task.spawn(function()
	while true do
		task.wait(0.2)
		if next(shown) or active or player:GetAttribute("CarryingCart") == true then refresh() end
	end
end)

UserInputService.LastInputTypeChanged:Connect(function()
	if active then show(active, activeInput, false) end
end)
