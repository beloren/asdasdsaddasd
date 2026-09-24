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

local UiKit = require(ReplicatedStorage.Shared.UiKit)
local DropPreviewBuilder = require(ReplicatedStorage.Shared.UiBuilders.DropPreviewUi)
local W, H = DropPreviewBuilder.W, DropPreviewBuilder.H

local function sfx(name) if okSfx then pcall(UiSfx.play, name) end end
local function rarityColor(r) return Config.RarityColors[r or ""] or Color3.fromRGB(205, 205, 205) end
local function setCaption(button, value)
	local caption = button:FindFirstChild("Caption")
	if caption then caption.Text = value end
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
-- v20: окно собирает Shared.UiBuilders.DropPreviewUi (StarterGui/DropPreviewUi).
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("DropPreviewUi")
gui.Enabled = false
local dimmer = gui:WaitForChild("Dimmer")
local panel = gui:WaitForChild("Panel")
local panelScale = panel:WaitForChild("PanelScale")
local title = panel:WaitForChild("TitleBar"):WaitForChild("Title")
local closeButton = panel:WaitForChild("CloseButton")
local tabsHolder = panel:WaitForChild("SourceTabs")
local sourceTabs = { Geode = tabsHolder:WaitForChild("Geode"), Chest = tabsHolder:WaitForChild("Chest") }
local chips = panel:WaitForChild("Types")
local list = panel:WaitForChild("Rows")
local detail = panel:WaitForChild("Detail")
local detailStroke = detail:FindFirstChild("SkinStroke") or Instance.new("UIStroke", detail)
local detailGlow = detail:WaitForChild("Glow")
local bigView = detail:WaitForChild("BigPreview")
local dragHint = detail:WaitForChild("DragHint")
local detailRarity = detail:WaitForChild("Rarity")
local detailName = detail:WaitForChild("ItemName")
local detailChance = detail:WaitForChild("Chance")
local detailDesc = detail:WaitForChild("Desc")
local footer = panel:WaitForChild("Footer")
local templates = panel:WaitForChild("Templates")
local rowTemplate = templates:WaitForChild("RowTemplate")
local chipTemplate = templates:WaitForChild("ChipTemplate")

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
	detailName.Text = rowTitle(row):upper() .. (owned and "  ✅" or "")
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
	local b = rowTemplate:Clone()
	b.Visible = true -- шаблоны в Templates скрыты
	b.Name = "Row"
	b:SetAttribute("RowId", row.Id)
	b.LayoutOrder = order
	b.Parent = list
	local select = b:FindFirstChild("Select")
	if select then select.Color = color; select.Enabled = false end
	local skinStroke = b:FindFirstChild("SkinStroke")
	if skinStroke then skinStroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.35) end
	local bar = b:FindFirstChild("Bar")
	if bar then bar.BackgroundColor3 = color; bar.ImageColor3 = color end
	local view = b:FindFirstChild("Preview", true)
	if view then table.insert(rowCleanups, ItemPreview.Mount(view, row, { Spin = false, Tilt = 15 })) end
	local owned = row.Kind == "Skin" and ownedSkins[row.SkinId]
	b.Title.Text = rowTitle(row):upper() .. (owned and "  ✅" or "")
	b.Rarity.Text = (row.Rarity or ""):upper()
	b.Rarity.TextColor3 = color
	b.Chance.Text = DropTables.ChanceText(row.Chance)
	b.OneIn.Text = DropTables.OneIn(row.Chance)
	-- Мини-полоска шанса (логарифмическая, чтобы 0.1% тоже было видно).
	local fill = b:FindFirstChild("Track") and b.Track:FindFirstChild("Fill")
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(1 + math.log10(math.max(row.Chance, 1e-4)) / 4, 0.03, 1), 1)
		fill.BackgroundColor3 = color
		fill.ImageColor3 = color
	end
	local baseColor = b.BackgroundColor3
	b.MouseEnter:Connect(function() b.BackgroundColor3 = baseColor:Lerp(color, 0.18) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = baseColor end)
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
	title.Text = tableInfo.Title:upper() .. " DROPS"
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
	UiKit.SetTabActive(tabsHolder, currentSource)
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
		local chip = chipTemplate:Clone()
		chip.Visible = true -- шаблоны в Templates скрыты
		chip.Name = "Chip_" .. tostring(id)
		chip.LayoutOrder = index
		setCaption(chip, (currentSource == "Geode" and id or info.DisplayName:gsub(" Chest", "")):upper())
		UiKit.ApplySkin(chip, selected and "Button_Yellow" or "Button_Dark")
		local chipStroke = chip:FindFirstChild("SkinStroke")
		if chipStroke and info.Color then chipStroke.Color = info.Color end
		chip.Parent = chips
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
