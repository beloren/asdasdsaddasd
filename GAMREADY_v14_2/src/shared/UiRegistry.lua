--------------------------------------------------------------------------------
-- UiRegistry — список ВСЕХ экранов игры и их билдеров (v20).
--
-- • tools/BuildAllUI.lua проходит по этому списку и кладёт каждый ScreenGui
--   в StarterGui. Дальше UI правится мышкой в Studio — игра берёт именно
--   то, что лежит в StarterGui (Roblox копирует его в PlayerGui).
-- • Клиентские скрипты получают свой экран через UiRegistry.Get(name):
--     1) экран есть в StarterGui → ждём его копию в PlayerGui;
--     2) нет (билдер не запускали) → собираем тем же билдером на лету,
--        чтобы игра не ломалась.
--   Если копия в StarterGui СТАРШЕ минимальной версии (UiKitVersion <
--   MinVersion — осталась от прошлых билдеров со старыми именами), она
--   заменяется свежей сборкой и в Output пишется просьба перезапустить
--   BuildAllUI.
--
-- Запись: { Name = "<ScreenGui>", Module = "<путь от Shared>", Fn = "Build",
--           MinVersion = 20, What = "описание" }
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = script.Parent

local UiRegistry = {}

UiRegistry.Entries = {
	-- HUD
	{ Name = "Hud", Module = "UiBuilders.HudUi", MinVersion = 20, What = "портрет, деньги, престиж" },
	{ Name = "TopbarDock", Module = "UiBuilders.HudUi", Fn = "BuildTopbar", MinVersion = 21, What = "ряд кнопок в топбаре" },
	{ Name = "CartInteractionUi", Module = "UiBuilders.CartInteractionUi", MinVersion = 20, What = "экранные подсказки промптов" },
	{ Name = "HotbarUi", Module = "UiBuilders.InventoryUi", Fn = "BuildHotbar", MinVersion = 20, What = "хотбар" },
	{ Name = "SatchelInventory", Module = "UiBuilders.InventoryUi", Fn = "BuildSatchel", MinVersion = 20, What = "рюкзак (клавиша ~)" },
	{ Name = "InventoryDragOverlay", Module = "UiBuilders.InventoryUi", Fn = "BuildDragOverlay", MinVersion = 20, What = "слой перетаскивания предметов" },
	{ Name = "BuffBar", Module = "UiBuilders.BuffBarUi", MinVersion = 20, What = "панель баффов" },
	{ Name = "LootFeedUi", Module = "UiBuilders.LootFeedUi", MinVersion = 20, What = "лента добычи" },
	{ Name = "Toast", Module = "ToastUiBuilder", MinVersion = 20, What = "уведомления" },
	{ Name = "QuestUi", Module = "UiBuilders.QuestUi", MinVersion = 25, What = "квесты + трекер" },
	{ Name = "MobileShiftLockButton", Module = "UiBuilders.ShiftLockUi", MinVersion = 20, What = "кнопка шифтлока (телефон)" },
	{ Name = "SocialHud", Module = "UiBuilders.SocialHudUi", MinVersion = 20, What = "кнопка наград за группу/избранное" },
	{ Name = "QuestMarkerUi", Module = "UiBuilders.QuestMarkerUi", MinVersion = 21, What = "стрелка навигации квеста" },

	-- ОКНА
	{ Name = "ShopUi", Module = "UiBuilders.ShopUi", MinVersion = 22, What = "магазин за Robux" },
	{ Name = "UpgradeShopUi", Module = "UiBuilders.UpgradeShopUi", MinVersion = 21, What = "прокачка (Upgrade Mole)" },
	{ Name = "SettingsMenu", Module = "UiBuilders.SettingsUi", MinVersion = 20, What = "настройки и промокоды" },
	{ Name = "DailyRewardUi", Module = "UiBuilders.DailyRewardUi", MinVersion = 22, What = "награды за вход / время" },
	{ Name = "ReturnScreenUi", Module = "UiBuilders.ReturnScreenUi", MinVersion = 20, What = "экран возвращения" },
	{ Name = "StarterPackOffer", Module = "UiBuilders.StarterPackUi", MinVersion = 21, What = "стартовый набор" },
	{ Name = "CollectionMenu", Module = "UiBuilders.CollectionMenuUi", MinVersion = 21, What = "книга-меню" },
	{ Name = "SkinUi", Module = "SkinUiBuilder", MinVersion = 21, What = "скины" },
	{ Name = "PerkUi", Module = "PerkUiBuilder", MinVersion = 22, What = "перки престижа" },
	{ Name = "RebirthDialogButtons", Module = "PrestigeUiBuilder", MinVersion = 21, What = "окно престижа у NPC" },
	{ Name = "MerchantUi", Module = "MerchantUiBuilder", MinVersion = 20, What = "торговец" },
	{ Name = "MarketTicker", Module = "MerchantUiBuilder", Fn = "BuildMarketTicker", MinVersion = 21, What = "табло курса руды" },
	{ Name = "GeodeUi", Module = "GeodeUiBuilder", MinVersion = 23, What = "жеоды" },
	{ Name = "DropPreviewUi", Module = "UiBuilders.DropPreviewUi", MinVersion = 21, What = "окно шансов" },
	{ Name = "DecorStorageUi", Module = "UiBuilders.DecorStorageUi", MinVersion = 22, What = "сундук-хранилище на базе" },
	{ Name = "IslandUi", Module = "UiBuilders.IslandUi", MinVersion = 22, What = "острова и путешествия" },
	{ Name = "GearUi", Module = "GearUiBuilder", MinVersion = 22, What = "снаряжение, лут сундуков" },
	{ Name = "OfferUi", Module = "OfferUiBuilder", MinVersion = 21, What = "предложения" },
	{ Name = "GroupRewardUi", Module = "SocialRewardCard", Fn = "BuildGroup", MinVersion = 20, What = "награда за группу" },
	{ Name = "LikeRewardUi", Module = "SocialRewardCard", Fn = "BuildLike", MinVersion = 20, What = "награда за лайк" },

	-- МИНИ-ИГРЫ И БОЙ
	{ Name = "CombatUi", Module = "CombatUiBuilder", MinVersion = 20, What = "бой" },
	{ Name = "BoulderGameUi", Module = "BoulderGameUiBuilder", MinVersion = 20, What = "мини-игра валуна" },
	{ Name = "MineArcUi", Module = "MineVeinUiBuilder", MinVersion = 20, What = "мини-игра шахты" },
	{ Name = "MinerDialogUi", Module = "MinerDialogUiBuilder", MinVersion = 20, What = "диалог шахтёра" },
	{ Name = "MiningRhythmUi", Module = "UiBuilders.MiningRhythmUi", MinVersion = 20, What = "ритм добычи" },
	{ Name = "TutorialUi", Module = "TutorialUiBuilder", MinVersion = 21, What = "обучение" },
	{ Name = "RubbleCrystalHotbar", Module = "UiBuilders.RubbleCrystalUi", MinVersion = 20, What = "кристалл в руках" },
	{ Name = "OrePreviewHud", Module = "UiBuilders.OrePreviewUi", MinVersion = 20, What = "руда в руках" },
	{ Name = "PlacementUi", Module = "UiBuilders.PlacementUi", MinVersion = 21, What = "подсказки установки" },
	{ Name = "MoneyGainFx", Module = "UiBuilders.MoneyFxUi", MinVersion = 20, What = "«+$X» при начислении денег" },
	{ Name = "RevealCards", Module = "UiBuilders.RevealCardsUi", MinVersion = 20, What = "карточки открытия жеод/сундуков" },
	{ Name = "MobBillboardTemplates", Module = "UiBuilders.MobBillboardsUi", MinVersion = 20, What = "таблички гоблинов и валунов" },
	{ Name = "WorldUiTemplates", Module = "UiBuilders.WorldUi", MinVersion = 21, What = "шаблоны билбордов (мобы, валуны, промпты)" },
}

