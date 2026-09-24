--------------------------------------------------------------------------------
-- InventoryUi — хотбар + рюкзак (панель в стиле Satchel над хотбаром).
-- Клиенты: InventoryUI.client.lua (всё), CustomCartUI.client.lua (слот кирки/щита).
--
-- «HotbarUi»:
--   ScreenGui "HotbarUi" → Frame "Bar" (UIListLayout)
--     → ImageButton "Slot1".."Slot6" [Slot] и "PickaxeSlot" [Slot, акцент Gold] в центре
--       каждый: ImageLabel "Preview", TextLabel "KeyBadge", TextLabel "CountLabel",
--               TextLabel "ToolName", ImageLabel "CooldownShade", TextLabel "Seconds"
--       у PickaxeSlot ещё: ImageLabel "CooldownOverlay", TextLabel "CooldownText",
--               TextLabel "ShieldLabel"
--
-- «SatchelInventory» (панель рюкзака, клавиша ~):
--   ScreenGui "SatchelInventory" (Enabled=false)
--   └─ ImageLabel "InventoryFrame" [Panel, акцент Peach]
--        ├─ Frame "Header" → TextLabel "CountLabel", ImageLabel "SearchFrame" [Input]
--        │     → TextBox "SearchBox", TextButton "SearchClear"
--        ├─ ScrollingFrame "FilterTabs" → ImageButton "All"/"Ores"/"Tools"/"Totems"/"Decor"/"Relics"
--        └─ ScrollingFrame "ScrollingFrame" → Frame "UIGridFrame" (UIGridLayout)
--   Folder "Templates" → ImageButton "Slot" (ячейка: Highlight, Preview, ToolName, CountLabel)
--
-- «InventoryDragOverlay»: ScreenGui → Frame "DragLayer" (сюда едет «призрак» ячейки).
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

Builder.ICON_SIZE = 60
Builder.ICON_BUFFER = 5
Builder.HEADER = 40
Builder.TABS = 32
Builder.FILTERS = {
	{ Id = "All", Label = "ALL" }, { Id = "Ores", Label = "ORES" }, { Id = "Tools", Label = "TOOLS" },
	{ Id = "Totems", Label = "TOTEMS" }, { Id = "Decor", Label = "DECOR" }, { Id = "Relics", Label = "RELICS" },
}

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
	local size = isPickaxe and 58 or 50
	local slot = UiKit.Slot(bar, name, {
		_Accent = isPickaxe and "Gold" or nil,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size, size),
		ClipsDescendants = false,
	}, true)
	if isPickaxe then
		local stroke = slot:FindFirstChild("SkinStroke")
		if stroke then
			stroke.Color = Theme.Accents.Gold.Main
			stroke.Thickness = 2
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
		Position = UDim2.fromOffset(3, 1),
		Size = UDim2.fromOffset(16, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = isPickaxe and Theme.Accents.Gold.Light or Theme.Colors.Text,
		ZIndex = 4,
	})
	UiKit.Text(slot, "ToolName", "", {
		_Style = "Small",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -16),
		Size = UDim2.new(1, 10, 0, 14),
		Visible = false,
		ZIndex = 4,
	})
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
	local bar = UiKit.Group(gui, "Bar", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(7 * 58, 60),
	})
	UiKit.List(bar, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 6),
	})
	-- 1 2 3 | F | 4 5 6 — LayoutOrder ставит кирку ровно в центр.
	hotbarSlot(bar, "Slot1", "1", 1, false)
	hotbarSlot(bar, "Slot2", "2", 2, false)
	hotbarSlot(bar, "Slot3", "3", 3, false)
	hotbarSlot(bar, "PickaxeSlot", "F", 4, true)
	hotbarSlot(bar, "Slot4", "4", 5, false)
	hotbarSlot(bar, "Slot5", "5", 6, false)
	hotbarSlot(bar, "Slot6", "6", 7, false)
	return gui
end

function Builder.BuildCell(parent)
	local size = Builder.ICON_SIZE
	local cell = UiKit.Slot(parent, "Slot", { Size = UDim2.fromOffset(size, size), ClipsDescendants = false }, true)
	-- Подсветка «в руках» (толщина 0 = выключена).
	local highlight = UiKit.Stroke(cell, Color3.fromRGB(0, 162, 255), 0, 0, "Highlight")
	highlight.Thickness = 0
	UiKit.Icon(cell, "Preview", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10),
		ZIndex = 2,
	})
	local name = UiKit.Text(cell, "ToolName", "", {
		_Style = "Small",
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.new(1, -6, 0, 13),
		ZIndex = 3,
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
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
	local frame = UiKit.Plate(gui, "InventoryFrame", "Panel", {
		_Accent = "Peach",
		Size = UDim2.fromOffset(460, 340),
		Position = UDim2.new(0.5, -230, 1, -440),
	})
	local header = UiKit.Group(frame, "Header", { Size = UDim2.new(1, 0, 0, Builder.HEADER) })
	UiKit.Text(header, "CountLabel", "0/24", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(0, 160, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Accents.Peach.Light,
	})
	local searchBox, searchFrame = UiKit.Input(header, "SearchBox", "Search", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 200, 0, 28),
	})
	searchFrame.Name = "SearchFrame"
	searchBox.Size = UDim2.new(1, -30, 1, -4)
	local clear = UiKit.TextButton(searchFrame, "SearchClear", "X", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		TextColor3 = Theme.Colors.Close,
		Visible = false,
	})
	clear:SetAttribute("DisableGlobalHover", true)

	local tabs = UiKit.Scroll(frame, "FilterTabs", {
		Position = UDim2.fromOffset(Builder.ICON_BUFFER, Builder.HEADER),
		Size = UDim2.new(1, -Builder.ICON_BUFFER * 2, 0, Builder.TABS - 4),
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
	})
	UiKit.List(tabs, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center })
	for index, filter in Builder.FILTERS do
		local b = Instance.new("ImageButton")
		b.Name = filter.Id
		b.AutoButtonColor = false
		b.LayoutOrder = index
		b.Size = UDim2.new(0, 70, 1, 0)
		UiKit.ApplySkin(b, index == 1 and "TabActive" or "Tab", "Peach")
		UiKit.Text(b, "Caption", filter.Label, {
			_Style = "Heading",
			Size = UDim2.new(1, -8, 1, -6),
			Position = UDim2.fromOffset(4, 3),
			ZIndex = 2,
		})
		b.Parent = tabs
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
	return gui
end

function Builder.BuildDragOverlay()
	local gui = UiKit.Screen("InventoryDragOverlay", { DisplayOrder = 30 })
	UiKit.Group(gui, "DragLayer", { Visible = false, ZIndex = 50 })
	return gui
end

return Builder
