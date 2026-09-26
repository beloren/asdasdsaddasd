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
	Poor = "Yellow",
	Grey = "Dark",
}
local DARK_CARD = UiKit.Theme.Skins.Card.Color

local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("IslandUi")
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

local function renderDetail()
	local entry = selectedId and islandInfo(selectedId)
	if not entry then return end
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
		end
		applyCard(visual, decorated(entry))
	end
	footer.Text = state.RebirthUnlocked
		and ('<font color="#6CFF9A">%s</font>'):format(tr("PRESTIGE UNLOCKED - talk to the Prestige Mayor at your base."))
		or ('<font color="#FF9E3C">%s</font>'):format(tr("PRESTIGE LOCKED - unlock every island first."))
	refreshArrows()
	if detailView.Visible then renderDetail() end
end

local function showGrid(animated)
	selectedId = nil
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
	local tween = TweenService:Create(panelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = panelScale.Scale * 0.85 })
	tween:Play()
	tween.Completed:Wait()
	if not isOpen then gui.Enabled = false end
end

local function open(state)
	render(state)
	if isOpen then return end
	isOpen = true
	showGrid(false)
	fitScale()
	local target = panelScale.Scale
	panelScale.Scale = target * 0.85
	gui.Enabled = true
	playSfx("UiMenuOpen")
	TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
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
	cinematicMode:Fire(true)

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
	cinematicMode:Fire(false)
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
	cinematicMode:Fire(true)
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
	cinematicMode:Fire(false)
	cinematicBusy = false
end

--------------------------------------------------------------------------------
-- СЕТЬ
--------------------------------------------------------------------------------
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
