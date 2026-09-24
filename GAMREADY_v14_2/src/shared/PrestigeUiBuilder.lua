--------------------------------------------------------------------------------
-- PrestigeUiBuilder (v20) — ОКНО ПРЕСТИЖА у NPC: какие условия нужны и что
-- даст престиж. Единый стиль UiKit (акцент Orange).
-- tools/BuildAllUI.lua → StarterGui/RebirthDialogButtons; если его нет,
-- CustomCartUI.client.lua соберёт это же окно сам.
--
-- КОНТРАКТ (имена читает CustomCartUI.client.lua):
--   ScreenGui "RebirthDialogButtons" (Enabled=false)
--   ├─ ImageLabel "Panel" (окно) → TitleBar → "Title", "Ribbon", "CloseButton"
--   │    └─ Frame → Body
--   │         ├─ TextLabel "Intro"
--   │         ├─ ImageLabel "RequirementsCard" → "Header", Frame "Requirements"
--   │         ├─ ImageLabel "Bonuses" → "Title", ImageLabel "MONEYRow"/"SPEEDRow"
--   │         │     (в каждом TextLabel "Label", "Current", "Next")
--   │         └─ ImageButton "RebirthButton" → TextLabel "Caption"
--   └─ Folder "Templates" → ImageLabel "RequirementRow"
--        → ImageLabel "Box" (→ "Check", "Cross"), TextLabel "Label"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21 -- v20.9: галочка/крестик фигурами

local function requirementRow(parent)
	local row = UiKit.Plate(parent, "RequirementRow", "Inset", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 0.6 })
	local box = UiKit.Plate(row, "Box", "Slot", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		ZIndex = 2,
	})
	-- Галочка/крестик картинкой (Theme.Icons.Check) или символом.
	local check = UiKit.ThemeIcon(box, "Check", "Check", "@Check", {
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		ZIndex = 3,
	})
	check.Emoji.TextColor3 = Theme.Colors.Positive
	UiKit.PaintShape(check.Emoji:FindFirstChild("Shape"), Theme.Colors.Positive)
	-- v20.9: крестик — фигура (символа ✕ в шрифтах Roblox нет → был «квадратик»).
	UiKit.Shape(box, "Cross", "Cross", {
		Size = UDim2.new(1, -8, 1, -8),
		Color = Theme.Colors.MutedText,
		Visible = false,
		ZIndex = 3,
	})
	UiKit.Text(row, "Label", "Upgrade Mine to tier 5", {
		_Style = "Body",
		Position = UDim2.fromOffset(42, 4),
		Size = UDim2.new(1, -48, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	return row
end

function Builder.Build()
	local gui = UiKit.Screen("RebirthDialogButtons", { DisplayOrder = 15, Enabled = false })
	gui:SetAttribute("BuilderVersion", Builder.VERSION)

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "⭐ Prestige",
		Accent = "Orange",
		Size = UDim2.fromOffset(680, 480),
		Visible = true,
	})
	local body = parts.Body

	UiKit.Text(body, "Intro", "", {
		_Style = "Body",
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = Theme.Colors.SubText,
	})

	-- ЛЕВО: чек-лист условий (строки строит клиент из шаблона RequirementRow).
	local requirementsCard = UiKit.Plate(body, "RequirementsCard", "Inset", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(0.56, -6, 1, -118),
	})
	UiKit.SectionHeader(requirementsCard, "Header", "What you need", "Orange", {
		_Layout = "Left",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 28),
	})
	local requirements = UiKit.Group(requirementsCard, "Requirements", {
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -50),
	})
	UiKit.List(requirements, { Padding = UDim.new(0, 8) })

	-- ПРАВО: что даст престиж.
	local bonuses = UiKit.Card(body, "Bonuses", "Gold", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 38),
		Size = UDim2.new(0.44, -6, 1, -118),
	})
	UiKit.Text(bonuses, "Title", "What you get", {
		_Style = "Title",
		_Gradient = { Theme.Accents.Gold.Light, Theme.Accents.Gold.Main },
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local function bonusRow(name, label, icon, y)
		local row = UiKit.Plate(bonuses, name, "Inset", {
			Position = UDim2.new(0, 10, 0, y),
			Size = UDim2.new(1, -20, 0, 104),
		})
		UiKit.Text(row, "Label", icon .. " " .. label, {
			_Style = "Heading",
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.new(1, -16, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.SubText,
			ZIndex = 2,
		})
		UiKit.Text(row, "Current", "NOW: -", {
			_Style = "Body",
			Position = UDim2.fromOffset(8, 34),
			Size = UDim2.new(1, -16, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		})
		UiKit.Text(row, "Next", "NEXT: -", {
			_Style = "Heading",
			Position = UDim2.fromOffset(8, 66),
			Size = UDim2.new(1, -16, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.Positive,
			ZIndex = 2,
		})
		return row
	end
	bonusRow("MONEYRow", "PRESTIGE POINTS", "⭐", 42)
	bonusRow("SPEEDRow", "AFTER PRESTIGE", "🕳", 154)

	-- НИЗ: крупная кнопка.
	UiKit.Button(body, "RebirthButton", "PRESTIGE", "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(320, 60),
		_TextStyle = "Title",
	})

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	requirementRow(templates).Visible = false
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
