--------------------------------------------------------------------------------
-- BuildBoulderGameUI — Studio Command Bar: собирает StarterGui/BoulderGameUi
-- (мини-игра валунов). Сборка — в ReplicatedStorage.Shared.BoulderGameUiBuilder.
--   1. Rojo-синк. 2. Вставить файл в Command Bar и выполнить.
--   3. Править вид мышкой. Картинки: Panel/Track/TrackImage (полоса),
--      Panel/Track/Runner/RunnerImage (бегунок). Имена не менять.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("BoulderGameUiBuilder")
assert(module, "[BuildBoulderGameUI] Нет Shared.BoulderGameUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("BoulderGameUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildBoulderGameUI] Готово: StarterGui/BoulderGameUi.")
