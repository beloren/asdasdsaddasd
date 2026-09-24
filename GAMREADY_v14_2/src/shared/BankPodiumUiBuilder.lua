--------------------------------------------------------------------------------
-- BankPodiumUiBuilder (v20) — окно ПОДИУМА БАНКА (какой кристалл стоит на
-- подиуме и приносит деньги). Единый стиль UiKit (акцент Green).
-- Встраивается в ScreenGui "GeodeUi" (GeodeUiBuilder вызывает Install).
--
-- СТРУКТУРА (контракт GeodeUI.client.lua; всё — прямые дети панели):
--   ImageLabel "PodiumPanel" (UIScale "ResponsiveScale")
--   ├─ ImageLabel "Header" (полоса заголовка) → TextLabel "Title"
--   ├─ ImageButton "CloseButton" → TextLabel "Caption"
--   ├─ ImageLabel "BankIncome" → TextLabel "Text"      — «💰 +$X/SEC»
--   └─ ScrollingFrame "CrystalGrid" (UIGridLayout "CardLayout")
--        └─ ImageButton "CrystalCardTemplate" → "Name", ImageLabel "IconBackground"
--             → ImageLabel "Icon"; "Income", "Installed"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}

function Builder.Install(gui)
	local existing = gui:FindFirstChild("PodiumPanel")
	if existing then existing:Destroy() end
	local accent = UiKit.Accent("Green")

	local panel, parts = UiKit.Window(gui, "PodiumPanel", {
		Title = "🏦 Bank Vault",
		Accent = "Green",
		Size = UDim2.fromOffset(800, 530),
		Position = UDim2.fromScale(0.5, 0.52),
		Flat = true,
		CloseInRoot = true,
	})
	parts.TitleBar.Name = "Header"
	UiKit.Scale(panel, "ResponsiveScale", 1)
	local top, pad = parts.Top, parts.Pad

	local income = UiKit.Plate(panel, "BankIncome", "Pill", {
		_Accent = Theme.Accents.Gold,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, top),
		Size = UDim2.fromOffset(270, 36),
		ZIndex = 5,
	})
	UiKit.Text(income, "Text", "PICK A CRYSTAL", {
		_Style = "Number",
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 1, -8),
		TextColor3 = Theme.Accents.Gold.Light,
		ZIndex = 6,
	})

	local grid = UiKit.Scroll(panel, "CrystalGrid", {
		Position = UDim2.fromOffset(pad, top + 46),
		Size = UDim2.new(1, -pad * 2, 1, -(top + 46 + pad)),
		ZIndex = 3,
	})
	UiKit.Padding(grid, 12, 4, 12, 12)
	local layout = UiKit.Grid(grid, UDim2.fromOffset(170, 214), UDim2.fromOffset(16, 16), { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	layout.Name = "CardLayout"

	local card = UiKit.CardButton(grid, "CrystalCardTemplate", accent, { Visible = false, ZIndex = 3 })
	UiKit.Text(card, "Name", "CRYSTAL", {
		_Style = "Heading",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 24),
		ZIndex = 4,
	})
	local background = UiKit.Plate(card, "IconBackground", "Slot", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.fromOffset(140, 140),
		ZIndex = 4,
	})
	UiKit.Corner(background, 999)
	UiKit.Icon(background, "Icon", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 5,
	})
	-- Рамка «стоит на подиуме» (включает клиент у установленного кристалла).
	local selection = UiKit.Group(background, "SelectionFrame", {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		Visible = false,
		ZIndex = 6,
	})
	UiKit.Corner(selection, 999)
	UiKit.Stroke(selection, Theme.Accents.Gold.Main, 3, 0, "SelectionStroke")
	UiKit.Text(card, "Income", "$0/SEC", {
		_Style = "Number",
		Position = UDim2.new(0, 8, 1, -32),
		Size = UDim2.new(1, -16, 0, 26),
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 5,
	})
	UiKit.Text(card, "Installed", "ON", {
		_Style = "Heading",
		Position = UDim2.new(1, -90, 0, 34),
		Size = UDim2.fromOffset(84, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Accents.Gold.Light,
		Visible = false,
		ZIndex = 6,
	})
	return panel
end

return Builder
