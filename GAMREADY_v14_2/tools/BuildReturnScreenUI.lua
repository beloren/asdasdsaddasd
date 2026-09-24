-- Standalone Command Bar builder for StarterGui/ReturnScreenUi.
-- Rerunning destroys and rebuilds only ReturnScreenUi.
--
-- Раньше "экран возвращения" (src/client/ReturnScreenUI.client.lua) собирался
-- ПОЛНОСТЬЮ кодом в рантайме — единственный экран в проекте без авторской
-- версии в StarterGui, которую можно подвинуть/перекрасить в Studio, как это
-- уже сделано для Daily Reward / Group Reward / Like Reward и т.д.
--
-- Этот билдер кладёт готовую именованную иерархию в StarterGui/ReturnScreenUi.
-- Клиентский скрипт при старте её находит (playerGui клонирует StarterGui
-- автоматически) и просто подставляет текст/цвета/видимость строк — никакой
-- геометрии в коде клиента больше нет. Если билдер не запущен (например,
-- сразу после клонирования репозитория), клиент соберёт временный fallback
-- по тем же цветам, чтобы игра не сломалась, и напомнит запустить этот файл.
--
-- Контракт (что обязано существовать под этими именами — клиент проверяет их
-- при старте и откажется работать с внятным warn, если что-то не так):
--   ReturnScreenUi (ScreenGui)
--     Dimmer (Frame)
--     Panel (Frame)
--       Title (TextLabel)
--       AwaySubtitle (TextLabel)
--       RowCart (Frame) -> Icon, Label, Value (TextLabel)
--       RowSafe (Frame) -> Icon, Label, Value (TextLabel)
--       RowStreak (Frame) -> Icon, Label, Value (TextLabel)
--       HintLabel (TextLabel)
--       CollectButton (TextButton)

local StarterGui = game:GetService("StarterGui")

-- Та же палитра, что использовал прежний процедурный экран — правки цвета
-- теперь достаточно сделать здесь ИЛИ руками в Studio на готовых инстансах,
-- код клиента их не трогает.
local COLORS = {
	Dimmer = Color3.new(0, 0, 0),
	PanelBg = Color3.fromRGB(18, 22, 32),
	PanelStroke = Color3.fromRGB(90, 130, 200),
	RowBg = Color3.fromRGB(28, 33, 46),
	Title = Color3.fromRGB(255, 255, 255),
	Subtitle = Color3.fromRGB(138, 147, 166),
	Caption = Color3.fromRGB(196, 204, 220),
	ValueDefault = Color3.fromRGB(255, 255, 255),
	CartValue = Color3.fromRGB(120, 220, 255),
	SafeValue = Color3.fromRGB(95, 255, 130),
	StreakValue = Color3.fromRGB(255, 190, 70),
	Hint = Color3.fromRGB(138, 147, 166),
	ButtonBg = Color3.fromRGB(60, 150, 250),
	ButtonText = Color3.new(1, 1, 1),
}

local function corner(parent, radius)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
	return instance
end

local function stroke(parent, thickness, color, transparency)
	local instance = Instance.new("UIStroke")
	instance.Thickness = thickness
	instance.Color = color
	instance.Transparency = transparency or 0
	instance.Parent = parent
	return instance
end

