--------------------------------------------------------------------------------
-- GeodeUiBuilder (v9) — ОКНА ЖЕОД: хранилище и вскрытие, покупка жеод,
-- меню «сколько открыть», оверлей вскрытия. Свой стиль: «аметистовая
-- пещера» — тёмный фиолетовый камень, аметистовые грани, неровная
-- «каменная» полоса заголовка. Подиум банка — отдельный билдер
-- (BankPodiumUiBuilder), здесь он только подключается.
-- tools/BuildGeodeUI.lua (или tools/BuildAllUI.lua) — в StarterGui;
-- GeodeUI.client.lua пересобирает старую версию сам.
--
-- КОНТРАКТ (как прежний tools/BuildGeodeUI.lua):
--   ScreenGui "GeodeUi" (BuilderVersion) → ImageButton "Dimmer";
--   ImageLabel "VaultPanel" → Header/Title, CloseButton(Caption), Body,
--     ScrollingFrame "GeodeGrid" → "GeodeCardTemplate" (Name, IconBackground/Icon,
--     Count, InfoButton), ImageButton "BuyGeodesButton"(Caption),
--     ImageLabel "DropInfoPanel" → InfoTitle, InfoRarity, ChanceScroll/InfoChances,
--     ImageButton "CrackButton"(Caption);
--   ImageLabel "BuyGeodesPanel" → "BuyGeodesGrid" → "BuyGeodeCardTemplate"
--     (Name, IconBackground/Icon, Owned, BuyButton(Caption, ProductIcon));
--   "PodiumPanel" — BankPodiumUiBuilder;
--   ImageLabel "OpeningOverlay" → Flash, EggImage, ResultImage(DropOutline),
--     ResultText, CrackTapButton, ClickHint, SkipButton(Caption);
--   Frame "OpenCountMenu" → Title, TextButton "Open3"/"Open1"/"Open5".
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local BankPodiumUiBuilder = require(ReplicatedStorage.Shared.BankPodiumUiBuilder)

local Builder = {}
Builder.VERSION = 2

local INK = Color3.fromRGB(14, 8, 22)
local STONE = Color3.fromRGB(44, 32, 64)
local STONE_DEEP = Color3.fromRGB(26, 18, 40)
local FACET = Color3.fromRGB(70, 52, 104)
local AMETHYST = Color3.fromRGB(185, 120, 255)
local AMETHYST_LIGHT = Color3.fromRGB(225, 190, 255)
local GREEN = Color3.fromRGB(70, 195, 100)

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
local function gradient(parent, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
end
local function text(parent, name, value, zIndex, color, font)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = font or Enum.Font.FredokaOne
	item.Text = value or ""
	item.TextColor3 = color or Color3.new(1, 1, 1)
	item.TextScaled = true
	item.TextWrapped = true
	item.RichText = true
	item.TextStrokeTransparency = 1
	item.ZIndex = zIndex or 4
	item.Parent = parent
	stroke(item, 2, INK, true)
	return item
end
-- Кнопка-самоцвет: ImageButton с подписью "Caption" (контракт setButtonText).
local function gemButton(parent, name, value, color, zIndex)
	local item = Instance.new("ImageButton")
	item.Name = name
	item.Image = ""
	item.AutoButtonColor = false
	item.BackgroundColor3 = color
	item.ZIndex = zIndex or 4
	item.Parent = parent
	corner(item, UDim.new(0, 10))
	stroke(item, 3, INK)
	gradient(item, Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 200))
	local caption = text(item, "Caption", value, (zIndex or 4) + 1)
	caption.Size = UDim2.new(1, -10, 1, -8)
	caption.Position = UDim2.fromOffset(5, 4)
	return item
end

