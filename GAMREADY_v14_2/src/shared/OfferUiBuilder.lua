--------------------------------------------------------------------------------
-- OfferUiBuilder (v10) — КОНТЕКСТНЫЕ ПРЕДЛОЖЕНИЯ и кнопка 🚀 Rocket Pickaxe.
-- Свой стиль: «купон» — тёмная плашка-билет с ярким ценником справа и
-- пунктирной отрывной линией. Стопка купонов справа посередине экрана.
-- tools/BuildOfferUI.lua (или tools/BuildAllUI.lua) → StarterGui/OfferUi;
-- OfferPrompts.client.lua без неё строит сам.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "OfferUi" (BuilderVersion)
--   ├─ Frame "Stack" (UIListLayout, UIScale "AutoScale")
--   │    └─ TextButton "OfferTemplate" → "Icon", "Label", Frame "Price" → "Text",
--   │         TextButton "Close", UIScale "Pop", UIStroke "Glow"
--   └─ TextButton "RocketButton" → "Icon", "State", Frame "Cooldown" (шторка)
--------------------------------------------------------------------------------
local Builder = {}
Builder.VERSION = 1

local INK = Color3.fromRGB(14, 10, 20)
local TICKET = Color3.fromRGB(36, 30, 52)
local TAG = Color3.fromRGB(255, 200, 50)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end
local function stroke(parent, thickness, color, contextual, name)
	local s = Instance.new("UIStroke")
	s.Name = name or "Outline"
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function text(parent, name, size, position, content, color, font)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = size
	t.Position = position or UDim2.new()
	t.BackgroundTransparency = 1
	t.Text = content or ""
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.RichText = true
	t.Parent = parent
	stroke(t, 2, INK, true)
	return t
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "OfferUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("BuilderVersion", Builder.VERSION)

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(1, 0.5)
	stack.Position = UDim2.new(1, -14, 0.55, 0)
	stack.Size = UDim2.fromOffset(250, 260)
	stack.BackgroundTransparency = 1
	stack.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stack
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = stack

	-- КУПОН
	local offer = Instance.new("TextButton")
	offer.Name = "OfferTemplate"
	offer.Visible = false
	offer.Text = ""
	offer.AutoButtonColor = false
	offer.Size = UDim2.fromOffset(240, 54)
	offer.BackgroundColor3 = TICKET
	offer.Parent = stack
	corner(offer, UDim.new(0, 14))
	stroke(offer, 3, INK)
	local glow = stroke(offer, 2, TAG, false, "Glow")
	glow.Transparency = 0.2
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 160, 200))
	gradient.Parent = offer
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = offer
	text(offer, "Icon", UDim2.fromOffset(40, 40), UDim2.fromOffset(8, 7), "🛡")
	local label = text(offer, "Label", UDim2.new(1, -140, 0, 36), UDim2.fromOffset(52, 9), "Shield now")
	label.TextXAlignment = Enum.TextXAlignment.Left
	-- Отрывная линия купона.
	for i = 0, 5 do
		local dash = Instance.new("Frame")
		dash.Name = "Perforation"
		dash.BorderSizePixel = 0
		dash.BackgroundColor3 = Color3.fromRGB(90, 80, 120)
		dash.Size = UDim2.fromOffset(2, 5)
		dash.Position = UDim2.new(1, -84, 0, 5 + i * 8)
		dash.Parent = offer
	end
	local price = Instance.new("Frame")
	price.Name = "Price"
	price.AnchorPoint = Vector2.new(1, 0.5)
	price.Position = UDim2.new(1, -8, 0.5, 0)
	price.Size = UDim2.fromOffset(70, 34)
	price.BackgroundColor3 = TAG
	price.Parent = offer
	corner(price, UDim.new(0, 10))
	stroke(price, 2, INK)
	text(price, "Text", UDim2.new(1, -8, 1, -6), UDim2.fromOffset(4, 3), "R$ 9", INK, Enum.Font.GothamBlack).TextStrokeTransparency = 1
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(0, 2, 0, 2)
	close.Size = UDim2.fromOffset(20, 20)
	close.BackgroundColor3 = Color3.fromRGB(90, 85, 110)
	close.Text = "×"
	close.Font = Enum.Font.GothamBlack
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.ZIndex = 3
	close.Parent = offer
	corner(close, UDim.new(1, 0))
	stroke(close, 2, INK)

	-- 🚀 КНОПКА РАКЕТНОЙ КИРКИ
	local rocket = Instance.new("TextButton")
	rocket.Name = "RocketButton"
	rocket.Visible = false
	rocket.Text = ""
	rocket.AutoButtonColor = false
	rocket.AnchorPoint = Vector2.new(1, 1)
	rocket.Position = UDim2.new(1, -16, 1, -150)
	rocket.Size = UDim2.fromOffset(72, 72)
	rocket.BackgroundColor3 = Color3.fromRGB(60, 50, 90)
	rocket.ClipsDescendants = true
	rocket.Parent = gui
	corner(rocket, UDim.new(1, 0))
	stroke(rocket, 4, INK)
	local rocketGlow = stroke(rocket, 2, Color3.fromRGB(255, 120, 60), false, "Glow")
	rocketGlow.Transparency = 1
	text(rocket, "Icon", UDim2.new(1, -22, 1, -30), UDim2.fromOffset(11, 6), "🚀")
	text(rocket, "State", UDim2.new(1, -10, 0, 18), UDim2.new(0, 5, 1, -22), "OFF [R]", Color3.fromRGB(200, 200, 220), Enum.Font.GothamBlack)
	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.4
	shade.BorderSizePixel = 0
	shade.ZIndex = 4
	shade.Parent = rocket
	return gui
end

return Builder
