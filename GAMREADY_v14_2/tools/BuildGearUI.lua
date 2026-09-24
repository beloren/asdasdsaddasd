--------------------------------------------------------------------------------
-- BuildGearUI — Studio Command Bar: собирает StarterGui/GearUi (панель
-- снаряжения: динамит/сундуки, подсказка прицела, окно лута, табличка
-- таймера сундука). Сборка — ReplicatedStorage.Shared.GearUiBuilder.
-- В SlotTemplate/Image можно поставить общую рамку; иконки предметов клиент
-- берёт из атрибутов GearUi: Icon_Dynamite, Icon_Chest_Common, … (rbxassetid).
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("GearUiBuilder")
assert(module, "[BuildGearUI] Нет Shared.GearUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("GearUi")
if existing then existing:Destroy() end
local gui = require(module).Build()
for _, key in { "Dynamite", "Chest_Common", "Chest_Rare", "Chest_Epic", "Chest_Legendary" } do
	gui:SetAttribute("Icon_" .. key, "")
end
gui.Parent = StarterGui
print("[BuildGearUI] Готово: StarterGui/GearUi.")
