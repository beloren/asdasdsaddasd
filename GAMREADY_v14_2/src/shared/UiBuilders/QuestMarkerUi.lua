--------------------------------------------------------------------------------
-- QuestMarkerUi (v20) — стрелка у края экрана к цели квеста + шаблон
-- шеврона под ногами. Клиент: QuestMarker.client.lua.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "QuestMarkerUi"
--   ├─ Frame "EdgeArrow" (вращается клиентом) → ImageLabel "Image" (свой
--   │    ассет стрелки, смотрит ВПРАВО), Frame "Glyph" (запасная стрелка-фигура)
--   └─ Folder "Templates" → SurfaceGui "Chevron" → ImageLabel "Image",
--        Frame "Glyph" (шеврон-фигура)
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21

-- v20.9: запасной значок — фигура из рамок (UiKit.Shape): символов ➤ и ▲
-- в шрифтах Roblox нет, был «квадратик».
local function glyphPair(parent, kind)
	UiKit.Icon(parent, "Image", "", { ZIndex = 2 })
	UiKit.Shape(parent, "Glyph", kind, { Color = Theme.Accents.Gold.Main, Size = UDim2.fromScale(0.9, 0.9) })
end

function Builder.Build()
	local gui = UiKit.Screen("QuestMarkerUi", { DisplayOrder = 6 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local arrow = UiKit.Group(gui, "EdgeArrow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(46, 46),
		Visible = false,
	})
	glyphPair(arrow, "ArrowRight")

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local chevron = Instance.new("SurfaceGui")
	chevron.Name = "Chevron"
	chevron.Face = Enum.NormalId.Top
	chevron.LightInfluence = 0
	chevron.AlwaysOnTop = false
	chevron.Parent = templates
	glyphPair(chevron, "ChevronUp")
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
