--------------------------------------------------------------------------------
-- BoulderGameUiBuilder — интерфейс мини-игры валунов (Config.BoulderGame).
-- Один источник правды (как MineVeinUiBuilder): tools/BuildAllUI.lua
-- кладёт результат в StarterGui/BoulderGameUi, BoulderGameUI.client.lua
-- строит его сам, если билдер не запускали.
--
-- СТРУКТУРА (имена — контракт с клиентом, оформление — свободно):
--   ScreenGui "BoulderGameUi" (атрибут BuilderVersion)
--   ├─ Frame "Panel"            — ставится клиентом СПРАВА от валуна
--   │    ├─ UIScale "AutoScale"
--   │    ├─ TextLabel "Title"    — "TIER 3 BOULDER"
--   │    ├─ Frame "Track"        — вертикальная полоса
--   │    │    ├─ ImageLabel "TrackImage" (пустой Image = цветная плашка)
--   │    │    ├─ Frame "GoodZone"     (позиция/высота — от клиента)
--   │    │    ├─ Frame "PerfectZone"
--   │    │    └─ Frame "Runner"       — бегунок (ImageLabel "RunnerImage")
--   │    ├─ Frame "Progress" → Frame "Fill", TextLabel "Count" ("2/5")
--   │    ├─ TextLabel "Verdict"  (+ UIScale "Pop")
--   │    └─ TextLabel "Hint"     — "CLICK TO STRIKE"
--   └─ TextLabel "Result"       — "PERFECT BREAK!" по центру (+ UIScale "Pop")
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

-- v20: подложки — ImageLabel со скинами UiKit, текст — стиль темы.
local function plate(parent, name, skin, size, position, color, transparency)
	local p = UiKit.Plate(parent, name, skin, { Size = size, Position = position or UDim2.new() })
	if color then p.BackgroundColor3 = color end
	if transparency then p.BackgroundTransparency = transparency end
	return p
end
local function text(parent, name, size, position, content, color, style)
	return UiKit.Text(parent, name, content or "", {
		_Style = style or "Title",
		Size = size,
		Position = position or UDim2.new(),
		TextColor3 = color or Color3.new(1, 1, 1),
		ZIndex = 5,
	})
end

function Builder.Build()
	local gui = UiKit.Screen("BoulderGameUi", { DisplayOrder = 14 })
	gui:SetAttribute("BuilderVersion", math.max(Config.BoulderGame.UiVersion or 1, Builder.VERSION))

	local panel = UiKit.Plate(gui, "Panel", "Panel", {
		_Accent = "Orange",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(112, 334),
		Visible = false,
	})
	UiKit.Scale(panel, "AutoScale", 1)

	text(panel, "Title", UDim2.new(1, -10, 0, 22), UDim2.fromOffset(5, 6), "BOULDER", Theme.Accents.Orange.Light)

	local track = plate(panel, "Track", "BarTrack", UDim2.fromOffset(46, 220), UDim2.new(0.5, -23, 0, 34), Color3.fromRGB(60, 55, 52))
	UiKit.Icon(track, "TrackImage", "", { ZIndex = 1 })
	local good = plate(track, "GoodZone", "Divider", UDim2.new(1, -6, 0.28, 0), UDim2.new(0, 3, 0.3, 0), Color3.fromRGB(80, 200, 110), 0.1)
	good.ZIndex = 2
	local perfect = plate(track, "PerfectZone", "Divider", UDim2.new(1, -6, 0.085, 0), UDim2.new(0, 3, 0.4, 0), Theme.Colors.Money)
	perfect.ZIndex = 3
	local runner = plate(track, "Runner", "Slot", UDim2.new(1, 14, 0, 8), UDim2.new(0, -7, 0.5, 0), Color3.new(1, 1, 1), 0)
	runner.AnchorPoint = Vector2.new(0, 0.5)
	runner.ZIndex = 4
	local runnerStroke = runner:FindFirstChild("SkinStroke")
	if runnerStroke then runnerStroke.Color = Color3.fromRGB(12, 14, 22) end
	UiKit.Icon(runner, "RunnerImage", "", { ZIndex = 5 })

	local progress, fill = UiKit.Bar(panel, "Progress", "Orange", {
		Position = UDim2.new(0, 10, 0, 262),
		Size = UDim2.new(1, -20, 0, 14),
	})
	fill.BackgroundColor3 = Color3.fromRGB(255, 160, 60)
	text(progress, "Count", UDim2.new(1, 0, 1, 6), UDim2.fromOffset(0, -3), "0/5", nil, "Number")

	local verdict = text(panel, "Verdict", UDim2.new(1, 20, 0, 26), UDim2.new(0, -10, 0, 282), "")
	UiKit.Scale(verdict, "Pop", 1)
	text(panel, "Hint", UDim2.new(1, -10, 0, 16), UDim2.new(0, 5, 1, -20), "CLICK TO STRIKE", Theme.Colors.SubText, "Small")

	local result = text(gui, "Result", UDim2.fromOffset(480, 72), UDim2.fromScale(0.5, 0.24), "PERFECT BREAK!", Theme.Colors.Money)
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Visible = false
	UiKit.Scale(result, "Pop", 1)

	-- КАРТОЧКА ДРОПА: крупный итог, под ним плашки наград; монеты фонтаном.
	-- Клиент клонирует RewardTemplate/CoinTemplate. DropCard → Title, Row
	-- (UIListLayout), RewardTemplate (Icon, Label, UIStroke "Glow"), CoinTemplate.
	local card = UiKit.Group(gui, "DropCard", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(480, 160),
		Visible = false,
	})
	UiKit.Scale(card, "Pop", 1)
	local cardTitle = UiKit.TitleText(card, "Title", "PERFECT BREAK!", "Gold", {
		Size = UDim2.new(1, 0, 0, 58),
		Rotation = -3,
		ZIndex = 5,
	})
	cardTitle.TextStroke.Thickness = 3
	local row = UiKit.Group(card, "Row", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 82) })
	UiKit.List(row, { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) })

	local reward = UiKit.Card(card, "RewardTemplate", "Gold", {
		Size = UDim2.fromOffset(108, 80),
		Visible = false,
	})
	UiKit.Stroke(reward, Color3.fromRGB(12, 14, 22), 0, 0, "Glow")
	UiKit.Text(reward, "Icon", "💰", {
		_Stroke = 0,
		Position = UDim2.fromOffset(5, 8),
		Size = UDim2.new(1, -10, 0, 36),
		ZIndex = 5,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(reward, "Label", "$100", {
		_Style = "Number",
		Position = UDim2.fromOffset(5, 46),
		Size = UDim2.new(1, -10, 0, 26),
		ZIndex = 5,
	})
	UiKit.Scale(reward, "Pop", 1)

	local coin = UiKit.Text(gui, "CoinTemplate", "🪙", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		Visible = false,
	})
	coin.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	return gui
end

return Builder
