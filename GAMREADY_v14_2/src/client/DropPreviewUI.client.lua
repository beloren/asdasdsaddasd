--------------------------------------------------------------------------------
-- DropPreviewUI (LocalScript) v18 — ОКНО ШАНСОВ С ПРЕДПРОСМОТРОМ.
--
-- Все жеоды и сундуки в одном окне:
--   • вкладки GEODES / CHESTS и фишки типов (Stone … Singularity, Common …);
--   • список наград: 3D-превью, полоска цвета редкости, название, шанс
--     в % и «1 in N», отметка ✔ у уже открытых скинов;
--   • клик по строке — большой крутящийся предпросмотр справа (скин можно
--     покрутить мышью/пальцем), описание и шанс;
--   • внизу — сколько наград за открытие, гарантия скина (x/10), сердца жеоды.
-- Цифры берутся из shared/DropTables — того же модуля, что роллит сервер.
--
-- Открыть: BindableEvent PlayerGui.OpenDropPreview:Fire("Geode"|"Chest", id),
-- промпт «View Drops» у сундука (атрибут DropPreview = "Chest:<Rarity>"),
-- кнопка «🔍 ALL DROPS» в окне жеод.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage.Shared.Config)
local DropTables = require(ReplicatedStorage.Shared.DropTables)
local ItemPreview = require(ReplicatedStorage.Shared.ItemPreview)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local okSfx, UiSfx = pcall(require, ReplicatedStorage.Shared.UiSfx)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(12, 10, 20)
local PANEL = Color3.fromRGB(30, 27, 44)
local DEEP = Color3.fromRGB(20, 18, 30)
local ROW = Color3.fromRGB(40, 36, 58)
local MUTED = Color3.fromRGB(165, 160, 185)
local W, H = 780, 470

local function sfx(name) if okSfx then pcall(UiSfx.play, name) end end
local function rarityColor(r) return Config.RarityColors[r or ""] or Color3.fromRGB(205, 205, 205) end
local function corner(p, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 10) c.Parent = p return c end
local function stroke(p, t, c, contextual)
	local s = Instance.new("UIStroke")
	s.Thickness = t
	s.Color = c or INK
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do l[k] = v end
	l.Parent = parent
	stroke(l, 1.5, INK, true)
	return l
end
local function button(parent, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do b[k] = v end
	b.Parent = parent
	corner(b, 10)
	stroke(b, 2, INK)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	return b
end

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ ИГРОКА (владение скинами, гарантия, сердца)
--------------------------------------------------------------------------------
local ownedSkins = {}
local chestPity = 0
local geodeHearts = 0
task.spawn(function()
	local skinRemote = ReplicatedStorage.Shared:WaitForChild("SkinRequest", 30)
	if skinRemote then
		skinRemote.OnClientEvent:Connect(function(_, state)
			if type(state) == "table" and type(state.Owned) == "table" then
				ownedSkins = {}
				for _, entry in state.Owned do ownedSkins[entry.Id] = true end
			end
		end)
	end
end)
task.spawn(function()
	local gearRemote = ReplicatedStorage.Shared:WaitForChild("GearRequest", 30)
	if gearRemote then
		gearRemote.OnClientEvent:Connect(function(_, state)
			if type(state) == "table" and state.ChestSkinPity ~= nil then chestPity = tonumber(state.ChestSkinPity) or 0 end
		end)
	end
end)
task.spawn(function()
	local geodeRemote = ReplicatedStorage.Shared:WaitForChild("GeodeRequest", 30)
	if geodeRemote then
		geodeRemote.OnClientEvent:Connect(function(_, state)
			if type(state) == "table" and state.GeodeHearts ~= nil then geodeHearts = tonumber(state.GeodeHearts) or 0 end
		end)
	end
end)

--------------------------------------------------------------------------------
-- ОКНО
--------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "DropPreviewUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 65
gui.Enabled = false
gui.Parent = playerGui

local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 0.45
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
panel.BackgroundColor3 = PANEL
panel.Parent = gui
corner(panel, 18)
stroke(panel, 4, INK)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local title = text(panel, { Text = "🎲 DROP CHANCES", Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(300, 34),
	TextColor3 = Color3.fromRGB(255, 215, 90) })
local closeButton = button(panel, { Name = "CloseButton", Text = "X", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Color3.fromRGB(225, 55, 70) })
closeButton.ZIndex = 5

-- Вкладки источника.
local sourceTabs = {}
local function sourceTab(name, label, x)
	local b = button(panel, { Name = name .. "Tab", Text = label, Position = UDim2.fromOffset(x, 50), Size = UDim2.fromOffset(130, 34),
		BackgroundColor3 = ROW })
	sourceTabs[name] = b
	return b
end
sourceTab("Geode", "🪨 GEODES", 18)
sourceTab("Chest", "🎁 CHESTS", 156)

-- Фишки типов.
local chips = Instance.new("ScrollingFrame")
chips.Name = "Types"
chips.BackgroundTransparency = 1
chips.Position = UDim2.fromOffset(18, 90)
chips.Size = UDim2.new(1, -36, 0, 40)
chips.ScrollingDirection = Enum.ScrollingDirection.X
chips.AutomaticCanvasSize = Enum.AutomaticSize.X
chips.CanvasSize = UDim2.new()
chips.ScrollBarThickness = 4
chips.Parent = panel
local chipsLayout = Instance.new("UIListLayout")
chipsLayout.FillDirection = Enum.FillDirection.Horizontal
chipsLayout.Padding = UDim.new(0, 6)
chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipsLayout.Parent = chips

-- Список наград.
local list = Instance.new("ScrollingFrame")
list.Name = "Rows"
list.BackgroundColor3 = DEEP
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(18, 138)
list.Size = UDim2.new(1, -300, 1, -186)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ScrollBarThickness = 6
list.Parent = panel
corner(list, 12)
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 8)
listPad.PaddingBottom = UDim.new(0, 8)
listPad.Parent = list

