--------------------------------------------------------------------------------
-- RevealCardsUi (v20) — экран карточек открытия жеод/сундуков.
-- Логика — Shared.RevealCards (клонирует Templates/Card).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "RevealCards" (Enabled=false)
--   ├─ TextButton "Dimmer"
--   ├─ Frame "Holder" (UIScale "Scale") → TextLabel "Header", Frame "Row", TextLabel "Hint"
--   └─ Folder "Templates" → Frame "Card" (UIScale "Pop")
--        ├─ ImageLabel "Rays" (фон за карточкой у Rare+, картинка по редкости)
--        └─ Frame "Flipper"
--             ├─ ImageLabel "Back" [Card] → ImageLabel "Inner" [Inset], TextLabel "Mark"
--             └─ ImageLabel "Front" [Card] → Frame "Band", ViewportFrame "Preview",
--                  "Rarity", "Title", "Detail", "Chance", ImageLabel "Badge" [Pill] → "Text"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21
Builder.CARD_W, Builder.CARD_H, Builder.GAP = 170, 236, 16

function Builder.BuildCard(parent)
	local W, H = Builder.CARD_W, Builder.CARD_H
	local slot = UiKit.Group(parent, "Card", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
	})
	UiKit.Scale(slot, "Pop", 1)

	-- v20.30: фон за карточкой — картинка по редкости (UiTheme.RarityBackdrop).
	UiKit.Backdrop(slot, "Rays", "Legendary", {
		Size = UDim2.fromOffset(H * 1.7, H * 1.7),
		Visible = false,
		ZIndex = 0,
		Transparency = 0.1,
	})

	local flipper = UiKit.Group(slot, "Flipper", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
	})

	-- РУБАШКА
	local back = UiKit.Card(flipper, "Back", "Purple", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	UiKit.Plate(back, "Inner", "Inset", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -22, 1, -22),
		ZIndex = 3,
	})
	UiKit.Text(back, "Mark", "?", {
		_Style = "Title",
		_Gradient = { Theme.Accents.Purple.Light, Theme.Accents.Purple.Main },
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(90, 110),
		ZIndex = 4,
	})

	-- ЛИЦО
	local front = UiKit.Card(flipper, "Front", "Grey", { Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 2 })
	local band = UiKit.Group(front, "Band", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0.62, 0),
		ZIndex = 2,
	})
	UiKit.Gradient(band, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90, "Fade").Transparency = UiKit.NSeq(0.35, 1)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(8, 22)
	viewport.Size = UDim2.new(1, -16, 0, 120)
	viewport.ZIndex = 3
	viewport.Parent = front
	local function line(name, style, y, h, color)
		return UiKit.Text(front, name, name:upper(), {
			_Style = style,
			Position = UDim2.fromOffset(8, y),
			Size = UDim2.new(1, -16, 0, h),
			TextColor3 = color or Theme.Colors.Text,
			ZIndex = 4,
		})
	end
	line("Rarity", "Heading", 6, 16)
	line("Title", "Title", 146, 30)
	line("Detail", "Body", 178, 20, Theme.Colors.Money)
	line("Chance", "Small", 204, 16, Theme.Colors.SubText)
	local badge = UiKit.Plate(front, "Badge", "Pill", {
		_Accent = "Green",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(110, 26),
		Rotation = -4,
		Visible = false,
		ZIndex = 6,
	})
	UiKit.Text(badge, "Text", "NEW!", {
		_Style = "Heading",
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.new(1, -12, 1, -4),
		ZIndex = 7,
	})
	return slot
end

function Builder.Build()
	local gui = UiKit.Screen("RevealCards", { DisplayOrder = 70 })
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	UiKit.Dimmer(gui, { Visible = true, BackgroundTransparency = 1 })

	local holder = UiKit.Group(gui, "Holder", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(1100, 340),
	})
	UiKit.Scale(holder, "Scale", 1)
	UiKit.TitleText(holder, "Header", "EPIC CHEST", "Gold", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(600, 42),
	})
	UiKit.Group(holder, "Row", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(1100, Builder.CARD_H),
	})
	local hint = UiKit.Text(holder, "Hint", "TAP TO CONTINUE", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 18),
		Size = UDim2.fromOffset(300, 22),
		TextColor3 = Theme.Colors.SubText,
	})
	hint.TextTransparency = 1

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	Builder.BuildCard(templates)
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
