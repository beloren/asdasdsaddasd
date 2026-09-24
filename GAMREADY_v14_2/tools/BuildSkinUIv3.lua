--------------------------------------------------------------------------------
-- BuildSkinUIv3 — Studio Command Bar: собирает НОВОЕ меню скинов
-- StarterGui/SkinUi (карточки → экран с баффами/дебаффами и EQUIP).
-- Заменяет старые BuildSkinUI*.lua. Сборка — Shared.SkinUiBuilder.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("SkinUiBuilder")
assert(module, "[BuildSkinUIv3] Нет Shared.SkinUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("SkinUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildSkinUIv3] Готово: StarterGui/SkinUi (новое меню скинов).")