-- Большой предпросмотр.
local detail = Instance.new("Frame")
detail.Name = "Detail"
detail.BackgroundColor3 = DEEP
detail.Position = UDim2.new(1, -272, 0, 138)
detail.Size = UDim2.new(0, 254, 1, -186)
detail.Parent = panel
corner(detail, 12)
local detailStroke = stroke(detail, 3, ROW)
local detailGlow = Instance.new("Frame")
detailGlow.Size = UDim2.new(1, 0, 0, 180)
detailGlow.BackgroundColor3 = Color3.new(1, 1, 1)
detailGlow.BackgroundTransparency = 0.6
detailGlow.Parent = detail
corner(detailGlow, 12)
local glowGrad = Instance.new("UIGradient")
glowGrad.Rotation = 90
glowGrad.Transparency = NumberSequence.new(0.3, 1)
glowGrad.Parent = detailGlow
local bigView = Instance.new("ViewportFrame")
bigView.Name = "BigPreview"
bigView.BackgroundTransparency = 1
bigView.Position = UDim2.fromOffset(10, 8)
bigView.Size = UDim2.new(1, -20, 0, 172)
bigView.Parent = detail
local dragHint = text(detail, { Text = "⟲ drag to rotate", Position = UDim2.fromOffset(10, 162), Size = UDim2.new(1, -20, 0, 14),
	Font = Enum.Font.GothamBold, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center })
local detailRarity = text(detail, { Text = "", Position = UDim2.fromOffset(12, 184), Size = UDim2.new(1, -24, 0, 18) })
local detailName = text(detail, { Text = "", Position = UDim2.fromOffset(12, 202), Size = UDim2.new(1, -24, 0, 30) })
local detailChance = text(detail, { Text = "", Position = UDim2.fromOffset(12, 234), Size = UDim2.new(1, -24, 0, 22),
	TextColor3 = Color3.fromRGB(255, 225, 130) })
local detailDesc = text(detail, { Text = "", Position = UDim2.fromOffset(12, 260), Size = UDim2.new(1, -24, 0, 50),
	Font = Enum.Font.GothamBold, TextScaled = false, TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Color3.fromRGB(220, 218, 232) })

-- Подвал.
local footer = text(panel, { Name = "Footer", Text = "", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -12),
	Size = UDim2.new(1, -36, 0, 28), Font = Enum.Font.GothamBold, TextColor3 = MUTED, RichText = true })

--------------------------------------------------------------------------------
-- ЛОГИКА
--------------------------------------------------------------------------------
local currentSource, currentId = "Geode", Config.Geodes.Order[1]
local selectedRow = nil
local cleanupBig = nil
local rowCleanups = {}
local bigControl = {}

local function clearRows()
	for _, fn in rowCleanups do pcall(fn) end
	rowCleanups = {}
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function chanceString(row)
	return ("%s  ·  %s"):format(DropTables.ChanceText(row.Chance), DropTables.OneIn(row.Chance))
end

