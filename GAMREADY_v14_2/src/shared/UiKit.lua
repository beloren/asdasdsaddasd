--------------------------------------------------------------------------------
-- UiKit — кирпичики ЕДИНОГО интерфейса (v20).
--
-- Все билдеры окон (Shared.UiBuilders.*) собирают UI только отсюда, поэтому
-- у всего интерфейса один стиль (см. Shared.UiTheme).
--
-- ПРАВИЛО: любая видимая подложка — ImageLabel/ImageButton со «скином»
-- (атрибут UiSkin). Пока картинки нет — рисуется цветом и тонкой рамкой;
-- как только в UiTheme.Skins[<ключ>].Image вписан ассет (или ты поставил
-- Image прямо в Studio) — показывается картинка. Frame используется только
-- как невидимый контейнер для раскладки.
--
-- Основное:
--   UiKit.Screen(name, props)                    → ScreenGui
--   UiKit.Window(gui, name, opts)                → панель-окно (заголовок, лента, X, тело)
--   UiKit.Plate(parent, name, skin, props)       → ImageLabel со скином
--   UiKit.PlateButton(parent, name, skin, props) → ImageButton со скином
--   UiKit.Text(parent, name, text, props)        → TextLabel в стиле темы
--   UiKit.Button(parent, name, text, variant, props) → кнопка (ImageButton + Caption)
--   UiKit.CloseButton(parent, props)             → красный «X»
--   UiKit.Card / Slot / Bar / Scroll / SectionHeader / Tabs / Input / Badge / HudButton …
--------------------------------------------------------------------------------

local Theme = require(script.Parent:WaitForChild("UiTheme"))

local UiKit = {}
UiKit.Theme = Theme
UiKit.VERSION = Theme.VERSION

--------------------------------------------------------------------------------
-- БАЗА
--------------------------------------------------------------------------------
local function apply(inst, props)
	if props then
		for key, value in props do
			if key ~= "Parent" and key ~= "Children" and type(key) == "string" and key:sub(1, 1) ~= "_" then
				inst[key] = value
			end
		end
	end
	return inst
end
UiKit.Apply = apply

function UiKit.New(className, props, parent)
	local inst = Instance.new(className)
	apply(inst, props)
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UiKit.ImageUri(id)
	if id == nil or id == 0 or id == "" then
		return ""
	end
	if type(id) == "number" then
		return "rbxassetid://" .. tostring(id)
	end
	local s = tostring(id)
	if s:match("^%d+$") then
		return "rbxassetid://" .. s
	end
	return s
end

function UiKit.Accent(nameOrColor)
	if type(nameOrColor) == "table" and nameOrColor.Main then
		return nameOrColor
	end
	if typeof(nameOrColor) == "Color3" then
		return { Main = nameOrColor, Light = nameOrColor:Lerp(Color3.new(1, 1, 1), 0.55), Dark = nameOrColor:Lerp(Color3.new(0, 0, 0), 0.25) }
	end
	return Theme.Accents[nameOrColor or Theme.DefaultAccent] or Theme.Accents[Theme.DefaultAccent]
end

-- Двухточечные последовательности явными ключами (так надёжнее для
-- экспорта в .rbxm вне Studio).
function UiKit.Seq(a, b)
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) })
end
function UiKit.NSeq(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) })
end

local function scaleColor(color, k)
	return Color3.new(math.clamp(color.R * k, 0, 1), math.clamp(color.G * k, 0, 1), math.clamp(color.B * k, 0, 1))
end

function UiKit.Corner(parent, px)
	if not px or px <= 0 then
		return nil
	end
	local c = parent:FindFirstChild("SkinCorner")
	if not c then
		c = Instance.new("UICorner")
		c.Name = "SkinCorner"
		c.Parent = parent
	end
	c.CornerRadius = px >= 999 and UDim.new(1, 0) or UDim.new(0, px)
	return c
end

function UiKit.Stroke(parent, color, thickness, transparency, name)
	local s = Instance.new("UIStroke")
	s.Name = name or "Stroke"
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Parent = parent
	return s
end

function UiKit.Gradient(parent, top, bottom, rotation, name)
	local g = Instance.new("UIGradient")
	g.Name = name or "Gradient"
	g.Rotation = rotation or 90
	g.Color = UiKit.Seq(top, bottom or top)
	g.Parent = parent
	return g
end

function UiKit.Padding(parent, all, horizontal, top, bottom)
	local p = Instance.new("UIPadding")
	local h = UDim.new(0, horizontal or all or 0)
	p.PaddingLeft = h
	p.PaddingRight = h
	p.PaddingTop = UDim.new(0, top or all or 0)
	p.PaddingBottom = UDim.new(0, bottom or top or all or 0)
	p.Parent = parent
	return p
end

function UiKit.List(parent, props)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, Theme.Metrics.Gap)
	apply(l, props)
	l.Parent = parent
	return l
end

function UiKit.Grid(parent, cellSize, cellPadding, props)
	local g = Instance.new("UIGridLayout")
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.CellSize = cellSize
	g.CellPadding = cellPadding or UDim2.fromOffset(Theme.Metrics.Gap, Theme.Metrics.Gap)
	apply(g, props)
	g.Parent = parent
	return g
end

function UiKit.Aspect(parent, ratio)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio or 1
	a.Parent = parent
	return a
end

