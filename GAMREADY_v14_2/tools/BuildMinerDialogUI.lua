--------------------------------------------------------------------------------
-- BuildMinerDialogUI — Studio Command Bar: собирает StarterGui/MinerDialogUi —
-- диалог шахтёра в стиле Grow a Garden (реплика справа от шахтёра + ответы).
--
-- Сборка живёт в ReplicatedStorage.Shared.MinerDialogUiBuilder (тот же модуль
-- использует клиент, если в StarterGui нет свежей версии).
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo).
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Править вид мышкой. Choices/ChoiceTemplate — шаблон кнопки ответа,
--      должен остаться Visible = false. Сдвиг облачка от шахтёра —
--      MinerDialogUi.StudsOffset (X — вправо по экрану, Y — вверх).
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("MinerDialogUiBuilder")
assert(module, "[BuildMinerDialogUI] Нет ReplicatedStorage.Shared.MinerDialogUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)
local existing = StarterGui:FindFirstChild("MinerDialogUi")
if existing then existing:Destroy() end
local gui = Builder.Build()
gui.Parent = StarterGui
print(("[BuildMinerDialogUI] Готово: StarterGui/MinerDialogUi (версия %d)."):format(Builder.VERSION))
