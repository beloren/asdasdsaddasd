--------------------------------------------------------------------------------
-- BuildMineArcUI — Studio Command Bar: собирает StarterGui/MineArcUi —
-- интерфейс мини-игры "РУДНАЯ ЖИЛА" (вариант A).
--
-- Сама сборка живёт в ReplicatedStorage.Shared.MineVeinUiBuilder (тот же
-- модуль использует клиент, если в StarterGui нет свежей версии), поэтому
-- вид в Studio и в игре всегда совпадает.
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo), чтобы модуль был в Shared.
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Подставить свои картинки (ImageLabel с пустым Image):
--        Container/Vein/VeinImage            — рудная жила (фон полосы)
--        Container/Vein/GoodZoneTemplate     — кристальная зона (GOOD)
--        Container/Vein/PerfectZoneTemplate  — самородок (PERFECT)
--        Container/Vein/Pick                 — кирка-бегунок
--        Container/HitPips/Pip1..3           — кружки результатов
--      Как только у ImageLabel задан Image, клиент прячет его запасные
--      плашки (камешки, блики, рукоять) и делает фон прозрачным. Зоны
--      тянутся по ширине — для них удобнее ScaleType = Slice.
--   Шаблоны зон должны оставаться Visible = false — клиент их клонирует.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("MineVeinUiBuilder")
assert(module, "[BuildMineArcUI] Нет ReplicatedStorage.Shared.MineVeinUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)

local existing = StarterGui:FindFirstChild("MineArcUi")
if existing then
	existing:Destroy()
end

local gui = Builder.Build()
gui.Parent = StarterGui

print(("[BuildMineArcUI] Готово: StarterGui/MineArcUi (версия %d). Подставь картинки в ImageLabel'ы — см. шапку скрипта."):format(Builder.VERSION))
