--------------------------------------------------------------------------------
-- IslandUI (LocalScript) — окно Island Keeper, катсцены подъёма острова
-- и улучшения печи, подписи над своими островами.
--
-- Сервер: server/Services/IslandService.lua, канал RemoteEvent "IslandRequest":
--   сервер → клиент: "Open"(state) / "State"(state) / "Result"(ok, reason, action, id)
--                    "Rise"(islandId, focusPosition, seconds, radius)
--                    "SmelterUpgraded"(newLevel)
--   клиент → сервер: "RequestState" / "Buy"(islandId) / "UpgradeSmelter"
-- Клиент ничего не решает сам: цены, доступность и "хватает ли денег"
-- присылает сервер, окно их только рисует.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local Localization = require(ReplicatedStorage.Shared.Localization)

if not (Config.Islands and Config.Islands.Enabled) then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("IslandRequest", 30)
if not remote then
	warn("[IslandUI] RemoteEvent IslandRequest не появился - окно островов работать не будет.")
	return
end

local cinematicMode = ReplicatedStorage.Shared:FindFirstChild("CinematicMode")
if not cinematicMode then
	cinematicMode = Instance.new("BindableEvent")
	cinematicMode.Name = "CinematicMode"
	cinematicMode.Parent = ReplicatedStorage.Shared
end

local function tr(text, args)
	return Localization.Translate(player.LocaleId, text, args)
end

local function playSfx(name)
	pcall(UiSfx.play, name)
end

--------------------------------------------------------------------------------
-- ОКНО (по референсу: тёмная панель с голубой рамкой, скошенная вкладка
-- заголовка, красный крестик; внутри — КВАДРАТНЫЕ карточки, листаются
-- стрелками/свайпом). Клик по карточке открывает экран улучшения: что
-- даёт, сколько стоит, кнопка покупки и "НАЗАД". Купленное — серое.
-- Улучшения плавильни делаются ВНУТРИ её карточки.
--------------------------------------------------------------------------------
-- v20: окно собирает Shared.UiBuilders.IslandUi (правится в StarterGui/IslandUi).
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local IslandBuilder = require(ReplicatedStorage.Shared.UiBuilders.IslandUi)
local PANEL_SIZE = IslandBuilder.PANEL_SIZE
local CARD_W = IslandBuilder.CARD_W
local CARD_H = IslandBuilder.CARD_H
local CARD_SIZE = CARD_W -- шаг прокрутки стрелками

-- Смысловые состояния → вариант кнопки темы.
local COLORS = {
	Text = UiKit.Theme.Colors.Text,
	Muted = UiKit.Theme.Colors.SubText,
	Buy = "Green",
	Poor = "Red", -- v20.105: не хватает денег - красная
	Grey = "Dark",
}
local DARK_CARD = UiKit.Theme.Skins.Card.Color

local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("IslandUi")
-- v20.143: хуки полноэкранного дерева островов (заполняются в конце файла)
local treeHooks = {}
gui.Enabled = false
local dimmer = gui:WaitForChild("Dimmer")
local panel = gui:WaitForChild("Panel")
local panelScale = panel:WaitForChild("PanelScale")
local closeButton = panel:WaitForChild("CloseButton")
local toast = panel:WaitForChild("Toast")
local templates = panel:WaitForChild("Templates")
local content = panel:WaitForChild("Content")
local gridView = content:WaitForChild("GridView")
local scroller = gridView:WaitForChild("Cards")
local leftArrow = gridView:WaitForChild("Left")
local rightArrow = gridView:WaitForChild("Right")
local footer = gridView:WaitForChild("Footer")
local detailView = content:WaitForChild("DetailView")
local backButton = detailView:WaitForChild("Back")
local previewHolder = detailView:WaitForChild("PreviewHolder")
local info = detailView:WaitForChild("Info")
local detailTitle = info:WaitForChild("Title")
local detailDesc = info:WaitForChild("Desc")
local perksHeader = info:WaitForChild("PerksHeader")
local perksList = info:WaitForChild("Perks")
local upgradeBox = info:WaitForChild("Upgrade")
local upgradeTitle = upgradeBox:WaitForChild("Title")
local pipRow = upgradeBox:WaitForChild("Pips")
local upgradeText = upgradeBox:WaitForChild("Text")
local priceLabel = detailView:WaitForChild("Price")
local actionButton = detailView:WaitForChild("Action")
local actionText = actionButton:WaitForChild("Caption")

panel:WaitForChild("TitleBar"):WaitForChild("Title").Text = tr("Islands")
panel:WaitForChild("Subtitle").Text = tr("Unlock islands behind your base!")
gridView:WaitForChild("Hint").Text = tr("Tap a card to see what it gives")
backButton:WaitForChild("Caption").Text = tr("BACK")

--------------------------------------------------------------------------------
-- КАРТОЧКА (общая для сетки и превью на экране улучшения) — клон шаблона.
--------------------------------------------------------------------------------
local function makeCardVisual(parent, width, height)
	local card = templates:WaitForChild("Card"):Clone()
	card.Visible = true -- шаблоны в Templates скрыты
	card.Size = UDim2.fromOffset(width, height or width)
	card.Parent = parent
	return {
		Card = card,
		Rim = card:FindFirstChild("SkinStroke"),
		Scale = card:FindFirstChild("Pop"),
		Image = card:FindFirstChild("Image"),
		Icon = card:WaitForChild("Icon"),
		Name = card:WaitForChild("Title"),
		ChipText = card:WaitForChild("Chip"):WaitForChild("Text"),
		Lock = card:WaitForChild("Lock"),
		Shine = card:FindFirstChild("Shine"),
	}
end

-- Состояния: OWNED — приглушённая, LOCKED — тёмная с замком, иначе —
-- рамка и лёгкий тон цвета острова.
local function applyCard(visual, entry)
	local color = entry.Color or Color3.new(1, 1, 1)
	local hasImage = visual.Image ~= nil and typeof(entry.Image) == "string" and entry.Image ~= ""
	if visual.Image then visual.Image.Image = hasImage and UiKit.ImageUri(entry.Image) or "" end
	visual.Icon.Text = hasImage and "" or (entry.Icon ~= "" and entry.Icon or "?")
	visual.Name.Text = tr(entry.DisplayName)
	visual.Lock.Visible = false
	if visual.Shine then visual.Shine.Visible = true end
	if entry.Owned then
		visual.Card.BackgroundColor3 = DARK_CARD:Lerp(Color3.fromRGB(90, 92, 100), 0.35)
		visual.Icon.TextTransparency = 0.35
		visual.Name.TextColor3 = Color3.fromRGB(205, 205, 212)
		if visual.Rim then visual.Rim.Color = Color3.fromRGB(120, 122, 132) end
		if visual.Shine then visual.Shine.Visible = false end
		local levelText = entry.UpgradeLevel and ("  LV %d/%d"):format(entry.UpgradeLevel, entry.UpgradeMax) or ""
		visual.ChipText.Text = '<font color="#9CFFB4">✅ ' .. tr("OWNED") .. "</font>" .. levelText
	elseif not entry.RequiresMet then
		visual.Card.BackgroundColor3 = DARK_CARD
		visual.Icon.TextTransparency = 0.6
		visual.Name.TextColor3 = COLORS.Muted
		if visual.Rim then visual.Rim.Color = Color3.fromRGB(70, 70, 80) end
		visual.Lock.Visible = true
		visual.ChipText.Text = '<font color="#FFB35A">' .. tr("Needs {name}", { name = tr(entry.RequiresName or "") }) .. "</font>"
	else
		visual.Card.BackgroundColor3 = DARK_CARD:Lerp(color, 0.28)
		visual.Icon.TextTransparency = 0
		visual.Name.TextColor3 = COLORS.Text
		if visual.Rim then visual.Rim.Color = color end
		visual.ChipText.Text = entry.CanAfford
			and ('<font color="#FFE27A">' .. entry.CostText .. "</font>")
			or ('<font color="#FF9E6A">' .. entry.CostText .. "</font>")
	end