local byName = {}
for _, entry in UiRegistry.Entries do
	byName[entry.Name] = entry
end

function UiRegistry.Entry(name)
	return byName[name]
end

local function resolveModule(path)
	local node = Shared
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

-- Папка не прячет интерфейс: всё, что лежит в Folder "Templates" внутри
-- ScreenGui, Roblox рисует на экране. Поэтому шаблоны всегда выключены,
-- а клиент включает клон (clone.Visible = true).
local function hideTemplates(root)
	return require(Shared.UiKit).HideTemplates(root)
end
UiRegistry.HideTemplates = hideTemplates

-- Собирает ScreenGui (без родителя). Ошибка билдера → error с понятным текстом.
function UiRegistry.Build(name)
	local entry = byName[name]
	assert(entry, "[UiRegistry] Неизвестный экран: " .. tostring(name))
	local module = resolveModule(entry.Module)
	assert(module, "[UiRegistry] Нет модуля Shared." .. entry.Module)
	local builder = require(module)
	local fn = builder[entry.Fn or "Build"]
	assert(type(fn) == "function", "[UiRegistry] У Shared." .. entry.Module .. " нет функции " .. (entry.Fn or "Build"))
	local gui = fn()
	hideTemplates(gui)
	gui.Name = name
	-- v20.18: не ниже MinVersion реестра. UiKit.Screen ставит общую версию
	-- UiKit (20), и экраны, чей билдер сам свою версию не пишет, после
	-- подъёма MinVersion навсегда считались «старыми» — даже сразу после
	-- BuildAllUI (ложное «собран старым билдером» в Output).
	gui:SetAttribute("UiKitVersion", math.max(tonumber(gui:GetAttribute("UiKitVersion")) or 0, entry.MinVersion or 0))
	return gui
