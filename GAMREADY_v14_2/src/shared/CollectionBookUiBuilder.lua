--------------------------------------------------------------------------------
-- CollectionBookUiBuilder (v20) — КНИГА КОЛЛЕКЦИИ (руда × мутации, мобы,
-- кристаллы). Единый стиль UiKit, акцент Teal. Строит MutationBookPanel
-- внутрь ScreenGui "CollectionMenu" (см. UiBuilders/CollectionMenuUi).
--
-- СТРУКТУРА (имена — контракт CollectionMenu.client.lua):
--   ImageLabel "MutationBookPanel" (окно; BuilderVersion)
--   ├─ TitleBar → "Title", "Ribbon", "CloseButton"
--   ├─ Frame "Sidebar" (слева снаружи) → ImageButton "TabOreMutations" / "TabMobs" / "TabCrystals" / "TabTrophies"
--   │     (у каждой UIStroke "SelectionStroke" и TextLabel "Icon")
--   ├─ ImageLabel "LeftPage" [Inset] → "PageTitle", ImageLabel "ProgressChip" → "Text",
--   │     ScrollingFrame "Scroller" (UIGridLayout)
--   ├─ ImageLabel "RightPage" [Inset] → ViewportFrame "PreviewImage", "ItemNameLabel",
--   │     Frame "StatsRow" → "PriceLabel", "ChanceLabel"; "DescriptionLabel"
--   └─ Folder "Templates" → ImageButton "ItemCell" [Card] (→ ImageLabel "Icon", TextLabel "Caption"),
--        ImageLabel "LockedCell" [Slot] → "QuestionMark"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21 -- v20.2: вкладка TabTrophies

local SIZE = Vector2.new(880, 540)

function Builder.BuildPanel()
	local accent = UiKit.Accent("Teal")
	local panel, parts = UiKit.Window(nil, "MutationBookPanel", {
		Title = "📖 Collection",
		Accent = "Teal",
		Size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		ZIndex = 6,
	})
	panel:SetAttribute("BuilderVersion", Builder.VERSION)
	panel:SetAttribute("BaseWidth", SIZE.X)
	panel:SetAttribute("BaseHeight", SIZE.Y)
	local body = parts.Body

	-- Вкладки — медальоны слева, снаружи окна.
	local sidebar = UiKit.Group(panel, "Sidebar", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, -8, 0, 70),
		Size = UDim2.fromOffset(62, 300),
		ZIndex = 7,
	})
	UiKit.List(sidebar, { Padding = UDim.new(0, 12) })
	for order, info in { { "TabOreMutations", "💎" }, { "TabMobs", "👺" }, { "TabCrystals", "🔮" }, { "TabTrophies", "🏆" } } do
		local tab = UiKit.PlateButton(sidebar, info[1], "Round", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(60, 60),
			ZIndex = 7,
		})
		UiKit.Stroke(tab, accent.Main, 2, 0, "SelectionStroke")
		UiKit.Text(tab, "Icon", info[2], {
			_Stroke = 0,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 1, -20),
			ZIndex = 8,
		}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	end

	local function page(name, anchorX)
		return UiKit.Plate(body, name, "Inset", {
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.fromScale(anchorX, 0),
			Size = UDim2.new(0.5, -6, 1, 0),
			ZIndex = 6,
		})
	end

	local left = page("LeftPage", 0)
	UiKit.Text(left, "PageTitle", "ORES", {
		_Style = "Title",
		_Gradient = { accent.Light, accent.Main },
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -150, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local chip = UiKit.Plate(left, "ProgressChip", "Pill", {
		_Accent = accent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(112, 28),
		ZIndex = 7,
	})
	UiKit.Text(chip, "Text", "0/0", {
		_Style = "Number",
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.new(1, -12, 1, -6),
		TextColor3 = accent.Light,
		ZIndex = 8,
	})
	local scroller = UiKit.Scroll(left, "Scroller", {
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.new(1, -20, 1, -54),
		ZIndex = 7,
	})
	UiKit.Grid(scroller, UDim2.fromOffset(112, 112), UDim2.fromOffset(10, 10), { FillDirectionMaxCells = 3 })

	local right = page("RightPage", 1)
	local preview = Instance.new("ViewportFrame")
	preview.Name = "PreviewImage"
	preview.AnchorPoint = Vector2.new(0.5, 0)
	preview.Position = UDim2.new(0.5, 0, 0, 14)
	preview.Size = UDim2.fromOffset(190, 190)
	preview.BackgroundColor3 = Color3.fromRGB(20, 26, 30)
	preview.BackgroundTransparency = 0.2
	preview.BorderSizePixel = 0
	preview.ZIndex = 7
	preview.Parent = right
	UiKit.Stroke(preview, accent.Main, 1.5, 0, "Outline")
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.Parent = preview
	preview.CurrentCamera = camera
	UiKit.Text(right, "ItemNameLabel", "PICK AN ITEM", {
		_Style = "Title",
		Position = UDim2.fromOffset(10, 212),
		Size = UDim2.new(1, -20, 0, 34),
		ZIndex = 7,
	})
	local stats = UiKit.Group(right, "StatsRow", {
		Position = UDim2.fromOffset(10, 250),
		Size = UDim2.new(1, -20, 0, 28),
		ZIndex = 7,
	})
	UiKit.Text(stats, "PriceLabel", "", {
		_Style = "Number",
		Size = UDim2.new(0.5, -5, 1, 0),
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 8,
	})
	UiKit.Text(stats, "ChanceLabel", "", {
		_Style = "Number",
		Position = UDim2.new(0.5, 5, 0, 0),
		Size = UDim2.new(0.5, -5, 1, 0),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 8,
	})
	local description = UiKit.Text(right, "DescriptionLabel", "", {
		_Style = "Body",
		_Stroke = 0,
		Position = UDim2.fromOffset(14, 288),
		Size = UDim2.new(1, -28, 1, -298),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 7,
	})
	description.TextScaled = false
	description.TextSize = 16

	-- ШАБЛОНЫ ячеек.
	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel
	local item = UiKit.CardButton(templates, "ItemCell", accent, {
		Size = UDim2.fromOffset(112, 112),
		Visible = false,
		ZIndex = 8,
	})
	UiKit.Icon(item, "Icon", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.7),
		ZIndex = 9,
	})
	local caption = UiKit.Text(item, "Caption", "", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 10,
	})
	caption.TextScaled = false
	caption.TextSize = 14
	local locked = UiKit.Slot(templates, "LockedCell", {
		Size = UDim2.fromOffset(112, 112),
		Visible = false,
		ZIndex = 8,
	})
	UiKit.Text(locked, "QuestionMark", "?", {
		_Style = "Title",
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.new(1, -40, 1, -40),
		TextColor3 = Theme.Colors.MutedText,
		ZIndex = 9,
	})
	UiKit.HideTemplates(panel) -- шаблоны выключены с рождения
	return panel
end

-- Ставит панель в ScreenGui "CollectionMenu" (заменяя старую).
function Builder.Install(collectionGui)
	local existing = collectionGui:FindFirstChild("MutationBookPanel")
	if existing then existing:Destroy() end
	local panel = Builder.BuildPanel()
	panel.Parent = collectionGui
	UiKit.HideTemplates(panel) -- шаблоны выключены с рождения
	return panel
end

return Builder