function UiKit.Scale(parent, name, value)
	local s = Instance.new("UIScale")
	s.Name = name or "UIScale"
	s.Scale = value or 1
	s.Parent = parent
	return s
end

-- Невидимый контейнер (только раскладка).
function UiKit.Group(parent, name, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	apply(f, props)
	f.Parent = parent
	return f
end

--------------------------------------------------------------------------------
-- СКИНЫ
--------------------------------------------------------------------------------
-- (Пере)применяет скин к ImageLabel/ImageButton. accent — таблица акцента
-- или Color3 (цвет рамки/заливки/тона). Вызывается и билдерами, и
-- tools/ApplyUiSkins.lua (там — только картинки, без сброса цветов).
function UiKit.ApplySkin(inst, skinKey, accentValue, imagesOnly)
	local skin = Theme.Skins[skinKey]
	if not skin then
		return inst
	end
	inst:SetAttribute("UiSkin", skinKey)
	local accentColor
	if typeof(accentValue) == "Color3" then
		accentColor = accentValue
	elseif type(accentValue) == "table" then
		accentColor = accentValue.Main
	elseif type(accentValue) == "string" then
		accentColor = UiKit.Accent(accentValue).Main
	end
	if accentColor then
		inst:SetAttribute("UiAccent", accentColor)
	else
		accentColor = inst:GetAttribute("UiAccent")
	end

	local image = UiKit.ImageUri(skin.Image)
	local stroke = inst:FindFirstChild("SkinStroke")
	local gradient = inst:FindFirstChild("SkinGradient")

	if not imagesOnly then
		inst.BorderSizePixel = 0
		local fill = skin.Color
		if skin.FillAccent and accentColor then
			fill = accentColor
		end
		inst.BackgroundColor3 = fill or Color3.new(0, 0, 0)
		inst.BackgroundTransparency = skin.Transparency or 0
		UiKit.Corner(inst, skin.Corner or 0)
		if skin.StrokeThickness and skin.StrokeThickness > 0 then
			if not stroke then
				stroke = UiKit.Stroke(inst, nil, nil, nil, "SkinStroke")
			end
			stroke.Thickness = skin.StrokeThickness
			stroke.Transparency = skin.StrokeTransparency or 0
			stroke.Color = (skin.StrokeAccent and accentColor) or skin.StrokeColor or Color3.new(0, 0, 0)
		elseif stroke then
			stroke:Destroy()
			stroke = nil
		end
		if skin.Gradient then
			local base = Color3.new(1, 1, 1)
			if not gradient then
				gradient = UiKit.Gradient(inst, base, base, 90, "SkinGradient")
			end
			gradient.Color = UiKit.Seq(scaleColor(base, skin.Gradient[1]), scaleColor(base, skin.Gradient[2]))
		elseif gradient then
			gradient:Destroy()
			gradient = nil
		end
	end

	if inst:GetAttribute("UiSkinLocked") == true then
		return inst
	end
	if image ~= "" then
		inst.Image = image
		inst.BackgroundTransparency = 1
		if skin.Slice then
			inst.ScaleType = Enum.ScaleType.Slice
			inst.SliceCenter = skin.Slice
			inst.SliceScale = skin.SliceScale or 1
		else
			inst.ScaleType = Enum.ScaleType.Stretch
		end
		inst.ImageColor3 = (skin.Tint and accentColor) or Color3.new(1, 1, 1)
		inst.ImageTransparency = skin.ImageTransparency or 0
		if stroke then
			stroke.Enabled = skin.KeepStroke == true
		end
		if gradient then
			gradient.Enabled = false
		end
	else
		inst.Image = ""
		if stroke then
			stroke.Enabled = true
		end
		if gradient then
			gradient.Enabled = true
		end
	end
	return inst
end

-- Красит подложку в цвет состояния: без картинки — фон, с картинкой —
-- ImageColor3 (свой ассет остаётся виден, только тонируется).
function UiKit.Tint(inst, color)
	inst.BackgroundColor3 = color
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		if inst.Image ~= "" then
			inst.ImageColor3 = color
		end
	end
end

-- ImageLabel-подложка со скином.
function UiKit.Plate(parent, name, skinKey, props)
	local p = Instance.new("ImageLabel")
	p.Name = name
	p.Size = UDim2.fromScale(1, 1)
	UiKit.ApplySkin(p, skinKey or "Inset", props and props._Accent)
	apply(p, props)
	p.Parent = parent
	return p
end

-- ImageButton-подложка со скином.
function UiKit.PlateButton(parent, name, skinKey, props)
	local b = Instance.new("ImageButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Size = UDim2.fromScale(1, 1)
	UiKit.ApplySkin(b, skinKey or "Button_Dark", props and props._Accent)
	apply(b, props)
	b.Parent = parent
	return b
end

-- Прозрачная картинка-иконка.
function UiKit.Icon(parent, name, image, props)
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.Image = UiKit.ImageUri(image)
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = UDim2.fromScale(1, 1)
	apply(i, props)
	i.Parent = parent
	return i
end

--------------------------------------------------------------------------------
-- ТЕКСТ
--------------------------------------------------------------------------------
-- props: обычные свойства TextLabel + служебные
--   _Style = "Title"|"Heading"|"Body"|"Small"|"Number"|"Plain"
--   _Stroke = толщина обводки (0 — без), _StrokeColor
--   _Gradient = { верх, низ } — вертикальный градиент текста
local function styleText(t, props)
	local style = props and props._Style or "Body"
	t.FontFace = Theme.Fonts[style] or Theme.Fonts.Body
	t.TextColor3 = Theme.Colors.Text
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextScaled = true
	t.RichText = true
	t.TextWrapped = true
	local strokeThickness = props and props._Stroke
	if strokeThickness == nil then
		strokeThickness = Theme.TextStroke[style] or 1.4
	end
	if strokeThickness > 0 then
		local s = Instance.new("UIStroke")
		s.Name = "TextStroke"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Color = props and props._StrokeColor or Theme.Colors.TextStroke
		s.Thickness = strokeThickness
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = t
	end
	if props and props._Gradient then
		UiKit.Gradient(t, props._Gradient[1], props._Gradient[2], 90, "TextGradient")
	end
	if props and props._MaxTextSize then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = props._MaxTextSize
		c.MinTextSize = props._MinTextSize or 1
		c.Parent = t
	end
end

function UiKit.Text(parent, name, text, props)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = UDim2.fromScale(1, 1)
	styleText(t, props)
	t.Text = text or ""
	apply(t, props)
	t.Parent = parent
	return t
end

-- Переводит готовый (кодовый или авторский) TextLabel/TextButton на
-- шрифт и обводку темы, не трогая текст, размер и место.
function UiKit.StyleText(t, style, strokeThickness)
	if not t then return t end
	style = style or "Heading"
	t.FontFace = Theme.Fonts[style] or Theme.Fonts.Heading
	t.TextStrokeTransparency = 1
	local thickness = strokeThickness or Theme.TextStroke[style] or 1.4
	local s = t:FindFirstChild("TextStroke")
	if thickness > 0 then
		if not s then
			s = Instance.new("UIStroke")
			s.Name = "TextStroke"
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			s.Color = Theme.Colors.TextStroke
			s.LineJoinMode = Enum.LineJoinMode.Round
			s.Parent = t
		end
		s.Thickness = thickness
	elseif s then
		s:Destroy()
	end
	return t
end

-- TextButton в стиле темы (для текстовых кнопок без подложки, строк-ссылок).
function UiKit.TextButton(parent, name, text, props)
	local t = Instance.new("TextButton")
	t.Name = name
	t.AutoButtonColor = false
	t.Size = UDim2.fromScale(1, 1)
	styleText(t, props)
	t.Text = text or ""
	apply(t, props)
	t.Parent = parent
	return t
end

function UiKit.Input(parent, name, placeholder, props)
	local plate = UiKit.Plate(parent, name .. "Bg", "Input", { Size = props and props.Size or UDim2.new(1, 0, 0, 36), Position = props and props.Position or UDim2.new(), AnchorPoint = props and props.AnchorPoint or Vector2.zero, LayoutOrder = props and props.LayoutOrder or 0 })
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -16, 1, -6)
	box.Position = UDim2.fromOffset(8, 3)
	box.FontFace = Theme.Fonts.Plain
	box.TextColor3 = Theme.Colors.Text
	box.PlaceholderColor3 = Theme.Colors.MutedText
	box.PlaceholderText = placeholder or ""
	box.Text = ""
	box.TextScaled = true
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = plate
	return box, plate
end

--------------------------------------------------------------------------------
-- КНОПКИ
--------------------------------------------------------------------------------
-- variant: "Green" | "Claim" | "Yellow" | "Track" | "Red" | "Blue" | "Purple" | "Dark" | "Gift"
-- Возвращает ImageButton (имя name) с дочерним TextLabel "Caption".
-- props._Icon = картинка слева от текста (ImageLabel "Icon").
function UiKit.Button(parent, name, text, variant, props)
	local skinKey = "Button_" .. (variant or "Green")
	local skin = Theme.Skins[skinKey] or Theme.Skins.Button_Green
	local b = Instance.new("ImageButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(160, 44)
	UiKit.ApplySkin(b, Theme.Skins[skinKey] and skinKey or "Button_Green", props and props._Accent)
	b:SetAttribute("ButtonVariant", variant or "Green")
	local caption = UiKit.Text(b, "Caption", text, {
		_Style = props and props._TextStyle or "Heading",
		_StrokeColor = skin.TextStroke,
		_Stroke = props and props._Stroke or 1.8,
		TextColor3 = skin.TextColor or Theme.Colors.Text,
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		ZIndex = 2,
	})
	if props and props._Icon ~= nil then
		local icon = UiKit.Icon(b, "Icon", props._Icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.new(0, 22, 0, 22),
			ZIndex = 2,
		})
		caption.Position = UDim2.new(0, 34, 0, 4)
		caption.Size = UDim2.new(1, -42, 1, -8)
		if icon.Image == "" then
			icon.Visible = false
			caption.Position = UDim2.fromOffset(6, 4)
			caption.Size = UDim2.new(1, -12, 1, -8)
		end
	end
	apply(b, props)
	b.Parent = parent
	return b, caption
end

-- Перекрашивает готовую кнопку в другой вариант (Green/Yellow/Red/Dark/...):
-- подложка + цвет и обводка подписи. Для клиентов, меняющих состояние кнопки.
function UiKit.SetButtonVariant(button, variant, captionName)
	local skinKey = "Button_" .. (variant or "Green")
	local skin = Theme.Skins[skinKey]
	if not skin then return end
	UiKit.ApplySkin(button, skinKey)
	button:SetAttribute("ButtonVariant", variant)
	local caption = button:FindFirstChild(captionName or "Caption")
	if caption and caption:IsA("TextLabel") then
		caption.TextColor3 = skin.TextColor or Theme.Colors.Text
		local textStroke = caption:FindFirstChild("TextStroke")
		if textStroke and skin.TextStroke then textStroke.Color = skin.TextStroke end
	end
end

-- Цена в Robux: зелёная кнопка со значком Robux слева.
function UiKit.RobuxButton(parent, name, price, props)
	local robux = UiKit.ImageUri(Theme.Icons.Robux)
	local b, caption = UiKit.Button(parent, name, robux ~= "" and tostring(price or "") or ("R$ " .. tostring(price or "")), "Green", props)
	local icon = UiKit.Icon(b, "RobuxIcon", Theme.Icons.Robux, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(0, 22, 0, 22),
		ZIndex = 3,
		Visible = robux ~= "",
	})
	if robux ~= "" then
		caption.Position = UDim2.new(0, 36, 0, 4)
		caption.Size = UDim2.new(1, -44, 1, -8)
	end
	return b, caption, icon
