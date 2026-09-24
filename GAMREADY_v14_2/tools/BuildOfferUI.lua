--------------------------------------------------------------------------------
-- BuildOfferUI — Studio Command Bar: StarterGui/OfferUi (купоны контекстных
-- предложений + кнопка 🚀 Rocket Pickaxe). Вид — Shared.OfferUiBuilder.
-- Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("OfferUiBuilder")
assert(module, "[BuildOfferUI] Нет Shared.OfferUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("OfferUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildOfferUI] Готово: StarterGui/OfferUi.")
