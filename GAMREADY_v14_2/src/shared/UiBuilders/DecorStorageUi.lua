--------------------------------------------------------------------------------
-- DecorStorageUi (v20.22) — окно сундука-хранилища на базе.
-- Клиент: DecorStorageUI.client.lua (ячейки — клоны Templates/Cell).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "DecorStorageUi" (Enabled=false)
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Panel" [окно, Flat] (UIScale "PanelScale")
--        ├─ TitleBar → "Title";  ImageButton "CloseButton"
--        ├─ TextLabel "ChestLabel"   — «CHEST 3/10»
--        ├─ ImageButton "TakeAllButton" [Button_Yellow] → "Caption"
--        ├─ ImageLabel "ChestBg" [Inset] → Frame "ChestGrid" (UIGridLayout)
--        ├─ TextLabel "BagLabel"     — «YOUR ORE»
--        ├─ ImageButton "PutAllButton" [Button_Green] → "Caption"
--        ├─ ImageLabel "BagBg" [Inset] + ScrollingFrame "BagGrid" (UIGridLayout)
--        ├─ TextLabel "EmptyBag"     — «No ore in your backpack»
--        ├─ TextLabel "Hint"
--        └─ Folder "Templates"
--             └─ ImageButton "Cell" [Slot] → ViewportFrame "Preview",
--                  Frame "RarityBar", TextLabel "ItemName", "Count", "Rarity"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 22
Builder.CELL = 80
Builder.GAP = 8
Builder.COLUMNS = 5
Builder.W = Builder.COLUMNS * Builder.CELL + (Builder.COLUMNS - 1) * Builder.GAP + 2 * 12 + 2 * 8
Builder.H = 560

function Builder.BuildCell(parent)
	local cell = UiKit.Slot(parent, "Cell", { Size = UDim2.fromOffset(Builder.CELL, Builder.CELL), _Accent = "Peach" }, true)
	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.BackgroundTransparency = 1
	preview.BorderSizePixel = 0
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.Position = UDim2.fromScale(0.5, 0.46)
	preview.Size = UDim2.new(1, -16, 1, -24)
	preview.ZIndex = 2
	preview.Parent = cell
	UiKit.Group(cell, "RarityBar", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -14, 0, 3),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(200, 200, 200),
		ZIndex = 3,
	})
	local name = UiKit.Text(cell, "ItemName", "", {
		_Style = "Small",
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 0, 14),
		ZIndex = 4,
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
	UiKit.Text(cell, "Count", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -5, 1, -7),
		Size = UDim2.fromOffset(44, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	UiKit.Text(cell, "Rarity", "", {
		_Style = "Small",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 5, 1, -7),
		Size = UDim2.fromOffset(40, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 4,
	})
	return cell
end

local function grid(parent)
	UiKit.Grid(parent, UDim2.fromOffset(Builder.CELL, Builder.CELL), UDim2.fromOffset(Builder.GAP, Builder.GAP))
	UiKit.Padding(parent, 8, 8, 8, 8)
end

function Builder.Build()
	local gui = UiKit.Screen("DecorStorageUi", { DisplayOrder = 62 })
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	UiKit.Dimmer(gui, { Visible = true })

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "STORAGE CHEST",
		Accent = "Peach",
		Size = UDim2.fromOffset(Builder.W, Builder.H),
		Visible = true,
		Flat = true,
		CloseInRoot = true,
	})
	UiKit.Scale(panel, "PanelScale", 1)
	-- Имя сундука длинное — одна строка, шрифт ужимается под ширину.
	parts.Title.TextWrapped = false
	parts.Title.TextScaled = true
	parts.Title.Size = UDim2.new(1, -170, parts.Title.Size.Y.Scale, parts.Title.Size.Y.Offset)
	local top, pad = parts.Top, parts.Pad
	local rowH = 34
	local chestH = 2 * Builder.CELL + Builder.GAP + 16

	local function header(name, text, y, buttonName, buttonText, variant)
		UiKit.Text(panel, name, text, {
			_Style = "Heading",
			Position = UDim2.fromOffset(pad + 4, y),
			Size = UDim2.new(0.5, 0, 0, rowH),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Accents.Peach.Light,
			ZIndex = 3,
		})
		UiKit.Button(panel, buttonName, buttonText, variant, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -pad, 0, y),
			Size = UDim2.fromOffset(130, rowH),
			ZIndex = 3,
		})
	end

	header("ChestLabel", "CHEST 0/10", top, "TakeAllButton", "TAKE ALL", "Yellow")
	local chestY = top + rowH + 6
	local chestBg = UiKit.Plate(panel, "ChestBg", "Inset", {
		Position = UDim2.fromOffset(pad, chestY),
		Size = UDim2.new(1, -pad * 2, 0, chestH),
		ZIndex = 2,
	})
	local chestGrid = UiKit.Group(panel, "ChestGrid", { Position = chestBg.Position, Size = chestBg.Size, ZIndex = 3 })
	grid(chestGrid)

	local bagY = chestY + chestH + 10
	header("BagLabel", "YOUR ORE", bagY, "PutAllButton", "PUT ALL", "Green")
	local hintH = 30
	local listY = bagY + rowH + 6
	local listSize = UDim2.new(1, -pad * 2, 1, -(listY + hintH + pad))
	UiKit.Plate(panel, "BagBg", "Inset", {
		Position = UDim2.fromOffset(pad, listY),
		Size = listSize,
		ZIndex = 2,
	})
	local bag = UiKit.Scroll(panel, "BagGrid", {
		Position = UDim2.fromOffset(pad, listY),
		Size = listSize,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 3,
	})
	grid(bag)
	UiKit.Text(panel, "EmptyBag", "No ore in your backpack", {
		_Style = "Body",
		Position = UDim2.fromOffset(pad, listY),
		Size = listSize,
		TextColor3 = Theme.Colors.TextDim or Color3.fromRGB(190, 190, 200),
		Visible = false,
		ZIndex = 4,
	})
	UiKit.Text(panel, "Hint", "Click ore to move it. Ore in the chest is safe, even if you die.", {
		_Style = "Small",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, pad, 1, -pad + 2),
		Size = UDim2.new(1, -pad * 2, 0, hintH - 6),
		TextColor3 = Theme.Colors.TextDim or Color3.fromRGB(190, 190, 200),
		ZIndex = 3,
	})

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel
	Builder.BuildCell(templates)
	UiKit.HideTemplates(gui)
	return gui
end

return Builder
