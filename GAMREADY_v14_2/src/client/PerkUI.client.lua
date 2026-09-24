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

local gui = playerGui:WaitForChild("PerkUi", 3)
if not gui or (tonumber(gui:GetAttribute("BuilderVersion")) or 0) < (cfg.PerkUiVersion or 2) or not gui:FindFirstChild("Tree", true)
	or not gui:FindFirstChild("Shrines", true) then
	if gui then gui:Destroy() end
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
-- v4: вкладки и список святилищ.
local tabs = panel:WaitForChild("Tabs")
local perksTab = tabs:WaitForChild("PerksTab")
local shrinesTab = tabs:WaitForChild("ShrinesTab")
local shrinesList = panel:WaitForChild("Shrines")
local shrineTemplate = shrinesList:WaitForChild("ShrineTemplate")
local SHRINES = cfg.Shrines or { Order = {}, Types = {} }
local mode = "Perks"
local selectedShrine = nil
local shrineState = {}

local remote = ReplicatedStorage.Shared:WaitForChild("PrestigeRequest", 30)
if not remote then
	warn("[PerkUI] PrestigeRequest не появился — окно перков отключено.")
	return
end

local PERK_BY_ID = {}
for _, perk in cfg.Perks do PERK_BY_ID[perk.Id] = perk end
local BRANCH_OF = {}
for _, branch in cfg.Branches or {} do
	for _, perkId in branch.Perks do BRANCH_OF[perkId] = branch end
end

local NODE_SIZE = 70
local NODE_GAP = 18

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

local function renderTree()
	pointsLabel.Text = "⭐ " .. tostring(state.Points)
	for _, child in tree:GetChildren() do
		if child:GetAttribute("Generated") then child:Destroy() end
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
					line.Position = UDim2.new(0.5, 0, 0, y - NODE_GAP - 4)
					line.Size = UDim2.fromOffset(line.Size.X.Offset, NODE_GAP + 8)
					line.BackgroundColor3 = locked and COLOR_LOCKED or branch.Color
					line.Parent = nodes
				end
				local node = nodeTemplate:Clone()
				node.Name = "Node_" .. perkId
				node.Visible = true
				node.Position = UDim2.new(0.5, 0, 0, y)
				node.ZIndex = 2
				node.BackgroundColor3 = locked and COLOR_LOCKED or (maxed and branch.Color:Lerp(COLOR_INK, 0.15) or branch.Color:Lerp(COLOR_STAR, 0.55))
				node.Icon.Text = perk.Icon
				node.Icon.TextTransparency = locked and 0.55 or 0
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

local function renderShrineDetail()
	local def = selectedShrine and SHRINES.Types[selectedShrine]
	if not def then
		detail.Visible = false
		return
	end
	detail.Visible = true
	local info = shrineState[selectedShrine] or {}
	detail.Icon.Text = def.Icon or "🗿"
	detail.Title.Text = tr(def.DisplayName)
	detail.Title.TextColor3 = Color3.fromRGB(255, 220, 110)
	detail.Level.Text = tr("SHRINE · never resets")
	detail.Now.Text = shrineEffect(def)
	detail.Next.Text = tr("Place it on your base")
	detail.Hint.Visible = false
	if info.Owned then
		upgradeText.Text = "✔ " .. tr("OWNED")
		upgradeButton.BackgroundColor3 = COLOR_GREY
	else
		local affordable = state.Points >= (def.Cost or math.huge)
		upgradeText.Text = "⭐ " .. tostring(def.Cost or 0)
		upgradeButton.BackgroundColor3 = affordable and COLOR_GREEN or COLOR_ORANGE
	end
end

local function renderShrines()
	pointsLabel.Text = "⭐ " .. tostring(state.Points)
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
			card.Icon.Text = def.Icon or "🗿"
			card.Title.Text = tr(def.DisplayName)
			card.Status.Text = info.Owned and ("✔ " .. tr("OWNED")) or ("⭐ " .. tostring(def.Cost or 0))
			card.Status.TextColor3 = info.Owned and COLOR_GREEN_TEXT or COLOR_GOLD_TEXT
			card.BackgroundColor3 = (selectedShrine == shrineId) and COLOR_STAR:Lerp(Color3.new(1, 1, 1), 0.25)
				or (info.Owned and COLOR_GREEN:Lerp(COLOR_INK, 0.35) or COLOR_STAR)
			press(card)
			card.Activated:Connect(function()
				UiSfx.play("UiButtonClick")
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
	perksTab.BackgroundColor3 = mode == "Perks" and Color3.fromRGB(255, 200, 70) or COLOR_STAR
	shrinesTab.BackgroundColor3 = mode == "Shrines" and Color3.fromRGB(255, 200, 70) or COLOR_STAR
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
	local perk = selected and PERK_BY_ID[selected]
	if not perk then
		detail.Visible = false
		return
	end
	detail.Visible = true
	local info = infoOf(perk.Id)
	local branch = BRANCH_OF[perk.Id]
	detail.Icon.Text = perk.Icon
	detail.Title.Text = tr(perk.Title)
	detail.Title.TextColor3 = branch and branch.Color or Color3.new(1, 1, 1)
	detail.Level.Text = ("LV %d/%d"):format(info.Level, perk.MaxLevel)
	detail.Now.Text = info.Level > 0 and effectText(perk, info.Level) or "—"
	local hint = detail.Hint
	hint.Visible = false
	if info.Level >= perk.MaxLevel then
		detail.Next.Text = "✔ MAX"
		upgradeText.Text = "MAX"
		upgradeButton.BackgroundColor3 = COLOR_GREY
	elseif info.Locked then
		local required = info.Requires and PERK_BY_ID[info.Requires]
		detail.Next.Text = "▶ " .. effectText(perk, info.Level + 1)
		hint.Visible = true
		hint.Text = "🔒 " .. tr("Needs {p}", { p = required and tr(required.Title) or "?" })
		upgradeText.Text = "🔒"
		upgradeButton.BackgroundColor3 = COLOR_GREY
	else
		detail.Next.Text = "▶ " .. effectText(perk, info.Level + 1)
		local affordable = state.Points >= (info.Cost or math.huge)
		upgradeText.Text = "⭐ " .. tostring(info.Cost or 0)
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
		selected = first
	end
	if mode == "Shrines" then
		renderShrines()
	else
		renderTree()
	end
	renderDetail()
end

local function open()
	isOpen = true
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = hrp and hrp.Position or nil
	gui.Enabled = true
	UiSfx.play("UiMenuOpen")
	if autoScale then
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
	UiSfx.play("UiMenuClose")
	gui.Enabled = false
end

closeButton.Activated:Connect(close)
upgradeButton.Activated:Connect(function()
	if mode == "Shrines" then
		if selectedShrine and not (shrineState[selectedShrine] and shrineState[selectedShrine].Owned) then
			remote:FireServer("BuyShrine", selectedShrine)
		end
		return
	end
	if not selected then return end
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
	local node = column and column.Nodes:FindFirstChild("Node_" .. perkId)
	local scale = node and node:FindFirstChild("PressScale")
	if scale then
		scale.Scale = 1.25
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

remote.OnClientEvent:Connect(function(command, payload)
	if command == "Open" then
		applyState(payload)
		open()
	elseif command == "State" then
		applyState(payload)
	elseif command == "BuyResult" and type(payload) == "table" then
		UiSfx.play(payload.Ok and "UiButtonClick" or "UiError")
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
