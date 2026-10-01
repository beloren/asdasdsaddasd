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
} do FULLSCREEN[name] = true end

local HIDE = {}
for _, name in UI.FocusHide or {
	"Hud", "TopbarDock", "HotbarUi", "BuffBar", "LootFeedUi", "QuestUi", "SocialHud", "QuestMarkerUi",
	"MobileShiftLockButton", "OrePreviewHud", "RubbleCrystalHotbar", "MarketTicker", "CartInteractionUi",
	"PlacementUi", "CombatUi", "StarterPackOffer",
	"CollectionMenu", "CompassUi", -- v20.120: книга-меню и компас тоже прячутся
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

local function release()
	focusedBy = nil
	for gui in wanted do
		gui:SetAttribute("FocusHidden", nil)
		if gui.Parent then gui.Enabled = true end
	end
	table.clear(wanted)
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
			if gui ~= opener and HIDE[gui.Name] and gui:IsA("ScreenGui") and gui.Enabled then
				wanted[gui] = true
				gui:SetAttribute("FocusHidden", true) -- v20.112: сторожа (EnsureCoreUiEnabled) не включают обратно
				gui.Enabled = false
			end
		end
	elseif focusedBy then
		release()
	end
end
