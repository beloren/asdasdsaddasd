--------------------------------------------------------------------------------
-- ChestFX (LocalScript) v16 — ОТКРЫТИЕ СУНДУКА ЗАЖАТИЕМ + ЛУТ В МИР.
--
-- 1) ЗАЖАТИЕ. Промпт готового сундука (атрибут ChestOpen = true) нужно
--    держать полностью (Config.Chests.HoldSeconds). Пока держишь: сундук
--    трясётся всё сильнее, крышка приоткрывается на петле, из щелей бьёт
--    свет цвета редкости, летят искры. Отпустил раньше — всё плавно
--    откатывается в закрытое состояние. Двигаются только ЛОКАЛЬНЫЕ CFrame —
--    сервер модель не трогает.
-- 2) ОТКРЫТИЕ. Сервер шлёт Shared.ChestFx "Open" { Model, Rarity, Owner,
--    Items } всем. Клиент прячет серверную модель и играет на локальной
--    копии: крышка улетает, столб света, награды вылетают фонтаном,
--    падают вокруг, у владельца потом влетают в него. Список наград —
--    в ленте справа (LootFeed), отдельного окна нет.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local okReveal, RevealCards = pcall(require, ReplicatedStorage.Shared.RevealCards) -- v18
if not okReveal then RevealCards = nil end
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей

local player = Players.LocalPlayer
local CFG = Config.Chests

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ChestFX"
fxFolder.Parent = workspace

local function rarityColor(rarity)
	local info = CFG.Types[rarity]
	return (info and info.Color) or Config.RarityColors[rarity] or Color3.fromRGB(255, 220, 120)
end

local function partsOf(model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

local function findLid(model)
	local lid = model:FindFirstChild("Lid", true)
	if lid and lid:IsA("BasePart") then return lid end
	return nil
end

--------------------------------------------------------------------------------
-- ПОЗА СУНДУКА: тряска + угол крышки. Всё считается от исходных CFrame.
--------------------------------------------------------------------------------
local states = {} -- [model] = { Base, Rel, Lid, Hinge, Progress, Holding, Light, Emitter, Highlight, Welds }

local function stateFor(model)
	local state = states[model]
	if state then return state end
	local pivot = model:GetPivot()
	state = { Base = pivot, Rel = {}, Progress = 0, Holding = false, Welds = {} }
	for _, p in partsOf(model) do
		state.Rel[p] = pivot:ToObjectSpace(p.CFrame)
	end
	local lid = findLid(model)
	if lid then
		state.Lid = lid
		-- Петля — задняя нижняя кромка крышки (+Z).
		state.Hinge = CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2)
		-- Сварка крышки с корпусом двигала бы весь сундук — локально выключаем.
		for _, d in model:GetDescendants() do
			if d:IsA("WeldConstraint") and (d.Part0 == lid or d.Part1 == lid) and d.Enabled then
				d.Enabled = false
				table.insert(state.Welds, d)
			end
		end
	end
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local rarity = model:GetAttribute("ChestRarity") or "Common"
	local color = rarityColor(rarity)
	if root then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 0
		light.Shadows = false
		light.Parent = root
		state.Light = light
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.25, 0)
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(3, 7)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Rate = 0
		emitter.Parent = root
		state.Emitter = emitter
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	state.Highlight = highlight
	states[model] = state
	return state
end

local function applyPose(model, state, progress, t)
	local amplitude = math.rad(1 + 7 * progress) * (progress > 0.001 and 1 or 0)
	local bounce = progress > 0.001 and math.abs(math.sin(t * (10 + 18 * progress))) * 0.12 * progress or 0
	local shake = state.Base * CFrame.new(0, bounce, 0) * CFrame.Angles(
		math.sin(t * 43) * amplitude * 0.5,
		math.sin(t * 29) * amplitude * 0.3,
		math.sin(t * 37 + 1) * amplitude)
	local lidAngle = math.rad(38) * (progress ^ 1.4)
	for p, rel in state.Rel do
		if p.Parent then
			if p == state.Lid then
				p.CFrame = shake * rel * state.Hinge * CFrame.Angles(lidAngle, 0, 0) * state.Hinge:Inverse()
			else
				p.CFrame = shake * rel
			end
		end
	end
	if state.Light then state.Light.Brightness = 6 * progress end
	if state.Emitter then state.Emitter.Rate = 60 * progress end
	if state.Highlight then
		state.Highlight.FillTransparency = 1 - 0.45 * progress
		state.Highlight.OutlineTransparency = 1 - 0.8 * progress
	end
end

local function restore(model, state)
	for p, rel in state.Rel do
		if p.Parent then p.CFrame = state.Base * rel end
	end
	for _, weld in state.Welds do weld.Enabled = true end
	if state.Light then state.Light:Destroy() end
	if state.Emitter then state.Emitter:Destroy() end
	if state.Highlight then state.Highlight:Destroy() end
	states[model] = nil