local function rowTitle(row)
	if row.Kind == "Money" then
		if row.Amount then return "$" .. NumberFormat.abbreviate(row.Amount) end
		local cam = player:GetAttribute("MineTier") or 1
		local cart = player:GetAttribute("CartTier") or 1
		local ok, value = pcall(Config.CartValue, cam, cart)
		if ok and value and row.Carts then
			return ("$%s – $%s"):format(NumberFormat.abbreviate(value * row.Carts[1]), NumberFormat.abbreviate(value * row.Carts[2]))
		end
		return "Cash"
	end
	return row.Title
end

local function showDetail(row)
	selectedRow = row
	if cleanupBig then cleanupBig() cleanupBig = nil end
	local color = rarityColor(row.Rarity)
	detailStroke.Color = color
	detailGlow.BackgroundColor3 = color
	detailRarity.Text = (row.Rarity or ""):upper()
	detailRarity.TextColor3 = color
	local owned = row.Kind == "Skin" and ownedSkins[row.SkinId]
	detailName.Text = rowTitle(row):upper() .. (owned and "  ✔" or "")
	detailChance.Text = chanceString(row)
	detailDesc.Text = (row.Description or "") .. (owned and "\nYou already own it (duplicate → cash)." or "")
	bigControl = { Angle = 0 }
	cleanupBig = ItemPreview.Mount(bigView, row, { Spin = true, SpinSpeed = 0.6, Tilt = 10, Zoom = 0.95, Control = bigControl })
	dragHint.Visible = true
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then
			local s = child:FindFirstChild("Select")
			if s then s.Enabled = child:GetAttribute("RowId") == row.Id end
		end
	end
end

-- Поворот большого превью мышью / пальцем.
do
	local dragging, lastX = false, 0
	bigView.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, lastX = true, input.Position.X
			bigControl.Paused = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				task.delay(1.5, function() if not dragging then bigControl.Paused = false end end)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local dx = input.Position.X - lastX
		lastX = input.Position.X
		bigControl.Angle = (bigControl.Angle or 0) + math.rad(dx * 0.8)
		dragHint.Visible = false
	end)
end

