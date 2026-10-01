--------------------------------------------------------------------------------
-- SellMoleUI (v20.108) — КРОТ-СКУПЩИК (см. server/Services/SellMoleService).
--   • Меню над кротом в стиле диалога шахтёра (MinerDialogUiBuilder):
--     SELL ALL / SELL HAND / NOT NOW.
--   • Анимация всех кротов в workspace.SellMoles (видят все игроки):
--     вылезает из земли, «дышит» масштабом, по State = "Burrow" зарывается,
--     комья земли из стадов разлетаются и залетают обратно в ямку.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local cfg = Config.SellMole or {}
if not cfg.Enabled then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("SellMoleRequest", 30)
if not remote then return end

local DialogBuilder = require(ReplicatedStorage.Shared.MinerDialogUiBuilder)
local okStud, StudTexture = pcall(require, ReplicatedStorage.Shared.StudTexture)

local function sfx(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end

--------------------------------------------------------------------------------
-- МЕНЮ
--------------------------------------------------------------------------------
local gui = DialogBuilder.Build()
gui.Name = "SellMoleDialogUi"
gui.Enabled = false
gui.Parent = playerGui
local root = gui:WaitForChild("Root")
local pop = root:FindFirstChild("Pop")
local bubble = root:FindFirstChild("Bubble")
local text = bubble:FindFirstChild("Text")
local nameTitle = bubble:FindFirstChild("NameTag") and bubble.NameTag:FindFirstChild("Title")
if nameTitle then nameTitle.Text = "MOLE" end
local choices = root:FindFirstChild("Choices")
local template = choices:FindFirstChild("ChoiceTemplate")
template.Visible = false

local open = false
local typeToken = 0

local function close(silent)
	if not open then return end
	open = false
	typeToken += 1
	if pop then
		local out = TweenService:Create(pop, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out:Play()
		out.Completed:Once(function()
			if not open then gui.Enabled = false end
		end)
	else
		gui.Enabled = false
	end
	if not silent then remote:FireServer("Close") end
end

local function typeLine(line)
	typeToken += 1
	local my = typeToken
	text.Text = line
	text.MaxVisibleGraphemes = 0
	task.spawn(function()
		local total = utf8.len(text.ContentText) or #line
		for i = 1, total do
			if typeToken ~= my then return end
			text.MaxVisibleGraphemes = i
			task.wait(0.016)
		end
		text.MaxVisibleGraphemes = -1
	end)
end

local function setChoices(list)
	for _, child in choices:GetChildren() do
		if child:IsA("GuiButton") and child ~= template then child:Destroy() end
	end
	for index, choice in list do
		local button = template:Clone()
		button.Name = "Choice" .. index
		button.LayoutOrder = index
		button.Visible = true
		button.BackgroundColor3 = DialogBuilder.CHOICE_COLORS[choice.Kind] or DialogBuilder.CHOICE_COLORS.Ask
		require(ReplicatedStorage.Shared.TutorialTarget).Mark(button, "Mole:" .. tostring(choice.Value)) -- v20.110: цель обучения
		local label = button:FindFirstChild("Label")
		if label then label.Text = choice.Text end
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = button
		task.delay(0.05 * index, function()
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		button.Parent = choices
		button.Activated:Connect(function()
			if not open then return end
			sfx("DialogueChoice")
			close(true)
			remote:FireServer("Choice", choice.Value)
		end)
	end
end

local function openMenu(payload)
	payload = typeof(payload) == "table" and payload or {}
	local npc = payload.Npc
	if not (npc and npc.Parent) then return end
	local adornee = npc:FindFirstChild("Head", true) or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
	gui.Adornee = adornee
	gui.Enabled = true
	open = true
	if pop then
		pop.Scale = 0.3
		TweenService:Create(pop, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local count = tonumber(payload.Count) or 0
	local capacity = tonumber(payload.Capacity) or -1
	local line = payload.Line or "Selling today?"
	if capacity > 0 then
		line ..= ("\n<b>%d/%d</b> ore in your backpack."):format(count, capacity)
	end
	typeLine(line)
	local list = { { Kind = "Yes", Text = "💰 SELL ALL", Value = "All" } }
	if (tonumber(payload.HandCount) or 0) > 0 then
		table.insert(list, { Kind = "Ask", Text = ("✋ SELL HAND (%d)"):format(payload.HandCount), Value = "Hand" })
	end
	table.insert(list, { Kind = "No", Text = "NOT NOW", Value = "No" })
	setChoices(list)
end

local skip = Instance.new("TextButton")
skip.Name = "SkipTyping"
skip.BackgroundTransparency = 1
skip.Text = ""
skip.Size = UDim2.fromScale(1, 1)
skip.ZIndex = 1
skip.Parent = bubble
skip.Activated:Connect(function()
	typeToken += 1
	text.MaxVisibleGraphemes = -1
end)

RunService.Heartbeat:Connect(function()
	if not open then return end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local adornee = gui.Adornee
	if not (hrp and adornee and adornee.Parent) or (hrp.Position - adornee.Position).Magnitude > 18 then
		close()
	end
end)

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Open" then
		openMenu(payload)
	elseif action == "Close" then
		close(true)
	end
end)

--------------------------------------------------------------------------------
-- АНИМАЦИЯ КРОТОВ
--------------------------------------------------------------------------------
local folder = workspace:WaitForChild("SellMoles", 30)
if not folder then return end

local DIRT = cfg.DirtColor or Color3.fromRGB(110, 72, 40)

local function dirtCube(position, size)
	local cube = Instance.new("Part")
	cube.Name = "MoleDirt"
	cube.Size = Vector3.new(size, size, size)
	cube.Color = DIRT:Lerp(Color3.new(0, 0, 0), math.random() * 0.25)
	cube.Material = Enum.Material.SmoothPlastic
	cube.TopSurface = Enum.SurfaceType.Studs
	cube.BottomSurface = Enum.SurfaceType.Inlet
	cube.Anchored = true
	cube.CanCollide = false
	cube.CanQuery = false
	cube.CanTouch = false
	cube.CastShadow = false
	cube.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	if okStud and StudTexture then pcall(StudTexture.ApplyPart, cube) end
	cube.Parent = workspace
	return cube
end

-- комья разлетаются; back = true - потом залетают обратно в ямку
local function dirtBurst(center, back)
	local count = cfg.DirtCount or 10
	for i = 1, count do
		local size = 0.35 + math.random() * 0.45
		local cube = dirtCube(center + Vector3.new(0, 0.3, 0), size)
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local dist = 2.5 + math.random() * 3
		local landing = center + Vector3.new(math.cos(angle) * dist, size / 2, math.sin(angle) * dist)
		local apex = (center + landing) / 2 + Vector3.new(0, 2.5 + math.random() * 2, 0)
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		task.spawn(function()
			local up = TweenService:Create(cube, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) * spin })
			up:Play()
			up.Completed:Wait()
			local down = TweenService:Create(cube, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(landing) * spin:Inverse() })
			down:Play()
			down.Completed:Wait()
			task.wait(0.25 + math.random() * 0.25)
			if back then
				local hole = center - Vector3.new(0, 0.6, 0)
				local into = TweenService:Create(cube, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					CFrame = CFrame.new(hole) * spin, Size = Vector3.new(0.05, 0.05, 0.05),
				})
				into:Play()
				into.Completed:Wait()
			else
				local fade = TweenService:Create(cube, TweenInfo.new(0.4), { Transparency = 1, Size = cube.Size * 0.4 })
				fade:Play()
				fade.Completed:Wait()
			end
			cube:Destroy()
		end)
	end
