-- Standalone Studio builder. Replaces only StarterGui/DailyRewardUi.

local StarterGui = game:GetService("StarterGui")
-- ЕДИНЫЙ СТИЛЬ С МАГАЗИНОМ (по прямому запросу — "дейлиревардс переделай
-- под стилистику шопа"): та же тёмная полупрозрачная панель, то же
-- скругление 0-4px, та же тёмная шапка с лентой-закладкой слева и красным
-- X справа, те же цветные тонкие обводки карточек. См.
-- tools/BuildShopUi.lua — палитра держится в паре с ним.
local COLORS = {
	Panel = Color3.fromRGB(18, 17, 23),
	Header = Color3.fromRGB(12, 11, 16),
	Card = Color3.fromRGB(30, 28, 38),
	CardStroke = Color3.fromRGB(70, 75, 90),
	Locked = Color3.fromRGB(38, 36, 46),
	Yellow = Color3.fromRGB(230, 185, 60), -- жёлтый = действие/награда (стайл-гайд)
	Green = Color3.fromRGB(80, 200, 90),   -- зелёный = готово/забрано
	Close = Color3.fromRGB(220, 70, 70),   -- красный = закрыть
	Ribbon = Color3.fromRGB(190, 130, 245),
	White = Color3.fromRGB(245, 247, 255),
}

local function addCorner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 4)
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Parent = inst
	return s
end
-- Placeholder-текст на будущее для Studio-превью (реальный текст на клиенте
-- всегда переписывается из Config.Quests.DailyRewards[day].Text — см.
-- DailyRewardUI.client.lua:render). Держим синхронно с конфигом просто
-- для удобства, чтобы то, что видно в Studio до запуска игры, не вводило
-- в заблуждение.
local REWARDS = { "$75K", "$350K", "1.75x MINING\n45 MIN", "$2M", "2.5x MINING\n1 HOUR", "$400M", "GOLD\nSKIN" }

local function label(name, text, size, position, textSize)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Arcade
	item.Text = text
	item.TextColor3 = COLORS.White
	item.TextSize = textSize
	item.TextStrokeTransparency = 1
	item.TextWrapped = true
	return item
end

local function rewardCard(day, size, position, parent)
	local card = Instance.new("ImageButton")
	card.Name = "Day" .. day
	card.Size = size
	card.Position = position
	card.BackgroundColor3 = COLORS.Card
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Image = ""
	card.Parent = parent
	addCorner(card, UDim.new(0, 4))
	-- День 7 — финальная награда, выделяется зелёной обводкой (как
	-- выделенная колонка на референсе), остальные нейтральные.
	addStroke(card, day == 7 and COLORS.Green or COLORS.CardStroke, day == 7 and 2 or 1)
	local dayLabel = label("Day", "DAY " .. day, UDim2.new(1, -12, 0, 28), UDim2.fromOffset(6, 7), 16)
	dayLabel.TextColor3 = COLORS.Yellow
	dayLabel.Parent = card
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = day == 7 and UDim2.fromOffset(75, 36) or UDim2.new(0.5, 0, 0, 36)
	icon.Size = day == 7 and UDim2.fromOffset(60, 44) or UDim2.fromOffset(64, 50)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = card
	local reward = label(
		"Reward", REWARDS[day],
		day == 7 and UDim2.fromOffset(330, 40) or UDim2.new(1, -10, 0, 42),
		day == 7 and UDim2.fromOffset(120, 24) or UDim2.fromOffset(5, 88), 13
	)
	-- БОЛЬШИЕ ЯРКИЕ ОБВЕДЁННЫЕ буквы — та же логика, что и в fallback-версии
	-- на клиенте (DailyRewardUI.client.lua): TextScaled сам подбирает
	-- размер под содержимое (короткие "$2M" — крупно, двухстрочные бусты —
	-- не вылезают за край), клиент только красит TextColor3 по типу
	-- награды (Money/MiningBoost/Skin), саму эту "жирность" не переопределяет.
	reward.TextScaled = true
	reward.Font = Enum.Font.GothamBlack
	reward.TextStrokeTransparency = 0.35
	reward.TextStrokeColor3 = Color3.fromRGB(10, 12, 18)
	local rewardSizeLimit = Instance.new("UITextSizeConstraint")
	rewardSizeLimit.MaxTextSize = day == 7 and 30 or 22
	rewardSizeLimit.MinTextSize = 10
	rewardSizeLimit.Parent = reward
	reward.Parent = card
	local status = label(
		"Status", "LOCKED",
		day == 7 and UDim2.fromOffset(330, 20) or UDim2.new(1, -12, 0, 18),
		day == 7 and UDim2.fromOffset(120, 66) or UDim2.new(0, 6, 1, -20), 11
	)
	status.TextColor3 = Color3.fromRGB(170, 178, 198)
	status.Parent = card
