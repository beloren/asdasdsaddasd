--------------------------------------------------------------------------------
-- PerkUI (LocalScript) v9 — окно престижа ДЕРЕВОМ (PrestigeService,
-- Config.Prestige.Branches). Сервер открывает его командой "Open" по клику
-- на чемоданчик у NPC ребёрта. Узел ветки открывается, когда у предыдущего
-- есть UnlockLevel уровней (проверяет и сервер). Перки не сбрасываются.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local Builder = require(ReplicatedStorage.Shared.PerkUiBuilder)

-- Цвета узлов (оформление окна — в PerkUiBuilder).
local COLOR_LOCKED = Color3.fromRGB(46, 42, 70)
local COLOR_STAR = Color3.fromRGB(80, 70, 150)
local COLOR_INK = Color3.fromRGB(10, 8, 24)
local COLOR_GOLD_TEXT = Color3.fromRGB(255, 220, 110)
local COLOR_GREEN_TEXT = Color3.fromRGB(120, 255, 150)
local COLOR_GREEN = Color3.fromRGB(70, 200, 95)
local COLOR_ORANGE = Color3.fromRGB(215, 120, 45)
local COLOR_GREY = Color3.fromRGB(95, 98, 110)

local function press(guiButton)
	local scale = guiButton:FindFirstChild("PressScale") or Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = guiButton
	local function to(value, seconds)
		TweenService:Create(scale, TweenInfo.new(seconds or 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	guiButton.MouseEnter:Connect(function() to(1.06) end)
	guiButton.MouseLeave:Connect(function() to(1) end)
	guiButton.MouseButton1Down:Connect(function() to(0.92, 0.06) end)
	guiButton.MouseButton1Up:Connect(function() to(1.06) end)
end

local cfg = Config.Prestige
if not (cfg and cfg.Enabled) then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

-- v20: окно собирается билдером (Shared.PerkUiBuilder → StarterGui/PerkUi).
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("PerkUi")
if not (gui:FindFirstChild("Tree", true) and gui:FindFirstChild("Shrines", true)) then
	gui:Destroy()
	gui = Builder.Build()
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
gui.Enabled = false

local panel = gui:WaitForChild("Panel")
local autoScale = panel:FindFirstChild("AutoScale")
local pointsLabel = panel:WaitForChild("Points"):WaitForChild("Text")
local closeButton = panel:WaitForChild("CloseButton")
local tree = panel:WaitForChild("Tree")
local branchTemplate = tree:WaitForChild("BranchTemplate")
local nodeTemplate = tree:WaitForChild("NodeTemplate")
local linkTemplate = tree:WaitForChild("LinkTemplate")
local detail = panel:WaitForChild("Detail")
local upgradeButton = detail:WaitForChild("UpgradeButton")
local upgradeText = upgradeButton:WaitForChild("Text")
require(ReplicatedStorage.Shared.TutorialTarget).Mark(upgradeButton, "PerkUpgrade") -- v20.110
-- v4: вкладки и список святилищ.
local tabs = panel:WaitForChild("Tabs")
local perksTab = tabs:WaitForChild("PerksTab")
local shrinesTab = tabs:WaitForChild("ShrinesTab")

-- v20.67: подписи кнопок (PERKS / SHRINES / купить) всегда крупные и
-- читаемые: растянуты на всю кнопку, TextScaled и минимум 18 px - даже
-- если копия окна в месте старая или её подпись кто-то уменьшил.
local function readableCaption(button, minSize)
	local caption = button:FindFirstChild("Text") or button:FindFirstChild("Caption")
	if not (caption and caption:IsA("TextLabel")) then return end
	caption.AnchorPoint = Vector2.zero
	caption.Position = UDim2.fromOffset(6, 3)
	caption.Size = UDim2.new(1, -12, 1, -6)
	caption.TextScaled = true
	caption.TextWrapped = false
	local limit = caption:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	limit.MinTextSize = minSize or 18
	limit.MaxTextSize = 48
	limit.Parent = caption
end
readableCaption(perksTab, 20)
readableCaption(shrinesTab, 18)
readableCaption(upgradeButton, 24)
local shrinesList = panel:WaitForChild("Shrines")
local shrineTemplate = shrinesList:WaitForChild("ShrineTemplate")
local SHRINES = cfg.Shrines or { Order = {}, Types = {} }
local mode = "Perks"
local selectedShrine = nil
local shrineState = {}

local remote = ReplicatedStorage.Shared:WaitForChild("PrestigeRequest", 30)
if not remote then
	warn("[PerkUI] PrestigeRequest не появился - окно перков отключено.")
	return
end

local PERK_BY_ID = {}
for _, perk in cfg.Perks do PERK_BY_ID[perk.Id] = perk end
local ROOT_PERK = cfg.RootPerk -- v20.132: центральный узел «Starter Miner»
local BRANCH_OF = {}
for _, branch in cfg.Branches or {} do
	for _, perkId in branch.Perks do BRANCH_OF[perkId] = branch end
end

-- v20.21: узлы чуть меньше, промежутки больше — линии между улучшениями
-- видны целиком (не прячутся под плашкой уровня) и 4 узла влезают в ветку.
-- Иконка: ImageLabel "Icon" (+ "Emoji" внутри) или старый TextLabel.
local function setIcon(holder, emoji, imageId, transparency)
	if not holder then return end
	if holder:IsA("TextLabel") then
		holder.Text = emoji or ""
		holder.TextTransparency = transparency or 0
		return
	end
	local id = tonumber(imageId) or 0
	if id > 0 then holder.Image = "rbxassetid://" .. id end
	if holder:IsA("ImageLabel") then holder.ImageTransparency = transparency or 0 end
	local text = holder:FindFirstChild("Emoji")
	if text then
		text.Text = emoji or ""
		text.TextTransparency = transparency or 0
		text.Visible = holder.Image == ""
	end
end

-- v20.106: ИКОНКА ОЧКОВ ПРЕСТИЖА вместо «⭐» у чисел (Config.Prestige.PointIconId;
-- пока 0 - нарисованный фиолетовый ромб). Иконка - ImageLabel "PointIcon"
-- слева внутри надписи, текст сдвигается вправо.
local Points = {}
function Points.Icon(label)
	if not (label and label:IsA("TextLabel")) then return end
	local icon = label:FindFirstChild("PointIcon")
	if not icon then
		icon = Instance.new("ImageLabel")
		icon.Name = "PointIcon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)
		icon.Size = UDim2.fromScale(1, 0.9)
		icon.ZIndex = label.ZIndex + 1
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = icon
		local id = tonumber(cfg.PointIconId) or 0
		if id > 0 then
			icon.Image = "rbxassetid://" .. id
		else
			local diamond = Instance.new("Frame")
			diamond.Name = "Diamond"
			diamond.AnchorPoint = Vector2.new(0.5, 0.5)
			diamond.Position = UDim2.fromScale(0.5, 0.5)
			diamond.Size = UDim2.fromScale(0.62, 0.62)
			diamond.Rotation = 45
			diamond.BackgroundColor3 = Color3.fromRGB(190, 120, 255)
			diamond.BorderSizePixel = 0
			diamond.ZIndex = icon.ZIndex
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = Color3.fromRGB(40, 15, 70)
			stroke.Parent = diamond
			diamond.Parent = icon
		end
		icon.Parent = label
		local pad = label:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.22, 0)
		pad.Parent = label
	end
end
function Points.Set(label, value)
	if not label then return end
	label.Text = tostring(value)
	Points.Icon(label)
	label.PointIcon.Visible = true
end
function Points.Hide(label)
	local icon = label and label:FindFirstChild("PointIcon")
	if icon then icon.Visible = false end
end

local NODE_SIZE = 60
local NODE_GAP = 34
local CHIP_OVERHANG = 13 -- плашка уровня «3/10» свисает ниже узла

local state = { Points = 0 }
local levels = {}
local selected = nil
local isOpen = false
local openedAt = nil

local function effectText(perk, level)
	local value = level * perk.PerLevel
	local shown = perk.Percent and tostring(math.floor(value * 100 + 0.5)) or tostring(math.floor(value + 0.5))
	return tr(perk.Text, { v = shown, c = tostring(1 + math.floor(value + 0.5)) })
end

local function infoOf(perkId)
	return levels[perkId] or { Level = 0, MaxLevel = PERK_BY_ID[perkId] and PERK_BY_ID[perkId].MaxLevel or 1 }
end

local renderDetail

--------------------------------------------------------------------------------
-- v20.118: ПОЛНОЭКРАННОЕ ДЕРЕВО КАК НА РЕФЕРЕНСЕ (Config.Prestige.FullScreen):
-- окна нет - узлы висят прямо поверх размытого мира, дерево можно таскать
-- мышью/пальцем (колесо - масштаб), карточка перка всплывает рядом с узлом,
-- внизу большая кнопка CLOSE. Вкладка SHRINES - крупные 3D-превью святилищ,
-- клик - карточка с ценой, покупкой и подсказкой. Остальной интерфейс
-- прячет ScreenFocus (полупрозрачная подложка на весь экран).
--------------------------------------------------------------------------------
local FULL = cfg.FullScreen ~= false and cfg.TreeLayout ~= nil
local CANVAS = typeof(cfg.TreeCanvas) == "Vector2" and cfg.TreeCanvas or Vector2.new(1500, 1000)
local pan = Vector2.zero
local zoom = 1
local dragging, dragMoved, dragStart, panStart = false, false, nil, nil
local fullClose = nil
local function isPhone()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize.X < 700
end
if FULL then
	NODE_SIZE = tonumber(cfg.FullNodeSize) or 96 -- узлы крупнее, как на референсе
	local backdrop = gui:FindFirstChild("FullBackdrop") or Instance.new("Frame")
	backdrop.Name = "FullBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 6, 18)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 0
	backdrop.Parent = gui
	local keep = { Points = true, Tabs = true, Tree = true, Shrines = true, Detail = true }
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and not keep[child.Name] then child.Visible = false end
	end
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	if panel:IsA("ImageLabel") then panel.ImageTransparency = 1 end
	for _, d in panel:GetChildren() do
		if d:IsA("UIStroke") or d:IsA("UISizeConstraint") or d:IsA("UIAspectRatioConstraint") then d:Destroy() end
	end
	if autoScale then autoScale.Scale = 1 end
	tabs.AnchorPoint = Vector2.new(0.5, 0)
	tabs.Position = UDim2.new(0.5, 0, 0, 14)
	local points = panel:FindFirstChild("Points")
	if points then
		points.AnchorPoint = Vector2.new(1, 0)
		points.Position = UDim2.new(1, -18, 0, 16)
	end
	tree.AnchorPoint = Vector2.zero
	tree.Position = UDim2.fromScale(0, 0)
	tree.Size = UDim2.fromScale(1, 1)
	tree.BackgroundTransparency = 1
	if tree:IsA("ImageLabel") then tree.ImageTransparency = 1 end
	tree.ClipsDescendants = true
	for _, d in tree:GetChildren() do
		if d:IsA("UIListLayout") or d:IsA("UIPadding") or d:IsA("UIStroke") then d:Destroy() end
	end
	-- святилища: по центру, крупные карточки с 3D-превью
	shrinesList.AnchorPoint = Vector2.new(0.5, 0)
	shrinesList.Position = UDim2.new(0.5, 0, 0, 74)
	shrinesList.Size = UDim2.new(0.86, 0, 1, -170)
	shrinesList.BackgroundTransparency = 1
	if shrinesList:IsA("ScrollingFrame") then shrinesList.ScrollBarImageTransparency = 0.4 end
	local grid = shrinesList:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(190, 220)
		grid.CellPadding = UDim2.fromOffset(18, 18)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	local icon = shrineTemplate:FindFirstChild("Icon")
	if icon then
		icon.Position = UDim2.fromOffset(10, 8)
		icon.Size = UDim2.new(1, -20, 0, 140)
	end
	local title = shrineTemplate:FindFirstChild("Title")
	if title then
		title.Position = UDim2.fromOffset(8, 150)
		title.Size = UDim2.new(1, -16, 0, 30)
		title.TextXAlignment = Enum.TextXAlignment.Center
	end
	local status = shrineTemplate:FindFirstChild("Status")
	if status then
		status.Position = UDim2.new(0, 8, 1, -34)
		status.Size = UDim2.new(1, -16, 0, 28)
	end
	-- карточка перка - плавающая
	detail.AnchorPoint = Vector2.zero
	detail.Size = UDim2.fromOffset(300, 380)
	detail.ZIndex = 20
	-- v20.122: карточка меньше (UIScale - вёрстка внутри не ломается) и с крестиком
	local detailScale = detail:FindFirstChild("DetailScale") or Instance.new("UIScale")
	detailScale.Name = "DetailScale"
	detailScale.Scale = tonumber(cfg.DetailScale) or 0.72
	detailScale.Parent = detail
	local detailClose = Instance.new("TextButton")
	detailClose.Name = "DetailClose"
	detailClose.AnchorPoint = Vector2.new(1, 0)
	detailClose.Position = UDim2.new(1, 8, 0, -8)
	detailClose.Size = UDim2.fromOffset(40, 40)
	detailClose.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	detailClose.Text = "X"
	detailClose.TextScaled = true
	detailClose.TextColor3 = Color3.new(1, 1, 1)
	detailClose.ZIndex = 40
	pcall(UiKit.StyleText, detailClose, "Heading")
	Instance.new("UICorner", detailClose).CornerRadius = UDim.new(1, 0)
	local detailCloseStroke = Instance.new("UIStroke")
	detailCloseStroke.Thickness = 3
	detailCloseStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	detailCloseStroke.Parent = detailClose
	detailClose.Parent = detail
	-- большая кнопка CLOSE внизу
	fullClose = UiKit.Button(panel, "BigClose", "CLOSE", "Red", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(240, 62),
		ZIndex = 25,
	})
	readableCaption(fullClose, 24)
	closeButton.Visible = false
