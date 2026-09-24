-- Standalone Command Bar builder for StarterGui/CollectionMenu.
-- Rebuilds BookButton, Dimmer and Submenu, but leaves MutationBookPanel intact.
--
-- ПОСЛЕ запуска: в Explorer найдёшь StarterGui → CollectionMenu → BookButton.
-- Дальше делай с ним что хочешь прямо в Studio:
--   • Своя иконка — вставь картинку в свойство Image (или просто задай
--     Config.UI.CollectionBookImageId в Config.lua, оба варианта работают).
--   • Своя позиция — перетащи мышкой в 2D-редакторе (или поменяй Position/
--     AnchorPoint в Properties). Игра подхватит её как есть и БОЛЬШЕ НЕ
--     БУДЕТ пересчитывать координаты сама — раз кнопка своя, её место
--     целиком на твоей стороне.
--   • Свой размер/поворот — тоже просто свойства (Size/Rotation), меняй
--     как обычный ImageButton.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local function imageUri(id)
	return id and id ~= 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local gui = StarterGui:FindFirstChild("CollectionMenu")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "CollectionMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95 -- выше InteractiveTutorial (90), иначе карточка гайда перехватывает клики поверх кнопки во время обучения
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.ClipToDeviceSafeArea = true
	end)
	gui.Parent = StarterGui
end

local existingButton = gui:FindFirstChild("BookButton")
if existingButton then existingButton:Destroy() end
for _, name in { "Dimmer", "Submenu" } do
	local existing = gui:FindFirstChild(name)
	if existing then existing:Destroy() end
end

local bookButton = Instance.new("ImageButton")
bookButton.Name = "BookButton"
bookButton.AnchorPoint = Vector2.new(0, 0.5)
bookButton.Position = UDim2.new(0, 14, 0.5, -26) -- стартовая позиция — там же, где была шестерёнка настроек; дальше просто перетаскивай
bookButton.Size = UDim2.fromOffset(52, 52)
bookButton.Rotation = -14
bookButton.BackgroundTransparency = 1
bookButton.AutoButtonColor = false
bookButton.ScaleType = Enum.ScaleType.Fit
bookButton.Parent = gui

-- Плейсхолдер-вид, пока не вставишь свою картинку в Image — просто
-- коричневая книжка с закладкой, тот же стиль, что у остальных
-- плейсхолдеров проекта.
bookButton.BackgroundColor3 = Color3.fromRGB(150, 100, 55)
bookButton.BackgroundTransparency = 0
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = bookButton
local bookmark = Instance.new("Frame")
bookmark.Name = "BookmarkPlaceholder" -- удали этот Frame сам, если вставишь свою картинку в Image — он тут только чтобы плейсхолдер не выглядел пустым квадратом
bookmark.AnchorPoint = Vector2.new(0.5, 0)
bookmark.Position = UDim2.new(0.75, 0, 0, -6)
bookmark.Size = UDim2.fromOffset(10, 22)
bookmark.BackgroundColor3 = Color3.fromRGB(210, 60, 90)
bookmark.BorderSizePixel = 0
bookmark.ZIndex = 2
bookmark.Parent = bookButton

local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 0.5
dimmer.BorderSizePixel = 0
dimmer.AutoButtonColor = false
dimmer.Text = ""
dimmer.Visible = false
dimmer.ZIndex = 5
dimmer.Parent = gui

local submenu = Instance.new("ImageLabel")
submenu.Name = "Submenu"
submenu.AnchorPoint = Vector2.new(0.5, 0.5)
submenu.Position = UDim2.fromScale(0.5, 0.5)
submenu.Size = UDim2.fromOffset(360, 340)
submenu.BackgroundColor3 = Color3.fromRGB(45, 140, 220)
submenu.BorderSizePixel = 0
submenu.Image = "" -- Фоновая текстура всей панели: rbxassetid://ID
submenu.ScaleType = Enum.ScaleType.Stretch
submenu.Visible = false
submenu.ZIndex = 6
submenu.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "MobileSubmenuScale"
scale.Parent = submenu

local header = Instance.new("ImageLabel")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundColor3 = Color3.fromRGB(35, 90, 165)
header.BorderSizePixel = 0
header.Image = "" -- Текстура шапки: rbxassetid://ID
header.ScaleType = Enum.ScaleType.Stretch
header.ZIndex = 7
header.Parent = submenu

local headerTitle = Instance.new("TextLabel")
headerTitle.Name = "Title"
headerTitle.Position = UDim2.fromOffset(16, 0)
headerTitle.Size = UDim2.new(1, -64, 1, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Font = Enum.Font.Arcade
headerTitle.Text = "COLLECTION MENU"
headerTitle.TextColor3 = Color3.new(1, 1, 1)
headerTitle.TextScaled = true
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.TextStrokeTransparency = 0
headerTitle.ZIndex = 8
headerTitle.Parent = header

local close = Instance.new("TextButton")
close.Name = "CloseButton"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 10)
close.Size = UDim2.fromOffset(30, 30)
close.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
close.BorderSizePixel = 0
close.Font = Enum.Font.Arcade
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.TextScaled = true
close.ZIndex = 9
close.Parent = submenu

local list = Instance.new("Frame")
list.Name = "List"
list.Position = UDim2.fromOffset(20, 64)
list.Size = UDim2.new(1, -40, 1, -74)
list.BackgroundTransparency = 1
list.ZIndex = 6
list.Parent = submenu
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local items = {
	{ Key = "Inventory", Label = "INVENTORY", Icon = "InventoryMenuIconId" },
	{ Key = "Shop", Label = "SHOP", Icon = "ShopMenuIconId" },
	{ Key = "Skins", Label = "SKINS", Icon = "SkinsMenuIconId" },
	{ Key = "Settings", Label = "SETTINGS", Icon = "SettingsMenuIconId" },
	{ Key = "Mutations", Label = "MUTATIONS", Icon = "MutationsMenuIconId" },
}
for order, item in items do
	local row = Instance.new("TextButton")
	row.Name = item.Key .. "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = Color3.new(1, 1, 1)
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	row.ZIndex = 6
	row.Parent = list

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Size = UDim2.fromOffset(36, 36)
	icon.BackgroundColor3 = Color3.fromRGB(220, 220, 230)
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = imageUri(Config.UI[item.Icon])
	icon.ZIndex = 7
	icon.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 60, 0.5, 0)
	label.Size = UDim2.new(1, -72, 1, -12)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.Text = item.Label
	label.TextColor3 = Color3.fromRGB(60, 60, 70)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 7
	label.Parent = row
end

print("[BuildCollectionMenu] Done: editable Submenu created. Set Submenu.Image for the background and Submenu/Header.Image for the header.")
