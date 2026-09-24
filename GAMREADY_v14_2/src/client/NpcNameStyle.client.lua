--------------------------------------------------------------------------------
-- NpcNameStyle (LocalScript) v20.3 — имена NPC над головой в едином стиле
-- (референс «Ice Man»): белое имя засечным шрифтом с тёмной обводкой и
-- маленькая «v»-стрелка под ним.
--
-- NPC-билборды собирают разные сервисы (продавец, прокачка, мэр престижа,
-- шахтёр, хранитель островов) и твои собственные модели NPC из Assets —
-- везде одна разметка: TextLabel "name" + TextLabel "arrow" (+ "dialog").
-- Поэтому стиль накладывается здесь, один раз для всех: шрифт/обводка —
-- образец StarterGui/WorldUiTemplates/TextStyles/NpcName (и NpcArrow).
-- Скрипты диалогов меняют у этих надписей только Visible — стиль не спорит.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldUi = require(ReplicatedStorage.Shared.WorldUi)

local styled = setmetatable({}, { __mode = "k" })

local function isNpcLabel(label)
	if not label:IsA("TextLabel") then return false end
	if label.Name ~= "name" and label.Name ~= "arrow" then return false end
	local board = label:FindFirstAncestorWhichIsA("BillboardGui")
	return board ~= nil and board:FindFirstChild("name", true) ~= nil
end

local function style(label)
	if styled[label] or not isNpcLabel(label) then return end
	styled[label] = true
	if label.Name == "name" then
		WorldUi.Restyle(label, "NpcName")
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 42
		limit.Parent = label
	else
		WorldUi.Restyle(label, "NpcArrow")
		label.Text = "v"
		label.TextScaled = true
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 20
		limit.Parent = label
	end
end

for _, descendant in workspace:GetDescendants() do
	if descendant.Name == "name" or descendant.Name == "arrow" then style(descendant) end
end
workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "name" or descendant.Name == "arrow" then
		task.defer(style, descendant)
	end
end)