end

local function isFresh(gui, entry)
	return (tonumber(gui:GetAttribute("UiKitVersion")) or 0) >= (entry.MinVersion or 0)
end

-- Клиент: получить экран. Возвращает gui, builtAtRuntime.
function UiRegistry.Get(name, timeout)
	assert(RunService:IsClient(), "[UiRegistry] Get вызывается только на клиенте")
	local entry = byName[name]
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(name)
	local authored = StarterGui:FindFirstChild(name)
	if not gui and authored then
		gui = playerGui:WaitForChild(name, timeout or 30)
	end
	if gui and entry and not isFresh(gui, entry) then
		warn(("[UiRegistry] StarterGui/%s собран старым билдером — собираю новый вид кодом. Запусти tools/BuildAllUI.lua, чтобы править его в Studio."):format(name))
		gui:Destroy()
		gui = nil
	end
	if gui then
		hideTemplates(gui)
		return gui, false
	end
	if not entry then
		return nil, false
	end
	local ok, built = pcall(UiRegistry.Build, name)
	if not ok then
		warn(built)
		return nil, false
	end
	built.Parent = playerGui
	-- Если копия из StarterGui всё-таки придёт позже — убираем дубль.
	local connection
	connection = playerGui.ChildAdded:Connect(function(child)
		if child.Name == name and child ~= built then
			task.defer(function()
				child:Destroy()
			end)
		end
	end)
	built.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return built, true
end

-- Сервер / Studio: собрать всё в target (StarterGui). filter — nil или { [name] = true }.
function UiRegistry.BuildAll(target, filter)
	local report = {}
	for _, entry in UiRegistry.Entries do
		if not filter or filter[entry.Name] then
			local ok, result = pcall(UiRegistry.Build, entry.Name)
			if ok then
				local existing = target:FindFirstChild(entry.Name)
				if existing then
					existing:Destroy()
				end
				result.Parent = target
				table.insert(report, "✔ " .. entry.Name .. " — " .. (entry.What or ""))
			else
				table.insert(report, "✘ " .. entry.Name .. " — " .. tostring(result))
			end
		end
	end
	return report
end

return UiRegistry