end

-- v20.120: КАРТОЧКА ТОЛЬКО ПО КЛИКУ/НАВЕДЕНИЮ и сама прячется через
-- Config.Prestige.DetailHideSeconds (5 с), если на ней нет курсора.
local detailShown = not FULL
local detailHideAt = 0
local hoveringDetail = false
local function showDetail()
	if not FULL then return end
	detailShown = true
	detailHideAt = os.clock() + (tonumber(cfg.DetailHideSeconds) or 5)
end
local function hideDetail()
	if not FULL then return end
	detailShown = false
	detail.Visible = false
end
if FULL then
	local detailClose = detail:FindFirstChild("DetailClose")
	if detailClose then
		detailClose.Activated:Connect(function()
			hoveringDetail = false
			hideDetail()
		end)
	end
	detail.MouseEnter:Connect(function() hoveringDetail = true end)
	detail.MouseLeave:Connect(function()
		hoveringDetail = false
		detailHideAt = math.max(detailHideAt, os.clock() + 2)
	end)
end

-- где рисовать карточку: справа от узла (или слева, если не влезает);
-- на телефоне - внизу по центру над CLOSE.
local function placeDetail()
	if not FULL then return end
	if detailShown and not hoveringDetail and os.clock() >= detailHideAt then
		hideDetail()
	end
	if not detailShown then
		detail.Visible = false
		return
	end
	if not detail.Visible then return end
	local area = panel.AbsoluteSize
	-- на маленьком экране карточка меньше (влезает над CLOSE)
	local fit = detail:FindFirstChild("FitScale") or Instance.new("UIScale")
	fit.Name = "FitScale"
	fit.Scale = math.clamp((area.Y - 170) / 380, 0.55, 1)
	fit.Parent = detail
	local dSize = detail.AbsoluteSize
	if isPhone() then
		detail.Position = UDim2.fromOffset((area.X - dSize.X) / 2, area.Y - dSize.Y - 90)
		return
	end
	local anchorGui = nil
	if mode == "Shrines" then
		anchorGui = selectedShrine and shrinesList:FindFirstChild("Shrine_" .. selectedShrine)
	else
		local holder = tree:FindFirstChild("FreeTree")
		anchorGui = holder and (selected == "__Start" and holder:FindFirstChild("StartNode") or (selected and holder:FindFirstChild("Node_" .. selected)))
	end
	local x, y
	if anchorGui then
		local a = anchorGui.AbsolutePosition - panel.AbsolutePosition
		local s = anchorGui.AbsoluteSize
		x = a.X + s.X + 18
		if x + dSize.X > area.X - 10 then x = a.X - dSize.X - 18 end
		y = a.Y + s.Y / 2 - dSize.Y / 2
	else
		x, y = area.X - dSize.X - 20, (area.Y - dSize.Y) / 2
	end
	x = math.clamp(x, 10, math.max(10, area.X - dSize.X - 10))
	y = math.clamp(y, 70, math.max(70, area.Y - dSize.Y - 90))
	detail.Position = UDim2.fromOffset(x, y)
