--------------------------------------------------------------------------------
-- ApplyUiSkins (v20) — поставить картинки подложек из Shared.UiTheme во ВЕСЬ
-- интерфейс в StarterGui, НЕ пересобирая его (твои правки позиций, размеров
-- и текстов сохраняются). Command Bar → вставить → Enter.
--
-- Как пользоваться:
--   1. Загрузи картинки (панель, заголовок, кнопки, карточки…) в Asset Manager.
--   2. Впиши их id в src/shared/UiTheme.lua → Theme.Skins.<ключ>.Image
--      (и иконки — в Theme.Icons), синхронизируй Rojo.
--   3. Запусти этот скрипт. Каждый ImageLabel/ImageButton с атрибутом
--      UiSkin = "<ключ>" получит картинку своего скина.
--
-- FULL = true — дополнительно сбросить цвета/рамки/прозрачность к теме
-- (если хочешь перекрасить всё после правок UiTheme.Colors / Skins).
-- Элементы с атрибутом UiSkinLocked = true не трогаются никогда.
--------------------------------------------------------------------------------
local FULL = false

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Свежая копия Shared: Command Bar может держать в памяти старую версию модулей.
local freshShared = ReplicatedStorage:WaitForChild("Shared"):Clone()
local UiKit = require(freshShared.UiKit)

local total = 0
for _, gui in StarterGui:GetChildren() do
	if gui:IsA("ScreenGui") then
		total += UiKit.ApplySkinsTo(gui, FULL)
	end
end
print(("[ApplyUiSkins] Обновлено элементов: %d"):format(total))
