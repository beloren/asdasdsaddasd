--------------------------------------------------------------------------------
-- SkillTreeUi (v20.143) — ПОЛНОЭКРАННЫЕ ДЕРЕВЬЯ ПРОКАЧКИ, как дерево
-- престижа: окна нет, узлы висят поверх размытого мира, ветки расходятся во
-- все стороны от центрального узла, поле таскается мышкой/пальцем, колесо и
-- щипок - масштаб, карточка узла всплывает рядом, внизу большая CLOSE.
--   StarterGui/UpgradeTreeUi - Experienced Miner (тиры, звёзды-улучшения)
--   StarterGui/IslandTreeUi  - Island Keeper (острова, печь, перки островов)
--   StarterGui/PrestigeTreeUi - дерево престижа (+ Frame "Tabs" → PerksTab,
--                               ShrinesTab; "Money" показывает очки престижа)
-- Логика: CustomCartUI.client.lua / IslandUI.client.lua через
-- Shared.SkillTreeView.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui (Enabled=false)
--   ├─ Frame "Backdrop"               затемнение на весь экран
--   ├─ Frame "Viewport" (Active)      область перетаскивания
--   │    └─ Frame "Canvas" (UIScale "Zoom") — сюда кладутся узлы и линии
--   ├─ TextLabel "Title", TextLabel "Money", TextLabel "Hint"
--   ├─ ImageLabel "Card" [Card]        карточка выбранного узла:
--   │    Title, Level, Text, ImageButton "Buy", ImageButton "More", ImageButton "Close"
--   ├─ ImageButton "BigClose"          большая кнопка CLOSE внизу
--   └─ Folder "Templates"
--        ├─ "RootNode"   центр дерева (Shape, Icon, Name)
--        ├─ "TierNode"   тир / уровень (Shape, Caption, Price, Name)
--        ├─ "StarNode"   звезда-улучшение (Shape повёрнут 45, Icon, Level, Name)
--        ├─ "FinalNode"  финальный узел (Shape круглый, Icon, Level, Name)
--        └─ Frame "Link" линия между узлами
-- ФОРМА УЗЛА - ImageLabel "Shape" в каждом шаблоне: поставь Image (белая
-- картинка), удали SkinCorner/Stroke - клиент сам красит её в цвет состояния.
-- Размер шаблона = размер узла на экране (при Zoom = 1).
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local TreeParts = require(script.Parent.TreeParts)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

local function build(name, title, accentColor, withTabs)
	local gui = UiKit.Screen(name, { DisplayOrder = 29, Enabled = false })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	gui.IgnoreGuiInset = true

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 8, 16)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = gui

	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Active = true
	viewport.ClipsDescendants = true
	viewport.ZIndex = 2
	viewport.Parent = gui
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(0, 0)
	canvas.BackgroundTransparency = 1
	canvas.ZIndex = 2
	canvas.Parent = viewport
	local zoom = Instance.new("UIScale")
	zoom.Name = "Zoom"
	zoom.Parent = canvas

	UiKit.Text(gui, "Title", title, {
		_Style = "Title", _MaxTextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.new(0.6, 0, 0, 46),
		TextColor3 = accentColor, ZIndex = 10,
	})
	UiKit.Text(gui, "Money", "", {
		_Style = "Number", _MaxTextSize = 30,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(260, 36),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Colors.Money, ZIndex = 10,
	})
	UiKit.Text(gui, "Hint", "Drag to move  •  Scroll or pinch to zoom", {
		_Style = "Small", _MaxTextSize = 16,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.new(0.6, 0, 0, 20),
		TextColor3 = Theme.Colors.SubText, ZIndex = 10,
	})

	local card = TreeParts.InfoCard(gui, "Card", {
		Size = UDim2.fromOffset(300, 236), Visible = false, ZIndex = 30,
	}, true)
	card:SetAttribute("OpenSize", Vector2.new(300, 236))
	local buy = card:FindFirstChild("Buy")
	if buy then
		buy.Position = UDim2.new(0.5, 0, 1, -62)
		buy.Size = UDim2.new(1, -24, 0, 46)
	end
	UiKit.Button(card, "More", "DETAILS", "Blue", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 40),
		ZIndex = card.ZIndex + 2,
	})

	if withTabs then
		local tabs = Instance.new("Frame")
		tabs.Name = "Tabs"
		tabs.BackgroundTransparency = 1
		tabs.AnchorPoint = Vector2.new(0.5, 0)
		tabs.Position = UDim2.new(0.5, 0, 0, 70)
		tabs.Size = UDim2.fromOffset(340, 50)
		tabs.ZIndex = 10
		tabs.Parent = gui
		UiKit.Button(tabs, "PerksTab", "PERKS", "Yellow", { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(164, 50), ZIndex = 11 })
		UiKit.Button(tabs, "ShrinesTab", "🗿 SHRINES", "Dark", { Position = UDim2.fromOffset(176, 0), Size = UDim2.fromOffset(164, 50), ZIndex = 11 })
	end

	UiKit.Button(gui, "BigClose", "CLOSE", "Red", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(240, 62), ZIndex = 25,
	})

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local root = TreeParts.Star(templates, "RootNode", 120, { WithName = true, Round = true, Color = accentColor, Icon = "⛏" })
	root:FindFirstChild("Level").Text = ""
	local tier = TreeParts.Node(templates, "TierNode", 78, 120)
	UiKit.Text(tier, "Name", "", {
		_Style = "Small", _MaxTextSize = 15, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -3), Size = UDim2.fromOffset(150, 18),
		TextColor3 = Color3.fromRGB(200, 205, 220), ZIndex = tier.ZIndex + 2,
	})
	TreeParts.Star(templates, "StarNode", 92, { WithName = true, Color = Theme.Accents.Gold.Main })
	TreeParts.Star(templates, "FinalNode", 104, { WithName = true, Round = true, Color = Theme.Accents.Gold.Main })
	TreeParts.Line(templates, "Link", 8)
	-- v20.168: узлы под картинки-подложки (Config.TreePlates): у формы нет
	-- скругления и обводки, не повёрнута, во весь узел, пиксельная.
	for _, nodeName in { "RootNode", "TierNode", "StarNode", "FinalNode" } do
		local node = templates:FindFirstChild(nodeName)
		local shape = node and node:FindFirstChild("Shape")
		if shape then
			for _, d in shape:GetChildren() do
				if d:IsA("UICorner") or d:IsA("UIStroke") or d:IsA("UIGradient") then d:Destroy() end
			end
			shape.Rotation = 0
			shape.Size = UDim2.fromScale(1, 1)
			shape.BackgroundTransparency = 1
			shape.ScaleType = Enum.ScaleType.Fit
			shape.ResampleMode = Enum.ResamplerMode.Pixelated
		end
	end
	UiKit.HideTemplates(gui)
	return gui
end

function Builder.BuildUpgrade()
	return build("UpgradeTreeUi", "UPGRADES", Color3.fromRGB(255, 190, 70))
end

function Builder.BuildIsland()
	return build("IslandTreeUi", "ISLANDS", Color3.fromRGB(120, 220, 255))
end

function Builder.BuildPrestige()
	return build("PrestigeTreeUi", "PRESTIGE", Color3.fromRGB(255, 150, 215), true)
end

Builder.Build = Builder.BuildUpgrade
return Builder