end

-- Красный «X». Картинка — UiTheme.Icons.Close; пусто → текст.
function UiKit.CloseButton(parent, props)
	local size = Theme.Metrics.CloseSize
	local b = Instance.new("ImageButton")
	b.Name = "CloseButton"
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -10, 0.5, 0)
	b.Size = UDim2.fromOffset(size, size)
	b.ScaleType = Enum.ScaleType.Fit
	b.Image = UiKit.ImageUri(Theme.Icons.Close)
	b:SetAttribute("UiIcon", "Close")
	b.ZIndex = 5
	local caption = UiKit.Text(b, "Caption", "X", {
		_Style = "Title",
		_Stroke = 2.5,
		TextColor3 = Theme.Colors.Close,
		ZIndex = 6,
		Visible = b.Image == "",
	})
	caption.TextXAlignment = Enum.TextXAlignment.Center
	apply(b, props)
	b.Parent = parent
	return b
end

--------------------------------------------------------------------------------
-- ОКНО
--------------------------------------------------------------------------------
-- Закладка-ленточка. Без картинки: цветная полоса + «хвост» уголком.
function UiKit.Ribbon(parent, accentName, props)
	local a = UiKit.Accent(accentName)
	local m = Theme.Metrics
	local ribbon = UiKit.Plate(parent, "Ribbon", "Ribbon", {
		_Accent = a,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 10, 0, -10),
		Size = UDim2.fromOffset(m.RibbonWidth, m.RibbonHeight - m.RibbonWidth / 2),
		ZIndex = 6,
	})
	-- «Хвост»: повёрнутый квадрат под полосой → острый низ закладки.
	local tail = UiKit.Plate(ribbon, "Tail", "Ribbon", {
		_Accent = a,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(m.RibbonWidth * 0.7071, m.RibbonWidth * 0.7071),
		Rotation = 45,
		ZIndex = 5,
	})
	tail:SetAttribute("HideWhenSkinned", true)
	if ribbon.Image ~= "" then
		tail.Visible = false
		ribbon.Size = UDim2.fromOffset(m.RibbonWidth, m.RibbonHeight)
	end
	apply(ribbon, props)
	return ribbon