local function buildRow(row, order)
	local color = rarityColor(row.Rarity)
	local b = Instance.new("TextButton")
	b.Name = "Row"
	b:SetAttribute("RowId", row.Id)
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = order
	b.Size = UDim2.new(1, -16, 0, 58)
	b.BackgroundColor3 = ROW
	b.Parent = list
	corner(b, 10)
	local select = stroke(b, 3, color)
	select.Name = "Select"
	select.Enabled = false
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 6, 1, -12)
	bar.Position = UDim2.fromOffset(6, 6)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = b
	corner(bar, 3)
	local view = Instance.new("ViewportFrame")
	view.BackgroundColor3 = DEEP
	view.BackgroundTransparency = 0.2
	view.Position = UDim2.fromOffset(18, 5)
	view.Size = UDim2.fromOffset(48, 48)
	view.Parent = b
	corner(view, 8)
	table.insert(rowCleanups, ItemPreview.Mount(view, row, { Spin = false, Tilt = 15 }))
	local owned = row.Kind == "Skin" and ownedSkins[row.SkinId]
	text(b, { Text = rowTitle(row):upper() .. (owned and "  ✔" or ""), Position = UDim2.fromOffset(74, 7), Size = UDim2.new(1, -220, 0, 24) })
	text(b, { Text = (row.Rarity or ""):upper(), Position = UDim2.fromOffset(74, 33), Size = UDim2.new(1, -220, 0, 16),
		TextColor3 = color, Font = Enum.Font.GothamBold })
	text(b, { Text = DropTables.ChanceText(row.Chance), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(120, 26), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 225, 130) })
	text(b, { Text = DropTables.OneIn(row.Chance), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 34),
		Size = UDim2.fromOffset(120, 16), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextColor3 = MUTED })
	-- Мини-полоска шанса (логарифмическая, чтобы 0.1% тоже было видно).
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 1)
	track.Position = UDim2.new(1, -10, 1, -4)
	track.Size = UDim2.fromOffset(120, 3)
	track.BackgroundColor3 = DEEP
	track.BorderSizePixel = 0
	track.Parent = b
	local fill = Instance.new("Frame")
	local width = math.clamp(1 + math.log10(math.max(row.Chance, 1e-4)) / 4, 0.03, 1)
	fill.Size = UDim2.fromScale(width, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	b.MouseEnter:Connect(function() b.BackgroundColor3 = ROW:Lerp(color, 0.18) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = ROW end)
	b.Activated:Connect(function()
		sfx("UiButtonClick")
		showDetail(row)
	end)
end

local renderChips

local function render()
	clearRows()
	local tableInfo = currentSource == "Geode" and DropTables.Geode(currentId) or DropTables.Chest(currentId)
	if not tableInfo then return end
	title.Text = "🎲 " .. tableInfo.Title:upper() .. " DROPS"
	title.TextColor3 = tableInfo.Color or Color3.fromRGB(255, 215, 90)
	local rows = table.clone(tableInfo.Rows)
	table.sort(rows, function(a, b) return a.Chance > b.Chance end)
	for index, row in rows do buildRow(row, index) end
	-- Самое редкое — сразу в предпросмотр (это интереснее всего).
	if rows[#rows] then showDetail(rows[#rows]) end
	local lines = {}
	if currentSource == "Geode" then
		table.insert(lines, "1 reward per geode")
		if geodeHearts > 0 then table.insert(lines, ('<font color="#FF6FB4">💖 %d heart%s: next geode gives x%d!</font>'):format(geodeHearts, geodeHearts == 1 and "" or "s", Config.Geodes.Heart.Rewards)) end
		table.insert(lines, "Skins drop only from chests")
	else
		table.insert(lines, ("%d rewards per chest"):format(tableInfo.Rolls or 1))
		if tableInfo.PityEvery then
			table.insert(lines, ('<font color="#FFD35A">Guaranteed skin every %d chests (%d/%d)</font>'):format(tableInfo.PityEvery, math.min(chestPity, tableInfo.PityEvery), tableInfo.PityEvery))
		end
		table.insert(lines, "+ bonus relic roll")
	end
	footer.Text = table.concat(lines, "   ·   ")
	for name, tab in sourceTabs do
		tab.BackgroundColor3 = name == currentSource and Color3.fromRGB(255, 190, 60) or ROW
		tab.TextColor3 = name == currentSource and INK or Color3.new(1, 1, 1)
	end
	renderChips()
end

renderChips = function()
	for _, child in chips:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local ids = currentSource == "Geode" and Config.Geodes.Order or Config.Chests.Order
	for index, id in ids do
		local info = currentSource == "Geode" and Config.Geodes.Types[id] or Config.Chests.Types[id]
		local selected = id == currentId
		local chip = button(chips, { Text = (currentSource == "Geode" and id or info.DisplayName:gsub(" Chest", "")):upper(),
			LayoutOrder = index, Size = UDim2.fromOffset(110, 32),
			BackgroundColor3 = selected and (info.Color or ROW) or ROW })
		chip.TextColor3 = selected and INK or Color3.new(1, 1, 1)
		chip.Activated:Connect(function()
			sfx("UiButtonClick")
			currentId = id
			render()
		end)
	end
end

for name, tab in sourceTabs do
	tab.Activated:Connect(function()
		sfx("UiButtonClick")
		currentSource = name
		currentId = name == "Geode" and Config.Geodes.Order[1] or Config.Chests.Order[1]
		render()
	end)
end

local function fitScale()
	local camera = workspace.CurrentCamera
	local v = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return math.min(1, (v.X - 20) / W, (v.Y - 20) / H)
end

local isOpen = false
local function open(source, id)
	if source == "Geode" and Config.Geodes.Types[id] then
		currentSource, currentId = "Geode", id
	elseif source == "Chest" and Config.Chests.Types[id] then
		currentSource, currentId = "Chest", id
	end
	isOpen = true
	gui.Enabled = true
	local target = fitScale()
	panelScale.Scale = target * 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	sfx("UiMenuOpen")
	render()
end

local function close()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
	clearRows()
	if cleanupBig then cleanupBig() cleanupBig = nil end
	sfx("UiMenuClose")
end

closeButton.Activated:Connect(close)
dimmer.Activated:Connect(close)
UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.Escape then close() end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if isOpen then panelScale.Scale = fitScale() end
	end)
end

local openEvent = playerGui:FindFirstChild("OpenDropPreview")
if not openEvent then
	openEvent = Instance.new("BindableEvent")
	openEvent.Name = "OpenDropPreview"
	openEvent.Parent = playerGui
end
openEvent.Event:Connect(function(source, id) open(source, id) end)

-- Промпт «View Drops» (атрибут DropPreview = "Chest:Epic" / "Geode:Stone").
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local spec = prompt:GetAttribute("DropPreview")
	if typeof(spec) ~= "string" then return end
	local source, id = spec:match("^(%a+):(%a+)$")
	if source then open(source, id) end
end)