local function cavePanel(gui, name, titleText)
	local item = Instance.new("ImageLabel")
	item.Name = name
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.fromScale(0.5, 0.52)
	item.Size = UDim2.fromOffset(760, 500)
	item.BackgroundColor3 = STONE
	item.Image = ""
	item.Visible = false
	item.ZIndex = 2
	item.Parent = gui
	corner(item, UDim.new(0, 18))
	stroke(item, 5, INK)
	gradient(item, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 130, 180))
	local responsive = Instance.new("UIScale")
	responsive.Name = "ResponsiveScale"
	responsive.Parent = item
	-- Аметистовые «кристаллики» по краям — декор.
	for i, spot in { { 0.03, 0.9, 18 }, { 0.07, 0.95, 12 }, { 0.96, 0.12, 14 }, { 0.93, 0.93, 20 } } do
		local gem = Instance.new("Frame")
		gem.Name = "Gem" .. i
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = UDim2.fromScale(spot[1], spot[2])
		gem.Size = UDim2.fromOffset(spot[3], spot[3] * 1.6)
		gem.Rotation = (i % 2 == 0) and 20 or -15
		gem.BackgroundColor3 = AMETHYST
		gem.BackgroundTransparency = 0.25
		gem.ZIndex = 2
		gem.Parent = item
		corner(gem, UDim.new(0, 3))
		stroke(gem, 2, INK)
	end
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.fromOffset(-12, -26)
	header.Size = UDim2.fromOffset(300, 52)
	header.BackgroundColor3 = AMETHYST
	header.ZIndex = 5
	header.Parent = item
	corner(header, UDim.new(0, 6)) -- угловатее — «сколотый камень»
	stroke(header, 3, INK)
	gradient(header, AMETHYST_LIGHT, Color3.fromRGB(120, 60, 200), 100)
	local title = text(header, "Title", titleText, 6)
	title.Position = UDim2.fromOffset(14, 5)
	title.Size = UDim2.new(1, -24, 1, -10)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local close = gemButton(item, "CloseButton", "X", Color3.fromRGB(215, 55, 70), 7)
	close.Position = UDim2.new(1, -27, 0, -19)
	close.Size = UDim2.fromOffset(46, 46)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(18, 62)
	body.Size = UDim2.new(1, -36, 1, -80)
	body.BackgroundColor3 = STONE_DEEP
	body.BackgroundTransparency = 0.2
	body.ZIndex = 2
	body.Parent = item
	corner(body, UDim.new(0, 14))
	return item, body
end

local function grid(parent, name)
	local item = Instance.new("ScrollingFrame")
	item.Name = name
	item.Position = UDim2.fromOffset(18, 68)
	item.Size = UDim2.new(1, -36, 1, -92)
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	item.ScrollBarThickness = 6
	item.ScrollBarImageColor3 = AMETHYST
	item.AutomaticCanvasSize = Enum.AutomaticSize.Y
	item.CanvasSize = UDim2.new()
	item.ZIndex = 3
	item.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = item
	local layout = Instance.new("UIGridLayout")
	layout.Name = "CardLayout"
	layout.CellSize = UDim2.fromOffset(170, 214)
	layout.CellPadding = UDim2.fromOffset(16, 16)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.Name
	layout.Parent = item
	return item
end

