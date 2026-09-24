--------------------------------------------------------------------------------
-- CollectionMenuUi — кнопка-книга слева (главное меню) + подменю
-- (Inventory / Shop / Skins / Settings / Mutations) + книга коллекции.
-- Клиент: CollectionMenu.client.lua.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "CollectionMenu"
--   ├─ ImageButton "BookButton" — иконка (UiIcon Book, эмодзи 📖) + подпись "Label"
--   ├─ TextButton "Dimmer"
--   ├─ ImageLabel "Submenu" (окно, акцент Blue) → TitleBar(Title, Ribbon, CloseButton)
--   │    └─ Frame → Body → Frame "List" → ImageButton "<Key>Row" [Card] → "Icon", "Label"
--   └─ ImageLabel "MutationBookPanel" — см. Shared.CollectionBookUiBuilder
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local CollectionBookUiBuilder = require(Shared.CollectionBookUiBuilder)
local Theme = UiKit.Theme

local Builder = {}

Builder.ITEMS = {
	{ Key = "Inventory", Label = "INVENTORY", Icon = "Inventory", Emoji = "🎒", Accent = "Peach" },
	{ Key = "Shop", Label = "SHOP", Icon = "Shop", Emoji = "🛒", Accent = "Purple" },
	{ Key = "Skins", Label = "SKINS", Icon = "Skins", Emoji = "🎨", Accent = "Pink" },
	{ Key = "Settings", Label = "SETTINGS", Icon = "Settings", Emoji = "⚙", Accent = "Teal" },
	{ Key = "Mutations", Label = "MUTATIONS", Icon = "Book", Emoji = "📖", Accent = "Green" },
}

function Builder.Build()
	local gui = UiKit.Screen("CollectionMenu", { DisplayOrder = 95 })
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.ClipToDeviceSafeArea = true
	end)

	-- Кнопка-книга: большая иконка с подписью (как кнопки HUD на референсе).
	local book = UiKit.HudButton(gui, "BookButton", "Menu", { Emoji = "📖", Image = Theme.Icons.Book }, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, -26),
		Size = UDim2.fromOffset(72, 72),
	})
	book.Icon:SetAttribute("UiIcon", "Book")

	UiKit.Dimmer(gui, { ZIndex = 5 })

	local submenu, parts = UiKit.Window(gui, "Submenu", {
		Title = "Menu",
		Accent = "Blue",
		Size = UDim2.fromOffset(380, 450),
		ZIndex = 6,
	})
	UiKit.Scale(submenu, "MobileSubmenuScale", 1)
	local list = UiKit.Group(parts.Body, "List", { ZIndex = 6 })
	UiKit.List(list, { Padding = UDim.new(0, 10) })
	for order, item in Builder.ITEMS do
		local row = UiKit.CardButton(list, item.Key .. "Row", item.Accent, {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 62),
			ZIndex = 6,
		})
		UiKit.ThemeIcon(row, "Icon", item.Icon, item.Emoji, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(42, 42),
			ZIndex = 7,
		})
		UiKit.Text(row, "Label", item.Label, {
			_Style = "Title",
			_Gradient = { UiKit.Accent(item.Accent).Light, UiKit.Accent(item.Accent).Main },
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 68, 0.5, 0),
			Size = UDim2.new(1, -80, 1, -16),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		})
	end

	CollectionBookUiBuilder.Install(gui)
	return gui
end

return Builder
