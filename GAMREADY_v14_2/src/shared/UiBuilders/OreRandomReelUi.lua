--------------------------------------------------------------------------------
-- OreRandomReelUi (v20.131) — ЛЕНТА РАНДОМ-БОКСА РУДЫ.
-- Клиент: OreRandomReel.client.lua (карточки - клоны Templates/Card).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "OreRandomReelUi" (Enabled = false)
--   ├─ Frame "Dim" - затемнение
--   ├─ TextLabel "Title" - «MYSTERY ORE BOX»
--   ├─ Frame "Reel" (ClipsDescendants, UIScale "Scale") - окно ленты
--   │    ├─ ImageLabel "Rays" - полоски за выпавшей рудой
--   │    ├─ Frame "Pointer" (две стрелки по бокам центра)
--   │    └─ Frame "Strip" - сюда клиент кладёт карточки
--   ├─ TextLabel "Result" - название выпавшей руды
--   └─ Folder "Templates" → ImageLabel "Card" [Card]
--        ├─ Frame "Model" - 3D-превью руды (ViewportFrame с чёрной обводкой)
--        ├─ TextLabel "OreName", TextLabel "Variant"
--        └─ UIScale "Drum"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)

local Builder = {}
Builder.VERSION = 20
Builder.CARD_W, Builder.CARD_H = 230, 150
Builder.REEL_H = 430

function Builder.Build()
	local gui = UiKit.Screen("OreRandomReelUi", { DisplayOrder = 140 })
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	dim.Parent = gui

	local reel = UiKit.Group(gui, "Reel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Builder.CARD_W + 140, Builder.REEL_H),
		ZIndex = 2,
	})
	reel.ClipsDescendants = true
	UiKit.Scale(reel, "Scale", 1)

	UiKit.Backdrop(reel, "Rays", "Legendary", {
		Size = UDim2.fromOffset(Builder.REEL_H, Builder.REEL_H),
		Visible = false,
		ZIndex = 2,
		Transparency = 0.15,
	})
	local strip = UiKit.Group(reel, "Strip", { ZIndex = 3 })
	strip.Size = UDim2.fromScale(1, 1)

	local pointer = UiKit.Group(reel, "Pointer", { ZIndex = 6 })
	pointer.Size = UDim2.fromScale(1, 1)
	for _, side in { -1, 1 } do
		local arrow = Instance.new("Frame")
		arrow.Name = side < 0 and "Left" or "Right"
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Position = UDim2.new(0.5, side * (Builder.CARD_W / 2 + 34), 0.5, 0)
		arrow.Size = UDim2.fromOffset(22, 22)
		arrow.Rotation = 45
		arrow.BackgroundColor3 = Color3.fromRGB(255, 225, 90)
		arrow.BorderSizePixel = 0
		arrow.ZIndex = 6
		arrow.Parent = pointer
		UiKit.Stroke(arrow, Color3.new(0, 0, 0), 2.5, 0, "Outline")
	end

	local title = UiKit.Text(gui, "Title", "MYSTERY ORE BOX", {
		_Style = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -Builder.REEL_H / 2 - 6),
		Size = UDim2.fromOffset(520, 54),
		ZIndex = 7,
	})
	title.TextScaled = true
	local result = UiKit.Text(gui, "Result", "", {
		_Style = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, Builder.REEL_H / 2 + 6),
		Size = UDim2.fromOffset(560, 50),
		ZIndex = 7,
	})
	result.TextScaled = true
	result.TextTransparency = 1

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local card = UiKit.Card(templates, "Card", "Purple", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Builder.CARD_W, Builder.CARD_H),
		ZIndex = 3,
	})
	UiKit.Scale(card, "Drum", 1)
	local model = UiKit.Group(card, "Model", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0, Builder.CARD_H - 50, 0, Builder.CARD_H - 50),
		ZIndex = 4,
	})
	model.ZIndex = 4
	local name = UiKit.Text(card, "OreName", "ORE", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -16, 0, 26),
		ZIndex = 5,
	})
	name.TextScaled = true
	local variant = UiKit.Text(card, "Variant", "I", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(44, 26),
		ZIndex = 5,
	})
	variant.TextScaled = true
	variant.TextXAlignment = Enum.TextXAlignment.Right
	return gui
end

return Builder
