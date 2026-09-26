--------------------------------------------------------------------------------
-- InventoryUi — хотбар + рюкзак (панель в стиле Satchel над хотбаром).
-- Клиенты: InventoryUI.client.lua (всё), CustomCartUI.client.lua (слот кирки/щита).
--
-- v20.50: стиль как в Fisch — тёмные полупрозрачные квадраты, номер слева
-- сверху, название по центру; рюкзак — тёмная панель, слева «Sort By»,
-- справа «View» (переключатели категорий), сверху вместимость/поиск/«?».
-- «HotbarUi»:
--   ScreenGui "HotbarUi" → Frame "Bar" (UIListLayout)
--     → "PickaxeSlot" (ВСЕГДА самый левый: кирка / щит при тележке),
--       "Slot1".."Slot6", "InventoryToggle" (ВСЕГДА самый правый: рюкзак)
--       каждый: ImageLabel "Preview", TextLabel "KeyBadge", TextLabel "CountLabel",
--               TextLabel "ToolName", ImageLabel "CooldownShade", TextLabel "Seconds"
--       у PickaxeSlot ещё: ImageLabel "CooldownOverlay", TextLabel "CooldownText",
--               TextLabel "ShieldLabel"
--
-- «SatchelInventory» (панель рюкзака, клавиша ~):
--   ScreenGui "SatchelInventory" (Enabled=false)
--   └─ ImageLabel "InventoryFrame" [Panel, акцент Peach]
--        ├─ Frame "Header" → TextLabel "CountLabel", Frame "SearchFrame"
--        │     → TextBox "SearchBox", TextButton "SearchClear", TextButton "Help" (+ TextLabel "HelpTip")
--        ├─ Frame "SortBy" (слева снаружи) → TextLabel "Title", TextButton "Sort_<Id>" (Rarity/Value/Name/Amount)
--        ├─ Frame "FilterTabs" (справа снаружи, «View») → TextButton "<Id>" (Ores/Tools/Totems/Decor/Relics)
--        │     каждый: Frame "Switch" → Frame "Knob", TextLabel "Caption"
--        └─ ScrollingFrame "ScrollingFrame" → Frame "UIGridFrame" (UIGridLayout)
--   Folder "Templates" → ImageButton "Slot" (ячейка: Highlight, Preview, ToolName, CountLabel)
--
-- «InventoryDragOverlay»: ScreenGui → Frame "DragLayer" (сюда едет «призрак» ячейки).
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

Builder.VERSION = 26
Builder.ICON_SIZE = 64
Builder.ICON_BUFFER = 6
Builder.HEADER = 40
Builder.TABS = 0 -- v20.50: вкладки уехали в колонку «View» справа
Builder.FILTERS = {
	{ Id = "Ores", Label = "Ores" }, { Id = "Tools", Label = "Tools" }, { Id = "Totems", Label = "Totems" },
	{ Id = "Decor", Label = "Decor" }, { Id = "Relics", Label = "Relics" },
}
Builder.SORTS = {
	{ Id = "Rarity", Label = "Rarity", Color = Color3.fromRGB(255, 170, 70) },
	{ Id = "Value", Label = "Value", Color = Color3.fromRGB(120, 230, 110) },
	{ Id = "Name", Label = "Name", Color = Color3.fromRGB(240, 120, 220) },
	{ Id = "Amount", Label = "Amount", Color = Color3.fromRGB(110, 220, 255) },
}

-- ВИД FISCH: тёмный полупрозрачный квадрат, тонкая тёмная рамка, скругление.
local FISCH_BG = Color3.fromRGB(20, 18, 16)
local function fischPlate(frame, transparency, radius)
	if frame:IsA("ImageLabel") or frame:IsA("ImageButton") then
		frame.Image = ""
		frame.ScaleType = Enum.ScaleType.Stretch
	end
	frame.BackgroundColor3 = FISCH_BG
	frame.BackgroundTransparency = transparency or 0.3
	for _, child in frame:GetChildren() do
		if child:IsA("UIGradient") or child.Name == "Shine" or child.Name == "Gloss" then child:Destroy() end
	end
	local corner = frame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 4)
	corner.Parent = frame
	local stroke = frame:FindFirstChild("SkinStroke") or frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Name = "SkinStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.45
	stroke.Thickness = 1.5
	stroke.Parent = frame
	frame:SetAttribute("FischStyle", true)
	return frame
end
Builder.FischPlate = fischPlate

