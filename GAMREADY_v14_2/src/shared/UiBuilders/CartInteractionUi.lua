--------------------------------------------------------------------------------
-- CartInteractionUi — экранные подсказки кастомных ProximityPrompt
-- («Take Cart», «Drop Cart», разговор с NPC). Клиент: CustomCartUI.client.lua.
-- (При Config.UI.WorldPrompts = true основные подсказки рисуются прямо на
-- объектах — см. WorldPrompts.client.lua и WorldUiTemplates.)
--
-- СТРУКТУРА (имена — контракт), для каждой из трёх плашек
-- "CartPromptGui" / "CartDropHintGui" / "TalkPromptGui":
--   ImageLabel [Toast] (рамка = акцент)
--   ├─ ImageLabel "FillOverlay" — заливка прогресса удержания (растёт по ширине)
--   ├─ ImageLabel "PromptKeyImage" — значок клавиши слева снаружи
--   ├─ TextLabel "Text"
--   └─ TextButton "TouchTarget" — нажатие пальцем/мышью
-- В "CartPromptGui" ещё TextLabel "HoldHint" («HOLD!» над плашкой).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = UiKit.Theme

local Builder = {}

local function prompt(gui, name, accentName, width, height, text)
	local accent = UiKit.Accent(accentName)
	local p = UiKit.Plate(gui, name, "Toast", {
		_Accent = accent,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(width, height),
		ClipsDescendants = false,
		Visible = false,
	})
	local fill = UiKit.Plate(p, "FillOverlay", "BarFill", {
		_Accent = accent,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 0.55,
		ZIndex = 1,
	})
	fill:SetAttribute("UiAccent", accent.Main)
	local keyId = Config.UI and Config.UI.PromptKeyImageId or 0
	UiKit.Icon(p, "PromptKeyImage", keyId, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.fromOffset(height, height),
		ZIndex = 10,
	})
	UiKit.Text(p, "Text", text, {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(1, -24, 1, -10),
		TextColor3 = Theme.Colors.Text,
		ZIndex = 2,
	})
	local touch = Instance.new("TextButton")
	touch.Name = "TouchTarget"
	touch.Text = ""
	touch.BackgroundTransparency = 1
	touch.Size = UDim2.fromScale(1, 1)
	touch.ZIndex = 20
	touch:SetAttribute("DisableGlobalHover", true)
	touch.Parent = p
	return p
end

function Builder.Build()
	local gui = UiKit.Screen("CartInteractionUi", { DisplayOrder = 5 })
	local take = prompt(gui, "CartPromptGui", "Gold", 200, 46, "")
	local hold = UiKit.Text(take, "HoldHint", "HOLD!", {
		_Style = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(150, 32),
		TextColor3 = Theme.Colors.Money,
		Visible = false,
		ZIndex = 25,
	})
	hold.TextScaled = true
	prompt(gui, "CartDropHintGui", "Blue", 220, 42, "Drop Cart")
	prompt(gui, "TalkPromptGui", "Purple", 200, 46, "")
	return gui
end

return Builder
