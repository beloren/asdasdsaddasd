local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local MODALS_BY_GUI = {
	CollectionMenu = { "Submenu", "MutationBookPanel" },
	DailyRewardUi = { "Panel" },
	-- OpeningOverlay — см. тот же список в CustomCartUI.client.lua: во время
	-- анимации вскрытия жеоды остальные панели скрыты, и без него сторож
	-- считал окно закрытым, хотя оно на весь экран.
	GeodeUi = { "VaultPanel", "PodiumPanel", "BuyGeodesPanel", "OpenCountMenu", "OpeningOverlay" },
	GroupRewardUi = { "Gift", "GiftHalfLeft", "GiftHalfRight", "Card" },
	LikeRewardUi = { "Gift", "GiftHalfLeft", "GiftHalfRight", "Card" },
	ShopUi = { "Panel" },
	SkinUi = { "Panel" },
	PerkUi = { "Panel" }, -- v8: чемоданчик перков престижа
	StarterPackOffer = { "Details" },
}

local function hasVisibleModal(gui, modalNames)
	for _, name in modalNames do
		local modal = gui:FindFirstChild(name, true)
		if modal and modal:IsA("GuiObject") and modal.Visible then
			return true
		end
	end
	return false
end

local function clearOrphanedDimmer(gui)
	local modalNames = MODALS_BY_GUI[gui.Name]
	if not modalNames then return end
	local dimmer = gui:FindFirstChild("Dimmer", true)
	if not dimmer or not dimmer:IsA("GuiObject") or not dimmer.Visible then return end
	if (gui:IsA("ScreenGui") and not gui.Enabled) or not hasVisibleModal(gui, modalNames) then
		dimmer.Visible = false
	end
end

--------------------------------------------------------------------------------
-- СТРАХОВКА ОТ «НЕ НАЖИМАЕТСЯ КРЕСТИК, ИЗ МЕНЮ НЕ ВЫЙТИ».
--
-- Dimmer в этих меню — полноэкранная КНОПКА (а не Frame), и ZIndex ей
-- обычно никто не задаёт, то есть он равен 1. Если у панели или её
-- крестика в собранном в Studio ассете ZIndex тоже оставлен по умолчанию,
-- затемнение оказывается с ними на одном уровне и выигрывает по порядку
-- потомков — нажатия до крестика просто не доходят. На тач-экране это
-- воспроизводится стабильно, на мышке иногда «проскакивает».
--
-- GeodeUI чинит это у себя сам (см. normalizeDimmerLayer там), но такое же
-- затемнение есть у ВСЕХ меню из списка выше, и собраны они одинаково.
-- Поэтому здесь — общая страховка на все окна разом: раз в 0.2 секунды
-- следим, что видимое затемнение лежит строго ниже своих соседей.
-- Идемпотентно и стоит копейки: если ZIndex уже правильный, ничего не
-- пишем.
local function keepDimmerBelowPanels(gui)
	if not MODALS_BY_GUI[gui.Name] then return end
	local dimmer = gui:FindFirstChild("Dimmer", true)
	if not dimmer or not dimmer:IsA("GuiObject") or not dimmer.Visible then return end
	local parent = dimmer.Parent
	if not parent then return end
	local lowest = nil
	for _, sibling in parent:GetChildren() do
		if sibling ~= dimmer and sibling:IsA("GuiObject") then
			lowest = lowest and math.min(lowest, sibling.ZIndex) or sibling.ZIndex
		end
	end
	if lowest and dimmer.ZIndex >= lowest then
		dimmer.ZIndex = lowest - 1
	end
end

local function clearSpecialOverlays()
	local tutorial = playerGui:FindFirstChild("InteractiveTutorial")
	if tutorial and Players.LocalPlayer:GetAttribute("NeedsTutorial") ~= true then
		local finaleDimmer = tutorial:FindFirstChild("FinaleDimmer", true)
		if finaleDimmer and finaleDimmer:IsA("GuiObject") then finaleDimmer.Visible = false end
	end

	local geodeGui = playerGui:FindFirstChild("GeodeUi")
	if geodeGui then
		local backdrop = geodeGui:FindFirstChild("CollectionContextBackdrop", true)
		local context = geodeGui:FindFirstChild("CollectionContext", true)
		if backdrop and backdrop:IsA("GuiObject") and backdrop.Visible
			and (not context or not context:IsA("GuiObject") or not context.Visible) then
			backdrop.Visible = false
		end
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.2 then return end
	elapsed = 0
	for guiName in MODALS_BY_GUI do
		local gui = playerGui:FindFirstChild(guiName)
		if gui then
			clearOrphanedDimmer(gui)
			keepDimmerBelowPanels(gui)
		end
	end
	clearSpecialOverlays()
end)
