--------------------------------------------------------------------------------
-- BuildRebirthDialogUI — Studio Command Bar: StarterGui/RebirthDialogButtons
-- (окно престижа у NPC: условия слева, что получишь справа).
-- Вид — Shared.PrestigeUiBuilder. Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("PrestigeUiBuilder")
assert(module, "[BuildRebirthDialogUI] Нет Shared.PrestigeUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("RebirthDialogButtons")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildRebirthDialogUI] Готово: StarterGui/RebirthDialogButtons.")
