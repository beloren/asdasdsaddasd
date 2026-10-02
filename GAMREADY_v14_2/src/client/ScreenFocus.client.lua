--------------------------------------------------------------------------------
-- ScreenFocus (LocalScript) v20.106 — БОЛЬШИЕ ОКНА ПОВЕРХ ВСЕГО.
-- Пока открыто окно почти на весь экран (магазин, торговец, прокачка,
-- жеоды, острова, перки, коллекция, настройки, сундук, окно тележки…),
-- остальной интерфейс (HUD, хотбар, квесты, баффы, лента, топбар) прячется
-- целиком, а мир позади размывается (BlurEffect). Закрыл - всё на месте.
-- Окно считается открытым, если у его ScreenGui видна дочерняя рамка,
-- закрывающая заметную часть экрана (Config.UI.FocusMinArea).
-- Мини-игры (шахта, валун, раскол жеоды) не трогаются.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = Config.UI or {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FULLSCREEN = {}
for _, name in UI.FocusGuis or {
	"ShopUi", "UpgradeShopUi", "SettingsMenu", "DailyRewardUi", "CollectionMenu", "SkinUi", "PerkUi",
	"MerchantUi", "GeodeUi", "DropPreviewUi", "DecorStorageUi", "CartInventoryUi", "IslandUi", "GearUi",
	"OfferUi", "ReturnScreenUi", "StarterPackOffer", "GroupRewardUi", "LikeRewardUi", "SatchelInventory",
	"CompassUi", -- v20.122: карта мира тоже прячет весь остальной интерфейс
} do FULLSCREEN[name] = true end

local HIDE = {}
for _, name in UI.FocusHide or {
	"Hud", "TopbarDock", "HotbarUi", "BuffBar", "LootFeedUi", "QuestUi", "SocialHud", "QuestMarkerUi",
	"MobileShiftLockButton", "OrePreviewHud", "RubbleCrystalHotbar", "MarketTicker", "CartInteractionUi",
	"PlacementUi", "CombatUi", "StarterPackOffer",
	"CollectionMenu", "CompassUi", -- v20.120: книга-меню и компас тоже прячутся
	"OfferUi", "Toast", "RebirthDialogButtons", -- v20.122: донат-подсказки справа и всплывашки тоже
} do HIDE[name] = true end

-- Дочерние рамки, которые окном НЕ считаются (оверлей раскола - мини-игра).
local IGNORE_CHILD = { OpeningOverlay = true, Templates = true, Banner = true }
local MIN_AREA = UI.FocusMinArea or 0.3

local blur = Instance.new("BlurEffect")
blur.Name = "ScreenFocusBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local focusedBy = nil -- ScreenGui, которое сейчас держит фокус
local wanted = {}     -- [ScreenGui] = true - мы его спрятали, вернуть при закрытии

local function inMinigame()
	return player:GetAttribute("MineExpeditionActive") == true
		or player:GetAttribute("BoulderGameActive") == true
end

local function isOpen(gui)
	if not (gui:IsA("ScreenGui") and gui.Enabled) then return false end
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local screen = math.max(1, view.X * view.Y)
	local overlay = gui:FindFirstChild("OpeningOverlay")
	if overlay and overlay:IsA("GuiObject") and overlay.Visible then return false end -- идёт раскол жеоды (мини-игра)
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and not IGNORE_CHILD[child.Name] then
			local size = child.AbsoluteSize
			if size.X * size.Y >= screen * MIN_AREA then
				local drawn = child.BackgroundTransparency < 1
					or ((child:IsA("ImageLabel") or child:IsA("ImageButton")) and child.Image ~= "" and child.ImageTransparency < 1)
				if drawn then return true end
			end
		end
	end
	return false
end

local function setBlur(on)
	if on then blur.Enabled = true end
	local tween = TweenService:Create(blur, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = on and (UI.FocusBlurSize or 16) or 0 })
	tween:Play()
	if not on then
		tween.Completed:Connect(function()
			if not focusedBy then blur.Enabled = false end
		end)
	end
end

