--------------------------------------------------------------------------------
-- BuildNotificationUI — Studio Command Bar: собирает StarterGui/Toast —
-- уведомления в стиле Grow a Garden (v14.3: компактные карточки сверху по
-- центру, на экране максимум две, очередь ускоряется, дубли склеиваются).
--
-- Сама сборка живёт в ReplicatedStorage.Shared.ToastUiBuilder (тот же
-- модуль использует клиент, если в StarterGui нет свежей версии), поэтому
-- вид в Studio и в игре всегда совпадает.
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo), чтобы модуль был в Shared.
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Править вид мышкой: Toast/Stack/Panel — шаблон одной карточки.
--      Размер карточки клиент берёт из шаблона. Свою подложку — в
--      Panel/Skin.Image (ScaleType = Slice). Шаблон должен остаться
--      Visible = false — клиент его клонирует.
--   Позиция стопки на экране — Toast/Stack.Position.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("ToastUiBuilder")
assert(module, "[BuildNotificationUI] Нет ReplicatedStorage.Shared.ToastUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)

local existing = StarterGui:FindFirstChild("Toast")
if existing then existing:Destroy() end

local gui = Builder.Build()
gui.Parent = StarterGui

print(("[BuildNotificationUI] Готово: StarterGui/Toast (версия %d). Шаблон карточки — Toast/Stack/Panel."):format(Builder.VERSION))
