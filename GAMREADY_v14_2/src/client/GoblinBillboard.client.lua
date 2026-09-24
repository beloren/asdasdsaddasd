local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared.Config)

local playerGui = player:WaitForChild("PlayerGui")
local templateSource = playerGui:WaitForChild("MobBillboardTemplates", 5)

local tracked = {}
local trackedBoulders = {}
-- Модели, для которых привязка билборда уже запущена, но ещё ждёт
-- дорепликации Head/Humanoid (см. комментарий в track).
local pending = {}
local pendingBoulders = {}

local BILLBOARD_PIXELS = Vector2.new(280, 58)
local BILLBOARD_STUDS = Vector2.new(8, 1.65)

local function tierColor(tier)
	local rarities = {"Common", "Uncommon", "Rare", "Rare", "Epic", "Epic", "Legendary", "Legendary", "Mythic", "Mythic"}
	return Config.RarityColors[rarities[math.clamp(tier, 1, #rarities)]] or Color3.new(1, 1, 1)
end

local function colorHex(color)
	return ("#%02X%02X%02X"):format(
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

local function makeText(parent, size, position, fontSize)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.AutomaticSize = Enum.AutomaticSize.None
	label.SizeConstraint = Enum.SizeConstraint.RelativeXY
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Arcade
	label.TextSize = math.max(18, fontSize or 14)
	label.TextScaled = false
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = parent
	return label
end

local function newBillboard(instanceName, adornee, height)
	local gui = Instance.new("BillboardGui")
	gui.Name = instanceName
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromScale(BILLBOARD_STUDS.X, BILLBOARD_STUDS.Y)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 110
	gui.Adornee = adornee
	gui.Parent = playerGui
	return gui
end

local function convertChildrenToScale(parent, parentPixels)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			local oldSize = child.Size
			local oldPosition = child.Position
			local childPixels = Vector2.new(
				parentPixels.X * oldSize.X.Scale + oldSize.X.Offset,
				parentPixels.Y * oldSize.Y.Scale + oldSize.Y.Offset
			)
			child.Size = UDim2.fromScale(
				oldSize.X.Scale + oldSize.X.Offset / parentPixels.X,
				oldSize.Y.Scale + oldSize.Y.Offset / parentPixels.Y
			)
			child.Position = UDim2.fromScale(
				oldPosition.X.Scale + oldPosition.X.Offset / parentPixels.X,
				oldPosition.Y.Scale + oldPosition.Y.Offset / parentPixels.Y
			)
			if child:IsA("TextLabel") then
				child.Font = Enum.Font.Arcade
				child.TextSize = math.max(child.TextSize, 18)
				child.TextStrokeColor3 = Color3.new(0, 0, 0)
				child.TextStrokeTransparency = 0
				if not child:FindFirstChildOfClass("UITextSizeConstraint") then
					local constraint = Instance.new("UITextSizeConstraint")
					constraint.MaxTextSize = child.TextSize
					constraint.MinTextSize = 1
					constraint.Parent = child
				end
				child.TextScaled = true
			end
			convertChildrenToScale(child, childPixels)
		end
	end
end

local function cloneTemplate(name, instanceName, adornee, height)
	templateSource = templateSource or playerGui:FindFirstChild("MobBillboardTemplates")
	local template = templateSource and templateSource:FindFirstChild(name)
	if not template then return nil end
	if template:IsA("BillboardGui") then
		local gui = template:Clone()
		gui.Name = instanceName
		gui.ResetOnSpawn = false
		gui.Size = UDim2.fromScale(BILLBOARD_STUDS.X, BILLBOARD_STUDS.Y)
		gui.SizeOffset = Vector2.new(0, 0.5)
		gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
		gui.Adornee = adornee
		gui.Enabled = true
		gui.Parent = playerGui
		convertChildrenToScale(gui, BILLBOARD_PIXELS)
		return gui
	end

	-- Places made with the previous builder can still render until it is rerun.
	if template:IsA("GuiObject") then
		local gui = newBillboard(instanceName, adornee, height)
		local content = template:Clone()
		content.AnchorPoint = Vector2.zero
		content.Position = UDim2.fromScale(0, 0)
		content.Visible = true
		content.Parent = gui
		convertChildrenToScale(gui, BILLBOARD_PIXELS)
		return gui
	end
	return nil
end

local function isBoulderModel(model)
	return model:IsA("Model") and (model:GetAttribute("IsRubbleBoulder") == true or model.Name == "RubbleBoulder")
end

local function createBillboard(model, head, humanoid)
	local height = head.Size.Y * 0.5 + 0.5
	local template = cloneTemplate("GoblinTemplate", model.Name .. "Billboard", head, height)
	if template then
		local icon = template:FindFirstChild("GoblinIcon", true)
		local placeholder = icon and icon:FindFirstChild("IconPlaceholder", true)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = Config.Goblins.IconImage or ""
		end
		if placeholder and placeholder:IsA("TextLabel") then
			placeholder.Visible = not icon or not icon:IsA("ImageLabel") or icon.Image == ""
			placeholder.TextColor3 = tierColor(model:GetAttribute("GoblinMineTier") or 1)
		end
		local info = template:FindFirstChild("Info", true)
		local title = info and info:FindFirstChild("Title", true)
		local healthBack = info and info:FindFirstChild("HealthBack", true)
		local healthFill = healthBack and healthBack:FindFirstChild("Fill", true)
		local healthText = healthBack and healthBack:FindFirstChild("Health", true)
		if not (title and title:IsA("TextLabel") and healthFill and healthFill:IsA("GuiObject") and healthText and healthText:IsA("TextLabel")) then
			template:Destroy()
		else
			local tier = model:GetAttribute("GoblinMineTier") or 1
			local definition = Config.Goblins.Types[model:GetAttribute("GoblinType") or "Warrior"]
			local record = {Gui = template, Head = head, Humanoid = humanoid, Title = title, Fill = healthFill, Health = healthText, Tier = tier, Name = definition and definition.DisplayName or "Goblin"}
			record.Title.Text = ("<b>%s <font color=\"#69EB82\">Lv. %d</font></b>"):format(record.Name, record.Tier)
			local function updateHealth(health)
				local ratio = math.clamp(health / humanoid.MaxHealth, 0, 1)
				record.Fill.Size = UDim2.fromScale(ratio, 1)
				record.Fill.BackgroundColor3 = ratio <= 0.3 and Color3.fromRGB(230, 60, 60) or ratio <= 0.6 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(90, 220, 90)
				record.Health.Text = ("HP %d/%d"):format(math.max(0, math.ceil(health)), math.ceil(humanoid.MaxHealth))
				record.Gui.Enabled = health > 0
			end
			updateHealth(humanoid.Health)
			record.HealthConnection = humanoid.HealthChanged:Connect(updateHealth)
			return record
		end
	end

	local gui = newBillboard(model.Name .. "Billboard", head, height)

	local icon = Instance.new("ImageLabel")
	icon.Name = "GoblinIcon"
	icon.Size = UDim2.fromOffset(38, 38)
	icon.Position = UDim2.fromOffset(1, 1)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Image = Config.Goblins.IconImage or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = gui
	local placeholder = makeText(icon, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 18)
	placeholder.Text = "G"
	placeholder.TextColor3 = tierColor(model:GetAttribute("GoblinMineTier") or 1)
	placeholder.Visible = icon.Image == ""

	local info = Instance.new("Frame")
	info.Size = UDim2.fromOffset(156, 38)
	info.Position = UDim2.fromOffset(42, 1)
	info.BackgroundTransparency = 1
	info.BorderSizePixel = 0
	info.Parent = gui
	local title = makeText(info, UDim2.new(1, -12, 0, 19), UDim2.fromOffset(6, 1), 11)
	title.TextColor3 = Color3.fromRGB(238, 240, 235)
	local healthBack = Instance.new("Frame")
	healthBack.Size = UDim2.new(1, -12, 0, 14)
	healthBack.Position = UDim2.new(0, 6, 1, -18)
	healthBack.BackgroundColor3 = Color3.fromRGB(7, 8, 9)
	healthBack.BackgroundTransparency = 0.15
	healthBack.BorderSizePixel = 0
	healthBack.ClipsDescendants = true
	healthBack.Parent = info
	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(104, 207, 80)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
	local healthText = makeText(healthBack, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 8)
	healthText.ZIndex = 2
	healthText.TextColor3 = Color3.new(1, 1, 1)
	convertChildrenToScale(gui, BILLBOARD_PIXELS)

	local tier = model:GetAttribute("GoblinMineTier") or 1
	local definition = Config.Goblins.Types[model:GetAttribute("GoblinType") or "Warrior"]
	local record = {Gui = gui, Head = head, Humanoid = humanoid, Title = title, Fill = healthFill, Health = healthText, Tier = tier, Name = definition and definition.DisplayName or "Goblin"}
	record.Title.Text = ("<b>%s <font color=\"#69EB82\">Lv. %d</font></b>"):format(record.Name, record.Tier)
	local function updateHealth(health)
		local ratio = math.clamp(health / humanoid.MaxHealth, 0, 1)
		record.Fill.Size = UDim2.fromScale(ratio, 1)
		record.Fill.BackgroundColor3 = ratio <= 0.3 and Color3.fromRGB(230, 60, 60) or ratio <= 0.6 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(90, 220, 90)
		record.Health.Text = ("HP %d/%d"):format(math.max(0, math.ceil(health)), math.ceil(humanoid.MaxHealth))
		record.Gui.Enabled = health > 0
	end
	updateHealth(humanoid.Health)
	record.HealthConnection = humanoid.HealthChanged:Connect(updateHealth)
	return record
end

local function createBoulderBillboard(model, root)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local top = boundsCFrame:PointToWorldSpace(Vector3.new(0, boundsSize.Y * 0.5 + 0.5, 0))
	local offset = top - root.Position
	local template = cloneTemplate("BoulderTemplate", "BoulderBillboard", root, 0)
	if template then template.StudsOffsetWorldSpace = offset end
	if template then
		local info = template:FindFirstChild("Info", true)
		local title = info and info:FindFirstChild("Title", true)
		local healthBack = info and info:FindFirstChild("HealthBack", true)
		local healthFill = healthBack and healthBack:FindFirstChild("Fill", true)
		local healthText = healthBack and healthBack:FindFirstChild("Health", true)
		local icon = template:FindFirstChild("BoulderIcon", true)
		local placeholder = icon and icon:FindFirstChild("IconPlaceholder", true)
		if not (title and title:IsA("TextLabel") and healthFill and healthFill:IsA("GuiObject") and healthText and healthText:IsA("TextLabel")) then
			template:Destroy()
		else
			local tier = model:GetAttribute("Tier") or 1
			if icon and icon:IsA("ImageLabel") then icon.Image = Config.Boulders.IconImage or "" end
			if placeholder and placeholder:IsA("TextLabel") then
				placeholder.TextColor3 = tierColor(tier)
				placeholder.Visible = not icon or not icon:IsA("ImageLabel") or icon.Image == ""
			end
			local record = {Gui = template, Root = root, Title = title, Fill = healthFill, Health = healthText, Tier = tier, Model = model}
			record.Title.Text = ("<b>BOULDER <font color=\"%s\">LV. %d</font></b>"):format(colorHex(tierColor(record.Tier)), record.Tier)
			local function updateHealth(health)
				local maxHealth = model:GetAttribute("MaxHealth") or 1
				local ratio = math.clamp(health / maxHealth, 0, 1)
				record.Fill.Size = UDim2.fromScale(ratio, 1)
				record.Fill.BackgroundColor3 = ratio <= 0.3 and Color3.fromRGB(230, 60, 60) or ratio <= 0.6 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(90, 220, 90)
				record.Health.Text = tostring(math.max(0, math.ceil(health)))
				record.Gui.Enabled = health > 0
			end
			updateHealth(model:GetAttribute("Health") or 0)
			record.HealthConnection = model:GetAttributeChangedSignal("Health"):Connect(function()
				updateHealth(model:GetAttribute("Health") or 0)
			end)
			return record
		end
	end

	local gui = newBillboard("BoulderBillboard", root, 0)
	gui.StudsOffsetWorldSpace = offset

	local icon = Instance.new("ImageLabel")
	icon.Name = "BoulderIcon"
	icon.Size = UDim2.fromOffset(38, 38)
	icon.Position = UDim2.fromOffset(1, 1)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = Config.Boulders.IconImage or ""
	icon.Parent = gui
	local tier = model:GetAttribute("Tier") or 1
	local placeholder = makeText(icon, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 18)
	placeholder.Text = "B"
	placeholder.TextColor3 = tierColor(tier)
	placeholder.Visible = icon.Image == ""

	local info = Instance.new("Frame")
	info.Size = UDim2.fromOffset(156, 38)
	info.Position = UDim2.fromOffset(42, 1)
	info.BackgroundTransparency = 1
	info.BorderSizePixel = 0
	info.Parent = gui
	local title = makeText(info, UDim2.new(1, -12, 0, 19), UDim2.fromOffset(6, 1), 11)
	title.TextColor3 = Color3.fromRGB(238, 240, 235)
	local healthBack = Instance.new("Frame")
	healthBack.Size = UDim2.new(1, -12, 0, 14)
	healthBack.Position = UDim2.new(0, 6, 1, -18)
	healthBack.BackgroundColor3 = Color3.fromRGB(7, 8, 9)
	healthBack.BackgroundTransparency = 0.15
	healthBack.BorderSizePixel = 0
	healthBack.ClipsDescendants = true
	healthBack.Parent = info
	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(104, 207, 80)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
	local healthText = makeText(healthBack, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 8)
	healthText.ZIndex = 2
	healthText.TextColor3 = Color3.new(1, 1, 1)
	convertChildrenToScale(gui, BILLBOARD_PIXELS)

	local record = {
		Gui = gui,
		Root = root,
		Title = title,
		Fill = healthFill,
		Health = healthText,
		Tier = tier,
		Model = model,
	}
	record.Title.Text = ("<b>BOULDER <font color=\"%s\">LV. %d</font></b>"):format(colorHex(tierColor(record.Tier)), record.Tier)
	local function updateHealth(health)
		local maxHealth = model:GetAttribute("MaxHealth") or 1
		local ratio = math.clamp(health / maxHealth, 0, 1)
		record.Fill.Size = UDim2.fromScale(ratio, 1)
		record.Fill.BackgroundColor3 = ratio <= 0.3 and Color3.fromRGB(230, 60, 60) or ratio <= 0.6 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(90, 220, 90)
		record.Health.Text = tostring(math.max(0, math.ceil(health)))
		record.Gui.Enabled = health > 0
	end
	updateHealth(model:GetAttribute("Health") or 0)
	record.HealthConnection = model:GetAttributeChangedSignal("Health"):Connect(function()
		updateHealth(model:GetAttribute("Health") or 0)
	end)
	return record
end

-- ВАЖНО (причина "над некоторыми гоблинами нет/пропадает GUI"):
-- ChildAdded на клиенте срабатывает в момент, когда до клиента доехала САМА
-- модель, а её детей (Head, Humanoid) Roblox может дореплицировать чуть
-- позже — это штатное поведение, а не редкий сбой. Раньше track() в такой
-- ситуации молча делал `return` и БОЛЬШЕ НИКОГДА не повторял попытку, из-за
-- чего конкретно этот гоблин навсегда оставался без билборда, а соседний
-- (успевший дореплицироваться) — с билбордом. Отсюда и "у некоторых есть, у
-- некоторых нет". Теперь дожидаемся нужных детей, а не сдаёмся на первом
-- же кадре.
local function track(model)
	if tracked[model] then return end
	-- Помечаем модель как "в процессе привязки", чтобы повторный ChildAdded
	-- или проход по GetChildren() не запустил вторую параллельную попытку и
	-- не создал дубль билборда.
	if pending[model] then return end
	pending[model] = true
	task.spawn(function()
		local head = model:FindFirstChild("Head") or model:WaitForChild("Head", 10)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local deadline = os.clock() + 10
			repeat
				task.wait(0.1)
				humanoid = model:FindFirstChildOfClass("Humanoid")
			until humanoid or os.clock() > deadline or not model.Parent
		end
		pending[model] = nil
		-- Гоблин мог умереть/деспавниться, пока мы ждали репликацию.
		if not model.Parent then return end
		if not head or not humanoid then
			warn(("[GoblinBillboard] У модели %s так и не появились Head/Humanoid — билборд не создан."):format(model.Name))
			return
		end
		if tracked[model] then return end
		local worldGui = head:FindFirstChild("GoblinInfo")
		if worldGui and worldGui:IsA("BillboardGui") then worldGui:Destroy() end
		tracked[model] = createBillboard(model, head, humanoid)
		tracked[model].DescendantConnection = model.DescendantAdded:Connect(function(descendant)
			if not tracked[model] then return end
			if descendant:IsA("BasePart") and descendant.Name == "Head" then
				tracked[model].Head = descendant
				tracked[model].Gui.Adornee = descendant
			elseif descendant:IsA("BillboardGui") and descendant.Name == "GoblinInfo" then
				descendant:Destroy()
			end
		end)
	end)
end

local function untrack(model)
	pending[model] = nil
	local record = tracked[model]
	if not record then return end
	if record.HealthConnection then record.HealthConnection:Disconnect() end
	if record.DescendantConnection then record.DescendantConnection:Disconnect() end
	if record.Gui then record.Gui:Destroy() end
	tracked[model] = nil
end

local function trackBoulder(model)
	-- v19: плашку ХП валунов рисует client/BoulderHitFX.
	if Config.BoulderHitFx and Config.BoulderHitFx.Enabled ~= false then return end
	if trackedBoulders[model] or pendingBoulders[model] then return end
	pendingBoulders[model] = true
	task.spawn(function()
		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not root then
			local deadline = os.clock() + 10
			repeat
				task.wait(0.1)
				root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			until root or os.clock() > deadline or not model.Parent
		end
		pendingBoulders[model] = nil
		if not model.Parent or not root or trackedBoulders[model] then return end
		local deadline = os.clock() + 5
		while model.Parent and (model:GetAttribute("Health") == nil or model:GetAttribute("MaxHealth") == nil) and os.clock() < deadline do
			task.wait(0.05)
		end
		if not model.Parent or trackedBoulders[model] then return end
		if model:FindFirstChild("BoulderHealth", true) then return end
		local record = createBoulderBillboard(model, root)
		if not record then return end
		trackedBoulders[model] = record
	end)
end

local function findBoulderAncestor(instance)
	local model = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")
	if model and isBoulderModel(model) then return model end
	return nil
end

local function untrackBoulder(model)
	pendingBoulders[model] = nil
	local record = trackedBoulders[model]
	if not record then return end
	if record.HealthConnection then record.HealthConnection:Disconnect() end
	if record.DescendantConnection then record.DescendantConnection:Disconnect() end
	if record.Gui then record.Gui:Destroy() end
	trackedBoulders[model] = nil
end

local function watchFolder(goblins)
	for _, model in goblins:GetChildren() do track(model) end
	goblins.ChildAdded:Connect(track)
	goblins.ChildRemoved:Connect(untrack)
end

local goblins = workspace:FindFirstChild("Goblins")
if goblins then watchFolder(goblins) end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Goblins" and child:IsA("Folder") then watchFolder(child) end
	if child:IsA("Model") and isBoulderModel(child) then trackBoulder(child) end
end)

-- Валуны могут находиться внутри папки/модели карты, поэтому одного
-- Workspace.ChildAdded недостаточно: он не срабатывает для вложенных моделей.
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ. Это ГЛОБАЛЬНЫЕ слушатели: они срабатывают на КАЖДЫЙ
-- инстанс, появляющийся или исчезающий где угодно в Workspace. А мир их
-- плодит непрерывно — кристалл раз в ~1.7с на каждого игрока (и это Model с
-- кучей потомков), Sound на каждый удар/звук через Sfx.play с Debris на 6с,
-- партиклы, сундуки, гоблины (у каждого десятки потомков). При 8 игроках
-- это тысячи срабатываний в минуту, и в каждом раньше вызывался
-- findBoulderAncestor: IsA + FindFirstAncestorOfClass с подъёмом по всему
-- дереву предков + GetAttribute. Чистые накладные расходы на клиенте у
-- КАЖДОГО игрока — отсюда часть просадки FPS именно в мультиплеере.
--
-- Валун — это Model с именем RubbleBoulder и атрибутом IsRubbleBoulder.
-- Имя приходит надёжнее атрибута при первой репликации, поэтому проверяем оба
-- признака и не поднимаемся по предкам для каждого появившегося инстанса.
workspace.DescendantAdded:Connect(function(descendant)
	if not descendant:IsA("Model") then return end
	if isBoulderModel(descendant) then
		trackBoulder(descendant)
	end
end)

-- На удалении вообще достаточно одного табличного лукапа: нас интересуют
-- ТОЛЬКО те модели, которые мы сами до этого затрекали.
-- Побочно чинится баг: раньше findBoulderAncestor срабатывал и на удаление
-- ЛЮБОЙ детали внутри валуна (осколок, партикл, звук), и билборд снимался
-- с ещё живого валуна — здоровье переставало отображаться до конца добычи.
workspace.DescendantRemoving:Connect(function(descendant)
	if trackedBoulders[descendant] then untrackBoulder(descendant) end
end)

for _, child in workspace:GetDescendants() do
	local boulder = findBoulderAncestor(child)
	if boulder then trackBoulder(boulder) end
end