local function cooldownShade(slot)
	local shade = UiKit.Plate(slot, "CooldownShade", "Inset", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 6,
	})
	local stroke = shade:FindFirstChild("SkinStroke")
	if stroke then stroke:Destroy() end
	UiKit.Text(slot, "Seconds", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.5),
		Visible = false,
		ZIndex = 7,
	})
end

local function hotbarSlot(bar, name, keyText, order, isPickaxe)
	local size = 66
	local slot = UiKit.Slot(bar, name, {
		LayoutOrder = order,
		Size = UDim2.fromOffset(size, size),
		ClipsDescendants = false,
	}, true)
	fischPlate(slot, 0.3, 4)
	if isPickaxe then
		local stroke = slot:FindFirstChild("SkinStroke")
		if stroke then
			stroke.Color = Theme.Accents.Gold.Main
			stroke.Transparency = 0.2
		end
	end
	UiKit.Icon(slot, "Preview", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, -8),
		ZIndex = 2,
	})
	UiKit.Text(slot, "KeyBadge", keyText, {
		_Style = "Number",
		_Stroke = 1,
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(14, 13),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = isPickaxe and Theme.Accents.Gold.Light or Color3.fromRGB(220, 220, 220),
		ZIndex = 4,
	})
	-- Название — ПО ЦЕНТРУ слота, поверх картинки (как в Fisch).
	local toolName = UiKit.Text(slot, "ToolName", "", {
		_Style = "Heading",
		_Stroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, -6, 0.46, 0),
		ZIndex = 4,
	})
	toolName.TextScaled = true
	toolName.TextWrapped = true
	local count = UiKit.Text(slot, "CountLabel", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -1),
		Size = UDim2.fromOffset(40, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	count.TextScaled = true
	cooldownShade(slot)
	if isPickaxe then
		UiKit.Text(slot, "ShieldLabel", "SHIELD", {
			_Style = "Heading",
			Position = UDim2.fromOffset(3, 18),
			Size = UDim2.new(1, -6, 0, 20),
			TextColor3 = Theme.Colors.Money,
			Visible = false,
			ZIndex = 5,
		})
		local overlay = UiKit.Plate(slot, "CooldownOverlay", "Inset", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = Color3.fromRGB(220, 60, 60),
			BackgroundTransparency = 0.15,
			ZIndex = 3,
		})
		local stroke = overlay:FindFirstChild("SkinStroke")
		if stroke then stroke:Destroy() end
		UiKit.Text(slot, "CooldownText", "", {
			_Style = "Number",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.5),
			Visible = false,
			ZIndex = 5,
		})
	end
	return slot
end

function Builder.BuildHotbar()
	local gui = UiKit.Screen("HotbarUi", { DisplayOrder = 12 })
	gui:SetAttribute("BuilderVersion", Builder.VERSION)
	local bar = UiKit.Group(gui, "Bar", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(8 * 70, 66),
	})
	UiKit.List(bar, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 6),
	})
	-- v20.50: F (кирка / щит с тележкой) — ВСЕГДА слева, 1..6, рюкзак — справа.
	hotbarSlot(bar, "PickaxeSlot", "F", 0, true)
	for index = 1, 6 do
		hotbarSlot(bar, "Slot" .. index, tostring(index), index, false)
	end
	local toggle = UiKit.Slot(bar, "InventoryToggle", {
		LayoutOrder = 100,
		Size = UDim2.fromOffset(66, 66),
		ClipsDescendants = false,
	}, true)
	fischPlate(toggle, 0.3, 4)
	UiKit.ThemeIcon(toggle, "Icon", "Inventory", "🎒", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
	})
	UiKit.Text(toggle, "KeyBadge", "~", {
		_Style = "Number",
		_Stroke = 1,
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(14, 13),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		ZIndex = 4,
	})
	local caption = UiKit.Text(toggle, "Caption", "Bag", {
		_Style = "Heading",
		_Stroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -6, 0, 16),
		ZIndex = 4,
	})
	caption.TextScaled = true
	return gui
end

