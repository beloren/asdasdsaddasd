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
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

-- v20: весь текст — UiKit.Text (жирный курсив темы с тёмной обводкой).
local function text(parent, name, props)
	local label = UiKit.Text(parent, name, props.Text or "", {
		_Style = props.Style or "Title",
		_Stroke = props.Stroke or 2,
		_MaxTextSize = props.MaxTextSize,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextColor3 = props.Color or Color3.new(1, 1, 1),
		TextXAlignment = props.AlignX or Enum.TextXAlignment.Center,
		ZIndex = props.ZIndex or 2,
	})
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
		Color = Theme.Colors.Money,
		MaxTextSize = 16,
	}).Visible = false

	-- Ряд делений. Клиент клонирует PipTemplate Config.Stagger.Pips раз и
	-- задаёт Fill.Size.X по заполнению шкалы.
	local bar = UiKit.Group(billboard, "Bar", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(92, 11),
	})
	UiKit.List(bar, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 3),
	})
	local pip = UiKit.Plate(bar, "PipTemplate", "BarTrack", {
		Visible = false,
		Size = UDim2.new(0.25, -3, 1, 0),
	})
	local fill = UiKit.Plate(pip, "Fill", "BarFill", {
		_Accent = Theme.Accents.Orange,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 2,
	})
	fill.BackgroundColor3 = Color3.fromRGB(255, 170, 60)

	-- Компактный значок награды: одна строка, не шире шкалы.
	local wanted = UiKit.Plate(billboard, "Wanted", "Pill", {
		_Accent = Theme.Accents.Gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 31),
		Size = UDim2.fromOffset(80, 15),
		Visible = false,
	})
	UiKit.Icon(wanted, "Icon", "", {
		Position = UDim2.fromOffset(3, 1),
		Size = UDim2.fromOffset(13, 13),
		Visible = false, -- включается клиентом, если сюда поставили картинку
		ZIndex = 2,
	})
	text(wanted, "Text", {
		Text = "💰 $0",
		Style = "Number",
		Size = UDim2.new(1, -6, 1, -2),
		Position = UDim2.fromOffset(3, 1),
		Color = Theme.Colors.Money,
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
		Style = "Heading",
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
		Style = "Heading",
	})
	return frame
end

function Builder.Build()
	local gui = UiKit.Screen("CombatUi", { DisplayOrder = 12 })
	gui:SetAttribute("BuilderVersion", math.max((Config.Stagger and Config.Stagger.UiVersion) or 1, Builder.VERSION))
	buildStaggerTemplate(gui)
	buildComboCounter(gui)
	buildPopup(gui)
	return gui
end

return Builder