end

local function scrollBy(direction)
	local maxX = math.max(0, scroller.AbsoluteCanvasSize.X - scroller.AbsoluteWindowSize.X)
	local target = math.clamp(scroller.CanvasPosition.X + direction * (CARD_SIZE + 16), 0, maxX)
	TweenService:Create(scroller, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CanvasPosition = Vector2.new(target, 0),
	}):Play()
	playSfx("UiTabSwitch")
end
leftArrow.Activated:Connect(function() scrollBy(-1) end)
rightArrow.Activated:Connect(function() scrollBy(1) end)
local function refreshArrows()
	local overflow = scroller.AbsoluteCanvasSize.X > scroller.AbsoluteWindowSize.X + 2
	leftArrow.Visible = overflow
	rightArrow.Visible = overflow
end
scroller:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refreshArrows)
scroller:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refreshArrows)

local preview = makeCardVisual(previewHolder, 150, 224)
preview.Card.Active = false

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ / ОТРИСОВКА
--------------------------------------------------------------------------------
local gridCards = {} -- [islandId] = visual
local currentState = nil
local selectedId = nil
local isOpen = false
local pendingAction = false
-- v20.168: анимация улучшения узла дерева после покупки острова/печи
local islandTreeBump = { Id = nil, Fn = nil }

local function islandInfo(id)
	for _, entry in (currentState and currentState.Islands) or {} do
		if entry.Id == id then return entry end
	end
	return nil
end

-- Карточка плавильни дополнительно показывает уровень печи.
local function decorated(entry)
	if entry.Id == "Smelter" and entry.Owned and currentState.Smelter then
		local copy = table.clone(entry)
		copy.UpgradeLevel = currentState.Smelter.Level
		copy.UpgradeMax = currentState.Smelter.MaxLevel
		return copy
	end
	return entry
end

local currentVariant = "Green"
local function setAction(text, variant, enabled)
	actionText.Text = text
	currentVariant = variant
	UiKit.SetButtonVariant(actionButton, variant)
	actionButton.Active = enabled
end

-- v20.140: кнопка мини-дерева купленного острова (Config.IslandPerks)
-- (билдер IslandUi: DetailView/PerksButton, Content/PerkTree, Templates/Perk*)
local perksButton = detailView:WaitForChild("PerksButton")
perksButton.Visible = false
require(ReplicatedStorage.Shared.TutorialTarget).Mark(perksButton, "IslandPerks")

local function renderDetail()
	local entry = selectedId and islandInfo(selectedId)
	if not entry then return end
	local hasPerks = entry.Owned and Config.IslandPerks and Config.IslandPerks.Islands[entry.Id] ~= nil
	perksButton.Visible = hasPerks == true
	priceLabel.Visible = not hasPerks
	entry = decorated(entry)
	applyCard(preview, entry)
	detailTitle.Text = tr(entry.DisplayName):upper()
	detailTitle.TextColor3 = (entry.Color or COLORS.Text):Lerp(Color3.new(1, 1, 1), 0.35)
	detailDesc.Text = tr(entry.Description)

	local smelter = currentState.Smelter
	local showUpgrade = entry.Id == "Smelter" and entry.Owned and smelter ~= nil
	perksHeader.Visible = not showUpgrade
	perksList.Visible = not showUpgrade
	upgradeBox.Visible = showUpgrade

	for _, child in perksList:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	perksHeader.Text = tr("WHAT YOU GET:")
	for index, perk in entry.Perks or {} do
		local line = templates:WaitForChild("PerkLine"):Clone()
		line.Visible = true -- шаблоны в Templates скрыты
		line.Text = '<font color="#6CFF9A">✅</font>  ' .. tr(perk)
		line.LayoutOrder = index
		line.Parent = perksList
	end

	if showUpgrade then
		for _, child in pipRow:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		for level = 1, smelter.MaxLevel do
			local pip = templates:WaitForChild("Pip"):Clone()
			pip.Visible = true -- шаблоны в Templates скрыты
			pip.LayoutOrder = level
			local reached = level <= smelter.Level
			pip.BackgroundColor3 = reached and UiKit.Theme.Accents.Gold.Main or UiKit.Theme.Skins.Slot.Color
			local pipStroke = pip:FindFirstChild("SkinStroke")
			if pipStroke then pipStroke.Color = reached and UiKit.Theme.Accents.Gold.Light or Color3.fromRGB(95, 95, 105) end
			local slots = smelter.Levels and smelter.Levels[level] and smelter.Levels[level].Slots or level
			pip.Text.Text = "x" .. slots
			pip.Parent = pipRow
		end
		upgradeTitle.Text = tr("FURNACE LV {level}/{max}", { level = smelter.Level, max = smelter.MaxLevel }) .. ' - <font color="#FFD75A">' .. tr(smelter.Name or "") .. "</font>"
		if smelter.NextSlots then
			upgradeText.Text = tr("Next: {name} - smelts {slots} → {next} ores at once, a bit faster. Ingot price x{mult}.", {
				name = tr(smelter.NextName or ""), slots = smelter.Slots, next = smelter.NextSlots, mult = smelter.Multiplier,
			})
			priceLabel.Text = '<font color="#FFD75A">' .. smelter.NextCostText .. "</font>"
			setAction(tr("UPGRADE"), smelter.CanAfford and COLORS.Buy or COLORS.Poor, true)
		else
			upgradeText.Text = tr("Max level! Smelts {slots} ores at once. Ingot price x{mult}.", { slots = smelter.Slots, mult = smelter.Multiplier })
			priceLabel.Text = ""
			setAction(tr("MAX LEVEL"), COLORS.Grey, false)
		end
	elseif entry.Owned then
		priceLabel.Text = '<font color="#9CFFB4">' .. tr("OWNED") .. "</font>"
		setAction(tr("OWNED"), COLORS.Grey, false)
	elseif not entry.RequiresMet then
		priceLabel.Text = '<font color="#FFD75A">' .. entry.CostText .. "</font>"
		setAction(tr("Needs {name}", { name = tr(entry.RequiresName or "") }), COLORS.Grey, false)
	else
		priceLabel.Text = '<font color="#FFD75A">' .. entry.CostText .. "</font>"
		setAction(tr("BUY"), entry.CanAfford and COLORS.Buy or COLORS.Poor, true)
	end
	if pendingAction then setAction("...", currentVariant, false) end
end

local function render(state)
	if not state then return end
	currentState = state
	for order, entry in state.Islands do
		local visual = gridCards[entry.Id]
		if not visual then
			visual = makeCardVisual(scroller, CARD_W, CARD_H)
			visual.Card.Name = "Card_" .. entry.Id
			visual.Card.LayoutOrder = order
			local id = entry.Id
			visual.Card.MouseEnter:Connect(function()
				TweenService:Create(visual.Scale, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
			end)
			visual.Card.MouseLeave:Connect(function()
				TweenService:Create(visual.Scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
			end)
			visual.Card.Activated:Connect(function()
				selectedId = id
				playSfx("UiButtonClick")
				-- переход на экран улучшения
				gridView.Visible = false
				detailView.Visible = true
				detailView.GroupTransparency = 1
				detailView.Position = UDim2.fromOffset(40, 0)
				renderDetail()
				TweenService:Create(detailView, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					GroupTransparency = 0, Position = UDim2.new(),
				}):Play()
			end)
			gridCards[entry.Id] = visual
			require(ReplicatedStorage.Shared.TutorialTarget).Mark(visual.Card, "IslandCard:" .. entry.Id) -- v20.110
		end
		applyCard(visual, decorated(entry))
	end
	footer.Text = state.RebirthUnlocked
		and ('<font color="#6CFF9A">%s</font>'):format(tr("PRESTIGE UNLOCKED - talk to the Prestige Mayor at your base."))
		or ('<font color="#FF9E3C">%s</font>'):format(tr("PRESTIGE LOCKED - unlock every island first."))
	refreshArrows()
	if detailView.Visible then renderDetail() end
	if treeHooks.Refresh then treeHooks.Refresh() end
end

local closePerksView = nil
local function showGrid(animated)
	selectedId = nil
	if closePerksView then closePerksView() end
	detailView.Visible = false
	gridView.Visible = true
	if animated then
		gridView.GroupTransparency = 1
		gridView.Position = UDim2.fromOffset(-40, 0)
		TweenService:Create(gridView, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 0, Position = UDim2.new(),
		}):Play()
	else
		gridView.GroupTransparency = 0
		gridView.Position = UDim2.new()
	end
