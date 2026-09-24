--------------------------------------------------------------------------------
-- OrePreviewUi (v20) — табличка над рудой/жеодой под курсором (цена,
-- мутации, крутящаяся 3D-копия). Клиент: OrePreviewHud.client.lua.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "OrePreviewHud"
--   ├─ Highlight "OrePreviewHighlight"
--   └─ BillboardGui "OrePreviewBillboard" → Frame "Card"
--        ├─ ImageLabel "Plate" [Card] (подложка под текстом)
--        ├─ ViewportFrame "Viewport" (+ Camera)
--        ├─ TextLabel "Price", TextLabel "Mutation"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

function Builder.Build()
	local gui = UiKit.Screen("OrePreviewHud", {})
	gui.IgnoreGuiInset = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local highlight = Instance.new("Highlight")
	highlight.Name = "OrePreviewHighlight"
	highlight.FillTransparency = 0.75
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = gui

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OrePreviewBillboard"
	billboard.Size = UDim2.fromOffset(150, 160)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = gui

	local card = UiKit.Group(billboard, "Card", {})
	UiKit.Card(card, "Plate", "Gold", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -8, 0, 58),
		BackgroundTransparency = 0.25,
	})
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(4, 0)
	viewport.Size = UDim2.new(1, -8, 1, -54)
	viewport.ZIndex = 2
	viewport.Parent = card
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	UiKit.Text(card, "Price", "$0", {
		_Style = "Number",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.new(1, -18, 0, 26),
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 5,
	})
	UiKit.Text(card, "Mutation", "", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -18, 0, 20),
		Visible = false,
		ZIndex = 5,
	})
	return gui
end

return Builder
