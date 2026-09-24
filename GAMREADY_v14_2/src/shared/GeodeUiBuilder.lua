--------------------------------------------------------------------------------
-- GeodeUiBuilder (v20) — ОКНА ЖЕОД: хранилище и вскрытие, покупка жеод,
-- меню «сколько открыть», оверлей вскрытия. Единый стиль UiKit (акцент Pink).
-- Подиум банка — отдельный билдер (BankPodiumUiBuilder), здесь он только
-- подключается. tools/BuildAllUI.lua → StarterGui/GeodeUi; GeodeUI.client.lua
-- пересобирает старую версию сам.
--
-- КОНТРАКТ (детали — прямые дети своих панелей):
--   ScreenGui "GeodeUi" (BuilderVersion) → ImageButton "Dimmer";
--   ImageLabel "VaultPanel" → Header/Title, CloseButton(Caption),
--     ScrollingFrame "GeodeGrid" → "GeodeCardTemplate" (Name, IconBackground/Icon,
--     Count, InfoButton), ImageButton "BuyGeodesButton"(Caption),
--     ImageLabel "DropInfoPanel" → InfoTitle, InfoRarity, ChanceScroll/InfoChances,
--     ImageButton "CrackButton"(Caption), ImageButton "AllDropsButton"(Caption);
--   ImageLabel "BuyGeodesPanel" → CloseButton, "BuyGeodesGrid" → "BuyGeodeCardTemplate"
--     (Name, IconBackground/Icon, Owned, BuyButton(Caption, ProductIcon));
--   "PodiumPanel" — BankPodiumUiBuilder;
--   ImageLabel "OpeningOverlay" → Flash, EggImage, ResultImage(DropOutline),
--     ResultText, CrackTapButton, ClickHint, SkipButton(Caption), Frame "ResultCards";
--   ImageLabel "OpenCountMenu" → Title, TextButton "Open3"/"Open1"/"Open5";
--   TextButton "CollectionContextBackdrop", ImageLabel "CollectionContextTemplate"
--     → Title, Close, Install/Extract/Delete, ConfirmDelete/CancelDelete (Caption).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local BankPodiumUiBuilder = require(ReplicatedStorage.Shared.BankPodiumUiBuilder)
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

local ACCENT = UiKit.Accent("Pink")

local function cavePanel(gui, name, titleText)
	local panel, parts = UiKit.Window(gui, name, {
		Title = titleText,
		Accent = ACCENT,
		Size = UDim2.fromOffset(780, 520),
		Position = UDim2.fromScale(0.5, 0.52),
		Flat = true,
		CloseInRoot = true,
		ZIndex = 2,
	})
	parts.TitleBar.Name = "Header"
	UiKit.Scale(panel, "ResponsiveScale", 1)
	return panel, parts
end

local function grid(panel, parts, name)
	local item = UiKit.Scroll(panel, name, {
		Position = UDim2.fromOffset(parts.Pad, parts.Top),
		Size = UDim2.new(1, -parts.Pad * 2, 1, -(parts.Top + parts.Pad)),
		ZIndex = 3,
	})
	UiKit.Padding(item, 10, 4, 10, 10)
	local layout = UiKit.Grid(item, UDim2.fromOffset(170, 214), UDim2.fromOffset(16, 16), {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.Name,
	})
	layout.Name = "CardLayout"
	return item
end

local function geodeCard(parent, name, isButton, iconHeight)
	local card = isButton and UiKit.CardButton(parent, name, ACCENT, { Visible = false, ZIndex = 3 })
		or UiKit.Card(parent, name, ACCENT, { Visible = false, ZIndex = 3 })
	UiKit.Text(card, "Name", "GEODE", {
		_Style = "Heading",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 24),
		ZIndex = 4,
	})
	local background = UiKit.Plate(card, "IconBackground", "Slot", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.new(1, -18, 0, iconHeight),
		ZIndex = 3,
	})
	UiKit.Icon(background, "Icon", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.76, 0.76),
		ZIndex = 4,
	})
	return card
end