end

backButton.Activated:Connect(function()
	playSfx("UiCancel")
	showGrid(true)
end)

--------------------------------------------------------------------------------
-- v20.140: МИНИ-ДЕРЕВО ОСТРОВА. Две звезды слева (уровни) → финальный узел
-- справа (открывается, когда обе звезды на максимуме). Справа - карточка
-- выбранного узла с кнопкой покупки. Сервер - IslandPerkService.
--------------------------------------------------------------------------------
local perkRemote = ReplicatedStorage.Shared:WaitForChild("IslandPerkRequest", 10)
local NumberFormatMod = require(ReplicatedStorage.Shared.NumberFormat)
local perkState = {}
local perkIsland = nil
local perkSelected = nil
local perkBusy = false

local perkView = content:WaitForChild("PerkTree")
perkView.Visible = false
local perkBack = perkView:WaitForChild("Back")
local perkTitle = perkView:WaitForChild("Title")
local nodeArea = perkView:WaitForChild("Nodes")
local card = perkView:WaitForChild("Card")
local cardStroke = card:FindFirstChildWhichIsA("UIStroke")
local cardTitle = card:WaitForChild("Title")
local cardLevel = card:WaitForChild("Level")
local cardText = card:WaitForChild("Text")
local cardBuy = card:WaitForChild("Buy")

-- Форма узла (Shape) красится картинкой, если ей задали Image, иначе фоном.
local function paintShape(shape, color)
	if not shape then return end
	if shape.Image ~= "" then
		shape.ImageColor3 = color
	else
		shape.BackgroundColor3 = color
	end
end

local perkNodes = {} -- [perkId] = { Button, Icon, Level, Def, IsFinal }
local perkLines = {}

local function perkPct(v) return tostring(math.floor((v or 0) * 1000 + 0.5) / 10) end
local function perkText(def, value)
	local text = tr(def.Text or "")
	return (text:gsub("{v}", perkPct(value)))
end

local function renderPerks()
	local island = perkIsland and Config.IslandPerks.Islands[perkIsland]
	if not island then return end
	for perkId, node in perkNodes do
		local st = perkState[perkId] or { Level = 0, MaxLevel = node.IsFinal and 1 or (node.Def.MaxLevel or 10), Locked = true }
		local maxed = st.Level >= st.MaxLevel
		local color = node.IsFinal and UiKit.Theme.Accents.Gold.Main or Color3.fromRGB(110, 190, 255)
		paintShape(node.Shape, st.Locked and Color3.fromRGB(60, 62, 74) or (maxed and color or color:Lerp(Color3.fromRGB(30, 34, 48), 0.45)))
		if node.Stroke then
			node.Stroke.Color = perkSelected == perkId and Color3.new(1, 1, 1) or Color3.fromRGB(12, 14, 22)
			node.Stroke.Thickness = perkSelected == perkId and 4 or 3
		end
		node.Level.Text = st.Locked and (node.IsFinal and tr("LOCKED") or "") or (maxed and "MAX" or (st.Level .. "/" .. st.MaxLevel))
		node.Level.TextColor3 = (not st.Locked and not maxed and st.CanAfford) and Color3.fromRGB(108, 255, 126) or Color3.fromRGB(240, 240, 245)
	end
	for _, line in perkLines do
		local st = perkState[line.From]
		local done = st and st.Level >= st.MaxLevel
		line.Frame.BackgroundColor3 = done and UiKit.Theme.Accents.Gold.Main or Color3.fromRGB(80, 84, 98)
	end
	local node = perkSelected and perkNodes[perkSelected]
	if not node then return end
	local def = node.Def
	if cardStroke then cardStroke.Color = node.IsFinal and UiKit.Theme.Accents.Gold.Main or Color3.fromRGB(110, 190, 255) end
	local st = perkState[perkSelected] or { Level = 0, MaxLevel = node.IsFinal and 1 or (def.MaxLevel or 10), Value = 0, Locked = true }
	local maxed = st.Level >= st.MaxLevel
	cardTitle.Text = (def.Icon or "") .. " " .. tr(def.Title or perkSelected)
	cardLevel.Text = node.IsFinal and (maxed and tr("OWNED") or tr("FINAL UPGRADE")) or (tr("Level") .. " " .. st.Level .. " / " .. st.MaxLevel)
	if node.IsFinal then
		cardText.Text = tr(def.Text or "")
	elseif maxed then
		cardText.Text = perkText(def, st.Value)
	else
		cardText.Text = perkText(def, st.Value) .. '\n<font color="#6CFF7E">' .. tr("Next") .. ": +" .. perkPct(st.NextValue) .. "%</font>"
	end
	local caption = cardBuy:FindFirstChild("Caption")
	if maxed then
		UiKit.SetButtonVariant(cardBuy, "Dark")
		if caption then caption.Text = tr("MAX") end
	elseif st.Locked then
		UiKit.SetButtonVariant(cardBuy, "Dark")
		if caption then caption.Text = node.IsFinal and tr("Max both stars") or tr("Buy the island") end
	elseif perkBusy then
		if caption then caption.Text = "..." end
	else
		UiKit.SetButtonVariant(cardBuy, st.CanAfford and "Green" or "Red")
		if caption then caption.Text = tr("BUY") .. "  $" .. NumberFormatMod.abbreviate(st.Cost or 0) end
	end
end

local function fetchPerks()
	if not perkRemote then return end
	task.spawn(function()
		local okCall, _, _, state = pcall(perkRemote.InvokeServer, perkRemote, "Get")
		if okCall and type(state) == "table" then
			perkState = state
			renderPerks()
		end
	end)
end

local function makePerkNode(perkId, def, isFinal, center)
	local button = templates:WaitForChild(isFinal and "PerkFinal" or "PerkStar"):Clone()
	button.Name = "Perk_" .. perkId
	button.Visible = true
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = center
	button.ZIndex = 23
	button.Parent = nodeArea
	local shape = button:FindFirstChild("Shape")
	local icon = button:FindFirstChild("Icon")
	if icon then icon.Text = def.Icon or "★" end
	local name = button:FindFirstChild("Name")
	if name then name.Text = tr(def.Title or perkId) end
	button.Activated:Connect(function()
		perkSelected = perkId
		playSfx("UiButtonClick")
		renderPerks()
	end)
	perkNodes[perkId] = {
		Button = button, Shape = shape, Stroke = shape and shape:FindFirstChildWhichIsA("UIStroke"),
		Level = button:FindFirstChild("Level") or Instance.new("TextLabel"), Def = def, IsFinal = isFinal,
	}
end

local function connect(fromId, a, b)
	local delta = b - a
	local line = templates:WaitForChild("PerkLine"):Clone()
	line.Name = "Line_" .. fromId
	line.Visible = true
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	line.Size = UDim2.fromOffset(delta.Magnitude, line.Size.Y.Offset > 0 and line.Size.Y.Offset or 6)
	line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	line.ZIndex = 22
	line.Parent = nodeArea
	table.insert(perkLines, { From = fromId, Frame = line })
end

