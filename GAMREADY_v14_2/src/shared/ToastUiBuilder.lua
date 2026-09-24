--------------------------------------------------------------------------------
-- ToastUiBuilder — уведомления в стиле Grow a Garden (v14.3).
--
-- ОДИН источник правды для двух мест:
--   • tools/BuildNotificationUI.lua (Command Bar) кладёт результат в
--     StarterGui — дальше вид правится мышкой в Studio;
--   • CustomCartUI.client.lua строит то же самое сам, если в StarterGui нет
--     свежего Toast (атрибут ToastUiVersion меньше VERSION).
--
-- СТРУКТУРА:
--   ScreenGui "Toast"
--   └─ Frame "Stack"                — точка крепления стопки (сверху по центру)
--        ├─ UIScale "AutoScale"     — клиент уменьшает на телефонах
--        └─ Frame "Panel"           — ШАБЛОН одной карточки (Visible = false,
--             │                       клиент его клонирует, на экране максимум 2)
--             ├─ UIScale "Pop"
--             ├─ ImageLabel "Skin"  — пустой Image = видна обычная плашка;
--             │                       поставь свой rbxassetid — и карточка
--             │                       примет твой вид (Slice)
--             ├─ Frame "Accent"     — цветная полоска слева (цвет по иконке)
--             ├─ ImageLabel "Icon" / ViewportFrame "IconViewport"
--             ├─ TextLabel "Text"
--             ├─ TextLabel "Count"  — «x3», когда одинаковые склеились
--             └─ TextButton "ActionButton" → TextLabel "Caption"
--
-- Меняй размеры/цвета/шрифты как хочешь: клиент ищет детали ПО ИМЕНАМ и
-- берёт размер карточки из самого шаблона.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = {}
Builder.VERSION = 2

local CREAM = Color3.fromRGB(255, 244, 214)
local WOOD = Color3.fromRGB(122, 78, 42)
local WOOD_DARK = Color3.fromRGB(58, 34, 16)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, name, mode)
	local s = Instance.new("UIStroke")
	s.Name = name or "UIStroke"
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

function Builder.Build()
	local okCfg, Config = pcall(require, ReplicatedStorage.Shared.Config)
	local defaultIcon = okCfg and Config.Notify and Config.Notify.Icons and Config.Notify.Icons.Default or 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "Toast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("ToastUiVersion", Builder.VERSION)

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 58)
	stack.Size = UDim2.fromOffset(300, 110)
	stack.BackgroundTransparency = 1
	stack.Parent = gui
	local autoScale = Instance.new("UIScale")
	autoScale.Name = "AutoScale"
	autoScale.Parent = stack

	-- ШАБЛОН КАРТОЧКИ — компактная «деревянная» плашка с кремовой рамкой.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 0)
	panel.Size = UDim2.fromOffset(290, 46)
	panel.BackgroundColor3 = WOOD
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = stack
	corner(panel, UDim.new(0, 12))
	stroke(panel, WOOD_DARK, 3, "Outline")
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 170, 150))
	gradient.Parent = panel
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = panel

	local skin = Instance.new("ImageLabel")
	skin.Name = "Skin"
	skin.Size = UDim2.fromScale(1, 1)
	skin.BackgroundTransparency = 1
	skin.Image = "" -- ← свой ассет
	skin.ScaleType = Enum.ScaleType.Slice
	skin.SliceCenter = Rect.new(24, 24, 40, 40)
	skin.ZIndex = 1
	skin.Parent = panel

	-- Кремовая «вставка» внутри дерева — как у табличек в GaG.
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -8, 1, -8)
	inner.BackgroundColor3 = Color3.fromRGB(96, 60, 30)
	inner.BackgroundTransparency = 0.35
	inner.BorderSizePixel = 0
	inner.ZIndex = 1
	inner.Parent = panel
	corner(inner, UDim.new(0, 9))

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.AnchorPoint = Vector2.new(0, 0.5)
	accent.Position = UDim2.new(0, 7, 0.5, 0)
	accent.Size = UDim2.new(0, 5, 1, -16)
	accent.BackgroundColor3 = Color3.fromRGB(120, 230, 90)
	accent.BorderSizePixel = 0
	accent.ZIndex = 3
	accent.Parent = panel
	corner(accent, UDim.new(1, 0))

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	icon.Size = UDim2.fromOffset(32, 32)
	icon.BackgroundTransparency = 1
	icon.Image = defaultIcon ~= 0 and ("rbxassetid://" .. tostring(defaultIcon)) or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 3
	icon.Parent = panel

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "IconViewport"
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	viewport.Position = UDim2.new(0, 14, 0.5, 0)
	viewport.Size = UDim2.fromOffset(36, 36)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(220, 220, 230)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Visible = false
	viewport.ZIndex = 3
	viewport.Parent = panel

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Position = UDim2.new(0, 54, 0, 5)
	text.Size = UDim2.new(1, -64, 1, -10)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextColor3 = CREAM
	text.Text = ""
	text.ZIndex = 3
	text.Parent = panel
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = 20
	textSize.Parent = text
	stroke(text, WOOD_DARK, 2, "TextStroke", Enum.ApplyStrokeMode.Contextual)

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.new(1, 6, 0, 2)
	count.Size = UDim2.fromOffset(34, 22)
	count.BackgroundColor3 = Color3.fromRGB(255, 196, 40)
	count.BorderSizePixel = 0
	count.Font = Enum.Font.FredokaOne
	count.TextScaled = true
	count.TextColor3 = Color3.new(1, 1, 1)
	count.Text = "x2"
	count.Visible = false
	count.ZIndex = 5
	count.Parent = panel
	corner(count, UDim.new(1, 0))
	stroke(count, WOOD_DARK, 2, "Outline")
	stroke(count, WOOD_DARK, 1.5, "TextStroke", Enum.ApplyStrokeMode.Contextual)

	-- Кнопка-действие («Open Shop», «Invite»): маленькая зелёная пилюля справа.
	local action = Instance.new("TextButton")
	action.Name = "ActionButton"
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -8, 0.5, 0)
	action.Size = UDim2.fromOffset(84, 28)
	action.BackgroundColor3 = Color3.fromRGB(96, 200, 72)
	action.AutoButtonColor = true
	action.Text = ""
	action.Visible = false
	action.ZIndex = 4
	action.Parent = panel
	corner(action, UDim.new(1, 0))
	stroke(action, Color3.fromRGB(30, 80, 20), 2.5, "Outline")
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, -10, 1, -6)
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.5)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextScaled = true
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.Text = "Open Shop"
	caption.ZIndex = 5
	caption.Parent = action
	stroke(caption, Color3.fromRGB(30, 80, 20), 1.5, "TextStroke", Enum.ApplyStrokeMode.Contextual)

	return gui
end

return Builder
