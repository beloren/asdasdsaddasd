--------------------------------------------------------------------------------
-- TopbarDock (v19.4) — круглые кнопки HUD в ОДНОМ РЯДУ с кнопками Roblox
-- (меню, чат, рюкзак) в верхней полосе экрана.
--
-- Место берётся из GuiService.TopbarInset — это свободная часть топбара
-- справа от штатных кнопок Roblox, она сама подстраивается под новый/старый
-- топбар, телефон и вырезы экрана. Кнопки выстраиваются слева направо по
-- LayoutOrder: 📜 квесты (1), 🎁 награды за время (2), 🎁 группа/избранное (3).
--
--   TopbarDock.Add(button, order) — перенести готовую кнопку в ряд.
-- Кнопка остаётся той же инстанцией — её обработчики и Visible работают
-- как раньше; меняются только родитель, размер и вид (тёмный круг, как у
-- кнопок Roblox).
--------------------------------------------------------------------------------
local GuiService = game:GetService("GuiService")

local TopbarDock = {}
TopbarDock.YOffset = 0 -- доп. сдвиг ряда по вертикали, px (минус — выше, плюс — ниже)

local BUTTON = 44 -- как у штатных кнопок нового топбара Roblox
local row

local function ensureRow()
	if row and row.Parent then return row end
	-- v20: контейнер ряда собирается билдером (StarterGui/TopbarDock).
	local gui = require(script.Parent.UiRegistry).Get("TopbarDock")
	row = gui:FindFirstChild("Row")
	if not row then
		row = Instance.new("Frame")
		row.Name = "Row"
		row.BackgroundTransparency = 1
		row.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 12)
		layout.Parent = row
	end
	local function place()
		local inset = GuiService.TopbarInset
		local height, top, left, width
		if inset.Height > 1 then
			-- Свободная часть топбара справа от кнопок Roblox (и на ПК, и на
			-- телефоне — Roblox сам сообщает её через TopbarInset).
			height, top, left, width = inset.Height, inset.Min.Y, inset.Min.X + 6, math.max(200, inset.Width - 8)
		else
			-- Топбар ещё не готов / скрыт — временно в левом верхнем углу.
			local topInset = GuiService:GetGuiInset()
			height = math.max(40, topInset.Y)
			top, left, width = 0, 16, 400
		end
		-- v19.5: кружки того же размера, что штатные кнопки Roblox (~70%
		-- высоты полосы), и строго по её центру — чуть выше, чем было.
		-- v19.6: кнопки Roblox в топбаре стоят НЕ по центру полосы, а ближе
		-- к её низу (центр примерно на 60% высоты) и занимают ~2/3 высоты.
		-- Ровно так же ставим и свои: ряд высотой в кружок, центр на 60%.
		local size = math.clamp(math.floor(height * 0.66 + 0.5), 28, BUTTON)
		local centerY = top + height * 0.6 + (TopbarDock.YOffset or 0)
		row.Position = UDim2.fromOffset(left, math.floor(centerY - size / 2 + 0.5))
		row.Size = UDim2.fromOffset(width, size)
		for _, child in row:GetChildren() do
			if child:IsA("GuiButton") then child.Size = UDim2.fromOffset(size, size) end
		end
		row:SetAttribute("ButtonSize", size)
	end
	TopbarDock.Refresh = place
	place()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() task.defer(place) end)
	end
	-- На телефоне TopbarInset иногда приходит не сразу — перепроверяем.
	task.delay(1, place)
	task.delay(3, place)
	return row
end

function TopbarDock.Add(button, order)
	if not button then return end
	local parent = ensureRow()
	local size = tonumber(parent:GetAttribute("ButtonSize")) or BUTTON
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position = UDim2.new()
	button.Size = UDim2.fromOffset(size, size)
	button.LayoutOrder = order or 10
	-- v20: кнопки, собранные билдером (атрибут UiSkin), уже в стиле темы и
	-- правятся в StarterGui — их вид не трогаем, только место и размер.
	if button:GetAttribute("UiSkin") then
		button.Parent = parent
		return
	end
	-- Вид штатных кнопок Roblox: тёмный полупрозрачный круг.
	button.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
	button.BackgroundTransparency = 0.3
	local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") then child:Destroy() end
	end
	-- Иконка по центру, ~60% круга (как у штатных кнопок). Текст самой
	-- кнопки переносим в дочернюю подпись, чтобы её можно было уменьшить,
	-- а бейджи-точки (дети кнопки) остались в углу круга.
	if button:IsA("TextButton") and button.Text ~= "" then
		local icon = Instance.new("TextLabel")
		icon.Name = "DockIcon"
		icon.BackgroundTransparency = 1
		icon.Text = button.Text
		icon.TextScaled = true
		icon.Font = button.Font
		icon.TextColor3 = button.TextColor3
		icon.Parent = button
		button.Text = ""
	end
	for _, child in button:GetChildren() do
		if child:IsA("TextLabel") and (child.Name == "DockIcon" or child.Name == "Caption" or child.Name == "Icon") then
			child.AnchorPoint = Vector2.new(0.5, 0.5)
			child.Position = UDim2.fromScale(0.5, 0.5)
			child.Size = UDim2.fromScale(0.6, 0.6)
		end
	end
	button.Parent = parent
end

return TopbarDock
