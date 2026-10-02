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

-- v20.112: HUD ОДНОЙ КАРТИНКОЙ (Config.UI.HudImage). Структура:
--   Frame "HudGui" (размер = Config.UI.HudImage.Size)
--   ├─ ImageLabel "Background" (вся картинка; ImageId из Config)
--   ├─ Frame "Placeholder" (рамки-заглушка, пока ImageId = 0)
--   ├─ ViewportFrame "Portrait" (живой портрет в окне картинки)
--   ├─ Frame "MoneyPill"   → ImageLabel "Icon" (невидимая точка), TextLabel "Value"
--   └─ Frame "RebirthPill" → ImageLabel "Icon" (невидимая точка), TextLabel "Value"
local function rect(r)
	r = r or { 0, 0, 1, 1 }
	return UDim2.fromScale(r[1], r[2]), UDim2.fromScale(r[3], r[4])
end

local function placeholderBox(parent, name, r, fill, border, z)
	local pos, size = rect(r)
	local box = Instance.new("Frame")
	box.Name = name
	box.Position = pos
	box.Size = size
	box.BackgroundColor3 = fill
	box.BorderSizePixel = 0
	box.ZIndex = z or 1
	box.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = border
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	return box
end

local function imagePill(parent, name, cfg, textRect, iconRect, color, text)
	local pill = Instance.new("Frame")
	pill.Name = name
	pill.BackgroundTransparency = 1
	pill.Size = UDim2.fromScale(1, 1)
	pill.ZIndex = 4
	pill.Parent = parent
	local iconPos, iconSize = rect(iconRect)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ImageTransparency = 1
	icon.Position = iconPos
	icon.Size = iconSize
	icon.ZIndex = 4
	icon.Parent = pill
	local pos, size = rect(textRect)
	UiKit.Text(pill, "Value", text, {
		_Style = "Number",
		_Stroke = 2,
		_StrokeColor = cfg.TextStrokeColor,
		Position = pos,
		Size = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		ZIndex = 5,
	})
	return pill
end

function Builder.BuildImage(cfg)
	local gui = UiKit.Screen("Hud", { DisplayOrder = 10 })
	gui:SetAttribute("HudStyle", "Image")
	local size = cfg.Size or Vector2.new(330, 110)
	local container = UiKit.Group(gui, "HudGui", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	local imageId = tonumber(cfg.ImageId) or 0
	local background = Instance.new("ImageLabel")
	background.Name = "Background"
	background.BackgroundTransparency = 1
	background.Size = UDim2.fromScale(1, 1)
	background.ScaleType = Enum.ScaleType.Stretch
	background.ResampleMode = Enum.ResamplerMode.Pixelated -- пиксель-арт без мыла
	background.Image = imageId > 0 and ("rbxassetid://" .. imageId) or ""
	background.ZIndex = 1
	background.Parent = container

	-- Заглушка в стиле референса: оранжевая рамка портрета и две полоски.
	local holder = Instance.new("Frame")
	holder.Name = "Placeholder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Visible = imageId <= 0
	holder.ZIndex = 1
	holder.Parent = container
	local orange, dark, slot = Color3.fromRGB(240, 140, 40), Color3.fromRGB(70, 35, 15), Color3.fromRGB(40, 28, 22)
	local p = cfg.Portrait or { 0.03, 0.09, 0.255, 0.82 }
	placeholderBox(holder, "PortraitFrame", { p[1] - 0.012, p[2] - 0.04, p[3] + 0.024, p[4] + 0.08 }, orange, dark, 1)
	placeholderBox(holder, "PortraitSlot", p, slot, dark, 2)
	for _, entry in { { "MoneyBar", cfg.Money, cfg.MoneyIcon, Color3.fromRGB(255, 200, 40), "🪙" }, { "PrestigeBar", cfg.Prestige, cfg.PrestigeIcon, Color3.fromRGB(255, 120, 200), "⭐" } } do
		local r, ir = entry[2], entry[3]
		placeholderBox(holder, entry[1], { ir[1] + ir[3] * 0.5, r[2] - 0.02, r[1] + r[3] - ir[1] - ir[3] * 0.5 + 0.01, r[4] + 0.04 }, slot, orange, 1)
		local badge = placeholderBox(holder, entry[1] .. "Icon", ir, entry[4], dark, 2)
		UiKit.Corner(badge, 999)
		UiKit.Text(badge, "Emoji", entry[5], { _Stroke = 0, ZIndex = 3, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1) })
	end

	local pos, psize = rect(cfg.Portrait)
	local portrait = Instance.new("ViewportFrame")
	portrait.Name = "Portrait"
	portrait.Position = pos
	portrait.Size = psize
	portrait.BackgroundTransparency = 1
	portrait.BorderSizePixel = 0
	portrait.ClipsDescendants = true
	portrait.ZIndex = 3
	portrait.Parent = container

	imagePill(container, "MoneyPill", cfg, cfg.Money, cfg.MoneyIcon, cfg.MoneyColor or Color3.fromRGB(255, 226, 90), "$0")
	local prestige = imagePill(container, "RebirthPill", cfg, cfg.Prestige, cfg.PrestigeIcon, cfg.PrestigeColor or Color3.fromRGB(185, 110, 255), "0")
	prestige:SetAttribute("Prefix", cfg.PrestigePrefix or "")
	gui:SetAttribute("UiKitVersion", 23)
	return gui
end

function Builder.Build()
	local okConfig, Config = pcall(require, Shared.Config)
	local imageCfg = okConfig and Config.UI and Config.UI.HudImage
	if imageCfg and imageCfg.Enabled ~= false then
		return Builder.BuildImage(imageCfg)
	end
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
	gui:SetAttribute("UiKitVersion", 23)
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
	-- v20.21: кнопка магазина — первой в ряду (client/ShopDockButton).
	-- Иконка — ImageLabel "Icon": впиши Image в Studio или UiTheme.Icons.Shop.
	local shop = UiKit.PlateButton(row, "ShopDockButton", "Round", {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(44, 44),
	})
	UiKit.ThemeIcon(shop, "Icon", "Shop", "🛒", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 2,
	})
	gui:SetAttribute("UiKitVersion", 21)
	return gui
end

return Builder
