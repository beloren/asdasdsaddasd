--------------------------------------------------------------------------------
-- MiningRhythmUi (v20) — кнопка мини-игры «TAP!» с кольцом-таймером.
-- Клиент: MiningRhythmUI.client.lua.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "MiningRhythmUi"
--   └─ Frame "PromptContainer"
--        ├─ ImageButton "RhythmButton" [Button_Yellow] → "Caption"
--        └─ Frame "RingHolder" → ImageLabel "Segment1".."Segment<N>"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)

local Builder = {}
Builder.VERSION = 20
Builder.RING_SEGMENTS = 10
Builder.BUTTON_SIZE = 92
Builder.RING_SIZE = 118

local function squarePerimeterPoint(t)
	t = t % 4
	local side = math.floor(t)
	local along = t - side
	if side == 0 then return along, 0
	elseif side == 1 then return 1, along
	elseif side == 2 then return 1 - along, 1
	else return 0, 1 - along end
end

function Builder.Build()
	local gui = UiKit.Screen("MiningRhythmUi", { DisplayOrder = 50 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local container = UiKit.Group(gui, "PromptContainer", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(120, 120),
	})
	UiKit.Button(container, "RhythmButton", "TAP!", "Yellow", {
		_TextStyle = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Builder.BUTTON_SIZE, Builder.BUTTON_SIZE),
		Visible = false,
		ZIndex = 5,
	})
	local ring = UiKit.Group(container, "RingHolder", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Builder.RING_SIZE, Builder.RING_SIZE),
		Visible = false,
		ZIndex = 4,
	})
	for i = 1, Builder.RING_SEGMENTS do
		local x, y = squarePerimeterPoint((i - 1) / Builder.RING_SEGMENTS * 4)
		UiKit.Plate(ring, "Segment" .. i, "Slot", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			ZIndex = 4,
		})
	end
	return gui
end

return Builder