end

local animating = {} -- [model] = connection

local function animate(model, prompt)
	if animating[model] then return end
	local state = stateFor(model)
	local lastCreak = 0
	animating[model] = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then
			animating[model]:Disconnect()
			animating[model] = nil
			states[model] = nil
			return
		end
		local hold = math.max(0.1, prompt and prompt.HoldDuration or 2)
		if state.Holding then
			state.Progress = math.min(1, state.Progress + dt / hold)
		elseif not state.Opened then
			-- Отпустил — плавный откат в закрытое состояние.
			state.Progress = math.max(0, state.Progress - dt * 3)
		end
		local t = os.clock()
		applyPose(model, state, state.Progress, t)
		if state.Holding and t - lastCreak > 0.45 - 0.3 * state.Progress then
			lastCreak = t
			Sfx.play("ChestCreak", model)
		end
		if not state.Holding and not state.Opened and state.Progress <= 0 then
			animating[model]:Disconnect()
			animating[model] = nil
			restore(model, state)
		end
	end)
end

local function chestModelOf(prompt)
	if not (prompt and prompt:GetAttribute("ChestOpen") == true) then return nil end
	return prompt:FindFirstAncestorOfClass("Model")
end

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	local model = chestModelOf(prompt)
	if not model then return end
	local state = stateFor(model)
	state.Holding = true
	animate(model, prompt)
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	local model = chestModelOf(prompt)
	local state = model and states[model]
	if state then state.Holding = false end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local model = chestModelOf(prompt)
	local state = model and states[model]
	if state then
		-- Держим финальную позу, пока сервер не пришлёт "Open".
		state.Holding = false
		state.Opened = true
		state.Progress = 1
		task.delay(2, function()
			-- Сервер не ответил (сундук ещё не готов и т.п.) — откатываемся.
			if states[model] == state and model.Parent then state.Opened = false end
		end)
	end
end)

--------------------------------------------------------------------------------
-- ОТКРЫТИЕ: крышка улетает, столб света, лут фонтаном
--------------------------------------------------------------------------------
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for key, value in props do p[key] = value end
	return p
end

local function lootToken(item, color, from, landing, isOwner, delay)
	task.delay(delay, function()
		local icons = CFG.LootIcons or {}
		local orb = part({
			Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Material = Enum.Material.Neon,
			Color = color, Transparency = 0.15,
		})
		orb.CFrame = CFrame.new(from)
		orb.Parent = fxFolder
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 64)
		gui.StudsOffset = Vector3.new(0, 1.4, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Parent = orb
		local icon = WorldUi.Text(nil, "Text", "Heading")
		icon.Size = UDim2.new(1, 0, 0.6, 0)
		icon.BackgroundTransparency = 1
		icon.Text = icons[item.Kind] or "🎁"
		icon.TextScaled = true
		icon.Parent = gui
		local label = WorldUi.Text(nil, "Text", "Heading")
		label.Position = UDim2.fromScale(0, 0.6)
		label.Size = UDim2.new(1, 0, 0.4, 0)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = tostring(item.Text or "")
		label.Parent = gui
		Sfx.play("LootPop", orb)
		-- Дуга вверх и падение на землю с небольшим отскоком.
		local flight, apex = 0.7, 6 + math.random() * 3
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - started) / flight, 0, 1)
			local position = from:Lerp(landing, k) + Vector3.new(0, 4 * apex * k * (1 - k), 0)
			orb.CFrame = CFrame.new(position)
			if k >= 1 then connection:Disconnect() end
		end)
		task.wait(flight + 0.7)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if isOwner and root and orb.Parent then
			-- Лут влетает во владельца.
			local startPos = orb.Position
			local t0 = os.clock()
			local pull
			pull = RunService.RenderStepped:Connect(function()
				local k = math.clamp((os.clock() - t0) / 0.35, 0, 1)
				if not root.Parent then pull:Disconnect() return end
				orb.CFrame = CFrame.new(startPos:Lerp(root.Position, k * k))
				orb.Size = Vector3.one * 1.1 * (1 - 0.7 * k)
				if k >= 1 then
					pull:Disconnect()
					orb:Destroy()
				end
			end)
		else
			TweenService:Create(orb, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.one * 0.2 }):Play()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			TweenService:Create(icon, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		Debris:AddItem(orb, 1.5)
	end)
end