end

-- v20.107: СВОБОДНОЕ ДЕРЕВО (Config.Prestige.TreeLayout) как на референсе:
-- стартовый узел в центре, ветки расходятся линиями, закрытые узлы - «?».
local Free = {}
local renderTree
-- v20.130: клик по узлу больше не пересобирает всё дерево (это и были
-- лаги) - только перекрашивает рамку выделения.
local function updateSelection()
	local holder = tree:FindFirstChild("FreeTree")
	if not holder then
		if renderTree then renderTree() end
		return
	end
	for _, node in holder:GetChildren() do
		local id = node.Name:match("^Node_(.+)$") or (node.Name == "StartNode" and "__Start" or nil)
		local outline = id and node:FindFirstChild("Outline")
		if outline then
			outline.Color = (selected == id) and Color3.new(1, 1, 1) or COLOR_INK
			outline.Thickness = (selected == id) and 5 or 4
		end
	end
end
function Free.Link(parent, size, a, b, color, toId)
	local ax, ay = a[1] * size.X, a[2] * size.Y
	local bx, by = b[1] * size.X, b[2] * size.Y
	local dx, dy = bx - ax, by - ay
	local line = linkTemplate:Clone()
	line.Name = "Link"
	line.Visible = true
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	-- позиция и длина в долях: не зависят от UIScale окна
	line.Position = UDim2.fromScale((a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
	line.Size = UDim2.new(math.sqrt(dx * dx + dy * dy) / math.max(1, size.X), 0, 0, 6)
	line.Rotation = math.deg(math.atan2(dy, dx))
	line.BackgroundColor3 = color
	line.ZIndex = 2
	if toId then line:SetAttribute("RevealTo", toId) end -- v20.144: проявляется вместе с узлом
	line.Parent = parent
end
function Free.Shape(node)
	local id = tonumber(cfg.NodeImageId) or 0
	if id <= 0 then return end
	node.Image = "rbxassetid://" .. id
	node.ImageColor3 = node.BackgroundColor3
	node.BackgroundTransparency = 1
	local corner = node:FindFirstChildOfClass("UICorner")
	if corner then corner:Destroy() end
	local outline = node:FindFirstChild("Outline")
	if outline then outline.Enabled = false end
end
function Free.Render()
	local layout = cfg.TreeLayout
	local holder = Instance.new("Frame")
	holder.Name = "FreeTree"
	holder:SetAttribute("Generated", true)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.Parent = tree
	local size = holder.AbsoluteSize
	if size.X < 10 then size = tree.AbsoluteSize end
	local startPos = layout.Start or { 0.5, 0.5 }
	if FULL then
		-- большое полотно, стартовый узел в центре экрана + сдвиг пальцем
		size = CANVAS * (isPhone() and 0.75 or 1)
		holder.ClipsDescendants = false
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(size.X, size.Y)
		holder.Position = UDim2.new(0.5, (0.5 - startPos[1]) * size.X + pan.X, 0.5, (0.5 - startPos[2]) * size.Y + pan.Y)
		local zoomScale = Instance.new("UIScale")
		zoomScale.Name = "Zoom"
		zoomScale.Scale = zoom
		zoomScale.Parent = holder
	end
	-- стартовый узел (v20.132: если задан RootPerk - это покупаемый перк
	-- «Starter Miner», без него ветки закрыты)
	local rootPerk = ROOT_PERK and PERK_BY_ID[ROOT_PERK]
	local start = nodeTemplate:Clone()
	start.Name = rootPerk and ("Node_" .. ROOT_PERK) or "StartNode"
	start:SetAttribute("TreeRoot", true)
	start.Visible = true
	start.AnchorPoint = Vector2.new(0.5, 0.5)
	start.Position = UDim2.fromScale(startPos[1], startPos[2])
	start.Size = UDim2.fromOffset(NODE_SIZE + 12, NODE_SIZE + 12)
	start.ZIndex = 3
	start.BackgroundColor3 = Color3.fromRGB(150, 90, 230)
	start.Lock.Visible = false
	if rootPerk then
		local info = infoOf(ROOT_PERK)
		local maxed = info.Level >= rootPerk.MaxLevel
		require(ReplicatedStorage.Shared.TutorialTarget).Mark(start, "PerkNode:" .. ROOT_PERK)
		setIcon(start.Icon, rootPerk.Icon, rootPerk.ImageId, 0)
		start.LevelChip.Level.Text = maxed and "MAX" or ("%d/%d"):format(info.Level, rootPerk.MaxLevel)
		start.LevelChip.Level.TextColor3 = maxed and COLOR_GREEN_TEXT or COLOR_GOLD_TEXT
		if not maxed then start.BackgroundColor3 = Color3.fromRGB(150, 90, 230):Lerp(COLOR_STAR, 0.4) end
		if start:FindFirstChild("CanBuy") then
			start.CanBuy.Visible = not maxed and state.Points >= (info.Cost or math.huge)
		end
		local outline = start:FindFirstChild("Outline")
		if outline then
			outline.Color = (selected == ROOT_PERK) and Color3.new(1, 1, 1) or COLOR_INK
			outline.Thickness = (selected == ROOT_PERK) and 5 or 4
		end
	else
		setIcon(start.Icon, "✦", nil, 0)
		start.LevelChip.Level.Text = tr("START")
		if start:FindFirstChild("CanBuy") then start.CanBuy.Visible = false end
	end
	Free.Shape(start)
	press(start)
	start.Activated:Connect(function()
		if dragMoved then return end
		UiSfx.play("UiButtonClick")
		selected = rootPerk and ROOT_PERK or "__Start"
		showDetail()
		updateSelection()
		renderDetail()
	end)
	start.Parent = holder
	for _, branch in cfg.Branches or {} do
		local prev = startPos
		local hideRest = false -- v20.120: за первым закрытым узлом ветки ничего не видно
		for _, perkId in branch.Perks do
			local perk = PERK_BY_ID[perkId]
			local pos = layout[perkId]
			-- v20.144: закрытые узлы (не куплен предыдущий) не видны совсем -
			-- появляются пузырьком, когда открываются (Config.Prestige.HideLocked)
			local lockedNow = perk and pos and (infoOf(perkId).Locked == true)
			if lockedNow and cfg.HideLocked ~= false then hideRest = true end
			if perk and pos and not hideRest then
				local info = infoOf(perkId)
				local locked = info.Locked == true
				if locked and cfg.HideDeepLocked ~= false then hideRest = true end
				local maxed = info.Level >= perk.MaxLevel
				Free.Link(holder, size, prev, pos, locked and COLOR_LOCKED or branch.Color, perkId)
				local node = nodeTemplate:Clone()
				node.Name = "Node_" .. perkId
				node:SetAttribute("Bought", info.Level > 0)
				node:SetAttribute("RevealDist", math.sqrt((pos[1] - startPos[1]) ^ 2 + (pos[2] - startPos[2]) ^ 2))
				prev = pos
				node.Visible = true
				require(ReplicatedStorage.Shared.TutorialTarget).Mark(node, locked and "PerkNode-" or ("PerkNode:" .. perkId)) -- v20.110
				node.AnchorPoint = Vector2.new(0.5, 0.5)
				node.Position = UDim2.fromScale(pos[1], pos[2])
				node.Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE)
				node.ZIndex = 3
				node.BackgroundColor3 = locked and COLOR_LOCKED or (maxed and branch.Color:Lerp(COLOR_INK, 0.15) or branch.Color:Lerp(COLOR_STAR, 0.55))
				setIcon(node.Icon, perk.Icon, perk.ImageId, 0)
				node.Icon.Visible = not locked
				local unknown = node:FindFirstChild("Unknown")
				if unknown then unknown.Visible = locked end
				node.LevelChip.Visible = not locked
				node.LevelChip.Level.Text = maxed and "MAX" or ("%d/%d"):format(info.Level, perk.MaxLevel)
				node.LevelChip.Level.TextColor3 = maxed and COLOR_GREEN_TEXT or COLOR_GOLD_TEXT
				node.Lock.Visible = false
				local outline = node:FindFirstChild("Outline")
				if outline then
					outline.Color = (selected == perkId) and Color3.new(1, 1, 1) or COLOR_INK
					outline.Thickness = (selected == perkId) and 5 or 4
				end
				local canBuy = node:FindFirstChild("CanBuy")
				if canBuy then
					canBuy.Visible = not locked and not maxed and state.Points >= (info.Cost or math.huge)
				end
				Free.Shape(node)
				press(node)
				node.Activated:Connect(function()
					if dragMoved then return end
					UiSfx.play("UiButtonClick")
					selected = perkId
					showDetail()
					updateSelection()
					renderDetail()
				end)
				node.Parent = holder
			end
		end
	end
end
function Free.Find(perkId)
	local holder = tree:FindFirstChild("FreeTree")
	return holder and holder:FindFirstChild("Node_" .. perkId)
end

-- v20.144: АНИМАЦИЯ ПОЯВЛЕНИЯ (Config.TreeReveal): при открытии - сначала
-- стартовый узел, потом темнеет экран, потом узлы пузырьками по очереди
-- (купленные, затем доступные). Узел, открывшийся после покупки, выскакивает
-- пузырьком, линия к нему проявляется. Дерево перерисовывается целиком,
-- поэтому для каждого узла запоминается момент, когда он должен появиться.
local TreeReveal = require(ReplicatedStorage.Shared.TreeReveal)
local revealAt = {}
local revealPending = false
local revealEnd = 0
function Free.Reveal()
	local holder = tree:FindFirstChild("FreeTree")
	if not (holder and FULL) then return end
	local s = TreeReveal.Settings()
	local now = os.clock()
	local nodes = {}
	for _, child in holder:GetChildren() do
		if child:IsA("GuiButton") and (child.Name:match("^Node_") or child.Name == "StartNode") then
			table.insert(nodes, child)
		end
	end
	if revealPending then
		revealPending = false
		table.clear(revealAt)
		local root, early, late = nil, {}, {}
		for _, node in nodes do
			if node:GetAttribute("TreeRoot") then
				root = node
			elseif node:GetAttribute("Bought") then
				table.insert(early, node)
			else
				table.insert(late, node)
			end
		end
		local function byDist(a, b) return (a:GetAttribute("RevealDist") or 0) < (b:GetAttribute("RevealDist") or 0) end
		table.sort(early, byDist)
		table.sort(late, byDist)
		if root then revealAt[root.Name] = now end
		local t = now + s.FirstDelay
		for _, node in early do revealAt[node.Name] = t; t += s.Stagger end
		t += s.LateGap
		for _, node in late do revealAt[node.Name] = t; t += s.Stagger end
		revealEnd = t
		local backdrop = gui:FindFirstChild("FullBackdrop")
		if backdrop then TreeReveal.Darken(backdrop, 0.55, s.DarkenDelay) end
		-- кнопки окна (PERKS / SHRINES / очки / CLOSE) - после бОльшей части веток
		local times = {}
		for name, at in revealAt do
			if root == nil or name ~= root.Name then table.insert(times, at - now) end
		end
		local chrome = {}
		for _, child in tabs:GetChildren() do
			if child:IsA("GuiButton") then table.insert(chrome, child) end
		end
		table.insert(chrome, panel:FindFirstChild("Points"))
		table.insert(chrome, fullClose)
		TreeReveal.Chrome(chrome, TreeReveal.ChromeTime(times, s.FirstDelay) + s.PopSeconds * 0.5)
	end
	for _, node in nodes do
		local at = revealAt[node.Name]
		if at == nil then
			at = math.max(now, revealEnd) + 0.05 -- открылся после покупки
			revealAt[node.Name] = at
		end
		if at > now - 0.02 then
			local delay = math.max(0, at - now)
			TreeReveal.Pop(node, delay, node:GetAttribute("TreeRoot") and s.RootSeconds or nil)
			local id = node.Name:match("^Node_(.+)$")
			if id then
				for _, line in holder:GetChildren() do
					if line:GetAttribute("RevealTo") == id then TreeReveal.FadeIn(line, math.max(0, delay - 0.05)) end
				end
			end
		end
	end
end

renderTree = function()
	Points.Set(pointsLabel, state.Points)
	for _, child in tree:GetChildren() do
		if child:GetAttribute("Generated") then child:Destroy() end
	end
	if cfg.TreeLayout then
		Free.Render()
		Free.Reveal()
		return
	end
	for branchIndex, branch in cfg.Branches or {} do
		local column = branchTemplate:Clone()
		column.Name = "Branch_" .. branch.Id
		column:SetAttribute("Generated", true)
		column.LayoutOrder = branchIndex
		column.Visible = true
		column.Header.BackgroundColor3 = branch.Color
		column.Header.Text.Text = tr(branch.Title)
		column.Parent = tree
		local nodes = column.Nodes
		for index, perkId in branch.Perks do
			local perk = PERK_BY_ID[perkId]
			if perk then
				local info = infoOf(perkId)
				local locked = info.Locked == true
				local maxed = info.Level >= perk.MaxLevel
				local y = (index - 1) * (NODE_SIZE + NODE_GAP)
				-- Линия от предыдущего узла: цвет ветки, если открыто.
				if index > 1 then
					local line = linkTemplate:Clone()
					line.Name = "Link"
					line.Visible = true
					-- От низа плашки уровня предыдущего узла до верха этого.
					line.Position = UDim2.new(0.5, 0, 0, y - NODE_GAP + CHIP_OVERHANG)
					line.Size = UDim2.fromOffset(line.Size.X.Offset, NODE_GAP - CHIP_OVERHANG)
					line.BackgroundColor3 = locked and COLOR_LOCKED or branch.Color
					line.ZIndex = 1 -- v20.64: линия ПОД узлом и плашкой уровня «0/10»
					line.Parent = nodes
				end
				local node = nodeTemplate:Clone()
				node.Name = "Node_" .. perkId
				node.Visible = true
				node.Position = UDim2.new(0.5, 0, 0, y)
				node.Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE)
				node.ZIndex = 3 -- выше линии-связки (у неё 1)
				node.BackgroundColor3 = locked and COLOR_LOCKED or (maxed and branch.Color:Lerp(COLOR_INK, 0.15) or branch.Color:Lerp(COLOR_STAR, 0.55))
				setIcon(node.Icon, perk.Icon, perk.ImageId, locked and 0.55 or 0)
				node.LevelChip.Level.Text = maxed and "MAX" or ("%d/%d"):format(info.Level, perk.MaxLevel)
				node.LevelChip.Level.TextColor3 = maxed and COLOR_GREEN_TEXT or COLOR_GOLD_TEXT
				node.Lock.Visible = locked
				local outline = node:FindFirstChild("Outline")
				if outline then
					outline.Color = (selected == perkId) and Color3.new(1, 1, 1) or COLOR_INK
					outline.Thickness = (selected == perkId) and 5 or 4
				end
				-- Можно купить прямо сейчас — лёгкое свечение.
				local canBuy = node:FindFirstChild("CanBuy")
				if canBuy then
					canBuy.Visible = not locked and not maxed and state.Points >= (info.Cost or math.huge)
				end
				press(node)
				node.Activated:Connect(function()
					UiSfx.play("UiButtonClick")
					selected = perkId
					renderTree()
					renderDetail()
				end)
				node.Parent = nodes
			end
		end
	end