function Builder.BuildCell(parent)
	local size = Builder.ICON_SIZE
	local cell = UiKit.Slot(parent, "Slot", { Size = UDim2.fromOffset(size, size), ClipsDescendants = false }, true)
	fischPlate(cell, 0.35, 4)
	-- Подсветка «в руках» (толщина 0 = выключена).
	local highlight = UiKit.Stroke(cell, Color3.fromRGB(0, 162, 255), 0, 0, "Highlight")
	highlight.Thickness = 0
	UiKit.Icon(cell, "Preview", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10),
		ZIndex = 2,
	})
	-- Название по центру ячейки, поверх картинки (как в Fisch).
	local name = UiKit.Text(cell, "ToolName", "", {
		_Style = "Heading",
		_Stroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 0.46, 0),
		ZIndex = 3,
	})
	name.TextScaled = true
	name.TextWrapped = true
	UiKit.Text(cell, "CountLabel", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -2),
		Size = UDim2.fromOffset(40, 15),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	})
	cooldownShade(cell)
	return cell
end

function Builder.BuildSatchel()
	local gui = UiKit.Screen("SatchelInventory", { DisplayOrder = 20, Enabled = false })
	gui:SetAttribute("BuilderVersion", Builder.VERSION)
	local frame = UiKit.Plate(gui, "InventoryFrame", "Panel", {
		Size = UDim2.fromOffset(560, 340),
		Position = UDim2.new(0.5, -280, 1, -440),
		ClipsDescendants = false,
	})
	fischPlate(frame, 0.2, 4)

	-- ШАПКА: вместимость слева (золотом), поиск по центру, «?» справа.
	local header = UiKit.Group(frame, "Header", { Size = UDim2.new(1, 0, 0, Builder.HEADER) })
	UiKit.Text(header, "CountLabel", "0/24", {
		_Style = "Number",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0, 110, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 215, 110),
	})
	local searchFrame = UiKit.Group(header, "SearchFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.45, 0, 0, 26),
	})
	local searchBox = Instance.new("TextBox")
	searchBox.Name = "SearchBox"
	searchBox.BackgroundTransparency = 1
	searchBox.Size = UDim2.new(1, -24, 1, 0)
	searchBox.FontFace = Theme.Fonts.Plain
	searchBox.PlaceholderText = "Search"
	searchBox.PlaceholderColor3 = Color3.fromRGB(150, 145, 140)
	searchBox.TextColor3 = Color3.fromRGB(235, 235, 235)
	searchBox.Text = ""
	searchBox.TextScaled = false
	searchBox.TextSize = 16
	searchBox.ClearTextOnFocus = false
	searchBox.TextXAlignment = Enum.TextXAlignment.Center
	searchBox.Parent = searchFrame
	local clear = UiKit.TextButton(searchFrame, "SearchClear", "X", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		TextColor3 = Theme.Colors.Close,
		Visible = false,
	})
	clear:SetAttribute("DisableGlobalHover", true)
	local help = UiKit.TextButton(header, "Help", "?", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		TextColor3 = Color3.fromRGB(200, 200, 200),
	})
	help:SetAttribute("DisableGlobalHover", true)
	local helpCorner = Instance.new("UICorner")
	helpCorner.CornerRadius = UDim.new(1, 0)
	helpCorner.Parent = help
	local helpStroke = Instance.new("UIStroke")
	helpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	helpStroke.Color = Color3.fromRGB(200, 200, 200)
	helpStroke.Thickness = 1.5
	helpStroke.Parent = help
	local tip = UiKit.Text(header, "HelpTip", "Click: hold item.  Drag: move to hotbar.  1-6: quick use.", {
		_Style = "Small",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 0, -4),
		Size = UDim2.fromOffset(300, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = 10,
	})
	tip.TextScaled = true
	local line = Instance.new("Frame")
	line.Name = "HeaderLine"
	line.AnchorPoint = Vector2.new(0.5, 1)
	line.Position = UDim2.fromScale(0.5, 1)
	line.Size = UDim2.new(1, -16, 0, 1)
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BackgroundTransparency = 0.85
	line.BorderSizePixel = 0
	line.Parent = header

	local function columnTitle(parent, text)
		local title = UiKit.Text(parent, "Title", text, {
			_Style = "Heading",
			_Stroke = 1.5,
			Size = UDim2.new(1, 0, 0, 22),
		})
		title.TextScaled = true
		local under = Instance.new("Frame")
		under.Name = "Underline"
		under.AnchorPoint = Vector2.new(0.5, 0)
		under.Position = UDim2.new(0.5, 0, 0, 24)
		under.Size = UDim2.new(0.9, 0, 0, 2)
		under.BackgroundColor3 = Color3.new(1, 1, 1)
		under.BorderSizePixel = 0
		under.Parent = parent
	end

	-- СЛЕВА СНАРУЖИ: «Sort By» — цветные кнопки в рамке, стрелка направления.
	local sortBy = UiKit.Group(frame, "SortBy", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, -14, 0, 0),
		Size = UDim2.fromOffset(104, 32 + #Builder.SORTS * 28),
	})
	columnTitle(sortBy, "Sort By")
	for index, sort in Builder.SORTS do
		local button = Instance.new("TextButton")
		button.Name = "Sort_" .. sort.Id
		button.AutoButtonColor = false
		button.Text = ""
		button.Position = UDim2.fromOffset(2, 32 + (index - 1) * 28)
		button.Size = UDim2.new(1, -4, 0, 22)
		button.BackgroundColor3 = FISCH_BG
		button.BackgroundTransparency = 0.35
		button:SetAttribute("SortColor", sort.Color)
		button:SetAttribute("DisableGlobalHover", true)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = sort.Color
		stroke.Thickness = 1.5
		stroke.Parent = button
		UiKit.Shape(button, "Arrow", "ChevronUp", {
			Color = Color3.fromRGB(200, 200, 200),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			ZIndex = 2,
		})
		local caption = UiKit.Text(button, "Caption", sort.Label, {
			_Style = "Heading",
			_Stroke = 1,
			Position = UDim2.fromOffset(22, 2),
			Size = UDim2.new(1, -26, 1, -4),
			TextColor3 = sort.Color,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		})
		caption.TextScaled = true
		button.Parent = sortBy
	end

	-- СПРАВА СНАРУЖИ: «View» — переключатели категорий.
	local view = UiKit.Group(frame, "FilterTabs", {
		Position = UDim2.new(1, 14, 0, 0),
		Size = UDim2.fromOffset(120, 32 + #Builder.FILTERS * 24),
	})
	columnTitle(view, "View")
	for index, filter in Builder.FILTERS do
		local row = Instance.new("TextButton")
		row.Name = filter.Id
		row.AutoButtonColor = false
		row.Text = ""
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(0, 32 + (index - 1) * 24)
		row.Size = UDim2.new(1, 0, 0, 20)
		row:SetAttribute("DisableGlobalHover", true)
		local switch = Instance.new("Frame")
		switch.Name = "Switch"
		switch.AnchorPoint = Vector2.new(0, 0.5)
		switch.Position = UDim2.new(0, 2, 0.5, 0)
		switch.Size = UDim2.fromOffset(34, 18)
		switch.BackgroundColor3 = Color3.fromRGB(70, 200, 90)
		switch.BorderSizePixel = 0
		switch.Parent = row
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(1, 0)
		sc.Parent = switch
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(1, 0.5)
		knob.Position = UDim2.new(1, -1, 0.5, 0)
		knob.Size = UDim2.fromOffset(16, 16)
		knob.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		knob.BorderSizePixel = 0
		knob.Parent = switch
		local kc = Instance.new("UICorner")
		kc.CornerRadius = UDim.new(1, 0)
		kc.Parent = knob
		local ks = Instance.new("UIStroke")
		ks.Color = Color3.fromRGB(230, 230, 230)
		ks.Thickness = 1.5
		ks.Parent = knob
		local caption = UiKit.Text(row, "Caption", filter.Label, {
			_Style = "Heading",
			_Stroke = 1.5,
			Position = UDim2.fromOffset(42, 1),
			Size = UDim2.new(1, -44, 1, -2),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		caption.TextScaled = true
		row.Parent = view
	end

	local scroll = UiKit.Scroll(frame, "ScrollingFrame", {
		Position = UDim2.fromOffset(0, Builder.HEADER + Builder.TABS),
		Size = UDim2.new(1, 0, 1, -(Builder.HEADER + Builder.TABS)),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ClipsDescendants = true,
	})
	local grid = UiKit.Group(scroll, "UIGridFrame", {})
	UiKit.Grid(grid, UDim2.fromOffset(Builder.ICON_SIZE, Builder.ICON_SIZE), UDim2.fromOffset(Builder.ICON_BUFFER, Builder.ICON_BUFFER))
	UiKit.Padding(grid, Builder.ICON_BUFFER, Builder.ICON_BUFFER, Builder.ICON_BUFFER, 0)

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	Builder.BuildCell(templates).Visible = false
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

function Builder.BuildDragOverlay()
	local gui = UiKit.Screen("InventoryDragOverlay", { DisplayOrder = 30 })
	UiKit.Group(gui, "DragLayer", { Visible = false, ZIndex = 50 })
	return gui
end

return Builder
