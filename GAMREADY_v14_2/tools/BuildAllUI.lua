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
local ONLY = {}

-- true = НЕ трогать экраны, которые уже есть в StarterGui и собраны этой
-- версией билдера (UiKitVersion совпадает). Удобно, чтобы добавить новые
-- экраны, не сбрасывая уже отредактированные.
local SKIP_EXISTING = false

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
assert(shared and shared:FindFirstChild("UiRegistry"), "[BuildAllUI] Нет ReplicatedStorage.Shared.UiRegistry — сначала синхронизируй проект через Rojo.")
local UiRegistry = require(shared.UiRegistry)

-- Устаревшие экраны прошлых версий (заменены новыми или больше не нужны).
local LEGACY = {
	"PreloadScreen", "ShopEntry", "SkinEntry", "InventoryEntry", "InventoryUi", "UpgradeShopV3", "ActionButtons", "PickaxeHotbar",
	"GamepassQuickBar", "UpgradeShopCards", "TutorialObjectiveCard", "MutationBookUi",
	"PreviewGroupReward", "PreviewLikeReward", "OpenDropPreview",
}
for _, name in LEGACY do
	local old = StarterGui:FindFirstChild(name)
	if old and old:IsA("ScreenGui") then
		old:Destroy()
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