-- Карточка-«друза»: гранёная плашка, иконка в каменной нише.
local function geodeCard(parent, name, className, iconHeight)
	local card = Instance.new(className)
	card.Name = name
	card.BackgroundColor3 = FACET
	card.Visible = false
	card.ZIndex = 3
	if card:IsA("ImageButton") then
		card.Image = ""
		card.AutoButtonColor = false
	elseif card:IsA("ImageLabel") then
		card.Image = ""
	end
	card.Parent = parent
	corner(card, UDim.new(0, 12))
	stroke(card, 3, INK)
	gradient(card, Color3.new(1, 1, 1), Color3.fromRGB(160, 145, 190))
	local cardName = text(card, "Name", "GEODE", 4)
	cardName.Position = UDim2.fromOffset(6, 6)
	cardName.Size = UDim2.new(1, -12, 0, 24)
	local background = Instance.new("ImageLabel")
	background.Name = "IconBackground"
	background.AnchorPoint = Vector2.new(0.5, 0)
	background.Position = UDim2.new(0.5, 0, 0, 34)
	background.Size = UDim2.new(1, -18, 0, iconHeight)
	background.BackgroundColor3 = STONE_DEEP
	background.ScaleType = Enum.ScaleType.Stretch
	background.ZIndex = 3
	background.Parent = card
	corner(background, UDim.new(0, 10))
	stroke(background, 2, AMETHYST)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.76, 0.76)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 4
	icon.Parent = background
	return card
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GeodeUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 28
	gui.Enabled = false
	gui:SetAttribute("BuilderVersion", Builder.VERSION)

	local dimmer = Instance.new("ImageButton")
	dimmer.Name = "Dimmer"
	dimmer.Image = ""
	dimmer.AutoButtonColor = false
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.fromRGB(8, 4, 14)
	dimmer.BackgroundTransparency = 0.35
	dimmer.ZIndex = 1
	dimmer.Parent = gui

	-- ХРАНИЛИЩЕ
	local vault = cavePanel(gui, "VaultPanel", "🪨 GEODES")
	local geodeGrid = grid(vault, "GeodeGrid")
	local geode = geodeCard(geodeGrid, "GeodeCardTemplate", "ImageButton", 136)
	local count = text(geode, "Count", "x0", 4, Color3.fromRGB(150, 255, 170), Enum.Font.GothamBlack)
	count.Position = UDim2.new(0, 6, 1, -34)
	count.Size = UDim2.new(1, -12, 0, 26)
	local info = gemButton(geode, "InfoButton", "i", Color3.fromRGB(90, 70, 150), 6)
	info.AnchorPoint = Vector2.new(1, 0)
	info.Position = UDim2.new(1, -12, 0, 40)
	info.Size = UDim2.fromOffset(28, 28)
	local buyOpen = gemButton(vault, "BuyGeodesButton", "🛒 BUY", GREEN, 6)
	buyOpen.Position = UDim2.new(1, -200, 0, 12)
	buyOpen.Size = UDim2.fromOffset(120, 40)

	local drop = Instance.new("ImageLabel")
	drop.Name = "DropInfoPanel"
	drop.Image = ""
	drop.Position = UDim2.new(1, 14, 0, 62)
	drop.Size = UDim2.fromOffset(280, 410)
	drop.BackgroundColor3 = STONE
	drop.Visible = false
	drop.ZIndex = 5
	drop.Parent = vault
	corner(drop, UDim.new(0, 16))
	stroke(drop, 4, INK)
	local infoTitle = text(drop, "InfoTitle", "DROPS", 6)
	infoTitle.Position = UDim2.fromOffset(14, 12)
	infoTitle.Size = UDim2.new(1, -28, 0, 32)
	infoTitle.TextXAlignment = Enum.TextXAlignment.Left
	local infoRarity = text(drop, "InfoRarity", "", 6, AMETHYST_LIGHT)
	infoRarity.Position = UDim2.fromOffset(14, 46)
	infoRarity.Size = UDim2.new(1, -28, 0, 22)
	infoRarity.TextXAlignment = Enum.TextXAlignment.Left
	local chanceScroll = Instance.new("ScrollingFrame")
	chanceScroll.Name = "ChanceScroll"
	chanceScroll.Position = UDim2.fromOffset(14, 76)
	chanceScroll.Size = UDim2.new(1, -28, 1, -146)
	chanceScroll.BackgroundColor3 = STONE_DEEP
	chanceScroll.BorderSizePixel = 0
	chanceScroll.ScrollBarThickness = 5
	chanceScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	chanceScroll.CanvasSize = UDim2.new()
	chanceScroll.ZIndex = 6
	chanceScroll.Parent = drop
	corner(chanceScroll, UDim.new(0, 10))
	local chances = Instance.new("TextLabel")
	chances.Name = "InfoChances"
	chances.BackgroundTransparency = 1
	chances.Font = Enum.Font.GothamBold
	chances.Size = UDim2.new(1, -12, 0, 0)
	chances.Position = UDim2.fromOffset(6, 4)
	chances.AutomaticSize = Enum.AutomaticSize.Y
	chances.TextXAlignment = Enum.TextXAlignment.Left
	chances.TextYAlignment = Enum.TextYAlignment.Top
	chances.TextColor3 = Color3.new(1, 1, 1)
	chances.TextSize = 14
	chances.TextWrapped = true
	chances.RichText = true
	chances.Text = ""
	chances.ZIndex = 7
	chances.Parent = chanceScroll
	local crack = gemButton(drop, "CrackButton", "⛏ CRACK", GREEN, 6)
	crack.AnchorPoint = Vector2.new(0, 1)
	crack.Position = UDim2.new(0, 14, 1, -12)
	crack.Size = UDim2.new(1, -28, 0, 50)
	crack.Active = false

	-- ПОКУПКА
	local buyPanel = cavePanel(gui, "BuyGeodesPanel", "🛒 BUY GEODES")
	local buyGrid = grid(buyPanel, "BuyGeodesGrid")
	local buyCard = geodeCard(buyGrid, "BuyGeodeCardTemplate", "ImageLabel", 110)
	local owned = text(buyCard, "Owned", "x0", 4, Color3.fromRGB(150, 255, 170), Enum.Font.GothamBold)
	owned.Position = UDim2.fromOffset(6, 148)
	owned.Size = UDim2.new(1, -12, 0, 18)
	local buy = gemButton(buyCard, "BuyButton", "R$0", GREEN, 5)
	buy.Position = UDim2.new(0, 8, 1, -40)
	buy.Size = UDim2.new(1, -16, 0, 32)
	local productIcon = Instance.new("ImageLabel")
	productIcon.Name = "ProductIcon"
	productIcon.Position = UDim2.fromOffset(7, 4)
	productIcon.Size = UDim2.fromOffset(24, 24)
	productIcon.BackgroundTransparency = 1
	productIcon.ScaleType = Enum.ScaleType.Fit
	productIcon.Visible = false
	productIcon.ZIndex = 7
	productIcon.Parent = buy

	-- ПОДИУМ БАНКА — свой билдер.
	BankPodiumUiBuilder.Install(gui)

	-- ОВЕРЛЕЙ ВСКРЫТИЯ
	local opening = Instance.new("ImageLabel")
	opening.Name = "OpeningOverlay"
	opening.Image = ""
	opening.Size = UDim2.fromScale(1, 1)
	opening.BackgroundColor3 = Color3.fromRGB(12, 8, 20)
	opening.BackgroundTransparency = 1
	opening.ImageTransparency = 1
	opening.Visible = false
	opening.ZIndex = 20
	opening.Parent = gui
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 23
	flash.Parent = opening
	local egg = Instance.new("ImageLabel")
	egg.Name = "EggImage"
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	egg.Position = UDim2.fromScale(0.5, 0.48)
	egg.Size = UDim2.fromOffset(230, 230)
	egg.BackgroundTransparency = 1
	egg.ScaleType = Enum.ScaleType.Fit
	egg.ZIndex = 21
	egg.Visible = false -- вскрытие — 3D-сцена; EggImage остаётся для контракта
	egg.Parent = opening
	local resultImage = egg:Clone()
	resultImage.Name = "ResultImage"
	resultImage.Position = UDim2.fromScale(0.5, 0.4)
	resultImage.Size = UDim2.fromOffset(250, 250)
	resultImage.ZIndex = 22
	resultImage.Parent = opening
	local outline = Instance.new("UIStroke")
	outline.Name = "DropOutline"
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = Config.Geodes.DropOutlineThickness
	outline.Transparency = Config.Geodes.DropOutlineTransparency
	outline.Parent = resultImage
	local resultText = text(opening, "ResultText", "", 22)
	resultText.AnchorPoint = Vector2.new(0.5, 0)
	resultText.Position = UDim2.fromScale(0.5, 0.63)
	resultText.Size = UDim2.new(0.75, 0, 0, 110)
	resultText.Visible = false
	local tap = Instance.new("ImageButton")
	tap.Name = "CrackTapButton"
	tap.Image = ""
	tap.AutoButtonColor = false
	tap.AnchorPoint = Vector2.new(0.5, 0.5)
	tap.Position = UDim2.fromScale(0.5, 0.5)
	tap.Size = UDim2.fromScale(1, 1)
	tap.BackgroundTransparency = 1
	tap.Visible = false
	tap.ZIndex = 22
	tap.Parent = opening
	local hint = text(opening, "ClickHint", "TAP!", 22, Color3.fromRGB(255, 235, 90))
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.Position = UDim2.new(0.5, -165, 0.48, 0)
	hint.Size = UDim2.fromOffset(130, 54)
	hint.Visible = false
	local skip = gemButton(opening, "SkipButton", "SKIP ▶", Color3.fromRGB(90, 70, 150), 24)
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -20, 1, -20)
	skip.Size = UDim2.fromOffset(120, 44)
	skip.Visible = false

	-- СКОЛЬКО ОТКРЫТЬ
	local menu = Instance.new("Frame")
	menu.Name = "OpenCountMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.5)
	menu.Size = UDim2.fromOffset(420, 220)
	menu.BackgroundColor3 = STONE
	menu.Visible = false
	menu.ZIndex = 40
	menu.Parent = gui
	corner(menu, UDim.new(0, 18))
	stroke(menu, 5, INK)
	local menuTitle = text(menu, "Title", "OPEN", 41)
	menuTitle.Position = UDim2.fromOffset(20, 16)
	menuTitle.Size = UDim2.new(1, -40, 0, 42)
	for _, amount in { 3, 1, 5 } do
		local option = Instance.new("TextButton")
		option.Name = "Open" .. amount
		option.AutoButtonColor = false
		option.BackgroundColor3 = amount == 5 and Color3.fromRGB(150, 80, 215) or GREEN
		option.Font = Enum.Font.FredokaOne
		option.Text = ""
		option.TextColor3 = Color3.new(1, 1, 1)
		option.TextScaled = true
		option.TextWrapped = true
		option.AnchorPoint = Vector2.new(0.5, 0)
		option.Position = UDim2.new(amount == 3 and 0.22 or amount == 1 and 0.5 or 0.78, 0, 0, 84)
		option.Size = UDim2.fromOffset(108, 80)
		option.ZIndex = 41
		option.Parent = menu
		corner(option, UDim.new(0, 14))
		stroke(option, 3, INK)
		gradient(option, Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 200))
	end
	return gui
end

return Builder
