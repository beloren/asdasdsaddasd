--------------------------------------------------------------------------------
-- UpgradeShopUi — окно Upgrade Mole (прокачка шахты / тележки / кирки,
-- динамит). Клиент: CustomCartUI.client.lua (блок «МАГАЗИН УЛУЧШЕНИЙ»).
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "UpgradeShopUi" (Enabled=false, включается кодом)
--   └─ ImageLabel "Panel" (окно, акцент Orange)
--        ├─ TitleBar → Title, Ribbon, CloseButton
--        ├─ TextLabel "Subtitle" (в TitleBar справа)
--        ├─ TextLabel "Toast" (под окном)
--        └─ Frame → Body → Frame "Content"
--             ├─ Frame "GridView" → Frame "CardRow" → Frame "SideGrid" (UIGridLayout),
--             │     TextLabel "GridHint", TextLabel "GridFooter"
--             └─ Frame "DetailView" (Visible=false)
--                  ├─ ImageButton "Back", Frame "PreviewHolder"
--                  ├─ Frame "Info" → DetailTitle, DetailDesc, StatsHeader, Frame "StatsList"
--                  ├─ Frame "SupplyTabs", TextLabel "PriceLabel"
--                  └─ ImageButton "Action", ImageButton "Action2"
--   Folder "Templates": ImageButton "Card" (Icon, Title, Level, Hint, Chip→Text, Lock, Shine),
--                       TextLabel "StatLine", ImageButton "SupplyTab"
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

Builder.PANEL_SIZE = Vector2.new(740, 470)
Builder.MAIN_CARD = Vector2.new(210, 300)
Builder.SMALL_CARD = Vector2.new(140, 144)

