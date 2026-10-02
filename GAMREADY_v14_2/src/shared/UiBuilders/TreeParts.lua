--------------------------------------------------------------------------------
-- TreeParts (v20.141) — общие детали деревьев прокачки для билдеров
-- UpgradeShopUi (дерево Experienced Miner) и IslandUi (деревья островов).
--
-- КАК ЗАМЕНИТЬ ФОРМУ УЗЛА (пятиугольник, звезда, своя картинка):
--   у шаблона узла есть ImageLabel "Shape" - это и есть форма. Поставь ему
--   Image = "rbxassetid://..." и удали UICorner "SkinCorner" (и UIStroke
--   "Stroke", если обводка уже нарисована на картинке). Клиент красит форму:
--   есть картинка - через ImageColor3, нет - через BackgroundColor3.
--   Rotation у "Shape" - поворот формы (ромб звезды = 45; для своей картинки
--   поставь 0). Всё остальное (Icon, Caption, Level, Name) - подписи.
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local TreeParts = {}

local OUTLINE = Color3.fromRGB(12, 14, 22)

local function shape(holder, corner, rotation, inset)
	local s = Instance.new("ImageLabel")
	s.Name = "Shape"
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.fromScale(0.5, 0.5)
	s.Size = UDim2.new(1, -(inset or 0), 1, -(inset or 0))
	s.BackgroundColor3 = Color3.fromRGB(95, 98, 110)
	s.BackgroundTransparency = 0
	s.BorderSizePixel = 0
	s.Image = ""
	s.ScaleType = Enum.ScaleType.Fit
	s.Rotation = rotation or 0
	s.ZIndex = holder.ZIndex
	UiKit.Corner(s, corner)
	UiKit.Stroke(s, OUTLINE, 3, 0, "Stroke")
	s.Parent = holder
	return s
end

local function holder(parent, name, size)
	local b = Instance.new("ImageButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Image = ""
	b.Size = UDim2.fromOffset(size, size)
	b.ZIndex = 6
	b.Parent = parent
	return b
end

local function caption(parent, name, text, style, props)
	props = props or {}
	props._Style = style
	props.ZIndex = props.ZIndex or (parent.ZIndex + 2)
	return UiKit.Text(parent, name, text, props)
end

-- Плашка ветки слева от строки (иконка + название + «Tier 3 / 9»).
function TreeParts.Tag(parent, name, width, height)
	local b = holder(parent, name, height)
	b.Size = UDim2.fromOffset(width, height)
	shape(b, 10, 0, 0)
	caption(b, "Title", "⛰ CAVE", "Heading", { Position = UDim2.fromOffset(5, 3), Size = UDim2.new(1, -10, 0.6, 0) })
	caption(b, "Sub", "Tier 1 / 9", "Number", {
		Position = UDim2.new(0, 5, 0.62, -2), Size = UDim2.new(1, -10, 0.34, 0),
		TextColor3 = Color3.fromRGB(255, 245, 210),
	})
	return b
end

-- Кружок тира: номер внутри, цена под ним.
function TreeParts.Node(parent, name, size, priceWidth)
	local b = holder(parent, name, size)
	shape(b, 999, 0, 0)
	caption(b, "Caption", "1", "Number", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.5),
	})
	caption(b, "Price", "$100", "Number", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3),
		Size = UDim2.fromOffset(priceWidth or (size + 22), 16),
	})
	return b
end

-- Звезда мелкого улучшения: ромб (Shape повёрнут на 45), иконка, уровень и
-- (необязательно) название над ней.
function TreeParts.Star(parent, name, size, opts)
	opts = opts or {}
	local b = holder(parent, name, size)
	local s = shape(b, opts.Round and 999 or 10, opts.Round and 0 or 45, opts.Round and 0 or math.floor(size * 0.29))
	s.BackgroundColor3 = opts.Color or Theme.Accents.Gold.Main
	caption(b, "Icon", opts.Icon or "★", "Heading", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.55, 0.55),
	})
	caption(b, "Level", "0/25", "Number", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.fromOffset(size + 40, 18),
		_MaxTextSize = 18,
	})
	if opts.WithName then
		caption(b, "Name", "Upgrade", "Small", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -3), Size = UDim2.fromOffset(150, 18),
			TextColor3 = Color3.fromRGB(200, 205, 220), _MaxTextSize = 15,
		})
	end
	return b
end

-- Линия-связь между узлами (клиент тянет и поворачивает её сам).
function TreeParts.Line(parent, name, thickness)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(95, 98, 110)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(40, thickness or 6)
	f.ZIndex = 5
	f.Parent = parent
	return f
end

-- Карточка выбранной звезды: Title, Level, Text, кнопки Buy (+ Close).
function TreeParts.InfoCard(parent, name, props, withClose)
	local card = UiKit.Plate(parent, name, "Card", props)
	UiKit.Text(card, "Title", "💪 Strength", { _Style = "Heading", _MaxTextSize = 24, Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, withClose and -64 or -24, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = card.ZIndex + 2 })
	UiKit.Text(card, "Level", "Level 0 / 25", { _Style = "Number", _MaxTextSize = 18, Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.SubText, ZIndex = card.ZIndex + 2 })
	local text = UiKit.Text(card, "Text", "+0% → +3%", { _Style = "Body", _MaxTextSize = 20, Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -24, 0, 56), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = card.ZIndex + 2 })
	text.TextWrapped = true
	UiKit.Button(card, "Buy", "BUY", "Green", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -24, 0, 46), ZIndex = card.ZIndex + 2 })
	if withClose then
		UiKit.Button(card, "Close", "X", "Red", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(36, 36), ZIndex = card.ZIndex + 2 })
	end
	return card
end

return TreeParts