-- v20.122: ПРЯЧЕМ НЕ МГНОВЕННО - верхние элементы экрана уезжают к
-- ближайшему краю, и только потом экран выключается; при закрытии окна
-- экран включается и элементы приезжают обратно.
local SLIDE = TweenInfo.new(UI.FocusSlideSeconds or 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_BACK = TweenInfo.new(UI.FocusSlideSeconds or 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local homes = {}  -- [GuiObject] = исходная позиция
local expectFalse -- см. guard ниже
local token = 0

local function offscreen(element)
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local size, centre = element.AbsoluteSize, element.AbsolutePosition + element.AbsoluteSize / 2
	local best, edge = math.huge, "Bottom"
	for name, value in { Left = centre.X, Right = view.X - centre.X, Top = centre.Y, Bottom = view.Y - centre.Y } do
		if value < best then best, edge = value, name end
	end
	local current = element.Position
	if edge == "Left" then return current - UDim2.fromOffset(size.X + 40, 0) end
	if edge == "Right" then return current + UDim2.fromOffset(size.X + 40, 0) end
	if edge == "Top" then return current - UDim2.fromOffset(0, size.Y + 40) end
	return current + UDim2.fromOffset(0, size.Y + 40)
end

-- v20.128: НАМЕРЕНИЯ СКРИПТОВ, пока экран спрятан под окном. Скрипт сам
-- закрыл экран (всплывашка, предложение) - после окна его НЕ включаем.
-- Скрипт включил его снова - прячем дальше, но после окна вернём.
expectFalse = {}
local closedByScript = {}
local guards = {}
local function guard(gui)
	if guards[gui] then return end
	guards[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not wanted[gui] then return end
		if gui.Enabled then
			closedByScript[gui] = nil
			if gui:GetAttribute("FocusHidden") == true and focusedBy then
				expectFalse[gui] = true
				gui.Enabled = false
			end
		elseif expectFalse[gui] then
			expectFalse[gui] = nil
		else
			closedByScript[gui] = true
		end
	end)
end

local function slideOut(gui)
	local myToken = token
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			if homes[child] == nil then
				-- v20.128: элемент мог уже уехать по диалогу обучения (CinematicHud) -
				-- его настоящий дом лежит в атрибуте CinematicHome
				local cinematicHome = child:GetAttribute("CinematicHome")
				homes[child] = typeof(cinematicHome) == "UDim2" and cinematicHome or child.Position
				child:SetAttribute("FocusHome", homes[child])
			end
			TweenService:Create(child, SLIDE, { Position = offscreen(child) }):Play()
		end
	end
	task.delay(SLIDE.Time, function()
		-- окно уже закрыли, пока ехали - экран не выключаем
		if myToken == token and wanted[gui] and gui.Parent and gui.Enabled then
			expectFalse[gui] = true
			gui.Enabled = false
		end
	end)
end

local function slideIn(gui)
	gui.Enabled = true
	for _, child in gui:GetChildren() do
		local home = homes[child]
		if home then
			homes[child] = nil
			child:SetAttribute("FocusHome", nil)
			-- диалог обучения ещё держит HUD у краёв - вернёт его сам CinematicHud
			if typeof(child:GetAttribute("CinematicHome")) ~= "UDim2" then
				local layoutPosition = child:GetAttribute("LayoutPosition")
				TweenService:Create(child, SLIDE_BACK, { Position = typeof(layoutPosition) == "UDim2" and layoutPosition or home }):Play()
			end
		end
	end
end

local function release()
	focusedBy = nil
	token += 1
	for gui in wanted do
		gui:SetAttribute("FocusHidden", nil)
		if guards[gui] then guards[gui]:Disconnect() guards[gui] = nil end
		if gui.Parent and closedByScript[gui] then
			-- скрипт сам закрыл экран: остаётся выключенным, но элементы на местах
			for _, child in gui:GetChildren() do
				local home = homes[child]
				if home then
					homes[child] = nil
					child:SetAttribute("FocusHome", nil)
					child.Position = home
				end
			end
		elseif gui.Parent then
			slideIn(gui)
		end
	end
	table.clear(wanted)
	table.clear(closedByScript)
	table.clear(expectFalse)
	for element in homes do
		if not element.Parent then homes[element] = nil end
	end
	setBlur(false)
end

while true do
	task.wait(0.12)
	local opener = nil
	if not inMinigame() then
		for _, gui in playerGui:GetChildren() do
			if FULLSCREEN[gui.Name] and isOpen(gui) then
				opener = gui
				break
			end
		end
	end
	if opener then
		if not focusedBy then setBlur(true) end
		focusedBy = opener
		for _, gui in playerGui:GetChildren() do
			if gui ~= opener and HIDE[gui.Name] and gui:IsA("ScreenGui") and gui.Enabled and not wanted[gui] then
				wanted[gui] = true
				guard(gui)
				gui:SetAttribute("FocusHidden", true) -- v20.112: сторожа (EnsureCoreUiEnabled) не включают обратно
				slideOut(gui)
			end
		end
	elseif focusedBy then
		release()
	else
		-- v20.130: СТОРОЖ. Окон нет, а что-то осталось спрятанным/уехавшим -
		-- вернуть. Кнопки больше не могут «закатиться и не вернуться».
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") then
				if gui:GetAttribute("FocusHidden") == true then
					gui:SetAttribute("FocusHidden", nil)
					gui.Enabled = true
				end
				for _, child in gui:GetChildren() do
					local home = child:IsA("GuiObject") and child:GetAttribute("FocusHome")
					if typeof(home) == "UDim2" then
						child:SetAttribute("FocusHome", nil)
						homes[child] = nil
						if typeof(child:GetAttribute("CinematicHome")) ~= "UDim2" then
							TweenService:Create(child, SLIDE_BACK, { Position = home }):Play()
						end
					end
				end
			end
		end
	end
end