end

-- Заголовок окна: крупный курсив с градиентом цвета акцента.
function UiKit.TitleText(parent, name, text, accentName, props)
	local a = UiKit.Accent(accentName)
	local t = UiKit.Text(parent, name or "Title", text, {
		_Style = "Title",
		_Gradient = { a.Light, a.Main },
		_StrokeColor = Color3.fromRGB(15, 10, 20),
		_Stroke = 2.5,
	})
	apply(t, props)
	return t
end

-- Собирает модальное окно.
-- opts:
--   Title, Accent ("Purple"…), Size (UDim2), Position, AnchorPoint,
--   Ribbon (true), Close (true), TitleAlign ("Center"|"Left"),
--   BodyName ("Body"), Scroll (false — Body будет ScrollingFrame),
--   Visible (false), ZIndex (1)
-- Возвращает panel, parts = { TitleBar, Title, CloseButton, Ribbon, Body, Frame }
-- Структура (имена — контракт):
--   ImageLabel <name> (прозрачный корень, AnchorPoint 0.5 — UiMotion работает)
--     ├─ ImageLabel "TitleBar" [UiSkin=TitleBar] → "Title", "CloseButton", "Ribbon"
--     └─ ImageLabel "Frame"    [UiSkin=Panel]    → <BodyName>
function UiKit.Window(parent, name, opts)
	opts = opts or {}
	local a = UiKit.Accent(opts.Accent)
	local m = Theme.Metrics
	local titleH = opts.TitleBarHeight or m.TitleBarHeight
	local gap = opts.TitleGap or 6

	local panel = Instance.new("ImageLabel")
	panel.Name = name or "Panel"
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Image = ""
	panel.AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5)
	panel.Position = opts.Position or UDim2.fromScale(0.5, 0.5)
	panel.Size = opts.Size or UDim2.fromOffset(720, 520)
	panel.Visible = opts.Visible == true
	panel.ZIndex = opts.ZIndex or 2
	panel:SetAttribute("UiAccent", a.Main)
	panel:SetAttribute("UiWindow", true)

	local titleBar = UiKit.Plate(panel, "TitleBar", "TitleBar", {
		_Accent = a,
		Size = UDim2.new(1, 0, 0, titleH),
		ZIndex = 3,
	})
	local title = UiKit.TitleText(titleBar, "Title", opts.Title or "", a, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -140, 0, math.floor(titleH * 0.8)),
		ZIndex = 4,
	})
	if opts.TitleAlign == "Left" then
		title.AnchorPoint = Vector2.new(0, 0.5)
		title.Position = UDim2.new(0, opts.Ribbon == false and 16 or 58, 0.5, 0)
		title.TextXAlignment = Enum.TextXAlignment.Left
	end

	local ribbon
	if opts.Ribbon ~= false then
		ribbon = UiKit.Ribbon(titleBar, a)
	end
	local close
	if opts.Close ~= false then
		close = UiKit.CloseButton(titleBar)
		-- CloseInRoot: кнопка — прямой ребёнок окна (для скриптов, которые
		-- ищут её через panel:WaitForChild("CloseButton")).
		if opts.CloseInRoot then
			close.AnchorPoint = Vector2.new(1, 0.5)
			close.Position = UDim2.new(1, -10, 0, math.floor(titleH / 2))
			close.ZIndex = 8
			close.Parent = panel
		end
	end

	local frame = UiKit.Plate(panel, "Frame", "Panel", {
		_Accent = a,
		Position = UDim2.fromOffset(0, titleH + gap),
		Size = UDim2.new(1, 0, 1, -(titleH + gap)),
		ZIndex = 2,
	})

	-- Flat: содержимое кладётся прямо в корень окна (для скриптов, которые
	-- ищут детали через panel:WaitForChild(...)). parts.Top — отступ сверху,
	-- с которого начинается тело, parts.Pad — внутренний отступ.
	if opts.Flat then
		panel.Parent = parent
		return panel, { TitleBar = titleBar, Title = title, CloseButton = close, Ribbon = ribbon, Body = panel, Frame = frame, Accent = a, Top = titleH + gap + m.Padding, Pad = m.Padding }
	end

	local bodyName = opts.BodyName or "Body"
	local body
	if opts.Scroll then
		body = UiKit.Scroll(frame, bodyName, {
			Position = UDim2.fromOffset(m.Padding, m.Padding),
			Size = UDim2.new(1, -m.Padding * 2, 1, -m.Padding * 2),
			ZIndex = 2,
		}, a)
	else
		body = UiKit.Group(frame, bodyName, {
			Position = UDim2.fromOffset(m.Padding, m.Padding),
			Size = UDim2.new(1, -m.Padding * 2, 1, -m.Padding * 2),
			ZIndex = 2,
		})
	end

	panel.Parent = parent
	return panel, { TitleBar = titleBar, Title = title, CloseButton = close, Ribbon = ribbon, Body = body, Frame = frame, Accent = a, Top = titleH + gap + m.Padding, Pad = m.Padding }