end

local existing = StarterGui:FindFirstChild("DailyRewardUi")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DailyRewardUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 500
gui.Parent = StarterGui

local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
dimmer.BackgroundTransparency = 0.28
dimmer.BorderSizePixel = 0
dimmer.Visible = false
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(560, 590)
panel.BackgroundColor3 = COLORS.Panel
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local scale = Instance.new("UIScale")
scale.Name = "ResponsiveScale"
scale.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = COLORS.Header
header.BorderSizePixel = 0
header.Parent = panel
addCorner(panel, UDim.new(0, 4))
addStroke(panel, Color3.fromRGB(150, 100, 210), 1)
addCorner(header, UDim.new(0, 4))

-- Лента-закладка слева в шапке — тот же элемент, что в магазине/квестах,
-- ради единого стиля всех окон.
local ribbon = Instance.new("Frame")
ribbon.Name = "RibbonIcon"
ribbon.AnchorPoint = Vector2.new(0, 0)
ribbon.Position = UDim2.fromOffset(14, 0)
ribbon.Size = UDim2.fromOffset(24, 38)
ribbon.BackgroundColor3 = COLORS.Ribbon
ribbon.BorderSizePixel = 0
ribbon.ZIndex = 4
ribbon.Parent = header
for _, xOffset in { -1, 1 } do
	local notch = Instance.new("Frame")
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.Position = UDim2.new(0.5, xOffset * 6, 1, -6)
	notch.Size = UDim2.fromOffset(9, 9)
	notch.Rotation = 45
	notch.BackgroundColor3 = COLORS.Header
	notch.BorderSizePixel = 0
	notch.ZIndex = 5
	notch.Parent = ribbon
end

label("Title", "DAILY REWARD", UDim2.new(1, -90, 1, 0), UDim2.fromOffset(24, 0), 27).Parent = header
local close = Instance.new("TextButton")
close.Name = "CloseButton"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 14)
close.Size = UDim2.fromOffset(42, 38)
close.BackgroundColor3 = Color3.new(0, 0, 0)
close.BackgroundTransparency = 1
close.TextColor3 = COLORS.Close
close.BorderSizePixel = 0
close.Font = Enum.Font.Arcade
close.Text = "X"
close.TextColor3 = COLORS.White
close.TextSize = 18
close.TextStrokeTransparency = 1
close.Parent = header

for day = 1, 6 do
	local column = (day - 1) % 3
	local row = math.floor((day - 1) / 3)
	rewardCard(day, UDim2.fromOffset(150, 150), UDim2.fromOffset(35 + column * 170, 76 + row * 164), panel)
end
rewardCard(7, UDim2.fromOffset(490, 94), UDim2.fromOffset(35, 405), panel)

local claim = Instance.new("TextButton")
claim.Name = "ClaimButton"
claim.Position = UDim2.fromOffset(35, 520)
claim.Size = UDim2.fromOffset(490, 48)
claim.BackgroundColor3 = COLORS.Yellow
claim.BorderSizePixel = 0
claim.Font = Enum.Font.Arcade
claim.Text = "CLAIM TODAY'S REWARD"
claim.TextColor3 = COLORS.White
claim.TextSize = 15
claim.TextStrokeTransparency = 1
claim.Active = false
claim.Parent = panel

print("[BuildDailyRewardUI] StarterGui/DailyRewardUi created. Replace each DayN/Icon image in Studio.")
