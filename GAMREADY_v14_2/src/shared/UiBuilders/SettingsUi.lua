--------------------------------------------------------------------------------
-- SettingsUi — настройки (звук, громкости, эффекты) и промокоды.
-- Клиент: CustomCartUI.client.lua. Окно показывается, только если
-- Config.UI.SettingsMenuEnabled ~= false.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "SettingsMenu"
--   ├─ ImageButton "GearButton" [Round] → ImageLabel "Icon"
--   └─ ImageLabel "Panel" (окно) → TitleBar(Title, Ribbon, CloseButton)
--        └─ Frame → ScrollingFrame "Body"
--             ├─ ImageLabel "Audio" [Inset] → "Title", "Subtitle", ImageButton "SoundToggle" (Caption)
--             ├─ ImageLabel "<Sfx|Music|Ui|Effects>SliderRow" → "Label", "Value",
--             │     ImageLabel "Track" [BarTrack] → "Fill" [BarFill], ImageButton "Thumb";
--             │     TextButton "SliderHitArea"
--             └─ ImageLabel "RedeemRow" → "Title", "Subtitle", TextBox "CodeInput",
--                   ImageButton "RedeemButton" (Caption), TextLabel "ResultText"
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

local function row(body, name, height, order)
	local r = UiKit.Plate(body, name, "Inset", { Size = UDim2.new(1, 0, 0, height), LayoutOrder = order })
	return r
end

local function titled(r, title, subtitle)
	UiKit.Text(r, "Title", title, {
		_Style = "Heading",
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -100, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(r, "Subtitle", subtitle, {
		_Style = "Small",
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -100, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})
end

local function slider(body, name, label, order)
	local r = row(body, name .. "Row", 56, order)
	UiKit.Text(r, "Label", label, {
		_Style = "Heading",
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -80, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(r, "Value", "100%", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 5),
		Size = UDim2.fromOffset(56, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})
	local track, fill = UiKit.Bar(r, "Track", "Teal", {
		Position = UDim2.new(0, 14, 1, -18),
		Size = UDim2.new(1, -28, 0, 8),
		ZIndex = 2,
	})
	track.Active = true
	fill.Size = UDim2.fromScale(1, 1)
	local thumb = UiKit.PlateButton(track, "Thumb", "Round", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		ZIndex = 4,
	})
	thumb:SetAttribute("DisableGlobalHover", true)
	local hit = Instance.new("TextButton")
	hit.Name = "SliderHitArea"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Position = UDim2.new(0, 4, 0, 22)
	hit.Size = UDim2.new(1, -8, 0, 32)
	hit.ZIndex = 10
	hit:SetAttribute("DisableGlobalHover", true)
	hit.Parent = r
	return r
end

function Builder.Build()
	local gui = UiKit.Screen("SettingsMenu", { DisplayOrder = 40 })

	local gear = UiKit.PlateButton(gui, "GearButton", "Round", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, -26),
		Size = UDim2.fromOffset(46, 46),
	})
	UiKit.ThemeIcon(gear, "Icon", "Settings", "⚙", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 2,
	})

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "Settings",
		Accent = "Teal",
		Size = UDim2.fromOffset(440, 560),
		Scroll = true,
	})
	local body = parts.Body
	UiKit.List(body, { Padding = UDim.new(0, 8) })
	UiKit.Padding(body, 2, 2, 2, 6)

	local audio = row(body, "Audio", 58, 1)
	titled(audio, "Audio", "Toggle your audio")
	UiKit.Button(audio, "SoundToggle", "On", "Green", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(72, 32),
		ZIndex = 2,
	})

	slider(body, "SfxSlider", "WORLD SOUNDS", 2)
	slider(body, "MusicSlider", "MUSIC", 3)
	slider(body, "UiSlider", "UI SOUNDS", 4)
	slider(body, "EffectsSlider", "VISUAL EFFECTS", 5)

	local redeem = row(body, "RedeemRow", 118, 6)
	titled(redeem, "Redeem Codes", "Look for codes on developer's socials!")
	redeem.Title.Size = UDim2.new(1, -24, 0, 24)
	redeem.Subtitle.Size = UDim2.new(1, -24, 0, 18)
	local _, inputPlate = UiKit.Input(redeem, "CodeInput", "Type code here..", {
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.new(1, -112, 0, 34),
	})
	inputPlate.ZIndex = 2
	UiKit.Button(redeem, "RedeemButton", "Claim", "Claim", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 54),
		Size = UDim2.fromOffset(88, 34),
		ZIndex = 2,
	})
	UiKit.Text(redeem, "ResultText", "", {
		_Style = "Small",
		Position = UDim2.fromOffset(12, 92),
		Size = UDim2.new(1, -24, 0, 18),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 2,
	})
	panel:SetAttribute("BaseWidth", 440)
	panel:SetAttribute("BaseHeight", 560)
	return gui
end

return Builder
