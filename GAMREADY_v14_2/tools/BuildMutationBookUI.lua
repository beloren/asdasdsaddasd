--------------------------------------------------------------------------------
-- BuildMutationBookUI — Studio Command Bar: ставит книгу коллекции
-- (MutationBookPanel) в StarterGui/CollectionMenu. Вид —
-- Shared.CollectionBookUiBuilder («музей кристаллов»). Кнопку-книгу и
-- подменю собирает tools/BuildCollectionMenu.lua. Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("CollectionBookUiBuilder")
assert(module, "[BuildMutationBookUI] Нет Shared.CollectionBookUiBuilder — сначала Rojo-синк.")
local gui = StarterGui:FindFirstChild("CollectionMenu")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "CollectionMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.Parent = StarterGui
end
require(module).Install(gui)
print("[BuildMutationBookUI] Готово: StarterGui/CollectionMenu/MutationBookPanel.")
