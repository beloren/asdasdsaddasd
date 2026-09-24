--------------------------------------------------------------------------------
-- BuildCombatUI — Studio Command Bar: собирает StarterGui/CombatUi —
-- интерфейс PvP v2: шкала оглушения над головой, значок WANTED,
-- комбо-счётчик атакующего и крупные надписи (KNOCKDOWN!/CLASH!).
--
-- Сама сборка живёт в ReplicatedStorage.Shared.CombatUiBuilder (тот же
-- модуль использует клиент, если в StarterGui нет свежей версии), поэтому
-- вид в Studio и в игре всегда совпадает.
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo), чтобы модуль был в Shared.
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Править вид мышкой в StarterGui/CombatUi:
--        StaggerTemplate/Bar/PipTemplate      — деление шкалы (Fill — заливка)
--        StaggerTemplate/State                — надпись "STUNNED!"
--        StaggerTemplate/Wanted               — значок награды
--        StaggerTemplate/Wanted/Icon          — поставь картинку мешка денег,
--                                               клиент сам её покажет
--        ComboCounter, Popup                  — экранные надписи
--   Имена объектов не переименовывай — по ним клиент находит элементы.
--   PipTemplate должен оставаться Visible = false — клиент его клонирует.
--   Если поднимешь Config.Stagger.UiVersion, клиент перестанет брать
--   устаревшую копию из StarterGui и соберёт свежую сам, пока не
--   перезапустишь этот билдер.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("CombatUiBuilder")
assert(module, "[BuildCombatUI] Нет ReplicatedStorage.Shared.CombatUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)

local existing = StarterGui:FindFirstChild("CombatUi")
if existing then
	existing:Destroy()
end

local gui = Builder.Build()
gui.Parent = StarterGui

print("[BuildCombatUI] Готово: StarterGui/CombatUi собран. Правь вид мышкой, имена не трогай.")