end

local function animate(model)
	if not model:IsA("Model") then return end
	-- ждём реплику деталей
	local deadline = os.clock() + 3
	while not model.PrimaryPart and os.clock() < deadline do task.wait() end
	if not model.Parent then return end
	local base = model:GetPivot()
	local _, size = model:GetBoundingBox()
	local depth = size.Y + 0.6
	local groundY = tonumber(model:GetAttribute("GroundY")) or base.Position.Y
	local holeCenter = Vector3.new(base.Position.X, groundY, base.Position.Z)
	local baseScale = model:GetScale()
	local offset = Instance.new("NumberValue")
	offset.Value = -depth
	local alive = true
	local bobbing = false
	local t0 = os.clock()

	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not (alive and model.Parent) then
			conn:Disconnect()
			return
		end
		if bobbing then
			local k = 1 + math.sin((os.clock() - t0) * (cfg.BobSpeed or 3) * math.pi) * (cfg.BobAmount or 0.06)
			pcall(model.ScaleTo, model, baseScale * k)
		end
		model:PivotTo(base + Vector3.new(0, offset.Value, 0))
	end)
	model:PivotTo(base + Vector3.new(0, -depth, 0))
	dirtBurst(holeCenter, false)
	local rise = TweenService:Create(offset, TweenInfo.new(cfg.RiseSeconds or 0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 0 })
	rise:Play()
	rise.Completed:Once(function()
		if alive then bobbing = true; t0 = os.clock() end
	end)

	local function burrow()
		bobbing = false
		pcall(model.ScaleTo, model, baseScale)
		dirtBurst(holeCenter, true)
		TweenService:Create(offset, TweenInfo.new(cfg.BurrowSeconds or 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Value = -depth }):Play()
	end
	if model:GetAttribute("State") == "Burrow" then burrow() end
	model:GetAttributeChangedSignal("State"):Connect(function()
		if model:GetAttribute("State") == "Burrow" then burrow() end
	end)
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			alive = false
			offset:Destroy()
		end
	end)
end

for _, child in folder:GetChildren() do task.spawn(animate, child) end
folder.ChildAdded:Connect(function(child) task.spawn(animate, child) end)