end

local function shrineEffect(def)
	if def.Kind == "Mutation" then
		local mutation = Config.Mutations[def.Mutation]
		return tr("1 of every {n} ore: guaranteed {m}", { n = tostring(def.Every or 3), m = mutation and mutation.DisplayName or def.Mutation })
	elseif def.Kind == "Luck" then
		return tr("+{v}% Luck (permanent)", { v = tostring(math.floor((def.Value or 0) * 100 + 0.5)) })
	end
	return tr("+{v}% Sell Income (permanent)", { v = tostring(math.floor((def.Value or 0) * 100 + 0.5)) })
end

-- v20.94: ИКОНКА СВЯТИЛИЩА = его 3D-модель (рисовать картинку не нужно):
-- широкой стороной к камере (у плоского святилища - верх), с обводкой.
local ShrineIcon = {}
function ShrineIcon.Set(holder, shrineId, def, transparency)
	if not holder then return end
	local ok = false
	if holder:IsA("ImageLabel") or holder:IsA("ImageButton") or holder:IsA("Frame") then
		local OrePreview = require(ReplicatedStorage.Shared.OrePreview)
		local key = "Shrine|" .. tostring(shrineId)
		local existing = holder:FindFirstChild("ModelView")
		if existing and existing:GetAttribute("Key") == key then
			ok = true
		else
			local okBuild, model = pcall(function()
				local PlaceableCatalog = require(ReplicatedStorage.Shared.PlaceableCatalog)
				return require(ReplicatedStorage.Shared.PlaceableFactory).BuildItem(PlaceableCatalog.ShrineId(shrineId))
			end)
			if okBuild and model then
				local okMount, mounted = pcall(OrePreview.MountModel, holder, model, key)
				ok = okMount and mounted
			end
		end
	end
	if ok then
		if holder:IsA("ImageLabel") or holder:IsA("ImageButton") then holder.Image = "" end
		local text = holder:FindFirstChild("Emoji")
		if text then text.Visible = false end
		for _, view in holder:GetChildren() do
			if view:IsA("ViewportFrame") then view.ImageTransparency = transparency or 0 end
		end
	else
		setIcon(holder, def.Icon or "🗿", def.ImageId, transparency)
	end
