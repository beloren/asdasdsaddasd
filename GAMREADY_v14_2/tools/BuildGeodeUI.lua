--------------------------------------------------------------------------------
-- BuildGeodeUI — Studio Command Bar: собирает StarterGui/GeodeUi (хранилище
-- жеод, покупка, вскрытие, меню «сколько открыть» + подиум банка).
-- Вид: Shared.GeodeUiBuilder («аметистовая пещера») и
-- Shared.BankPodiumUiBuilder («изумрудный сейф»). Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("GeodeUiBuilder")
assert(module, "[BuildGeodeUI] Нет Shared.GeodeUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("GeodeUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildGeodeUI] Готово: StarterGui/GeodeUi.")