local function buildPerkTree(islandId)
	for _, child in nodeArea:GetChildren() do child:Destroy() end
	table.clear(perkNodes)
	table.clear(perkLines)
	local island = Config.IslandPerks.Islands[islandId]
	if not island then return end
	local w = math.max(300, nodeArea.AbsoluteSize.X / math.max(panelScale.Scale, 0.01))
	local h = math.max(240, nodeArea.AbsoluteSize.Y / math.max(panelScale.Scale, 0.01))
	local stars = island.Stars or {}
	local finalPos = Vector2.new(w * 0.74, h * 0.5)
	for index, def in stars do
		local pos = Vector2.new(w * 0.26, h * (#stars == 1 and 0.5 or (index == 1 and 0.27 or 0.73)))
		if island.Final then connect(def.Id, pos, finalPos) end
		makePerkNode(def.Id, def, false, UDim2.fromOffset(pos.X, pos.Y))
	end
	if island.Final then
		makePerkNode(island.Final.Id, island.Final, true, UDim2.fromOffset(finalPos.X, finalPos.Y))
	end
	perkSelected = stars[1] and stars[1].Id or (island.Final and island.Final.Id)
end

local function openPerks(islandId)
	perkIsland = islandId
	local entry = islandInfo(islandId)
	perkTitle.Text = tr((entry and entry.DisplayName) or islandId):upper() .. " " .. tr("UPGRADES")
	perkView.Visible = true
	task.defer(function()
		buildPerkTree(islandId)
		renderPerks()
	end)
	fetchPerks()
end
local function closePerks()
	perkView.Visible = false
	perkIsland = nil
end
closePerksView = closePerks

perksButton.Activated:Connect(function()
	if selectedId then
		playSfx("UiButtonClick")
		openPerks(selectedId)
	end
end)
perkBack.Activated:Connect(function()
	playSfx("UiCancel")
	closePerks()
end)
cardBuy.Activated:Connect(function()
	local id = perkSelected
	local st = id and perkState[id]
	if not (id and perkRemote) or perkBusy or (st and (st.Locked or st.Level >= st.MaxLevel)) then return end
	perkBusy = true
	renderPerks()
	task.spawn(function()
		local okCall, ok, reason, state = pcall(perkRemote.InvokeServer, perkRemote, "Buy", id)
		perkBusy = false
		if okCall then
			if type(state) == "table" then perkState = state end
			playSfx(ok and "Upgrade" or "UiError")
			if not ok and reason then
				toast.Text = tr(reason)
				toast.TextTransparency = 0
				task.delay(2, function() toast.TextTransparency = 1 end)
			end
		end
		renderPerks()
	end)
end)
-- пока дерево открыто - раз в 2 с освежаем цены (деньги меняются)
task.spawn(function()
	while true do
		task.wait(2)
		if (perkView.Visible and gui.Enabled) or (treeHooks.IsOpen and treeHooks.IsOpen()) then fetchPerks() end
	end
end)

local toastToken = 0
local function showToast(text, good)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = good and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(255, 120, 120)
	toast.TextTransparency = 0
	task.delay(2.2, function()
		if toastToken == token then
			TweenService:Create(toast, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end)
end

local function fitScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.min(1.15, (viewport.X - 40) / PANEL_SIZE.X, (viewport.Y - 80) / PANEL_SIZE.Y)
end

local function keeperRoot()
	local folder = workspace:FindFirstChild("IslandKeeper")
	local npc = folder and folder:FindFirstChildWhichIsA("Model")
	return npc and (npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true))
end

local function close()
	if not isOpen then return end
	isOpen = false
	playSfx("UiMenuClose")
	if treeHooks.Close then
		treeHooks.Close()
		gui.Enabled = false
		return
	end
	local tween = TweenService:Create(panelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = panelScale.Scale * 0.85 })
	tween:Play()
	tween.Completed:Wait()
	if not isOpen then gui.Enabled = false end
end

local function open(state)
	render(state)
	if isOpen then return end
	isOpen = true
	playSfx("UiMenuOpen")
	if treeHooks.Open then
		-- v20.143: полноэкранное дерево вместо окна с карточками
		treeHooks.Open()
	else
		showGrid(false)
		fitScale()
		local target = panelScale.Scale
		panelScale.Scale = target * 0.85
		gui.Enabled = true
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
	task.spawn(function()
		while isOpen do
			task.wait(2)
			if not isOpen then break end
			local root = keeperRoot()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and hrp and (root.Position - hrp.Position).Magnitude > (Config.Islands.KeeperPromptDistance or 12) + 18 then
				close()
				break
			end
			remote:FireServer("RequestState")
		end
	end)
end

closeButton.Activated:Connect(close)
dimmer.Activated:Connect(close)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isOpen then return end
	if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Backspace then
		if detailView.Visible then showGrid(true) else close() end
	end
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if isOpen then fitScale() end
end)

-- captureSmelterSnapshot / cancelSmelterSnapshot определены ниже (катсцена
-- улучшения печи); здесь — только вызов.
local captureSmelterSnapshot, cancelSmelterSnapshot

require(ReplicatedStorage.Shared.TutorialTarget).Mark(actionButton, "IslandBuy") -- v20.110
actionButton.Activated:Connect(function()
	if not actionButton.Active or pendingAction or not selectedId then
		playSfx("UiError")
		return
	end
	local entry = islandInfo(selectedId)
	if not entry then return end
	pendingAction = true
	playSfx("UiConfirm")
	if entry.Id == "Smelter" and entry.Owned then
		captureSmelterSnapshot()
		remote:FireServer("UpgradeSmelter")
	else
		remote:FireServer("Buy", entry.Id)
	end
	renderDetail()
	task.delay(3, function()
		if pendingAction then pendingAction = false; renderDetail() end
	end)
end)

--------------------------------------------------------------------------------
-- КАТСЦЕНА ПОДЪЁМА ОСТРОВА
--------------------------------------------------------------------------------
local cinematicBusy = false

local function spawnDebris(center, radius)
	local folder = Instance.new("Folder")
	folder.Name = "IslandRiseDebris"
	folder.Parent = workspace
	local rocks = {}
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2 + (math.random() - 0.5) * 0.4
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local size = 0.8 + math.random() * 1.4
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Rock
		part.Color = Color3.fromRGB(120 + math.random(-15, 15), 105, 90)
		part.Size = Vector3.new(size, size * 0.8, size)
		part.Parent = folder
		table.insert(rocks, {
			Part = part,
			Position = center + dir * radius + Vector3.new(0, 0.5, 0),
			Velocity = dir * (8 + math.random() * 10) + Vector3.new(0, 16 + math.random() * 12, 0),
			Spin = CFrame.Angles(math.random() * 0.3, math.random() * 0.3, math.random() * 0.3),
			Rotation = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
		})
	end
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 1 / 20)
		local elapsed = os.clock() - started
		if elapsed > 1.4 or not folder.Parent then
			connection:Disconnect()
			if folder.Parent then folder:Destroy() end
			return
		end
		for _, rock in rocks do
			rock.Velocity -= Vector3.new(0, 60 * dt, 0)
			rock.Position += rock.Velocity * dt
			if rock.Position.Y < center.Y - 1 then
				rock.Position = Vector3.new(rock.Position.X, center.Y - 1, rock.Position.Z)
				rock.Velocity = Vector3.new(rock.Velocity.X * 0.5, math.abs(rock.Velocity.Y) * 0.3, rock.Velocity.Z * 0.5)
			end
			rock.Rotation = rock.Spin * rock.Rotation
			rock.Part.CFrame = CFrame.new(rock.Position) * rock.Rotation
			rock.Part.Transparency = elapsed > 1 and (elapsed - 1) / 0.4 or 0
		end
	end)
end