end

local function renderShrineDetail()
	local def = selectedShrine and SHRINES.Types[selectedShrine]
	if not def then
		detail.Visible = false
		return
	end
	detail.Visible = detailShown
	local info = shrineState[selectedShrine] or {}
	ShrineIcon.Set(detail.Icon, selectedShrine, def)
	detail.Title.Text = tr(def.DisplayName)
	detail.Title.TextColor3 = Color3.fromRGB(255, 220, 110)
	detail.Level.Text = tr("SHRINE · never resets")
	detail.Now.Text = shrineEffect(def)
	detail.Next.Text = tr("Place it on your base")
	detail.Hint.Visible = false
	if info.Owned then
		upgradeText.Text = "✅ " .. tr("OWNED")
		upgradeButton.BackgroundColor3 = COLOR_GREY
	else
		local affordable = state.Points >= (def.Cost or math.huge)
		Points.Set(upgradeText, def.Cost or 0)
		upgradeButton.BackgroundColor3 = affordable and COLOR_GREEN or COLOR_ORANGE
	end
end

local function renderShrines()
	Points.Set(pointsLabel, state.Points)
	for _, child in shrinesList:GetChildren() do
		if child:GetAttribute("Generated") then child:Destroy() end
	end
	for index, shrineId in SHRINES.Order or {} do
		local def = SHRINES.Types[shrineId]
		if def then
			local info = shrineState[shrineId] or {}
			local card = shrineTemplate:Clone()
			card.Name = "Shrine_" .. shrineId
			card:SetAttribute("Generated", true)
			card.Visible = true
			card.LayoutOrder = index
			ShrineIcon.Set(card.Icon, shrineId, def)
			card.Title.Text = tr(def.DisplayName)
			if info.Owned then card.Status.Text = "✅ " .. tr("OWNED"); Points.Hide(card.Status) else Points.Set(card.Status, def.Cost or 0) end
			card.Status.TextColor3 = info.Owned and COLOR_GREEN_TEXT or COLOR_GOLD_TEXT
			card.BackgroundColor3 = (selectedShrine == shrineId) and COLOR_STAR:Lerp(Color3.new(1, 1, 1), 0.25)
				or (info.Owned and COLOR_GREEN:Lerp(COLOR_INK, 0.35) or COLOR_STAR)
			press(card)
			card.Activated:Connect(function()
				UiSfx.play("UiButtonClick")
				showDetail()
				selectedShrine = shrineId
				renderShrines()
				renderShrineDetail()
			end)
			card.Parent = shrinesList
		end
	end
