--------------------------------------------------------------------------------
-- MobileLayoutOverride
-- Даёт возможность переопределить позицию/размер ЛЮБОГО UI-элемента на
-- телефоне БЕЗ единой строчки кода — целиком через Studio (см.
-- tools/BuildMobileLayoutEditor.lua + tools/HarvestMobileLayout.lua).
--
-- Как это работает:
-- 1) tools/BuildMobileLayoutEditor.lua создаёт в StarterGui черновик-редактор
--    с прямоугольником-плейсхолдером под каждый элемент (BookButton,
--    QuestPanel и т.д.). В Studio переключаешься на телефонный экран
--    (Test → Device) и просто ТАСКАЕШЬ мышкой эти прямоугольники, где
--    хочешь их видеть — как обычный Frame, никакого кода.
-- 2) tools/HarvestMobileLayout.lua читает получившиеся позиции и печатает
--    готовый кусок Lua (Config.MobileLayout) в Output — копируешь и
--    вставляешь в Config.lua.
-- 3) Реальные скрипты (CollectionMenu.client.lua, QuestUI.client.lua и
--    т.д.) вызывают MobileLayoutOverride.Apply(key, element) ПЕРЕД тем как
--    считать позицию своей формулой — если для этого key в
--    Config.MobileLayout что-то записано, применяется ОНО, а формула
--    полностью пропускается. Если ничего не записано — работает как раньше,
--    ничего не меняется (обратная совместимость по умолчанию).
--------------------------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MobileLayoutOverride = {}

-- Возвращает true, если для этого key нашлось и применилось переопределение
-- (значит вызывающий код должен ПРОПУСТИТЬ свою обычную формулу позиции).
-- Возвращает false, если переопределения нет — работай как раньше.
-- Ничего не делает вообще на ПК (переопределения только под телефон).
function MobileLayoutOverride.Apply(key, element)
	if not UserInputService.TouchEnabled then return false end
	local override = Config.MobileLayout and Config.MobileLayout[key]
	if not override then return false end
	if override.AnchorPoint then element.AnchorPoint = override.AnchorPoint end
	if override.Position then element.Position = override.Position end
	if override.Size then element.Size = override.Size end
	if override.Rotation then element.Rotation = override.Rotation end
	return true
end

return MobileLayoutOverride
