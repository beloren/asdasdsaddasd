--------------------------------------------------------------------------------
-- BuildAllUI (v20) — ОДИН скрипт, который собирает ВЕСЬ интерфейс игры в
-- StarterGui. Studio → View → Command Bar → вставить этот файл → Enter.
--
-- Все окна строятся билдерами из ReplicatedStorage.Shared (список — в
-- Shared.UiRegistry, стиль — Shared.UiTheme, кирпичики — Shared.UiKit),
-- поэтому сначала синхронизируй проект через Rojo.
--
-- ПОСЛЕ СБОРКИ: разворачивай ScreenGui в StarterGui и правь что угодно —
-- позиции, размеры, цвета, тексты, картинки (все подложки — ImageLabel,
-- поле Image). Игра использует именно то, что лежит в StarterGui. Главное —
-- не переименовывай элементы: скрипты находят их по именам (контракт
-- расписан в шапке каждого билдера в src/shared/UiBuilders и src/shared/*UiBuilder.lua).
--
-- ⚠ ПОВТОРНЫЙ ЗАПУСК пересобирает экраны с нуля — твои ручные правки в них
-- пропадут. Чтобы пересобрать только часть, впиши имена в ONLY. Чтобы
-- поменять только картинки подложек без пересборки — tools/ApplyUiSkins.lua.
--------------------------------------------------------------------------------

-- Пусто = собрать всё. Пример: local ONLY = { "ShopUi", "QuestUi" }
-- Работает, только когда PARTS ниже пустой.
local ONLY = {
	"UpgradeTreeUi",  -- v20.168: дерево Experienced Miner
	"IslandTreeUi",   -- дерево островов Island Keeper
	"PrestigeTreeUi", -- дерево престижа
}

-- v20.155: ТОЛЬКО ДЕТАЛИ. Окно целиком НЕ пересобирается: билдер собирает
-- его в памяти, и в твой StarterGui.<окно> копируются только перечисленные
-- элементы. Если такой элемент уже есть, он заменяется, всё остальное в
-- окне остаётся как ты настроил. Если окна в StarterGui нет, оно ставится
-- целиком. Чтобы вернуть обычную сборку, сделай PARTS = {}.
-- Пример: local PARTS = { GeodeUi = { "SkipButton", "AutoHammerButton", "CrackBallTemplate" } }
local PARTS = {} -- v20.168: сейчас собираются только деревья (ONLY выше)

-- true = НЕ трогать экраны, которые уже есть в StarterGui и собраны этой
-- версией билдера (UiKitVersion совпадает). Удобно, чтобы добавить новые
-- экраны, не сбрасывая уже отредактированные.
local SKIP_EXISTING = false

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
assert(shared and shared:FindFirstChild("UiRegistry"), "[BuildAllUI] Нет ReplicatedStorage.Shared.UiRegistry - сначала синхронизируй проект через Rojo.")
-- Command Bar запоминает однажды загруженные модули и после синхронизации
-- Rojo может отдать СТАРУЮ версию билдеров. Поэтому грузим свежую копию
-- папки Shared (require у клона всегда читает актуальный код).
local freshShared = shared:Clone()
local UiRegistry = require(freshShared.UiRegistry)

if next(PARTS) ~= nil then
	local lines = {}
	for guiName, names in PARTS do
		local ok, built = pcall(UiRegistry.Build, guiName)
		if not ok then
			table.insert(lines, "✘ " .. guiName .. " - " .. tostring(built))
			continue
		end
		local target = StarterGui:FindFirstChild(guiName)
		if not target then
			built.Parent = StarterGui
			table.insert(lines, "✔ " .. guiName .. " - окна не было, поставлено целиком")
			continue
		end
		for _, partName in names do
			local fresh = built:FindFirstChild(partName, true)
			if not fresh then
				table.insert(lines, "✘ " .. guiName .. "." .. partName .. " - нет в билдере")
				continue
			end
			-- куда класть: туда же, где лежит старый элемент, иначе в тот же
			-- путь, что в билдере (например OpeningOverlay)
			local old = target:FindFirstChild(partName, true)
			local parent = old and old.Parent
			if not parent then
				parent = target
				local path = {}
				local node = fresh.Parent
				while node and node ~= built do
					table.insert(path, 1, node.Name)
					node = node.Parent
				end
				for _, step in path do
					parent = parent:FindFirstChild(step) or parent
				end
			end
			if old then old:Destroy() end
			fresh.Parent = parent
			table.insert(lines, "✔ " .. guiName .. "." .. partName .. (old and " - заменён" or " - добавлен") .. " в " .. parent:GetFullName())
		end
		built:Destroy()
	end
	freshShared:Destroy()
	print("[BuildAllUI] Только детали:\n  " .. table.concat(lines, "\n  "))
	do return end
end

-- Устаревшие экраны прошлых версий (заменены новыми или больше не нужны).
local LEGACY = {
	"PreloadScreen", "ShopEntry", "SkinEntry", "InventoryEntry", "InventoryUi", "UpgradeShopV3", "ActionButtons", "PickaxeHotbar",
	"GamepassQuickBar", "UpgradeShopCards", "TutorialObjectiveCard", "MutationBookUi",
	"PreviewGroupReward", "PreviewLikeReward", "OpenDropPreview", "DialogResponses", "IslandShopUi",
	"CartPlacementHud", "PlacementGhostUi", "RubbleCrystalUI", "QuestEdgeArrow",
	"StarterPackOffer", -- v20.129: стартовый набор удалён
}
if #ONLY == 0 then -- при частичной сборке чужие экраны не удаляем
	for _, name in LEGACY do
		local old = StarterGui:FindFirstChild(name)
		if old and old:IsA("ScreenGui") then
			old:Destroy()
		end
	end
end

local filter = nil
if #ONLY > 0 then
	filter = {}
	for _, name in ONLY do
		filter[name] = true
	end
end
if SKIP_EXISTING then
	filter = filter or {}
	for _, entry in UiRegistry.Entries do
		local existing = StarterGui:FindFirstChild(entry.Name)
		local fresh = existing and (tonumber(existing:GetAttribute("UiKitVersion")) or 0) >= (entry.MinVersion or 0)
		if #ONLY == 0 then
			filter[entry.Name] = not fresh
		elseif filter[entry.Name] and fresh then
			filter[entry.Name] = nil
		end
	end
end

local report = UiRegistry.BuildAll(StarterGui, filter)
print("[BuildAllUI] Готово (" .. #report .. "):\n  " .. table.concat(report, "\n  "))

-- Шаблоны (Templates/*) во ВСЕХ экранах StarterGui — выключены: папка GUI не
-- прячет, а включаются они только клонами, когда реально нужны.
-- Цикл встроен сюда (а не вызов модуля): Command Bar может держать в памяти
-- старую версию UiRegistry, в которой этой функции ещё нет.
local hidden = 0
for _, gui in StarterGui:GetChildren() do
	if gui:IsA("ScreenGui") and (not filter or filter[gui.Name]) then
		for _, folder in gui:GetDescendants() do
			if folder:IsA("Folder") and folder.Name == "Templates" then
				for _, child in folder:GetChildren() do
					if child:IsA("GuiObject") and child.Visible then
						child.Visible = false
						hidden += 1
					end
				end
			end
		end
	end
end
print(("[BuildAllUI] Шаблоны в собранных экранах скрыты (выключено сейчас: %d)."):format(hidden))
freshShared:Destroy()