end

local function setMode(newMode)
	mode = newMode
	tree.Visible = mode == "Perks"
	shrinesList.Visible = mode == "Shrines"
	if perksTab:GetAttribute("UiSkin") then
		UiKit.ApplySkin(perksTab, mode == "Perks" and "Button_Yellow" or "Button_Dark")
		UiKit.ApplySkin(shrinesTab, mode == "Shrines" and "Button_Yellow" or "Button_Dark")
	else
		perksTab.BackgroundColor3 = mode == "Perks" and Color3.fromRGB(255, 200, 70) or COLOR_STAR
		shrinesTab.BackgroundColor3 = mode == "Shrines" and Color3.fromRGB(255, 200, 70) or COLOR_STAR
	end
	if mode == "Shrines" then
		selectedShrine = selectedShrine or (SHRINES.Order and SHRINES.Order[1])
		renderShrines()
		renderShrineDetail()
	else
		renderTree()
		renderDetail()
	end
end

renderDetail = function()
	if mode == "Shrines" then
		renderShrineDetail()
		return
	end
	if selected == "__Start" then
		detail.Visible = detailShown
		pcall(require(ReplicatedStorage.Shared.OrePreview).Clear, detail.Icon)
		setIcon(detail.Icon, "✦", nil)
		detail.Title.Text = tr("Start")
		detail.Title.TextColor3 = Color3.fromRGB(200, 150, 255)
		detail.Level.Text = ""
		detail.Now.Text = tr(cfg.StartText or "Your journey begins here.")
		detail.Next.Text = ""
		detail.Hint.Visible = false
		upgradeText.Text = "✦"
		Points.Hide(upgradeText)
		upgradeButton.BackgroundColor3 = COLOR_GREY
		return
	end
	local perk = selected and PERK_BY_ID[selected]
	if not perk then
		detail.Visible = false
		return
	end
	detail.Visible = detailShown
	local info = infoOf(perk.Id)
	local branch = BRANCH_OF[perk.Id]
	pcall(require(ReplicatedStorage.Shared.OrePreview).Clear, detail.Icon) -- v20.94: убрать 3D святилища
	setIcon(detail.Icon, perk.Icon, perk.ImageId)
	detail.Title.Text = tr(perk.Title)
	detail.Title.TextColor3 = branch and branch.Color or (perk.Id == ROOT_PERK and Color3.fromRGB(200, 150, 255)) or Color3.new(1, 1, 1)
	detail.Level.Text = ("LV %d/%d"):format(info.Level, perk.MaxLevel)
	detail.Now.Text = info.Level > 0 and effectText(perk, info.Level) or "-"
	local hint = detail.Hint
	hint.Visible = false
	if info.Level >= perk.MaxLevel then
		detail.Next.Text = "✅ MAX"
		upgradeText.Text = "MAX"
		if upgradeText:FindFirstChild("PointIcon") then upgradeText.PointIcon.Visible = false end
		upgradeButton.BackgroundColor3 = COLOR_GREY
	elseif info.Locked then
		local required = info.Requires and PERK_BY_ID[info.Requires]
		detail.Next.Text = "> " .. effectText(perk, info.Level + 1)
		hint.Visible = true
		hint.Text = "🔒 " .. tr("Needs {p}", { p = required and tr(required.Title) or "?" })
		upgradeText.Text = "🔒"
		Points.Hide(upgradeText)
		upgradeButton.BackgroundColor3 = COLOR_GREY
	else
		detail.Next.Text = "> " .. effectText(perk, info.Level + 1)
		local affordable = state.Points >= (info.Cost or math.huge)
		Points.Set(upgradeText, info.Cost or 0)
		upgradeButton.BackgroundColor3 = affordable and COLOR_GREEN or COLOR_ORANGE
	end