end

-- Полноэкранное затемнение (TextButton — клик мимо окна закрывает его).
function UiKit.Dimmer(parent, props)
	local d = Instance.new("TextButton")
	d.Name = "Dimmer"
	d.Text = ""
	d.AutoButtonColor = false
	d.BorderSizePixel = 0
	d.BackgroundColor3 = Theme.Colors.Dimmer
	d.BackgroundTransparency = Theme.Skins.Dimmer.Transparency
	d.Size = UDim2.fromScale(1, 1)
	d.Visible = false
	d.ZIndex = 1
	d:SetAttribute("DisableGlobalHover", true)
	apply(d, props)
	d.Parent = parent
	return d
end

--------------------------------------------------------------------------------
-- СОДЕРЖИМОЕ ОКОН
--------------------------------------------------------------------------------
function UiKit.Scroll(parent, name, props, accentName)
	local s = Instance.new("ScrollingFrame")
	s.Name = name
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = UDim2.fromScale(1, 1)
	s.ScrollBarThickness = Theme.Metrics.ScrollBar
	s.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 160)
	s.ScrollBarImageTransparency = 0.2
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	s.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	s.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	s.MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	apply(s, props)
	s.Parent = parent
	return s
end

-- Заголовок секции.
--   style "Center": «——— Money ———» (как в магазине референса)
--   style "Left":   текст слева + цветная линия под ним (как «Daily Quests»)
-- Структура: Frame name → TextLabel "Label", ImageLabel "Line" / "LineLeft"+"LineRight".
function UiKit.SectionHeader(parent, name, text, accentName, props)
	local a = UiKit.Accent(accentName)
	local style = props and props._Layout or "Center"
	local h = props and props._Height or 34
	local holder = UiKit.Group(parent, name, { Size = UDim2.new(1, 0, 0, h) })
	if style == "Left" then
		local label = UiKit.Text(holder, "Label", text, {
			_Style = "Heading",
			Size = UDim2.new(1, -8, 1, -6),
			Position = UDim2.fromOffset(8, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = a.Light,
		})
		local line = UiKit.Plate(holder, "Line", "Divider", {
			_Accent = a,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 2),
		})
		local g = UiKit.Gradient(line, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0, "Fade")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
		label.TextColor3 = Theme.Colors.Text
	else
		local label = UiKit.Text(holder, "Label", text, {
			_Style = "Title",
			_Gradient = { a.Light, a.Main },
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.4, 0, 1, -4),
		})
		label.TextScaled = true
		for i, side in { "LineLeft", "LineRight" } do
			local line = UiKit.Plate(holder, side, "Divider", {
				_Accent = a,
				AnchorPoint = Vector2.new(i == 1 and 0 or 1, 0.5),
				Position = UDim2.new(i == 1 and 0.08 or 0.92, 0, 0.5, 0),
				Size = UDim2.new(0.22, 0, 0, 2),
			})
			local g = UiKit.Gradient(line, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0, "Fade")
			g.Transparency = i == 1 and UiKit.NSeq(1, 0.1) or UiKit.NSeq(0.1, 1)
		end
	end
	apply(holder, props)
	return holder
