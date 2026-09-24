--------------------------------------------------------------------------------
-- BuildPerkUI — Studio Command Bar: собирает StarterGui/PerkUi (окно
-- чемоданчика перков престижа). Сборка — Shared.PerkUiBuilder.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("PerkUiBuilder")
assert(module, "[BuildPerkUI] Нет Shared.PerkUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("PerkUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildPerkUI] Готово: StarterGui/PerkUi.")
