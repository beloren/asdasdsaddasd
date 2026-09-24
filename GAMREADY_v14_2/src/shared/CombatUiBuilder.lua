--------------------------------------------------------------------------------
-- CombatUiBuilder — собирает интерфейс PvP v2 (шкала оглушения, WANTED,
-- комбо-счётчик, всплывающие надписи).
--
-- ОДИН источник правды для двух мест (как MineVeinUiBuilder):
--   • tools/BuildCombatUI.lua (Studio Command Bar) кладёт результат в
--     StarterGui/CombatUi — дальше вид правится мышкой: цвета, шрифты,
--     размеры, картинки в ImageLabel'ах;
--   • StaggerFX.client.lua строит то же самое сам, если в StarterGui нет
--     свежего CombatUi (игра не ломается без билдера).
--
-- СТРУКТУРА (ScreenGui "CombatUi", атрибут BuilderVersion):
--   ├─ BillboardGui "StaggerTemplate"   (Enabled=false, клиент клонирует на
--   │    │                               голову каждого игрока)
--   │    ├─ TextLabel "State"            — "STUNNED!" во время рагдолла
--   │    ├─ Frame "Bar"                  — ряд делений
--   │    │    └─ Frame "PipTemplate"     (Visible=false) → Frame "Fill"
--   │    └─ Frame "Wanted"               — компактный значок награды
--   │         ├─ ImageLabel "Icon"       — пустой = показывается эмодзи в Text
--   │         └─ TextLabel "Text"        — "💰 $1.2K"
--   ├─ Frame "ComboCounter"             — справа по центру у атакующего
--   │    ├─ TextLabel "Count"  ("x3")
--   │    ├─ TextLabel "Caption" ("HITS")
--   │    └─ UIScale "Pop"
--   └─ Frame "Popup"                    — крупная надпись по центру
--        ├─ TextLabel "Title"  ("KNOCKDOWN!", "CLASH!", "KNOCKED DOWN!")
--        ├─ TextLabel "Subtitle" (добыча/награда)
--        └─ UIScale "Pop"
-- Имена детей — контракт с клиентом; оформление можно менять свободно.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}

local OUTLINE = Color3.fromRGB(12, 14, 22)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 6)
	c.Parent = parent
	return c
end

local function stroke(parent, thickness, color, contextual)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or OUTLINE
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function text(parent, name, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = props.Size or UDim2.fromScale(1, 1)
	label.Position = props.Position or UDim2.new()
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.Font = props.Font or Enum.Font.FredokaOne
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.RichText = true
	label.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	label.ZIndex = props.ZIndex or 2
	label.Parent = parent
	stroke(label, props.Stroke or 2, OUTLINE, true)
	if props.MaxTextSize then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = props.MaxTextSize
		limit.Parent = label
	end
	return label
end

local function buildStaggerTemplate(parent)
	local cfg = Config.Stagger or {}
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StaggerTemplate"
	billboard.Enabled = false
	billboard.Size = UDim2.fromOffset(120, 46)
	billboard.StudsOffset = Vector3.new(0, cfg.BillboardHeight or 3.1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = cfg.BillboardMaxDistance or 90
	billboard.ResetOnSpawn = false
	billboard.Parent = parent

	-- "STUNNED!" — над шкалой, виден только во время рагдолла.
	text(billboard, "State", {
		Text = "STUNNED!",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 0),
		Color = Color3.fromRGB(255, 225, 90),
		MaxTextSize = 16,
	}).Visible = false

	-- Ряд делений. Клиент клонирует PipTemplate Config.Stagger.Pips раз и
	-- задаёт Fill.Size.X по заполнению шкалы.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 18)
	bar.Size = UDim2.fromOffset(92, 11)
	bar.BackgroundTransparency = 1
	bar.Parent = billboard
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local pip = Instance.new("Frame")
	pip.Name = "PipTemplate"
	pip.Visible = false
	pip.Size = UDim2.new(0.25, -3, 1, 0)
	pip.BackgroundColor3 = Color3.fromRGB(40, 42, 52)
	pip.BackgroundTransparency = 0.15
	pip.Parent = bar
	corner(pip, UDim.new(0, 3))
	stroke(pip, 1.5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
	fill.BorderSizePixel = 0
	fill.Parent = pip
	corner(fill, UDim.new(0, 3))
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	shine.Rotation = 90
	shine.Parent = fill

	-- Компактный значок награды: одна строка, не шире шкалы.
	local wanted = Instance.new("Frame")
	wanted.Name = "Wanted"
	wanted.AnchorPoint = Vector2.new(0.5, 0)
	wanted.Position = UDim2.new(0.5, 0, 0, 31)
	wanted.Size = UDim2.fromOffset(78, 15)
	wanted.BackgroundColor3 = Color3.fromRGB(60, 40, 10)
	wanted.BackgroundTransparency = 0.2
	wanted.Visible = false
	wanted.Parent = billboard
	corner(wanted, UDim.new(1, 0))
	stroke(wanted, 1.5, Color3.fromRGB(255, 200, 70))
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.Size = UDim2.fromOffset(13, 13)
	icon.Position = UDim2.fromOffset(3, 1)
	icon.Visible = false -- включается клиентом, если сюда поставили картинку
	icon.Parent = wanted
	text(wanted, "Text", {
		Text = "💰 $0",
		Size = UDim2.new(1, -6, 1, -2),
		Position = UDim2.fromOffset(3, 1),
		Color = Color3.fromRGB(255, 220, 90),
		Stroke = 1.5,
		MaxTextSize = 12,
	})
	return billboard
end

local function buildComboCounter(parent)
	local frame = Instance.new("Frame")
	frame.Name = "ComboCounter"
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(1, -40, 0.42, 0)
	frame.Size = UDim2.fromOffset(130, 80)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = frame
	text(frame, "Count", {
		Text = "x2",
		Size = UDim2.new(1, 0, 0.7, 0),
		Color = Color3.fromRGB(255, 205, 70),
		Stroke = 3,
	})
	text(frame, "Caption", {
		Text = "HITS",
		Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.fromScale(0, 0.7),
		Color = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBlack,
	})
	return frame
end

local function buildPopup(parent)
	local frame = Instance.new("Frame")
	frame.Name = "Popup"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.3)
	frame.Size = UDim2.fromOffset(420, 90)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = frame
	text(frame, "Title", {
		Text = "KNOCKDOWN!",
		Size = UDim2.new(1, 0, 0.62, 0),
		Color = Color3.fromRGB(255, 120, 70),
		Stroke = 3,
	})
	text(frame, "Subtitle", {
		Text = "",
		Size = UDim2.new(1, 0, 0.34, 0),
		Position = UDim2.fromScale(0, 0.64),
		Color = Color3.fromRGB(255, 225, 120),
		Font = Enum.Font.GothamBlack,
	})
	return frame
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 12
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("BuilderVersion", (Config.Stagger and Config.Stagger.UiVersion) or 1)
	buildStaggerTemplate(gui)
	buildComboCounter(gui)
	buildPopup(gui)
	return gui
end

return Builder