local function playOpen(payload)
	local model = payload.Model
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	local rarity = payload.Rarity or "Common"
	local color = rarityColor(rarity)
	local isOwner = payload.Owner == player.UserId
	local state = states[model]
	if animating[model] then
		animating[model]:Disconnect()
		animating[model] = nil
	end
	-- Серверную модель прячем, анимируем локальную копию.
	local pivot = state and state.Base or model:GetPivot()
	local copy = nil
	local archivable = model.Archivable
	model.Archivable = true
	local ok = pcall(function() copy = model:Clone() end)
	model.Archivable = archivable
	for _, p in partsOf(model) do p.LocalTransparencyModifier = 1 end
	for _, d in model:GetDescendants() do
		if d:IsA("BillboardGui") then d.Enabled = false end
	end
	if state then
		for _, weld in state.Welds do weld.Enabled = true end
		states[model] = nil
	end
	if not (ok and copy) then return end
	for _, d in copy:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("Highlight") then d:Destroy() end
	end
	for _, p in partsOf(copy) do
		p.Anchored = true
		p.CanCollide = false
		p.LocalTransparencyModifier = 0
	end
	copy.Parent = fxFolder
	Sfx.play("ChestBurst", copy)
	Sfx.play("ChestOpen", copy)
	local center = pivot.Position
	-- Крышка улетает вверх, кувыркаясь.
	local lid = findLid(copy)
	if lid then
		for _, d in copy:GetDescendants() do
			if d:IsA("WeldConstraint") and (d.Part0 == lid or d.Part1 == lid) then d:Destroy() end
		end
		local target = lid.CFrame * CFrame.new(0, 7, 3) * CFrame.Angles(math.rad(-160), math.rad(40), 0)
		TweenService:Create(lid, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
		task.delay(0.45, function()
			TweenService:Create(lid, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end)
	end
	-- v20.35: вместо столба света — эффект открытия (shared/RevealVfx):
	-- свой Assets/Reveal_Chest_<Редкость> или Reveal_<Редкость>, иначе плейсхолдер.
	pcall(function()
		require(ReplicatedStorage.Shared.RevealVfx).Play({ "Reveal_Chest_" .. rarity, "Reveal_" .. rarity, "RevealVFX" }, center + Vector3.new(0, 1, 0), {
			Color = color,
			Power = rarity == "Legendary" and 5 or rarity == "Epic" and 4 or rarity == "Rare" and 3 or 2,
		})
	end)
	local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Material = Enum.Material.Neon, Color = color })
	flash.CFrame = CFrame.new(center + Vector3.new(0, 1, 0))
	flash.Parent = fxFolder
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 9, Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 0.4)
	local sparkHolder = part({ Size = Vector3.one * 0.2, Transparency = 1 })
	sparkHolder.CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0))
	sparkHolder.Parent = fxFolder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.45, 0)
	sparks.Lifetime = NumberRange.new(0.5, 1)
	sparks.Speed = NumberRange.new(14, 26)
	sparks.SpreadAngle = Vector2.new(50, 50)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 0
	sparks.Parent = sparkHolder
	sparks:Emit(rarity == "Legendary" and 90 or rarity == "Epic" and 60 or 35)
	Debris:AddItem(sparkHolder, 2)
	-- Лут фонтаном.
	local items = type(payload.Items) == "table" and payload.Items or {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fxFolder, model, player.Character }
	for index, item in items do
		local angle = (index / math.max(1, #items)) * math.pi * 2 + math.random() * 0.6
		local distance = 3.5 + math.random() * 2.5
		local guess = center + Vector3.new(math.cos(angle) * distance, 4, math.sin(angle) * distance)
		local hit = workspace:Raycast(guess, Vector3.new(0, -14, 0), params)
		local landing = (hit and hit.Position or (guess - Vector3.new(0, 4, 0))) + Vector3.new(0, 0.6, 0)
		local itemColor = Config.RarityColors[item.Rarity or ""] or color
		lootToken(item, itemColor, center + Vector3.new(0, 1.5, 0), landing, isOwner, 0.15 + index * 0.12)
	end
	-- v18: владельцу — карточки открытия (общий вид с жеодами).
	if isOwner and RevealCards and #items > 0 then
		local info = CFG.Types and CFG.Types[rarity]
		task.delay(0.9 + #items * 0.12, function()
			RevealCards.Show(items, { Title = ((info and info.DisplayName) or "CHEST"):upper() .. " OPENED!", Color = color })
		end)
	end
	-- Корпус оседает и исчезает.
	task.delay(0.9, function()
		for _, p in partsOf(copy) do
			if p ~= lid then TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
		end
	end)
	Debris:AddItem(copy, 2)
end

local remote = ReplicatedStorage.Shared:WaitForChild("ChestFx", 60)
if not remote then
	warn("[ChestFX] ChestFx не появился — анимация открытия сундуков отключена.")
	return
end
remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "Open" and type(payload) == "table" then
		local ok, err = pcall(playOpen, payload)
		if not ok then warn("[ChestFX] ", err) end
	end
end)
