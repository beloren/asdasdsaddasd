--------------------------------------------------------------------------------
-- MobBillboardsUi (v20) — таблички над гоблинами и валунами (имя, уровень,
-- полоска HP). Клиент: GoblinBillboard.client.lua клонирует шаблоны и сам
-- переводит размеры в Scale (табличка не «растёт» издалека).
--
-- СТРУКТУРА (контракт; разметка в пикселях холста 200×41):
--   ScreenGui "MobBillboardTemplates" (Enabled=false)
--   ├─ BillboardGui "GoblinTemplate"  → ImageLabel "GoblinIcon"  → "IconPlaceholder"
--   └─ BillboardGui "BoulderTemplate" → ImageLabel "BoulderIcon" → "IconPlaceholder"
--        общее: Frame "Info" → TextLabel "Title",
--               ImageLabel "HealthBack" [BarTrack] → ImageLabel "Fill" [BarFill], TextLabel "Health"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiKit = require(script.Parent.Parent.UiKit)

local Builder = {}
Builder.VERSION = 20
Builder.PIXELS = Vector2.new(200, 41)
Builder.STUDS = Vector2.new(6, 1.23)

local function buildTemplate(parent, name, boulder)
	local Config = require(ReplicatedStorage.Shared.Config)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromScale(Builder.STUDS.X, Builder.STUDS.Y)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Enabled = false
	gui.Parent = parent

	local icon = UiKit.Plate(gui, boulder and "BoulderIcon" or "GoblinIcon", "Slot", {
		_Accent = boulder and "Grey" or "Green",
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.fromOffset(38, 38),
		ScaleType = Enum.ScaleType.Fit,
	})
	local image = boulder and (Config.Boulders and Config.Boulders.IconImage) or (Config.Goblins and Config.Goblins.IconImage)
	if image and image ~= "" then
		icon.Image = UiKit.ImageUri(image)
	end
	UiKit.Text(icon, "IconPlaceholder", boulder and "B" or "G", {
		_Style = "Title",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		ZIndex = 2,
	})

	local info = UiKit.Group(gui, "Info", {
		Position = UDim2.fromOffset(42, 1),
		Size = UDim2.fromOffset(156, 38),
	})
	UiKit.Text(info, "Title", "NAME Lv. 1", {
		_Style = "Heading",
		_MaxTextSize = 16,
		Position = UDim2.fromOffset(6, 1),
		Size = UDim2.new(1, -12, 0, 19),
	})
	local back = UiKit.Plate(info, "HealthBack", "BarTrack", {
		Position = UDim2.new(0, 6, 1, -18),
		Size = UDim2.new(1, -12, 0, 14),
		ClipsDescendants = true,
	})
	UiKit.Plate(back, "Fill", "BarFill", {
		_Accent = "Green",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	UiKit.Text(back, "Health", "HP 100/100", {
		_Style = "Small",
		_MaxTextSize = 12,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	})
	return gui
end

function Builder.Build()
	local gui = UiKit.Screen("MobBillboardTemplates", { DisplayOrder = 19 })
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	buildTemplate(gui, "GoblinTemplate", false)
	buildTemplate(gui, "BoulderTemplate", true)
	return gui
end

return Builder
