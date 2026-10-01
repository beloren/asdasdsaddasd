--------------------------------------------------------------------------------
-- CompassUi (v20.126) — КНОПКА TRAVEL + ОКНО ТЕЛЕПОРТА С КАРТОЧКАМИ МЕСТ.
-- Клиент: CompassUI.client.lua (карточки - клоны Templates/PlaceCardTemplate).
-- Всё правится в StarterGui/CompassUi (картинки - поле Image у ImageLabel).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "CompassUi"
--   ├─ ImageButton "CompassButton" → ImageLabel "Icon" (→ TextLabel "Emoji"), TextLabel "Label"
--   ├─ TextButton "Dimmer"
--   ├─ ImageLabel "Panel" [окно] (UIScale "ResponsiveScale")
--   │    ├─ TitleBar → "Title"; ImageButton "CloseButton"
--   │    ├─ ScrollingFrame "Places" (UIGridLayout) - сюда клиент кладёт карточки
--   │    ├─ TextLabel "Cooldown"
--   │    └─ Folder "Templates"
--   │         └─ ImageButton "PlaceCardTemplate" [Card] → ImageLabel "Icon"
--   │              (→ TextLabel "Emoji"), "PlaceName", "Subtitle", ImageButton "Go" (Caption)
--   └─ Frame "Fade" - затемнение при телепорте
-- Картинки карточек по месту - Config.Compass.PlaceImages (0 - эмодзи).
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 26
Builder.W, Builder.H = 640, 430

local function iconWithEmoji(parent, props, emoji)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = ""
	for k, v in props do icon[k] = v end
	icon.Parent = parent
	local text = UiKit.Text(icon, "Emoji", emoji, { _Style = "Heading", ZIndex = (props.ZIndex or 1) + 1 })
	text.TextScaled = true
	return icon
end

function Builder.Build()
	local gui = UiKit.Screen("CompassUi", { DisplayOrder = 96 })
	gui.IgnoreGuiInset = false
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	-- КНОПКА слева под книгой MENU (позицию на ПК/телефоне ставит клиент)
	local button = Instance.new("ImageButton")
	button.Name = "CompassButton"
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.zero
	button.Position = UDim2.new(0, 34, 0.5, 26)
	button.Size = UDim2.fromOffset(58, 58)
	button.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
	button.BackgroundTransparency = 0.15
	button.Image = ""
	button.Parent = gui
	UiKit.Corner(button, 999)
	UiKit.Stroke(button, Theme.Accents.Gold.Main, 3, 0, "Outline")
	iconWithEmoji(button, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.08), ZIndex = 2 }, "🧭")
	local label = UiKit.Text(button, "Label", "TRAVEL", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1.5, 0, 0, 18),
		ZIndex = 3,
	})
	label.TextScaled = true

	UiKit.Dimmer(gui, { ZIndex = 10 })
	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "TELEPORT",
		Accent = "Gold",
		Size = UDim2.fromOffset(Builder.W, Builder.H),
		Flat = true,
		CloseInRoot = true,
		ZIndex = 11,
	})
	UiKit.Scale(panel, "ResponsiveScale", 1)
	local top, pad = parts.Top, parts.Pad

	local places = UiKit.Scroll(panel, "Places", {
		Position = UDim2.fromOffset(pad, top),
		Size = UDim2.new(1, -pad * 2, 1, -top - pad),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 12,
	})
	local grid = UiKit.Grid(places, UDim2.fromOffset(180, 170), UDim2.fromOffset(14, 14))
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	UiKit.Padding(places, 6, 6, 6, 6)

	local cooldown = UiKit.Text(panel, "Cooldown", "Pick a place to teleport", {
		_Style = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Color3.fromRGB(255, 220, 120),
	})
	cooldown.TextScaled = true

	-- ШАБЛОН КАРТОЧКИ МЕСТА
	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel
	local card = UiKit.CardButton(templates, "PlaceCardTemplate", "Gold", { ZIndex = 13, Visible = false })
	iconWithEmoji(card, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -20, 0, 62),
		ZIndex = 14,
	}, "📍")
	local name = UiKit.Text(card, "PlaceName", "PLACE", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(1, -16, 0, 30),
		ZIndex = 14,
	})
	name.TextScaled = true
	local sub = UiKit.Text(card, "Subtitle", "", {
		_Style = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.new(1, -16, 0, 18),
		TextColor3 = Color3.fromRGB(210, 210, 225),
		ZIndex = 14,
	})
	sub.TextScaled = true
	UiKit.Button(card, "Go", "GO", "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0, 30),
		ZIndex = 14,
	})

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.Size = UDim2.new(1, 0, 1, 200)
	fade.Position = UDim2.fromOffset(0, -100)
	fade.ZIndex = 50
	fade.Visible = false
	fade.Parent = gui
	return gui
end

return Builder