local function playRiseCinematic(islandId, topPosition, seconds, radius)
	if cinematicBusy or typeof(topPosition) ~= "Vector3" then return end
	local camera = workspace.CurrentCamera
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (camera and hrp) then return end
	-- Камера уже в чужой катсцене (апгрейд, шахта) — не перехватываем.
	if camera.CameraType == Enum.CameraType.Scriptable then return end
	cinematicBusy = true
	seconds = tonumber(seconds) or 3
	close()
	cinematicMode:Fire(true, "Island")

	local restoreType = camera.CameraType
	local startCFrame = camera.CFrame
	local startFov = camera.FieldOfView
	local ok, err = pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		-- Ракурс: чуть сбоку от линии "игрок → остров", выше острова, чтобы
		-- было видно и сам остров, и участок перед ним.
		local toIsland = topPosition - hrp.Position
		toIsland = Vector3.new(toIsland.X, 0, toIsland.Z)
		local dir = toIsland.Magnitude > 1 and -toIsland.Unit or Vector3.new(0, 0, 1)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		-- Дистанция — от размера макета: большой остров должен влезть в кадр.
		radius = math.max(8, tonumber(radius) or (Config.Islands.Radius or 10))
		local distance = radius * 2.6 + 10
		local eye = topPosition + dir * distance + side * (distance * 0.3) + Vector3.new(0, distance * 0.55, 0)
		local focus = topPosition + Vector3.new(0, 2, 0)
		local shot = CFrame.lookAt(eye, focus)

		local flyIn = TweenService:Create(camera, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = shot, FieldOfView = 60 })
		flyIn:Play()
		flyIn.Completed:Wait()

		-- Остров уже поехал на сервере (Rise приходит в момент старта) —
		-- тряска камеры и осколки из земли на всю длительность подъёма.
		spawnDebris(topPosition, radius + 1)
		local riseStart = os.clock()
		local remaining = math.max(0.5, seconds - 0.7)
		local burstAt = 0.45
		while os.clock() - riseStart < remaining do
			local t = (os.clock() - riseStart) / remaining
			local amplitude = 0.45 * (1 - t) + 0.05
			camera.CFrame = shot * CFrame.new((math.random() - 0.5) * amplitude, (math.random() - 0.5) * amplitude, 0)
			if t > burstAt then
				burstAt = 2
				spawnDebris(topPosition, math.max(2, radius - 1))
			end
			RunService.RenderStepped:Wait()
		end
		camera.CFrame = shot
		playSfx("UiSuccess")
		task.wait(0.7)

		local back = TweenService:Create(camera, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = startCFrame, FieldOfView = startFov })
		back:Play()
		back.Completed:Wait()
	end)
	if not ok then warn("[IslandUI] Катсцена острова упала, возвращаю камеру:", err) end
	camera.CameraType = restoreType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or restoreType
	camera.FieldOfView = startFov
	cinematicMode:Fire(false, "Island")
	cinematicBusy = false
end

--------------------------------------------------------------------------------
-- КАТСЦЕНА УЛУЧШЕНИЯ ПЕЧИ — тот же приём, что у апгрейда шахты
-- (CustomCartUI, setupUpgradeRevealCinematic):
--   • ДО запроса снимаем слепок текущей печи;
--   • когда сервер удаляет старую — слепок в тот же кадр встаёт на её
--     место ("дублёр"), новую печь прячем ЛОКАЛЬНО, пока до неё не дойдёт
--     сцена — старая не пропадает ни на кадр;
--   • камера подлетает → старая трясётся, "вздувается", схлопывается →
--     новая вырастает с перелётом, осколками и вспышкой → камера назад.
--------------------------------------------------------------------------------
local ProximityPromptService = game:GetService("ProximityPromptService")

local smelterSnapshot = nil -- { Clone, Old, New, Connections = {} }

local function findOwnSmelter()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _, descendant in plots:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("IsSmelter") == true
			and descendant:GetAttribute("OwnerUserId") == player.UserId then
			return descendant
		end
	end
	return nil
end

local function setLocalHidden(model, hidden)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = hidden and 1 or 0
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = not hidden
		end
	end
end

local function cleanClone(model)
	local clone = model:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.LocalTransparencyModifier = 0
		elseif descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector") or descendant:IsA("BillboardGui")
			or descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	return clone
end

cancelSmelterSnapshot = function()
	local snapshot = smelterSnapshot
	smelterSnapshot = nil
	if not snapshot then return end
	for _, connection in snapshot.Connections do connection:Disconnect() end
	if snapshot.Clone then snapshot.Clone:Destroy() end
	if snapshot.New and snapshot.New.Parent then setLocalHidden(snapshot.New, false) end
end

captureSmelterSnapshot = function()
	cancelSmelterSnapshot()
	local model = findOwnSmelter()
	if not model then return end
	local snapshot = { Clone = cleanClone(model), Old = model, New = nil, Connections = {} }
	smelterSnapshot = snapshot
	local function showStandIn()
		if smelterSnapshot == snapshot and snapshot.Clone and snapshot.Clone.Parent == nil then
			snapshot.Clone.Parent = workspace
		end
	end
	table.insert(snapshot.Connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then showStandIn() end
	end))
	local island = model.Parent
	if island then
		table.insert(snapshot.Connections, island.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child:GetAttribute("IsSmelter") == true and child ~= model then
				snapshot.New = child
				setLocalHidden(child, true)
				-- Детали/билборды могут доехать чуть позже самой модели.
				table.insert(snapshot.Connections, child.DescendantAdded:Connect(function(descendant)
					if smelterSnapshot ~= snapshot then return end
					if descendant:IsA("BasePart") then descendant.LocalTransparencyModifier = 1
					elseif descendant:IsA("BillboardGui") then descendant.Enabled = false end
				end))
				showStandIn()
			end
		end))
	end
end

local function scaleAbout(model, baseScale, factor, anchor)
	local current = model:GetScale()
	local target = baseScale * math.max(factor, 0.02)
	if current <= 0 or math.abs(current - target) < 1e-4 then return end
	local k = target / current
	local pivotBefore = model:GetPivot().Position
	model:ScaleTo(target)
	model:PivotTo(model:GetPivot() + (anchor - pivotBefore) * (1 - k))
end

local function flash(position)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Range = 20
	light.Brightness = 6
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110))
	sparks.Size = NumberSequence.new(0.7)
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Parent = anchor
	sparks:Emit(28)
	task.delay(2, function() anchor:Destroy() end)
end

