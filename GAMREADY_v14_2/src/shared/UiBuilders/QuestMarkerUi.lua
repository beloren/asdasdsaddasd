--------------------------------------------------------------------------------
-- QuestMarkerUi (v20) — стрелка у края экрана к цели квеста + шаблон
-- шеврона под ногами. Клиент: QuestMarker.client.lua.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "QuestMarkerUi"
--   ├─ Frame "EdgeArrow" (вращается клиентом) → ImageLabel "Image" (свой
--   │    ассет стрелки, смотрит ВПРАВО), TextLabel "Glyph" (запасной ➤)
--   └─ Folder "Templates" → SurfaceGui "Chevron" → ImageLabel "Image",
--        TextLabel "Glyph" (▲)
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

local function glyphPair(parent, glyph, stroke)
	UiKit.Icon(parent, "Image", "", { ZIndex = 2 })
	UiKit.Text(parent, "Glyph", glyph, {
		_Style = "Title",
		_Stroke = stroke,
		TextColor3 = Theme.Accents.Gold.Main,
	})
end

function Builder.Build()
	local gui = UiKit.Screen("QuestMarkerUi", { DisplayOrder = 6 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local arrow = UiKit.Group(gui, "EdgeArrow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(46, 46),
		Visible = false,
	})
	glyphPair(arrow, "➤", 3)

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local chevron = Instance.new("SurfaceGui")
	chevron.Name = "Chevron"
	chevron.Face = Enum.NormalId.Top
	chevron.LightInfluence = 0
	chevron.AlwaysOnTop = false
	chevron.Parent = templates
	glyphPair(chevron, "▲", 0)
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