end

-- Карточка (товар, предмет, награда). Рамка = accent (Color3 редкости или имя акцента).
function UiKit.Card(parent, name, accentValue, props)
	local c = Instance.new("ImageLabel")
	c.Name = name
	c.Size = UDim2.fromOffset(200, 140)
	UiKit.ApplySkin(c, "Card", accentValue or "Grey")
	apply(c, props)
	c.Parent = parent
	return c
end

function UiKit.CardButton(parent, name, accentValue, props)
	local c = Instance.new("ImageButton")
	c.Name = name
	c.AutoButtonColor = false
	c.Size = UDim2.fromOffset(200, 140)
	UiKit.ApplySkin(c, "Card", accentValue or "Grey")
	apply(c, props)
	c.Parent = parent
	return c
end

-- Квадратная ячейка (хотбар, инвентарь). button = true → ImageButton.
function UiKit.Slot(parent, name, props, button)
	local s = Instance.new(button and "ImageButton" or "ImageLabel")
	s.Name = name
	if button then
		s.AutoButtonColor = false
	end
	s.Size = UDim2.fromOffset(64, 64)
	UiKit.ApplySkin(s, "Slot", props and props._Accent)
	apply(s, props)
	s.Parent = parent
	return s
end

-- Полоса прогресса: ImageLabel name [BarTrack] → ImageLabel "Fill" [BarFill] (+ TextLabel "Label").
function UiKit.Bar(parent, name, accentName, props)
	local a = UiKit.Accent(accentName or "Green")
	local track = UiKit.Plate(parent, name, "BarTrack", { Size = UDim2.new(1, 0, 0, 10) })
	local fill = UiKit.Plate(track, "Fill", "BarFill", {
		_Accent = a,
		Size = UDim2.fromScale(0, 1),
		ZIndex = (props and props.ZIndex or 1) + 1,
	})
	if props and props._Label then
		UiKit.Text(track, "Label", props._Label, {
			_Style = "Small",
			Size = UDim2.new(1, -8, 1, 0),
			Position = UDim2.fromOffset(4, 0),
			ZIndex = (props.ZIndex or 1) + 2,
		})
	end
	apply(track, props)
	return track, fill
end

-- Вкладки. tabs = { {Name=, Text=}, ... }. Возвращает Frame name с
-- ImageButton "<Name>" на каждую вкладку (+ Caption).
function UiKit.Tabs(parent, name, tabs, accentName, props)
	local holder = UiKit.Group(parent, name, { Size = UDim2.new(1, 0, 0, 44) })
	UiKit.List(holder, {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
	local buttons = {}
	for i, tab in tabs do
		local b = Instance.new("ImageButton")
		b.Name = tab.Name
		b.AutoButtonColor = false
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #tabs, 0, 1, 0)
		UiKit.ApplySkin(b, i == 1 and "TabActive" or "Tab", accentName)
		UiKit.Text(b, "Caption", tab.Text or tab.Name, {
			_Style = "Heading",
			Size = UDim2.new(1, -16, 1, -12),
			Position = UDim2.fromOffset(8, 6),
			ZIndex = 2,
		})
		b.Parent = holder
		buttons[tab.Name] = b
	end
	apply(holder, props)
	return holder, buttons
end

-- Переключает вид вкладок (для клиентов).
function UiKit.SetTabActive(tabsHolder, activeName)
	for _, b in tabsHolder:GetChildren() do
		if b:IsA("ImageButton") then
			local active = b.Name == activeName
			UiKit.ApplySkin(b, active and "TabActive" or "Tab")
			local caption = b:FindFirstChild("Caption")
			if caption then
				local skin = Theme.Skins[active and "TabActive" or "Tab"]
				caption.TextColor3 = skin.TextColor or Theme.Colors.Text
			end
		end
	end
end

-- Красная точка / бейдж с текстом.
function UiKit.Badge(parent, name, text, props)
	local b = UiKit.Plate(parent, name or "Badge", "Badge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 8,
	})
	UiKit.Text(b, "Count", text or "", {
		_Style = "Number",
		_Stroke = 1,
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		ZIndex = 9,
	})
	apply(b, props)
	return b
end

-- Кнопка HUD как на референсе: иконка сверху, подпись снизу, без фона.
-- Структура: ImageButton name → ImageLabel "Icon", TextLabel "Label", (TextLabel "Emoji").
function UiKit.HudButton(parent, name, label, icon, props)
	local b = Instance.new("ImageButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Image = ""
	b.Size = UDim2.fromOffset(76, 76)
	local iconImage = UiKit.ImageUri(icon and icon.Image)
	local iconLabel = UiKit.Icon(b, "Icon", iconImage, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.72, 0, 0.72, 0),
		ZIndex = 2,
	})
	UiKit.Aspect(iconLabel, 1)
	local emoji = UiKit.Text(b, "Emoji", icon and icon.Emoji or "", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(0.62, 0, 0.62, 0),
		ZIndex = 2,
		Visible = iconImage == "",
	})
	emoji.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(b, "Label", label or "", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1.2, 0, 0.3, 0),
		ZIndex = 3,
	})
	apply(b, props)
	b.Parent = parent
	return b