local function playSmelterUpgradeCinematic(level)
	local snapshot = smelterSnapshot
	if not snapshot then return end
	-- Новая печь могла реплицироваться чуть позже события.
	local deadline = os.clock() + 2
	while not snapshot.New and os.clock() < deadline do
		local found = findOwnSmelter()
		if found and found ~= snapshot.Old and found:GetAttribute("SmelterLevel") == level then
			snapshot.New = found
			setLocalHidden(found, true)
		end
		task.wait(0.05)
	end
	local newModel = snapshot.New
	local camera = workspace.CurrentCamera
	if not (newModel and camera) or cinematicBusy or camera.CameraType == Enum.CameraType.Scriptable then
		cancelSmelterSnapshot()
		return
	end
	cinematicBusy = true
	close()
	cinematicMode:Fire(true, "IslandTravel")
	local promptsWere = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false
	local restoreType = camera.CameraType
	local startCFrame = camera.CFrame
	local startFov = camera.FieldOfView
	local oldClone = snapshot.Clone
	local newClone = nil

	local ok, err = pcall(function()
		if oldClone.Parent == nil then oldClone.Parent = workspace end
		local newCf, newSize = newModel:GetBoundingBox()
		local oldCf, oldSize = oldClone:GetBoundingBox()
		local center = (newCf.Position + oldCf.Position) / 2
		local radius = math.max(newSize.Magnitude, oldSize.Magnitude) / 2
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local away = hrp and (hrp.Position - center) or Vector3.new(0, 0, 1)
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.5 and away.Unit or Vector3.new(0, 0, 1)
		local distance = radius / math.sin(math.rad(55 / 2)) * 1.25
		local elevation = math.rad(20)
		local eye = center + away * (math.cos(elevation) * distance) + Vector3.new(0, math.sin(elevation) * distance, 0)
		local shot = CFrame.lookAt(eye, center)
		camera.CameraType = Enum.CameraType.Scriptable
		local flyIn = TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = shot, FieldOfView = 55 })
		flyIn:Play()
		flyIn.Completed:Wait()
		task.wait(0.2)

		-- 1) Нарастающая тряска старой печи + дрожь камеры.
		local oldBase = oldClone:GetScale()
		local oldAnchor = Vector3.new(oldCf.Position.X, oldCf.Position.Y - oldSize.Y / 2, oldCf.Position.Z)
		local basePivot = oldClone:GetPivot()
		local started = os.clock()
		while true do
			local a = math.clamp((os.clock() - started) / 0.42, 0, 1)
			local amplitude = 0.05 + a * 0.28
			oldClone:PivotTo(basePivot + Vector3.new((math.random() - 0.5) * amplitude * 2, (math.random() - 0.5) * amplitude * 0.5, (math.random() - 0.5) * amplitude * 2))
			camera.CFrame = shot + Vector3.new((math.random() - 0.5) * a * 0.3, (math.random() - 0.5) * a * 0.3, 0)
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		oldClone:PivotTo(basePivot)
		camera.CFrame = shot
		-- 2) "Вздувается" и 3) схлопывается в основание.
		started = os.clock()
		while true do
			local a = math.clamp((os.clock() - started) / 0.1, 0, 1)
			pcall(scaleAbout, oldClone, oldBase, 1 + math.sin(a * math.pi / 2) * 0.06, oldAnchor)
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		started = os.clock()
		while true do
			local a = math.clamp((os.clock() - started) / 0.18, 0, 1)
			pcall(scaleAbout, oldClone, oldBase, 1.06 - a * a * 1.04, oldAnchor)
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		oldClone:Destroy()

		-- 4) Новая вырастает из того же основания с перелётом.
		newClone = cleanClone(newModel)
		newClone.Parent = workspace
		local newBase = newClone:GetScale()
		local newAnchor = Vector3.new(newCf.Position.X, newCf.Position.Y - newSize.Y / 2, newCf.Position.Z)
		pcall(scaleAbout, newClone, newBase, 0.02, newAnchor)
		spawnDebris(newAnchor, math.max(newSize.X, newSize.Z) / 2)
		flash(newAnchor + Vector3.new(0, 1, 0))
		playSfx("UiSuccess")
		started = os.clock()
		while true do
			local a = math.clamp((os.clock() - started) / 0.45, 0, 1)
			local c1, c3 = 1.6, 2.6
			local eased = 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
			pcall(scaleAbout, newClone, newBase, math.max(0.02, eased), newAnchor)
			camera.CFrame = shot + Vector3.new((math.random() - 0.5) * (1 - a) * 0.35, (math.random() - 0.5) * (1 - a) * 0.35, 0)
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		camera.CFrame = shot
		newClone:Destroy()
		newClone = nil
		setLocalHidden(newModel, false)
		task.wait(0.7)
		local back = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = startCFrame, FieldOfView = startFov })
		back:Play()
		back.Completed:Wait()
	end)
	if not ok then warn("[IslandUI] Катсцена печи упала, возвращаю всё на место:", err) end
	if newClone then newClone:Destroy() end
	if newModel.Parent then setLocalHidden(newModel, false) end
	if smelterSnapshot == snapshot then
		for _, connection in snapshot.Connections do connection:Disconnect() end
		if snapshot.Clone then snapshot.Clone:Destroy() end
		smelterSnapshot = nil
	end
	camera.CameraType = restoreType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or restoreType
	camera.FieldOfView = startFov
	ProximityPromptService.Enabled = promptsWere
	cinematicMode:Fire(false, "IslandTravel")
	cinematicBusy = false
end