-- Строка итога: иконка-эмодзи + подпись слева, значение справа — тот же
-- макет, что раньше строился в коде (buildRow), плюс имена Icon/Label/Value,
-- по которым клиент теперь их находит и заполняет данными с сервера.
-- valueColor "по умолчанию" сохраняется в атрибут RowDefaultValueColor —
-- клиент красит цифру в него, когда для строки нет отдельного акцентного
-- цвета (иначе используется тот, что уже стоит на самой строке).
local function row(name, order, emoji, caption, valueColor, parent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 46)
	frame.BackgroundColor3 = COLORS.RowBg
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Visible = false -- клиент включает нужные строки по факту данных
	frame:SetAttribute("RowValueColor", valueColor)
	frame.Parent = parent
	corner(frame, 10)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 34, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.Text = emoji
	icon.TextScaled = true
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.new(0, 40, 0, 0)
	label.Size = UDim2.new(1, -40, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = caption
	label.TextColor3 = COLORS.Caption
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Size = UDim2.fromScale(1, 1)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.Text = ""
	value.TextColor3 = valueColor or COLORS.ValueDefault
	value.TextSize = 17
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = frame

	return frame
end

local existing = StarterGui:FindFirstChild("ReturnScreenUi")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ReturnScreenUi"
-- Как и у остального UI проекта: респавн в игре ручной (CharacterAutoLoads =
-- false), дефолтный ResetOnSpawn = true уничтожил бы экран при респавне.
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 900

local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = COLORS.Dimmer
dimmer.BackgroundTransparency = 1
dimmer.BorderSizePixel = 0
dimmer.Visible = false
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
-- Size в Scale с ограничителем: на телефоне панель занимает почти всю
-- ширину, на мониторе не растягивается в простыню.
panel.Size = UDim2.new(0.86, 0, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = COLORS.PanelBg
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 16)
stroke(panel, 2, COLORS.PanelStroke, 0.35)

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(420, math.huge)
sizeLimit.Parent = panel

local scale = Instance.new("UIScale")
scale.Name = "PanelScale"
scale.Scale = 0.9
scale.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 18)
pad.PaddingBottom = UDim.new(0, 18)
pad.PaddingLeft = UDim.new(0, 18)
pad.PaddingRight = UDim.new(0, 18)
pad.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 26)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "WHILE YOU WERE AWAY"
title.TextColor3 = COLORS.Title
title.TextSize = 20
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "AwaySubtitle"
subtitle.LayoutOrder = 1
subtitle.Size = UDim2.new(1, 0, 0, 18)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamMedium
subtitle.Text = "You were gone"
subtitle.TextColor3 = COLORS.Subtitle
subtitle.TextSize = 14
subtitle.Parent = panel

local spacer = Instance.new("Frame")
spacer.Name = "Spacer"
spacer.LayoutOrder = 2
spacer.Size = UDim2.new(1, 0, 0, 6)
spacer.BackgroundTransparency = 1
spacer.Parent = panel

-- Фиксированный набор из трёх строк (Cart / Safe / Streak), а не динамически
-- досоздаваемых — как Day1..Day7 в Daily Reward. UIListLayout сам убирает
-- зазор под невидимые строки, так что клиенту достаточно переключать
-- Row.Visible по факту, какие поля пришли в пакете с сервера.
row("RowCart", 3, "⛏️", "Mine kept working", COLORS.CartValue, panel)
row("RowSafe", 4, "🔐", "Safe accumulated", COLORS.SafeValue, panel)
row("RowStreak", 5, "🔥", "Streak", COLORS.StreakValue, panel)

local hint = Instance.new("TextLabel")
hint.Name = "HintLabel"
hint.LayoutOrder = 6
hint.Size = UDim2.new(1, 0, 0, 16)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "Your cart is loaded — deliver it to the bank"
hint.TextColor3 = COLORS.Hint
hint.TextSize = 12
hint.Visible = false
hint.Parent = panel

local button = Instance.new("TextButton")
button.Name = "CollectButton"
button.LayoutOrder = 7
button.Size = UDim2.new(1, 0, 0, 44)
button.BackgroundColor3 = COLORS.ButtonBg
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.Text = "COLLECT ALL"
button.TextColor3 = COLORS.ButtonText
button.TextSize = 17
button.AutoButtonColor = true
button.Parent = panel
corner(button, 10)

gui.Parent = StarterGui

print("[BuildReturnScreenUI] StarterGui/ReturnScreenUi created. Tweak colors/layout freely in Studio — the client script only fills text/visibility by name.")