end

-- Выключает все шаблоны (прямые дети папок "Templates") — папка в Roblox
-- GUI НЕ прячет. Клиент включает только клон, когда он реально нужен.
function UiKit.HideTemplates(root)
	for _, folder in root:GetDescendants() do
		if folder:IsA("Folder") and folder.Name == "Templates" then
			for _, child in folder:GetChildren() do
				if child:IsA("GuiObject") then
					child.Visible = false
				end
			end
		end
	end
	return root
end

-- Полноэкранная ScreenGui.
function UiKit.Screen(name, props)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("UiKitVersion", UiKit.VERSION)
	apply(gui, props)
	return gui
end

--------------------------------------------------------------------------------
-- ApplySkinsTo(root) — перечитать картинки темы для всего дерева.
-- Не трогает позиции/размеры/тексты, только Image у элементов со скином.
--------------------------------------------------------------------------------
function UiKit.ApplySkinsTo(root, full)
	local count = 0
	for _, inst in root:GetDescendants() do
		if (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) then
			local key = inst:GetAttribute("UiSkin")
			if key and Theme.Skins[key] then
				UiKit.ApplySkin(inst, key, nil, not full)
				count += 1
				if inst:GetAttribute("HideWhenSkinned") then
					local parentImage = inst.Parent
					if parentImage and (parentImage:IsA("ImageLabel") or parentImage:IsA("ImageButton")) then
						inst.Visible = parentImage.Image == ""
					end
				end
			end
			local iconKey = inst:GetAttribute("UiIcon")
			if iconKey and Theme.Icons[iconKey] ~= nil and inst:GetAttribute("UiSkinLocked") ~= true then
				local uri = UiKit.ImageUri(Theme.Icons[iconKey])
				if uri ~= "" then
					inst.Image = uri
					local caption = inst:FindFirstChild("Caption") or inst:FindFirstChild("Emoji")
					if caption then
						caption.Visible = false
					end
				end
			end
		end
	end
	return count
end

-- Иконка из темы с запасным эмодзи. Структура: ImageLabel name [UiIcon=key]
-- → TextLabel "Emoji" (видна, пока картинки нет).
-- v20.30: фон за товаром — картинка из Theme.Backdrops (kind: Star, Burst,
-- Shine, BlackLightning, Spiral или редкость → Theme.RarityBackdrop).
-- props: Color (тон), Transparency, Size (по умолч. 1.6 от родителя), ZIndex.
-- Вращают её клиенты (свойство Rotation), как раньше «лучи».
function UiKit.BackdropKind(kindOrRarity)
	if Theme.Backdrops and Theme.Backdrops[kindOrRarity] then return kindOrRarity end
	local category = Theme.CategoryBackdrop and Theme.CategoryBackdrop[kindOrRarity]
	if category then return category.Kind end
	return (Theme.RarityBackdrop and Theme.RarityBackdrop[kindOrRarity]) or "Shine"
end

function UiKit.PaintBackdrop(image, kindOrRarity, color, transparency)
	local kind = UiKit.BackdropKind(kindOrRarity)
	image.Image = UiKit.ImageUri(Theme.Backdrops and Theme.Backdrops[kind])
	image.ImageColor3 = (Theme.BackdropKeepColor and Theme.BackdropKeepColor[kind]) and Color3.new(1, 1, 1) or (color or Color3.new(1, 1, 1))
	if transparency then image.ImageTransparency = transparency end
	image:SetAttribute("Backdrop", kind)
end

function UiKit.Backdrop(parent, name, kindOrRarity, props)
	props = props or {}
	local image = Instance.new("ImageLabel")
	image.Name = name or "Rays"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	image.Size = props.Size or UDim2.fromScale(1.6, 1.6)
	image.ZIndex = props.ZIndex or (parent and parent.ZIndex or 1)
	image.Visible = props.Visible ~= false
	UiKit.PaintBackdrop(image, kindOrRarity, props.Color, props.Transparency or 0.2)
	image.Parent = parent
	return image
end

function UiKit.ThemeIcon(parent, name, iconKey, emoji, props)
	local uri = UiKit.ImageUri(Theme.Icons[iconKey])
	local i = UiKit.Icon(parent, name, uri, props)
	i:SetAttribute("UiIcon", iconKey)
	-- «@Check», «@Cross», «@Diamond»… — запасной значок рисуется фигурой
	-- (UiKit.Shape), а не символом: у шрифтов Roblox нет ✔ ✕ ◈ ➤ ▼.
	local shapeKind = typeof(emoji) == "string" and emoji:match("^@(%a+)$")
	local e = UiKit.Text(i, "Emoji", shapeKind and "" or emoji or "", { _Stroke = 0, Visible = uri == "", ZIndex = i.ZIndex })
	e.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	if shapeKind then
		UiKit.Shape(e, "Shape", shapeKind, { ZIndex = i.ZIndex })
	end
	return i
end