end

local function applyState(payload)
	if type(payload) ~= "table" then return end
	state.Points = tonumber(payload.Points) or 0
	levels = {}
	for _, entry in payload.Perks or {} do levels[entry.Id] = entry end
	shrineState = {}
	for _, entry in payload.Shrines or {} do shrineState[entry.Id] = entry end
	if not selected then
		local first = cfg.Branches and cfg.Branches[1] and cfg.Branches[1].Perks[1]
		selected = cfg.TreeLayout and (ROOT_PERK and PERK_BY_ID[ROOT_PERK] and ROOT_PERK or "__Start") or first
	end
	if mode == "Shrines" then
		renderShrines()
	else
		renderTree()
	end
	renderDetail()
end

-- v20.120: пока открыто окно престижа - камера мира стоит (колесо и
-- перетаскивание двигают только карту прокачек).
local savedCameraType = nil
local function freezeCamera(on)
	local camera = workspace.CurrentCamera
	if not (camera and FULL) then return end
	if on then
		playerGui:SetAttribute("CameraHold", "Prestige") -- сторож камеры не трогает
		if savedCameraType == nil then
			savedCameraType = camera.CameraType
			camera.CameraType = Enum.CameraType.Scriptable
		end
	else
		playerGui:SetAttribute("CameraHold", nil)
		if savedCameraType ~= nil then
			camera.CameraType = savedCameraType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or savedCameraType
			savedCameraType = nil
		end
	end
end

