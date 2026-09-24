--------------------------------------------------------------------------------
-- BoulderGameUiBuilder — интерфейс мини-игры валунов (Config.BoulderGame).
-- Один источник правды (как MineVeinUiBuilder): tools/BuildBoulderGameUI.lua
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

local Builder = {}
local OUTLINE = Color3.fromRGB(12, 14, 22)

local function corner(parent, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 8)
	c.Parent = parent
end
local function stroke(parent, thickness, color, contextual)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or OUTLINE
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
end
local function frame(parent, name, size, position, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position or UDim2.new()
	f.BackgroundColor3 = color or Color3.new(1, 1, 1)
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
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
	stroke(t, 2, OUTLINE, true)
	return t
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BoulderGameUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 14
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("BuilderVersion", Config.BoulderGame.UiVersion or 1)

	local panel = frame(gui, "Panel", UDim2.fromOffset(110, 330), UDim2.fromOffset(0, 0), Color3.fromRGB(22, 26, 40), 0.1)
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Visible = false
	corner(panel, 14)
	stroke(panel, 4, OUTLINE)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = panel

	text(panel, "Title", UDim2.new(1, -10, 0, 22), UDim2.fromOffset(5, 6), "BOULDER", Color3.fromRGB(255, 215, 90))

	local track = frame(panel, "Track", UDim2.fromOffset(46, 220), UDim2.new(0.5, -23, 0, 34), Color3.fromRGB(70, 60, 55))
	corner(track, 10)
	stroke(track, 3, OUTLINE)
	local trackImage = Instance.new("ImageLabel")
	trackImage.Name = "TrackImage"
	trackImage.BackgroundTransparency = 1
	trackImage.Image = ""
	trackImage.Size = UDim2.fromScale(1, 1)
	trackImage.Parent = track
	local good = frame(track, "GoodZone", UDim2.new(1, -6, 0.28, 0), UDim2.new(0, 3, 0.3, 0), Color3.fromRGB(80, 200, 110), 0.1)
	corner(good, 6)
	local perfect = frame(track, "PerfectZone", UDim2.new(1, -6, 0.085, 0), UDim2.new(0, 3, 0.4, 0), Color3.fromRGB(255, 215, 70))
	corner(perfect, 6)
	perfect.ZIndex = 2
	local runner = frame(track, "Runner", UDim2.new(1, 14, 0, 8), UDim2.new(0, -7, 0.5, 0), Color3.new(1, 1, 1))
	runner.AnchorPoint = Vector2.new(0, 0.5)
	runner.ZIndex = 3
	corner(runner, 4)
	stroke(runner, 2, OUTLINE)
	local runnerImage = Instance.new("ImageLabel")
	runnerImage.Name = "RunnerImage"
	runnerImage.BackgroundTransparency = 1
	runnerImage.Image = ""
	runnerImage.Size = UDim2.fromScale(1, 1)
	runnerImage.ZIndex = 4
	runnerImage.Parent = runner

	local progress = frame(panel, "Progress", UDim2.new(1, -20, 0, 14), UDim2.new(0, 10, 0, 262), Color3.fromRGB(40, 42, 52))
	corner(progress, 7)
	stroke(progress, 2, OUTLINE)
	local fill = frame(progress, "Fill", UDim2.fromScale(0, 1), UDim2.new(), Color3.fromRGB(255, 160, 60))
	corner(fill, 7)
	text(progress, "Count", UDim2.new(1, 0, 1, 4), UDim2.fromOffset(0, -2), "0/5")

	local verdict = text(panel, "Verdict", UDim2.new(1, 20, 0, 26), UDim2.new(0, -10, 0, 280), "", Color3.new(1, 1, 1))
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = verdict
	text(panel, "Hint", UDim2.new(1, -10, 0, 16), UDim2.new(0, 5, 1, -20), "CLICK TO STRIKE", Color3.fromRGB(190, 195, 215), Enum.Font.GothamBlack)

	local result = text(gui, "Result", UDim2.fromOffset(460, 70), UDim2.fromScale(0.5, 0.24), "PERFECT BREAK!", Color3.fromRGB(255, 215, 80))
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Visible = false
	local resultPop = Instance.new("UIScale")
	resultPop.Name = "Pop"
	resultPop.Parent = result

	-- v9: КАРТОЧКА ДРОПА — «каменоломня»: крупный итог, под ним каменные
	-- плашки наград с золотой каймой; монеты фонтаном. Клиент клонирует
	-- RewardTemplate/CoinTemplate. Структура: DropCard → Title, Row
	-- (UIListLayout), RewardTemplate (Icon, Label, "Glow" UIStroke),
	-- CoinTemplate (TextLabel).
	local card = frame(gui, "DropCard", UDim2.fromOffset(470, 156), UDim2.fromScale(0.5, 0.3), Color3.new(0, 0, 0), 1)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Visible = false
	local cardScale = Instance.new("UIScale")
	cardScale.Name = "Pop"
	cardScale.Parent = card
	local cardTitle = text(card, "Title", UDim2.new(1, 0, 0, 58), UDim2.new(), "PERFECT BREAK!", Color3.fromRGB(255, 215, 80))
	cardTitle.Rotation = -3
	local titleStroke = cardTitle:FindFirstChildOfClass("UIStroke")
	if titleStroke then titleStroke.Thickness = 3 end
	local row = frame(card, "Row", UDim2.new(1, 0, 0, 80), UDim2.fromOffset(0, 70), Color3.new(0, 0, 0), 1)
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local reward = frame(card, "RewardTemplate", UDim2.fromOffset(106, 78), UDim2.new(), Color3.fromRGB(88, 84, 80))
	reward.Visible = false
	corner(reward, 14)
	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.Thickness = 4
	glow.Color = OUTLINE
	glow.Parent = reward
	local rewardGradient = Instance.new("UIGradient")
	rewardGradient.Rotation = 90
	rewardGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 145, 140))
	rewardGradient.Parent = reward
	local goldLip = frame(reward, "GoldLip", UDim2.new(1, -12, 0, 4), UDim2.fromOffset(6, 4), Color3.fromRGB(255, 205, 80))
	corner(goldLip, 2)
	text(reward, "Icon", UDim2.new(1, -10, 0, 36), UDim2.fromOffset(5, 8), "💰")
	text(reward, "Label", UDim2.new(1, -10, 0, 26), UDim2.fromOffset(5, 46), "$100")
	local rewardScale = Instance.new("UIScale")
	rewardScale.Name = "Pop"
	rewardScale.Parent = reward

	local coin = text(gui, "CoinTemplate", UDim2.fromOffset(34, 34), UDim2.new(), "🪙", Color3.fromRGB(255, 215, 80))
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Visible = false
	return gui
end

return Builder