--------------------------------------------------------------------------------
-- Фигуры вместо «квадратиков» (v20.9). У шрифтов Roblox нет ✔ ✕ ➤ ▲ ▼ ◈ ◇,
-- они рисуются пустым квадратом. UiKit.Shape собирает такие значки из Frame:
-- тёмный контур (Outline*) + цветная заливка (Fill*), всё в долях квадрата.
--   UiKit.Shape(parent, name, kind, { Color, ZIndex, Size, Position, AnchorPoint, Visible })
--   UiKit.PaintShape(shape, color, transparency)
-- kind: Check, Cross, ArrowRight, ChevronUp, ChevronDown, ChevronLeft,
--       ChevronRight, Diamond (◈), DiamondHollow (◇).
--------------------------------------------------------------------------------
local SHAPES = {
	Check = { { 0.1, 0.52, 0.4, 0.8 }, { 0.4, 0.8, 0.9, 0.2 } },
	Cross = { { 0.18, 0.18, 0.82, 0.82 }, { 0.82, 0.18, 0.18, 0.82 } },
	ChevronRight = { { 0.32, 0.14, 0.72, 0.5 }, { 0.32, 0.86, 0.72, 0.5 } },
	ChevronLeft = { { 0.68, 0.14, 0.28, 0.5 }, { 0.68, 0.86, 0.28, 0.5 } },
	ChevronUp = { { 0.14, 0.68, 0.5, 0.28 }, { 0.86, 0.68, 0.5, 0.28 } },
	ChevronDown = { { 0.14, 0.32, 0.5, 0.72 }, { 0.86, 0.32, 0.5, 0.72 } },
	ArrowRight = { { 0.12, 0.5, 0.8, 0.5 }, { 0.46, 0.14, 0.84, 0.5 }, { 0.46, 0.86, 0.84, 0.5 } },
}
local SHAPE_THICKNESS = 0.2
local SHAPE_OUTLINE = 0.07

local function shapeBar(shape, name, x1, y1, x2, y2, thickness, extend, color, z)
	local dx, dy = x2 - x1, y2 - y1
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
	bar.Size = UDim2.fromScale(math.sqrt(dx * dx + dy * dy) + thickness + extend * 2, thickness + extend * 2)
	bar.Rotation = math.deg(math.atan2(dy, dx))
	bar.BackgroundColor3 = color
	bar.ZIndex = z
	UiKit.Corner(bar, 999)
	bar.Parent = shape
	return bar
end

local function shapeSquare(shape, name, size, color, z)
	local square = Instance.new("Frame")
	square.Name = name
	square.BorderSizePixel = 0
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = UDim2.fromScale(0.5, 0.5)
	square.Size = UDim2.fromScale(size, size)
	square.Rotation = 45
	square.BackgroundColor3 = color
	square.ZIndex = z
	UiKit.Corner(square, 3)
	square.Parent = shape
	return square
end

function UiKit.Shape(parent, name, kind, props)
	props = props or {}
	local color = props.Color or Color3.new(1, 1, 1)
	local outline = props.OutlineColor or Theme.Colors.TextStroke or Color3.new(0, 0, 0)
	local z = props.ZIndex or (parent and parent:IsA("GuiObject") and parent.ZIndex) or 1
	local shape = Instance.new("Frame")
	shape.Name = name or "Shape"
	shape.BackgroundTransparency = 1
	shape.BorderSizePixel = 0
	shape.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	shape.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	shape.Size = props.Size or UDim2.fromScale(1, 1)
	shape.Visible = props.Visible ~= false
	shape.ZIndex = z
	shape:SetAttribute("ShapeKind", kind)
	UiKit.Aspect(shape, 1)

	local bars = SHAPES[kind]
	if bars then
		local thickness = props.Thickness or SHAPE_THICKNESS
		for index, b in bars do
			shapeBar(shape, "Outline" .. index, b[1], b[2], b[3], b[4], thickness, SHAPE_OUTLINE, outline, z)
		end
		for index, b in bars do
			shapeBar(shape, "Fill" .. index, b[1], b[2], b[3], b[4], thickness, 0, color, z + 1)
		end
	elseif kind == "Diamond" then
		shapeSquare(shape, "Outline1", 0.74, outline, z)
		shapeSquare(shape, "Fill1", 0.6, color, z + 1)
	elseif kind == "DiamondHollow" then
		shapeSquare(shape, "Outline1", 0.72, outline, z)
		shapeSquare(shape, "Fill1", 0.58, color, z + 1)
		shapeSquare(shape, "Outline2", 0.3, outline, z + 2)
	end
	shape.Parent = parent
	return shape
end

function UiKit.PaintShape(shape, color, transparency)
	if not shape then return end
	for _, child in shape:GetChildren() do
		if child:IsA("Frame") then
			if child.Name:match("^Fill") and color then
				child.BackgroundColor3 = color
			end
			child.BackgroundTransparency = transparency or 0
		end
	end
end

-- Надпись со «знаком» → фигура: текст убирается, внутрь кладётся Shape того
-- же цвета. Для подписей, которые сервер/старые билдеры создали символом.
function UiKit.GlyphToShape(label, kind, props)
	if not (label and label:IsA("TextLabel")) then return nil end
	local existing = label:FindFirstChild("Shape")
	if existing then return existing end
	props = props or {}
	props.Color = props.Color or label.TextColor3
	props.ZIndex = props.ZIndex or label.ZIndex
	label.Text = ""
	return UiKit.Shape(label, "Shape", kind, props)
end

return UiKit