local MovementLock = require(ReplicatedStorage.Shared.MovementLock)
local function open()
	isOpen = true
	freezeCamera(true)
	-- v20.132: шаг обучения «открой дерево престижа»
	local tutorialRemote = ReplicatedStorage.Shared:FindFirstChild("TutorialActionEvent")
	if tutorialRemote then tutorialRemote:FireServer("UiFlag", "PrestigeOpened") end
	-- v20.130: пока выбираешь перк - персонаж стоит (не убегает случайно)
	MovementLock.Lock("Prestige", 600)
	-- на телефоне дерево сразу чуть мельче, чтобы влезало
	if FULL and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and zoom == 1 then
		zoom = tonumber(cfg.PhoneZoom) or 0.75
	end
	if FULL then
		detailShown = false
		detail.Visible = false
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = hrp and hrp.Position or nil
	gui.Enabled = true
	-- v20.144: анимация открытия дерева (узлы по очереди)
	if FULL and cfg.TreeLayout and mode ~= "Shrines" then
		revealPending = true
		pcall(renderTree)
	end
	UiSfx.play("UiMenuOpen")
	if autoScale and not FULL then
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local target = math.min(1.1, (viewport.X - 40) / (Builder.Width + 20), (viewport.Y - 80) / (Builder.Height + 20))
		autoScale.Scale = target * 0.85
		TweenService:Create(autoScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
end

local function close()
	if not isOpen then return end
	isOpen = false
	freezeCamera(false)
	MovementLock.Unlock("Prestige")
	hideDetail()
	UiSfx.play("UiMenuClose")
	gui.Enabled = false
end

closeButton.Activated:Connect(close)
if fullClose then fullClose.Activated:Connect(close) end

-- v20.118: ТАСКАНИЕ ДЕРЕВА (мышь/палец) и масштаб колесом.
local pinching, pinchZoomStart = false, 1
local function applyPan()
	local holder = tree:FindFirstChild("FreeTree")
	if not (holder and FULL) then return end
	local layout = cfg.TreeLayout or {}
	local startPos = layout.Start or { 0.5, 0.5 }
	local size = holder.Size
	local limit = Vector2.new(size.X.Offset, size.Y.Offset) * 0.5 * zoom
	pan = Vector2.new(math.clamp(pan.X, -limit.X, limit.X), math.clamp(pan.Y, -limit.Y, limit.Y))
	holder.Position = UDim2.new(0.5, (0.5 - startPos[1]) * size.X.Offset * zoom + pan.X, 0.5, (0.5 - startPos[2]) * size.Y.Offset * zoom + pan.Y)
	local zoomScale = holder:FindFirstChild("Zoom")
	if zoomScale then zoomScale.Scale = zoom end
end
UserInputService.InputBegan:Connect(function(input)
	if not (FULL and isOpen and mode == "Perks") then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	-- не начинаем таскать с карточки перка и кнопок
	local p = Vector2.new(input.Position.X, input.Position.Y)
	for _, blocker in { detail, fullClose, tabs } do
		if blocker and blocker.Visible then
			local a, sz = blocker.AbsolutePosition, blocker.AbsoluteSize
			if p.X >= a.X and p.Y >= a.Y and p.X <= a.X + sz.X and p.Y <= a.Y + sz.Y then return end
		end
	end
	if pinching then return end
	dragging, dragMoved, dragStart, panStart = true, false, p, pan
end)
-- v20.130: ЩИПОК ДВУМЯ ПАЛЬЦАМИ - масштаб дерева на телефоне (раньше на
-- телефоне масштаба не было вовсе, а второй палец сбивал перетаскивание).
UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, inputState)
	if not (FULL and isOpen and mode == "Perks") then return end
	if inputState == Enum.UserInputState.Begin then
		pinching, pinchZoomStart = true, zoom
		dragging = false
		dragMoved = true -- отпускание после щипка - не клик по узлу
	elseif inputState == Enum.UserInputState.Change and pinching then
		zoom = math.clamp(pinchZoomStart * scale, 0.45, 1.6)
		applyPan()
	else
		pinching = false
		task.delay(0.1, function() dragMoved = false end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if not (FULL and isOpen) then return end
	if dragging and not pinching and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
		if delta.Magnitude > (input.UserInputType == Enum.UserInputType.Touch and 14 or 8) then dragMoved = true end
		if dragMoved then
			pan = panStart + delta
			applyPan()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and mode == "Perks" then
		zoom = math.clamp(zoom + input.Position.Z * 0.08, 0.6, 1.5)
		applyPan()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		-- клик по узлу после перетаскивания не засчитываем; сбрасываем чуть позже
		task.defer(function() dragMoved = false end)
	end
end)
RunService.RenderStepped:Connect(function()
	if isOpen and FULL then placeDetail() end
end)
upgradeButton.Activated:Connect(function()
	showDetail() -- v20.120: после покупки карточка не пропадает сразу
	if mode == "Shrines" then
		if selectedShrine and not (shrineState[selectedShrine] and shrineState[selectedShrine].Owned) then
			remote:FireServer("BuyShrine", selectedShrine)
		end
		return
	end
	if not selected or not PERK_BY_ID[selected] then return end
	remote:FireServer("Buy", selected)
end)
perksTab.Activated:Connect(function()
	UiSfx.play("UiButtonClick")
	setMode("Perks")
end)
shrinesTab.Activated:Connect(function()
	UiSfx.play("UiButtonClick")
	setMode("Shrines")
end)
UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.Escape then close() end
end)

local function bounceNode(perkId)
	local column = BRANCH_OF[perkId] and tree:FindFirstChild("Branch_" .. BRANCH_OF[perkId].Id)
	local node = Free.Find(perkId) or (column and column.Nodes:FindFirstChild("Node_" .. perkId))
	local scale = node and node:FindFirstChild("PressScale")
	if scale then
		scale.Scale = 1.25
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

tree:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if isOpen and mode ~= "Shrines" and cfg.TreeLayout then renderTree() end
end)

remote.OnClientEvent:Connect(function(command, payload)
	if command == "Open" then
		applyState(payload)
		open()
	elseif command == "State" then
		applyState(payload)
	elseif command == "BuyResult" and type(payload) == "table" then
		UiSfx.play(payload.Ok and "PerkUnlock" or "UiError") -- v20.129
		if payload.Ok and payload.ShrineId then
			-- святилище легло в инвентарь (вкладка TOTEMS)
		elseif payload.Ok then
			task.defer(bounceNode, payload.PerkId)
		elseif payload.Reason and isOpen then
			local hint = detail.Hint
			hint.Visible = true
			hint.Text = tr(payload.Reason)
		end
	end
end)

-- Отошёл от чемоданчика — закрываем.
task.spawn(function()
	while true do
		task.wait(0.5)
		if isOpen and openedAt then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp or (hrp.Position - openedAt).Magnitude > 16 then close() end
		end
	end
end)

-- v20.120: перерождение с открытым окном - закрываем (и возвращаем камеру).
player.CharacterAdded:Connect(function()
	if isOpen then close() end
end)
