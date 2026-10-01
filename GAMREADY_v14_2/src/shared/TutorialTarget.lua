--------------------------------------------------------------------------------
-- TutorialTarget (v20.110) — метка «сюда показывает обучение».
-- Любой элемент интерфейса регистрирует себя под именем:
--   TutorialTarget.Mark(button, "Upgrade:Mine")
-- Обучение (TutorialUI) ищет помеченные элементы по имени из шага
-- (Config.Tutorial.Steps[*].UiTargets; "*" в конце имени - любой хвост),
-- затемняет экран вокруг и наводит на них указатель.
--------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")

local TutorialTarget = {}
TutorialTarget.TAG = "TutorialTarget"
TutorialTarget.ATTR = "TutorialTarget"

function TutorialTarget.Mark(gui, name)
	if not (gui and name) then return end
	gui:SetAttribute(TutorialTarget.ATTR, name)
	if not CollectionService:HasTag(gui, TutorialTarget.TAG) then
		CollectionService:AddTag(gui, TutorialTarget.TAG)
	end
end

local function matches(name, pattern)
	if not name then return false end
	if pattern:sub(-1) == "*" then
		return name:sub(1, #pattern - 1) == pattern:sub(1, -2)
	end
	return name == pattern
end
TutorialTarget.Matches = matches

-- Виден ли элемент на экране целиком по цепочке предков.
local function shown(gui)
	if not gui:IsDescendantOf(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui") or game) then return false end
	local node = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") then
			if not node.Enabled then return false end
			break
		end
		node = node.Parent
	end
	local size = gui.AbsoluteSize
	if not (size.X > 4 and size.Y > 4) then return false end
	-- v20.115: центр элемента не обрезан родителями (прокрутка списка,
	-- ClipsDescendants) - иначе курсор показывал бы в пустоту.
	local center = gui.AbsolutePosition + size / 2
	local parent = gui.Parent
	while parent and not parent:IsA("LayerCollector") do
		if parent:IsA("GuiObject") and (parent.ClipsDescendants or parent:IsA("ScrollingFrame")) then
			local a, s = parent.AbsolutePosition, parent.AbsoluteSize
			if center.X < a.X or center.Y < a.Y or center.X > a.X + s.X or center.Y > a.Y + s.Y then
				return false
			end
		end
		parent = parent.Parent
	end
	return true
end
TutorialTarget.Shown = shown

-- Первый видимый элемент под одним из имён (по порядку списка).
function TutorialTarget.Find(patterns)
	if type(patterns) ~= "table" then return nil end
	local tagged = CollectionService:GetTagged(TutorialTarget.TAG)
	for index, pattern in patterns do
		for _, gui in tagged do
			if gui:IsA("GuiObject") and matches(gui:GetAttribute(TutorialTarget.ATTR), pattern) and shown(gui) then
				return gui, index
			end
		end
	end
	return nil
end

return TutorialTarget
