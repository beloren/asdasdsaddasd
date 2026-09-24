--------------------------------------------------------------------------------
-- HudUi — постоянный HUD: портрет персонажа, деньги, престиж + контейнер
-- ряда кнопок в топбаре (TopbarDock).
--
-- «Hud» (обновляет сервер HudService, портрет — PlayerPortraitHud.client):
--   ScreenGui "Hud"
--   └─ Frame "HudGui" (левый нижний угол; сюда же QuestUI кладёт трекер)
--        ├─ ViewportFrame "Portrait" → ImageLabel "PortraitFrame" (рамка поверх)
--        ├─ ImageLabel "MoneyPill"   [Pill] → ImageLabel "Icon" (→Emoji), TextLabel "Value"
--        └─ ImageLabel "RebirthPill" [Pill] → ImageLabel "Icon" (→Emoji), TextLabel "Value"
--
-- «TopbarDock» (Shared.TopbarDock ставит ряд справа от кнопок Roblox):
--   ScreenGui "TopbarDock" → Frame "Row" (UIListLayout; кнопки добавляют скрипты)
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

local function pill(parent, name, accentName, iconKey, emoji, text, props)
	local accent = UiKit.Accent(accentName)
	local p = UiKit.Plate(parent, name, "Pill", {
		_Accent = accent,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(210, 44),
		ClipsDescendants = false,
	})
	local icon = UiKit.ThemeIcon(p, "Icon", iconKey, emoji, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 3,
	})
	UiKit.Text(p, "Value", text, {
		_Style = "Number",
		_Stroke = 2,
		Position = UDim2.fromOffset(26, 3),
		Size = UDim2.new(1, -34, 1, -6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = accent.Light,
		ZIndex = 2,
	})
	UiKit.Apply(p, props)
	return p
end

function Builder.Build()
	local gui = UiKit.Screen("Hud", { DisplayOrder = 10 })

	local container = UiKit.Group(gui, "HudGui", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(320, 104),
	})

	-- Портрет — живой 3D-персонаж (заполняет PlayerPortraitHud.client).
	local portrait = Instance.new("ViewportFrame")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0, 0.5)
	portrait.Position = UDim2.new(0, 0, 0.5, 0)
	portrait.Size = UDim2.fromOffset(92, 92)
	portrait.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	portrait.BackgroundTransparency = 0.15
	portrait.BorderSizePixel = 0
	portrait.ClipsDescendants = true
	portrait.ZIndex = 3
	portrait.Parent = container
	UiKit.Corner(portrait, 999)
	UiKit.Stroke(portrait, Theme.Accents.Gold.Main, 2.5, 0, "Ring")
	-- Рамка поверх портрета: поставь свою картинку кольца в Image.
	local frame = UiKit.Icon(portrait, "PortraitFrame", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 18, 1, 18),
		ZIndex = 5,
	})
	frame:SetAttribute("UiIcon", "PortraitFrame")

	pill(container, "MoneyPill", "Gold", "Money", "💰", "$0", {
		Position = UDim2.new(0, 104, 0.5, -20),
		Size = UDim2.fromOffset(210, 44),
	})
	pill(container, "RebirthPill", "Purple", "Prestige", "⭐", "PRESTIGE: 0", {
		Position = UDim2.new(0, 104, 0.5, 26),
		Size = UDim2.fromOffset(160, 32),
	})
	return gui
end

function Builder.BuildTopbar()
	local gui = UiKit.Screen("TopbarDock", {
		DisplayOrder = 1250,
		ScreenInsets = Enum.ScreenInsets.None,
	})
	local row = UiKit.Group(gui, "Row", {
		Position = UDim2.fromOffset(120, 6),
		Size = UDim2.fromOffset(400, 44),
	})
	UiKit.List(row, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	})
	return gui
end

return Builder
