--------------------------------------------------------------------------------
-- DailyRewardUi — награды за время в игре (вид «Welcome Back!» из референса:
-- заголовок над полосой карточек, у забранных — галочка, у готовой —
-- уголки выделения, подпись под каждой карточкой, кнопка Claim снизу).
-- Клиент: DailyRewardUI.client.lua.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "DailyRewardUi"
--   ├─ ImageButton "DailyToggleButton" [Round] → "Caption" (эмодзи), ImageLabel "Badge"
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Panel" (прозрачный корень)
--        ├─ TextLabel "Title"
--        ├─ ImageLabel "Strip" [Panel, акцент Gold]
--        │     → ImageButton "Day1".."Day7" [Card]
--        │         → ImageLabel "Icon" (→ "Emoji"), TextLabel "Reward", TextLabel "Status",
--        │           ImageLabel "Check" (→ "Emoji"), Frame "Brackets" (4 уголка), TextLabel "Day"
--        ├─ ImageButton "CloseButton"
--        └─ ImageButton "ClaimButton" [Button_Claim] → "Caption"
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

Builder.CARD = Vector2.new(128, 128)
Builder.GAP = 14
Builder.SIZE = Vector2.new(620, 494)

local function bracket(parent, corner)
	-- Уголок выделения: две белые полоски (ImageLabel — можно заменить картинкой).
	local holder = UiKit.Group(parent, "Corner" .. corner, {
		AnchorPoint = Vector2.new(corner:find("R") and 1 or 0, corner:find("B") and 1 or 0),
		Position = UDim2.fromScale(corner:find("R") and 1 or 0, corner:find("B") and 1 or 0),
		Size = UDim2.fromOffset(22, 22),
		ZIndex = 8,
	})
	local horizontal = UiKit.Plate(holder, "H", "Divider", {
		_Accent = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(corner:find("R") and 1 or 0, corner:find("B") and 1 or 0),
		Position = UDim2.fromScale(corner:find("R") and 1 or 0, corner:find("B") and 1 or 0),
		Size = UDim2.new(1, 0, 0, 5),
		ZIndex = 8,
	})
	local vertical = horizontal:Clone()
	vertical.Name = "V"
	vertical.Size = UDim2.new(0, 5, 1, 0)
	vertical.Parent = holder
	return holder
end

local function card(strip, day, position)
	local c = UiKit.CardButton(strip, "Day" .. day, "Grey", {
		Position = position,
		Size = UDim2.fromOffset(Builder.CARD.X, Builder.CARD.Y),
		ZIndex = 3,
	})
	local icon = UiKit.Icon(c, "Icon", "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(72, 64),
		ZIndex = 4,
	})
	UiKit.Text(icon, "Emoji", "💰", { _Stroke = 0, ZIndex = 4 }).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(c, "Status", "LOCKED", {
		_Style = "Small",
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.new(1, -12, 0, 14),
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 5,
	})
	UiKit.Text(c, "Reward", "REWARD", {
		_Style = "Title",
		_Stroke = 2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -10, 0, 34),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 5,
		_MaxTextSize = 24,
	})
	local check = UiKit.ThemeIcon(c, "Check", "Check", "@Check", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(70, 70),
		Visible = false,
		ZIndex = 7,
	})
	UiKit.PaintShape(check.Emoji:FindFirstChild("Shape"), Color3.fromRGB(40, 220, 60))
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TextStroke"
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(10, 40, 10)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = check.Emoji
	local brackets = UiKit.Group(c, "Brackets", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 18, 1, 18),
		Visible = false,
		ZIndex = 8,
	})
	for _, corner in { "TL", "TR", "BL", "BR" } do
		bracket(brackets, corner)
	end
	-- Подпись под карточкой («1 MIN», как «Day 3» на референсе).
	UiKit.Text(c, "Day", "1 MIN", {
		_Style = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = Color3.fromRGB(225, 225, 230),
		ZIndex = 4,
	})
	return c
end

function Builder.Build()
	local gui = UiKit.Screen("DailyRewardUi", {
		DisplayOrder = 500,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})

	local toggle = UiKit.PlateButton(gui, "DailyToggleButton", "Round", { Size = UDim2.fromOffset(44, 44) })
	-- v20.21: иконка — ImageLabel "Icon" (UiTheme.Icons.Rewards или Image в Studio).
	UiKit.ThemeIcon(toggle, "Icon", "Rewards", "🎁", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 2,
	})
	UiKit.Badge(toggle, "Badge", "", { Size = UDim2.fromOffset(12, 12), Position = UDim2.new(1, -4, 0, 4), Visible = false })

	UiKit.Dimmer(gui)

	local size = Builder.SIZE
	local panel = UiKit.New("ImageLabel", {
		Name = "Panel",
		BackgroundTransparency = 1,
		Image = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Visible = false,
		ZIndex = 2,
	}, gui)
	panel:SetAttribute("BaseWidth", size.X)
	panel:SetAttribute("BaseHeight", size.Y)
	UiKit.Scale(panel, "ResponsiveScale", 1)

	UiKit.TitleText(panel, "Title", "Playtime Rewards!", "Gold", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, -60, 0, 56),
		ZIndex = 3,
	})

	local strip = UiKit.Plate(panel, "Strip", "Panel", {
		_Accent = "Gold",
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 2 * (Builder.CARD.Y + 40) + 20),
		ZIndex = 2,
	})
	local c, g = Builder.CARD, Builder.GAP
	local rowWidth4 = 4 * c.X + 3 * g
	local rowWidth3 = 3 * c.X + 2 * g
	for day = 1, 7 do
		local row = day <= 4 and 0 or 1
		local column = day <= 4 and (day - 1) or (day - 5)
		local rowWidth = row == 0 and rowWidth4 or rowWidth3
		local x = math.floor((size.X - rowWidth) / 2) + column * (c.X + g)
		local y = 12 + row * (c.Y + 42)
		card(strip, day, UDim2.fromOffset(x, y))
	end

	UiKit.CloseButton(panel, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0, 30),
		ZIndex = 9,
	})

	UiKit.Button(panel, "ClaimButton", "Claim", "Claim", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(340, 54),
		ZIndex = 3,
		_TextStyle = "Title",
	})
	return gui
end

return Builder