function Builder.Build()
	local gui = UiKit.Screen("GeodeUi", { DisplayOrder = 28, Enabled = false })
	gui:SetAttribute("BuilderVersion", Builder.VERSION)

	local dimmer = Instance.new("ImageButton")
	dimmer.Name = "Dimmer"
	dimmer.Image = ""
	dimmer.AutoButtonColor = false
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 0.45
	dimmer.BorderSizePixel = 0
	dimmer.ZIndex = 1
	dimmer:SetAttribute("DisableGlobalHover", true)
	dimmer.Parent = gui

	-- ХРАНИЛИЩЕ
	local vault, vaultParts = cavePanel(gui, "VaultPanel", "🪨 Geodes")
	local geodeGrid = grid(vault, vaultParts, "GeodeGrid")
	local geode = geodeCard(geodeGrid, "GeodeCardTemplate", true, 136)
	UiKit.Text(geode, "Count", "x0", {
		_Style = "Number",
		Position = UDim2.new(0, 6, 1, -34),
		Size = UDim2.new(1, -12, 0, 26),
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 4,
	})
	UiKit.Button(geode, "InfoButton", "i", "Purple", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 40),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 6,
	})
	UiKit.Button(vault, "BuyGeodesButton", "🛒 BUY", "Green", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0, 27),
		Size = UDim2.fromOffset(120, 38),
		ZIndex = 6,
	})

	local drop = UiKit.Card(vault, "DropInfoPanel", ACCENT, {
		Position = UDim2.new(1, 14, 0, 60),
		Size = UDim2.fromOffset(290, 440),
		Visible = false,
		ZIndex = 5,
	})
	UiKit.Text(drop, "InfoTitle", "DROPS", {
		_Style = "Title",
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -130, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})
	UiKit.Text(drop, "InfoRarity", "", {
		_Style = "Heading",
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.new(1, -28, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = ACCENT.Light,
		ZIndex = 6,
	})
	local chanceScroll = UiKit.Scroll(drop, "ChanceScroll", {
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.new(1, -28, 1, -146),
		ZIndex = 6,
	})
	chanceScroll.BackgroundTransparency = 0.5
	chanceScroll.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	local chances = UiKit.Text(chanceScroll, "InfoChances", "", {
		_Style = "Body",
		_Stroke = 1,
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 7,
	})
	chances.TextScaled = false
	chances.TextSize = 15
	UiKit.Button(drop, "CrackButton", "⛏ CRACK", "Green", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(1, -28, 0, 50),
		Active = false,
		ZIndex = 6,
		_TextStyle = "Title",
	})
	UiKit.Button(drop, "AllDropsButton", "🔍 ALL DROPS", "Purple", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 10),
		Size = UDim2.fromOffset(112, 30),
		ZIndex = 20,
	})

	-- ПОКУПКА
	local buyPanel, buyParts = cavePanel(gui, "BuyGeodesPanel", "🛒 Buy Geodes")
	local buyGrid = grid(buyPanel, buyParts, "BuyGeodesGrid")
	local buyCard = geodeCard(buyGrid, "BuyGeodeCardTemplate", false, 110)
	UiKit.Text(buyCard, "Owned", "x0", {
		_Style = "Heading",
		Position = UDim2.fromOffset(6, 148),
		Size = UDim2.new(1, -12, 0, 18),
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 4,
	})
	local buy = UiKit.Button(buyCard, "BuyButton", "R$0", "Green", {
		Position = UDim2.new(0, 8, 1, -40),
		Size = UDim2.new(1, -16, 0, 32),
		ZIndex = 5,
	})
	UiKit.Icon(buy, "ProductIcon", Theme.Icons.Robux, {
		Position = UDim2.fromOffset(7, 4),
		Size = UDim2.fromOffset(24, 24),
		Visible = false,
		ZIndex = 7,
	})

	-- ПОДИУМ БАНКА — свой билдер.
	BankPodiumUiBuilder.Install(gui)

	-- ОВЕРЛЕЙ ВСКРЫТИЯ
	local opening = UiKit.New("ImageLabel", {
		Name = "OpeningOverlay",
		Image = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 8, 20),
		BackgroundTransparency = 1,
		ImageTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
	}, gui)
	UiKit.Plate(opening, "Flash", "Dimmer", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 23,
	})
	local egg = UiKit.Icon(opening, "EggImage", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(230, 230),
		Visible = false,
		ZIndex = 21,
	})
	local resultImage = egg:Clone()
	resultImage.Name = "ResultImage"
	resultImage.Position = UDim2.fromScale(0.5, 0.4)
	resultImage.Size = UDim2.fromOffset(250, 250)
	resultImage.ZIndex = 22
	resultImage.Parent = opening
	local outline = Instance.new("UIStroke")
	outline.Name = "DropOutline"
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = Config.Geodes and Config.Geodes.DropOutlineThickness or 0
	outline.Transparency = Config.Geodes and Config.Geodes.DropOutlineTransparency or 1
	outline.Parent = resultImage
	UiKit.Text(opening, "ResultText", "", {
		_Style = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.63),
		Size = UDim2.new(0.75, 0, 0, 110),
		Visible = false,
		ZIndex = 22,
	})
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
	tap:SetAttribute("DisableGlobalHover", true)
	tap.Parent = opening
	UiKit.Text(opening, "ClickHint", "TAP!", {
		_Style = "Title",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -165, 0.48, 0),
		Size = UDim2.fromOffset(130, 54),
		TextColor3 = Theme.Colors.Money,
		Visible = false,
		ZIndex = 22,
	})
	UiKit.Button(opening, "SkipButton", "SKIP ▶", "Purple", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(130, 46),
		Visible = false,
		ZIndex = 30,
	})
	local resultCards = UiKit.Group(opening, "ResultCards", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(530, 360),
		Visible = false,
		ZIndex = 22,
	})
	local cardsLayout = UiKit.List(resultCards, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18),
	})
	cardsLayout.Name = "CardLayout"
	UiKit.Scale(resultCards, "ResponsiveScale", 1)

	-- Шаблон карточки результата вскрытия (клиент клонирует и задаёт размер).
	local resultCard = UiKit.Group(opening, "ResultCardTemplate", {
		Size = UDim2.fromOffset(245, 350),
		Visible = false,
		ZIndex = 22,
	})
	local resultCardImage = UiKit.Plate(resultCard, "ResultImage", "Slot", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(220, 220),
		ZIndex = 22,
	})
	resultCardImage.ScaleType = Enum.ScaleType.Fit
	local resultCardOutline = Instance.new("UIStroke")
	resultCardOutline.Name = "DropOutline"
	resultCardOutline.Thickness = 0
	resultCardOutline.Transparency = 1
	resultCardOutline.Parent = resultCardImage
	UiKit.Text(resultCard, "ResultText", "", {
		_Style = "Heading",
		Position = UDim2.fromOffset(4, 232),
		Size = UDim2.new(1, -8, 0, 108),
		ZIndex = 22,
	})
	-- Шарик «бей сюда» при вскрытии.
	local crackBall = UiKit.PlateButton(opening, "CrackBallTemplate", "Round", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = Color3.fromRGB(255, 210, 60),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 25,
	})
	crackBall.ScaleType = Enum.ScaleType.Fit
	local ballStroke = crackBall:FindFirstChild("SkinStroke")
	if ballStroke then
		ballStroke.Color = Color3.new(0, 0, 0)
		ballStroke.Thickness = 3
		ballStroke.Transparency = 0
	end

	-- КОНТЕКСТНОЕ МЕНЮ КРИСТАЛЛА на подиуме (клиент клонирует шаблон).
	local backdrop = UiKit.Dimmer(gui, { Name = "CollectionContextBackdrop", ZIndex = 79 })
	backdrop.Visible = false
	local context = UiKit.Card(gui, "CollectionContextTemplate", Theme.Accents.Green, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(280, 200),
		Visible = false,
		ZIndex = 80,
	})
	UiKit.Text(context, "Title", "CRYSTAL", {
		_Style = "Title",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -52, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 81,
	})
	local contextClose = UiKit.CloseButton(context, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 82,
	})
	contextClose.Name = "Close"
	for index, action in { { "Install", "PUT ON PODIUM", "Green" }, { "Extract", "TAKE IN HANDS", "Blue" }, { "Delete", "DELETE", "Red" } } do
		UiKit.Button(context, action[1], action[2], action[3], {
			Position = UDim2.fromOffset(12, 44 + (index - 1) * 48),
			Size = UDim2.new(1, -24, 0, 40),
			ZIndex = 81,
		})
	end
	UiKit.Button(context, "ConfirmDelete", "YES", "Red", {
		Position = UDim2.fromOffset(12, 44 + 2 * 48),
		Size = UDim2.new(0.5, -15, 0, 40),
		Visible = false,
		ZIndex = 83,
	})
	UiKit.Button(context, "CancelDelete", "NO", "Dark", {
		Position = UDim2.new(0.5, 3, 0, 44 + 2 * 48),
		Size = UDim2.new(0.5, -15, 0, 40),
		Visible = false,
		ZIndex = 83,
	})

	-- СКОЛЬКО ОТКРЫТЬ (кнопки — TextButton: клиент пишет Text напрямую).
	local menu = UiKit.Plate(gui, "OpenCountMenu", "Panel", {
		_Accent = ACCENT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 230),
		Visible = false,
		ZIndex = 40,
	})
	menu.BackgroundTransparency = 0.1
	UiKit.TitleText(menu, "Title", "OPEN", ACCENT, {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 46),
		ZIndex = 41,
	})
	for _, amount in { 3, 1, 5 } do
		local option = UiKit.TextButton(menu, "Open" .. amount, "", {
			_Style = "Title",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(amount == 3 and 0.22 or amount == 1 and 0.5 or 0.78, 0, 0, 84),
			Size = UDim2.fromOffset(112, 84),
			BackgroundTransparency = 0,
			BackgroundColor3 = amount == 5 and Theme.Skins.Button_Purple.Color or Theme.Skins.Button_Green.Color,
			ZIndex = 41,
		})
		UiKit.Stroke(option, Color3.fromRGB(230, 255, 210), 1.5, 0, "SkinStroke").ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		UiKit.Gradient(option, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190), 90, "SkinGradient")
	end
	return gui
end

return Builder