--------------------------------------------------------------------------------
-- СЕТЬ
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- v20.143: ПОЛНОЭКРАННОЕ ДЕРЕВО ОСТРОВОВ (как дерево престижа).
-- StarterGui/IslandTreeUi (билдер UiBuilders/SkillTreeUi) + Shared.SkillTreeView.
-- В центре - Island Keeper, три ветки расходятся в разные стороны: первый
-- узел ветки - сам остров (покупка), у плавильни дальше идут уровни печи,
-- в конце ветки - две звезды-перка острова и финальный узел между ними.
--------------------------------------------------------------------------------
do
	local ISLAND_TREE = Config.IslandPerks and Config.IslandPerks.FullScreen ~= false
	if ISLAND_TREE then
		local SkillTreeView = require(ReplicatedStorage.Shared.SkillTreeView)
		local TutorialTarget = require(ReplicatedStorage.Shared.TutorialTarget)
		local CollectionService = game:GetService("CollectionService")
		local treeGui = require(ReplicatedStorage.Shared.UiRegistry).Get("IslandTreeUi")
		treeGui.ResetOnSpawn = false
		treeGui.Enabled = false
		local view = SkillTreeView.new(treeGui, { LockName = "IslandTree", OnClose = function() close() end })
		islandTreeBump.Fn = function(id)
			if view:IsOpen() then view:Bump(id) end
		end
		local GREY = Color3.fromRGB(70, 74, 88)
		local DIM = Color3.fromRGB(44, 48, 62)
		local FIRST = 210
		local STEP = 135
		local DIRS = Config.IslandPerks.Dirs or { Anvil = { 0, -1 }, Income = { 0.87, 0.5 }, Smelter = { -0.87, 0.5 } }
		local nodeInfo = {}
		local links = {}   -- { Line, From } - красим, когда From куплен
		local built = false
		local busy = false

		local function unmark(guiObject)
			if guiObject and guiObject:GetAttribute(TutorialTarget.ATTR) then
				guiObject:SetAttribute(TutorialTarget.ATTR, nil)
				CollectionService:RemoveTag(guiObject, TutorialTarget.TAG)
			end
		end
		local function pctText(v) return tostring(math.floor((v or 0) * 1000 + 0.5) / 10) end

		local showCard
		local function onClick(id)
			playSfx("UiButtonClick")
			showCard(id)
		end

		local function link(fromId, a, b, toId)
			table.insert(links, { Line = view:Link(a, b, GREY, nil, fromId, toId), From = fromId })
		end

		local function build()
			view:Clear()
			table.clear(nodeInfo)
			table.clear(links)
			view:Node("Root", "Root", Vector2.zero, onClick)
			nodeInfo.Root = { Kind = "Root" }
			for _, islandId in Config.Islands.Order do
				local d = DIRS[islandId] or { 1, 0 }
				local dir = Vector2.new(d[1], d[2]).Unit
				local perp = Vector2.new(-dir.Y, dir.X)
				local pos = dir * FIRST
				local islandNode = "Island_" .. islandId
				link("Root", Vector2.zero, pos, islandNode)
				view:Node(islandNode, "Tier", pos, onClick)
				nodeInfo[islandNode] = { Kind = "Island", Island = islandId }
				local prevId, prevPos = islandNode, pos
				if islandId == "Smelter" then
					for level = 2, #(Config.Islands.Smelter.Levels or {}) do
						local p = prevPos + dir * STEP
						local id = "Furnace_" .. level
						link(prevId, prevPos, p, id)
						view:Node(id, "Tier", p, onClick)
						nodeInfo[id] = { Kind = "Furnace", Level = level, Island = islandId }
						prevId, prevPos = id, p
					end
				end
				local perks = Config.IslandPerks.Islands[islandId]
				if perks then
					local stars = perks.Stars or {}
					local starIds = {}
					for index, def in stars do
						local side = (#stars == 1) and 0 or (index == 1 and 1 or -1)
						local p = prevPos + dir * STEP * 1.15 + perp * 105 * side
						link(prevId, prevPos, p, def.Id)
						view:Node(def.Id, "Star", p, onClick)
						nodeInfo[def.Id] = { Kind = "Perk", Island = islandId, Def = def, Pos = p }
						table.insert(starIds, def.Id)
					end
					if perks.Final then
						local p = prevPos + dir * STEP * 2.3
						for _, starId in starIds do link(starId, nodeInfo[starId].Pos, p, perks.Final.Id) end
						view:Node(perks.Final.Id, "Final", p, onClick)
						nodeInfo[perks.Final.Id] = { Kind = "Perk", Island = islandId, Def = perks.Final, Final = true }
					end
				end
			end
			built = true
		end

		local function perkInfo(id, def, final)
			return perkState[id] or { Level = 0, MaxLevel = final and 1 or (def.MaxLevel or 10), Value = 0, Locked = true }
		end
		local function isDone(id)
			local info = nodeInfo[id]
			if not info then return false end
			if info.Kind == "Root" then return true end
			if info.Kind == "Island" then
				local entry = islandInfo(info.Island)
				return entry and entry.Owned == true
			end
			if info.Kind == "Furnace" then
				local sm = currentState and currentState.Smelter
				return sm ~= nil and info.Level <= sm.Level
			end
			local st = perkInfo(id, info.Def, info.Final)
			return st.Level >= st.MaxLevel
		end

		local function refresh()
			if not built then build() end
			view:Paint("Root", { Color = Color3.fromRGB(120, 220, 255), Icon = "🏝", Name = tr(currentState and currentState.KeeperName or "Island Keeper"), PlateState = "Owned", Branch = "Root" })
			local sm = currentState and currentState.Smelter
			for id, info in nodeInfo do
				if info.Kind == "Island" then
					local entry = islandInfo(info.Island) or {}
					local color = entry.Color or Color3.fromRGB(120, 170, 255)
					local props = { Caption = entry.Icon or "?", Name = tr(entry.DisplayName or info.Island) }
					-- v20.144: видно купленное и доступное к покупке, остальное скрыто
					props.Hidden = not (entry.Owned or entry.RequiresMet)
					props.Late = not entry.Owned
					props.Branch = info.Island -- v20.164: фон ветки острова (Config.TreePlates)
					if entry.Owned then
						props.Color = color
						props.Price = '<font color="#9CFFB4">' .. tr("OWNED") .. "</font>"
						props.PlateState = "Owned"
					elseif entry.RequiresMet then
						props.PlateState = entry.CanAfford and "Buy" or "NoMoney"
						props.Color = entry.CanAfford and Color3.fromRGB(70, 200, 95) or Color3.fromRGB(140, 60, 60)
						props.Price = '<font color="' .. (entry.CanAfford and "#6CFF7E" or "#FF5A5A") .. '">' .. tostring(entry.CostText or "") .. "</font>"
						props.Pulse = entry.CanAfford == true
					else
						props.PlateState = "Locked"
						props.Color = DIM
						props.Price = '<font color="#AAB0C4">' .. tr("Needs {name}", { name = tr(entry.RequiresName or "") }) .. "</font>"
					end
					view:Paint(id, props)
					local node = view.Nodes[id]
					if node then TutorialTarget.Mark(node.Holder, "IslandCard:" .. info.Island) end
				elseif info.Kind == "Furnace" then
					local levelDef = Config.Islands.Smelter.Levels[info.Level] or {}
					local props = {
						Caption = "x" .. tostring(levelDef.Slots or info.Level), Name = tr(levelDef.Name or ""),
						Hidden = not (sm and info.Level <= sm.Level + 1),
						Late = not (sm and info.Level <= sm.Level),
					}
					props.Branch = "Smelter" -- v20.164
					if sm and info.Level <= sm.Level then
						props.Color = Color3.fromRGB(255, 140, 60)
						props.Price = ""
						props.PlateState = "Owned"
					elseif sm and info.Level == sm.Level + 1 then
						props.PlateState = sm.CanAfford and "Buy" or "NoMoney"
						props.Color = sm.CanAfford and Color3.fromRGB(70, 200, 95) or Color3.fromRGB(140, 60, 60)
						props.Price = '<font color="' .. (sm.CanAfford and "#6CFF7E" or "#FF5A5A") .. '">' .. tostring(sm.NextCostText or "") .. "</font>"
						props.Pulse = sm.CanAfford == true
					else
						props.PlateState = "Locked"
						props.Color = DIM
						props.Price = ""
					end
					view:Paint(id, props)
				elseif info.Kind == "Perk" then
					local st = perkInfo(id, info.Def, info.Final)
					local maxed = st.Level >= st.MaxLevel
					local base = info.Final and UiKit.Theme.Accents.Gold.Main or Color3.fromRGB(110, 190, 255)
					view:Paint(id, {
						Color = st.Locked and DIM or (maxed and base or base:Lerp(Color3.fromRGB(30, 34, 48), 0.4)),
						Icon = info.Def.Icon or "★",
						Name = tr(info.Def.Title or id),
						Level = st.Locked and (info.Final and tr("LOCKED") or "") or (maxed and "MAX" or (st.Level .. "/" .. st.MaxLevel)),
						Pulse = not st.Locked and not maxed and st.CanAfford == true,
						-- звёзды видны, когда куплен остров; финал - когда обе звезды на максимуме
						Hidden = info.Final and st.Locked or not st.Owned,
						Late = st.Level == 0,
						PlateState = st.Locked and "Locked" or "Star", -- v20.164
					})
				end
			end
			for _, entry in links do
				entry.Line.BackgroundColor3 = isDone(entry.From) and UiKit.Theme.Accents.Gold.Main or GREY
			end
			view:SetMoney("")
			local shown = view:CardShownFor()
			if shown then showCard(shown) end
		end

		showCard = function(id)
			local info = nodeInfo[id]
			if not info then return end
			local buyButton = view.Card:FindFirstChild("Buy")
			unmark(buyButton)
			if info.Kind == "Root" then
				view:ShowCard(id, {
					Title = "🏝 " .. tr(currentState and currentState.KeeperName or "Island Keeper"),
					Level = (currentState and currentState.RebirthUnlocked) and ('<font color="#6CFF9A">' .. tr("PRESTIGE UNLOCKED") .. "</font>")
						or ('<font color="#FF9E3C">' .. tr("PRESTIGE LOCKED - unlock every island first.") .. "</font>"),
					Text = tr("Unlock islands behind your base, then upgrade each island."),
				})
			elseif info.Kind == "Island" then
				local entry = islandInfo(info.Island) or {}
				local card = {
					Title = (entry.Icon or "") .. " " .. tr(entry.DisplayName or info.Island),
					Text = tr(entry.Description or ""),
				}
				if entry.Owned then
					card.Level = '<font color="#9CFFB4">' .. tr("OWNED") .. "</font>"
				elseif not entry.RequiresMet then
					card.Level = tr("Needs {name}", { name = tr(entry.RequiresName or "") })
				else
					card.Level = tostring(entry.CostText or "")
					card.Buy = {
						Text = pendingAction and "..." or (tr("BUY") .. "  " .. tostring(entry.CostText or "")),
						Variant = entry.CanAfford and "Green" or "Red",
						OnClick = function()
							if pendingAction then return end
							pendingAction = true
							playSfx("UiConfirm")
							remote:FireServer("Buy", info.Island)
							islandTreeBump.Id = id
							showCard(id)
							task.delay(3, function()
								if pendingAction then pendingAction = false; refresh() end
							end)
						end,
					}
				end
				view:ShowCard(id, card)
				if card.Buy then TutorialTarget.Mark(buyButton, "IslandBuy") end
			elseif info.Kind == "Furnace" then
				local sm = currentState and currentState.Smelter
				local levelDef = Config.Islands.Smelter.Levels[info.Level] or {}
				local card = {
					Title = "🔥 " .. tr(levelDef.Name or ("Furnace " .. info.Level)),
					Text = tr("Smelts {slots} ores at once, a bit faster. Ingot price x{mult}.", {
						slots = levelDef.Slots or info.Level, mult = sm and sm.Multiplier or Config.Islands.Smelter.ValueMultiplier,
					}),
				}
				if not sm then
					card.Level = tr("Buy the Smelter Island first")
				elseif info.Level <= sm.Level then
					card.Level = '<font color="#9CFFB4">' .. tr("OWNED") .. "</font>"
				elseif info.Level == sm.Level + 1 then
					card.Level = tr("NEXT UPGRADE")
					card.Buy = {
						Text = pendingAction and "..." or (tr("UPGRADE") .. "  " .. tostring(sm.NextCostText or "")),
						Variant = sm.CanAfford and "Green" or "Red",
						OnClick = function()
							if pendingAction then return end
							pendingAction = true
							playSfx("UiConfirm")
							if captureSmelterSnapshot then captureSmelterSnapshot() end
							remote:FireServer("UpgradeSmelter")
							islandTreeBump.Id = id
							showCard(id)
							task.delay(3, function()
								if pendingAction then pendingAction = false; refresh() end
							end)
						end,
					}
				else
					card.Level = tr("LOCKED")
				end
				view:ShowCard(id, card)
			else
				local def = info.Def
				local st = perkInfo(id, def, info.Final)
				local maxed = st.Level >= st.MaxLevel
				local text
				if info.Final then
					text = tr(def.Text or "")
				else
					text = (tr(def.Text or "")):gsub("{v}", pctText(st.Value))
					if not maxed then text = text .. '\n<font color="#6CFF7E">' .. tr("Next") .. ": +" .. pctText(st.NextValue) .. "%</font>" end
				end
				local card = {
					Title = (def.Icon or "") .. " " .. tr(def.Title or id),
					Level = info.Final and (maxed and tr("OWNED") or tr("FINAL UPGRADE")) or (tr("Level") .. " " .. st.Level .. " / " .. st.MaxLevel),
					Text = text,
				}
				if maxed then
					card.Buy = { Text = tr("MAX"), Variant = "Dark" }
				elseif st.Locked then
					card.Buy = { Text = (not st.Owned) and tr("Buy the island") or tr("Max both stars"), Variant = "Dark" }
				else
					card.Buy = {
						Text = busy and "..." or (tr("BUY") .. "  $" .. NumberFormatMod.abbreviate(st.Cost or 0)),
						Variant = st.CanAfford and "Green" or "Red",
						OnClick = function()
							if busy or not perkRemote then return end
							busy = true
							showCard(id)
							task.spawn(function()
								local okCall, ok, reason, state = pcall(perkRemote.InvokeServer, perkRemote, "Buy", id)
								busy = false
								if okCall and type(state) == "table" then perkState = state end
								if not (okCall and ok) then playSfx("UiError") end
								refresh()
								if okCall and ok then view:Bump(id) end
								if okCall and not ok and reason then
									local level = view.Card:FindFirstChild("Level")
									if level then level.Text = '<font color="#FF6A6A">' .. tr(reason) .. "</font>" end
								end
							end)
						end,
					}
				end
				view:ShowCard(id, card)
			end
		end

		-- перки приходят отдельно (IslandPerkRequest) - после ответа перерисовать
		local baseRender = renderPerks
		renderPerks = function()
			baseRender()
			if view:IsOpen() then refresh() end
		end

		treeHooks.Open = function()
			refresh() -- сначала решить, какие узлы видны, потом анимация открытия
			view:Open()
			fetchPerks()
		end
		treeHooks.Close = function() view:Close() end
		treeHooks.IsOpen = function() return view:IsOpen() end
		treeHooks.Refresh = function() if view:IsOpen() then refresh() end end
		RunService.Heartbeat:Connect(function()
			if view:IsOpen() then view:Step(os.clock()) end
		end)
	end
end

remote.OnClientEvent:Connect(function(command, a, b, c, d)
	if command == "Open" then
		open(a)
	elseif command == "State" then
		if isOpen then render(a) end
	elseif command == "Result" then
		local success, reason, action = a, b, c
		pendingAction = false
		if success then
			playSfx("UiSuccess")
			showToast(action == "UpgradeSmelter" and tr("FURNACE UPGRADED!") or tr("ISLAND UNLOCKED!"), true)
		else
			if action == "UpgradeSmelter" then cancelSmelterSnapshot() end
			playSfx("UiError")
			showToast(tr(tostring(reason or "Something went wrong")), false)
		end
		if isOpen and currentState then render(currentState) end
		local bumpId = islandTreeBump.Id
		islandTreeBump.Id = nil
		if success and bumpId and islandTreeBump.Fn then islandTreeBump.Fn(bumpId) end
	elseif command == "Rise" then
		task.spawn(playRiseCinematic, a, b, c, d)
	elseif command == "SmelterUpgraded" then
		task.spawn(playSmelterUpgradeCinematic, a)
	end
end)

--------------------------------------------------------------------------------
-- ПОДПИСИ НАД СВОИМИ ОСТРОВАМИ — ВИДИТ ТОЛЬКО ВЛАДЕЛЕЦ.
--
-- Билборд создаётся КЛИЕНТОМ в собственном PlayerGui (Adornee — остров),
-- поэтому у других игроков его просто не существует. Висит высоко над
-- верхней точкой острова (Config.Islands.LabelHeight): видно издалека и
-- когда смотришь в небо. Размер в пикселях — не мельчает с расстоянием.
--------------------------------------------------------------------------------
-- ScreenGui с ResetOnSpawn = false: после смерти подписи не должны пропадать.
local labelFolder = Instance.new("ScreenGui")
labelFolder.Name = "IslandLabels"
labelFolder.ResetOnSpawn = false
labelFolder.Parent = playerGui
local islandLabels = {} -- [Model] = BillboardGui

local function removeLabel(model)
	local billboard = islandLabels[model]
	islandLabels[model] = nil
	if billboard then billboard:Destroy() end
end

local function updateLabelHeight(model, billboard)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then return end
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	local top = ok and (cf.Position.Y + size.Y / 2) or primary.Position.Y
	billboard.Adornee = primary
	billboard.StudsOffsetWorldSpace = Vector3.new(0, (top - primary.Position.Y) + (Config.Islands.LabelHeight or 45), 0)
	-- Центр по горизонтали — над серединой острова, а не над PrimaryPart
	-- (у своего макета PrimaryPart может стоять с краю).
	if ok then
		local offset = cf.Position - primary.Position
		billboard.StudsOffsetWorldSpace += Vector3.new(offset.X, 0, offset.Z)
	end
end

local function addLabel(model)
	if islandLabels[model] then return end
	if model:GetAttribute("OwnerUserId") ~= player.UserId then return end
	local islandId = model:GetAttribute("IslandId")
	local definition = islandId and Config.Islands.Definitions[islandId]
	if not definition then return end

	local billboard = templates:WaitForChild("IslandLabel"):Clone()
	billboard.Name = "IslandLabel_" .. islandId
	billboard.MaxDistance = Config.Islands.LabelMaxDistance or 1500
	billboard.Parent = labelFolder

	local color = definition.Color or Color3.new(1, 1, 1)
	billboard.Title.Text = tr(definition.DisplayName or islandId):upper()
	billboard.Title.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
	billboard.Tagline.Text = tr(definition.Tagline or definition.Description or "")

	islandLabels[model] = billboard
	updateLabelHeight(model, billboard)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then removeLabel(model) end
	end)
end

local function considerInstance(instance)
	if instance:IsA("Model") and instance:GetAttribute("IslandId") then
		-- Атрибуты и детали могут доехать на кадр позже самой модели.
		task.defer(addLabel, instance)
	end
end

task.spawn(function()
	local plots = workspace:WaitForChild("Plots", 60)
	if not plots then return end
	for _, descendant in plots:GetDescendants() do considerInstance(descendant) end
	plots.DescendantAdded:Connect(considerInstance)
	-- Высоту пересчитываем периодически: постройки на острове (и сам
	-- остров, пока выезжает из-под земли) доезжают постепенно.
	while true do
		task.wait(2)
		for model, billboard in islandLabels do
			if model.Parent then updateLabelHeight(model, billboard) end
		end
	end
end)