local function buildCard(parent)
	local card = UiKit.CardButton(parent, "Card", "Orange", { Size = UDim2.fromOffset(140, 144) })
	UiKit.Scale(card, "HoverScale", 1)
	card:SetAttribute("DisableGlobalHover", true)
	-- Блик сверху (можно заменить своей картинкой — скин Glow).
	local shine = UiKit.Plate(card, "Shine", "Glow", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0.3, 0),
		ZIndex = 2,
	})
	shine.BackgroundTransparency = 0.94
	UiKit.Text(card, "Icon", "⛏", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.07),
		Size = UDim2.fromScale(0.7, 0.32),
		ZIndex = 3,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(card, "Title", "CAVE", {
		_Style = "Title",
		_Stroke = 2,
		Position = UDim2.new(0, 6, 0.41, 0),
		Size = UDim2.new(1, -12, 0.14, 0),
		ZIndex = 3,
	})
	UiKit.Text(card, "Level", "LV 1/10", {
		_Style = "Number",
		Position = UDim2.new(0, 6, 0.56, 0),
		Size = UDim2.new(1, -12, 0.1, 0),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 3,
	})
	UiKit.Text(card, "Hint", "", {
		_Style = "Small",
		Position = UDim2.new(0, 8, 0.67, 0),
		Size = UDim2.new(1, -16, 0.11, 0),
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 3,
		_MaxTextSize = 14,
	})
	local chip = UiKit.Plate(card, "Chip", "Inset", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0.14, 0),
		ZIndex = 3,
	})
	UiKit.Text(chip, "Text", "$0", {
		_Style = "Number",
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 1, -6),
		ZIndex = 4,
	})
	UiKit.Text(card, "Lock", "🔒", {
		_Stroke = 0,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		ZIndex = 5,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	return card
end

function Builder.Build()
	local gui = UiKit.Screen("UpgradeShopUi", { DisplayOrder = 30, Enabled = false })
	local size = Builder.PANEL_SIZE
	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "Upgrades",
		Accent = "Orange",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.54),
	})
	panel:SetAttribute("BaseWidth", size.X)
	panel:SetAttribute("BaseHeight", size.Y)
	UiKit.Scale(panel, "PanelScale", 1)
	-- Кнопка закрытия у этого окна называется «Close» (так её ищет код).
	parts.CloseButton.Name = "Close"

	UiKit.Text(parts.TitleBar, "Subtitle", "Everything resets on prestige", {
		_Style = "Small",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -56, 1, -4),
		Size = UDim2.fromOffset(220, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 5,
	})
	local toast = UiKit.Text(panel, "Toast", "", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.new(1, -40, 0, 24),
		ZIndex = 9,
	})
	toast.TextTransparency = 1

	local content = UiKit.Group(parts.Body, "Content", { ClipsDescendants = true, ZIndex = 3 })

	-- ЭКРАН 1: СЕТКА КАРТОЧЕК
	local gridView = UiKit.Group(content, "GridView", { ZIndex = 3 })
	local row = UiKit.Group(gridView, "CardRow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1, -16, 0, Builder.MAIN_CARD.Y + 10),
		ZIndex = 3,
	})
	local side = UiKit.Group(row, "SideGrid", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(Builder.SMALL_CARD.X * 3 + 24, Builder.SMALL_CARD.Y * 2 + 12),
		ZIndex = 3,
	})
	UiKit.Grid(side, UDim2.fromOffset(Builder.SMALL_CARD.X, Builder.SMALL_CARD.Y), UDim2.fromOffset(12, 12), { FillDirectionMaxCells = 3 })
	UiKit.Text(gridView, "GridHint", "Tap a card to see what it gives", {
		_Style = "Small",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.new(1, -20, 0, 18),
		TextColor3 = Theme.Colors.SubText,
		_MaxTextSize = 15,
	})
	UiKit.Text(gridView, "GridFooter", "", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -20, 0, 22),
		_MaxTextSize = 17,
	})

	-- ЭКРАН 2: ВЫБРАННАЯ ВЕТКА
	local detail = UiKit.Group(content, "DetailView", { Visible = false, ZIndex = 3 })
	UiKit.Button(detail, "Back", "◀ BACK", "Blue", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(110, 38),
		ZIndex = 4,
	})
	UiKit.Group(detail, "PreviewHolder", {
		Position = UDim2.fromOffset(24, 50),
		Size = UDim2.fromOffset(150, 226),
		ZIndex = 3,
	})
	local info = UiKit.Group(detail, "Info", {
		Position = UDim2.fromOffset(212, 2),
		Size = UDim2.new(1, -216, 1, -72),
		ZIndex = 3,
	})
	UiKit.List(info, { Padding = UDim.new(0, 5) })
	UiKit.Text(info, "DetailTitle", "CAVE", {
		_Style = "Title",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		_MaxTextSize = 32,
	})
	UiKit.Text(info, "DetailDesc", "", {
		_Style = "Body",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Colors.SubText,
		_MaxTextSize = 16,
	})
	UiKit.Text(info, "StatsHeader", "", {
		_Style = "Heading",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Money,
		_MaxTextSize = 17,
	})
	local stats = UiKit.Group(info, "StatsList", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UiKit.List(stats, { Padding = UDim.new(0, 4) })

	local supplyTabs = UiKit.Group(detail, "SupplyTabs", {
		Position = UDim2.fromOffset(212, 44),
		Size = UDim2.new(1, -220, 0, 44),
		Visible = false,
		ZIndex = 4,
	})
	UiKit.List(supplyTabs, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) })
	UiKit.Text(detail, "PriceLabel", "", {
		_Style = "Number",
		Position = UDim2.new(0, 8, 1, -54),
		Size = UDim2.fromOffset(190, 26),
		Visible = false,
	})
	UiKit.Button(detail, "Action", "BUY", "Green", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -6),
		Size = UDim2.new(1, -236, 0, 50),
		ZIndex = 4,
	})
	UiKit.Button(detail, "Action2", "x5", "Green", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -6),
		Size = UDim2.new(0.5, -122, 0, 50),
		Visible = false,
		ZIndex = 4,
	})

	-- ШАБЛОНЫ
	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	buildCard(templates).Visible = false
	UiKit.Text(templates, "StatLine", "Damage: 1 → 2", {
		_Style = "Body",
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		_MaxTextSize = 17,
	})
	UiKit.Button(templates, "SupplyTab", "SMALL", "Red", {
		Size = UDim2.new(0.333, -6, 1, 0),
		Visible = false,
	})
	return gui
end

return Builder
