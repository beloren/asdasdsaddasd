local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("DamageNumberEvent")
local stacks = {}
local GUI_HEIGHT = 0.78
local STACK_STEP = 0.9

local function partTopY(part)
	local cf, size = part.CFrame, part.Size
	local extent = 0.5 * (
		math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z
	)
	return cf.Position.Y + extent
end

local function topOffset(target)
	local topY = partTopY(target)
	local model = target:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local head = humanoid and model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		topY = math.max(topY, partTopY(head))
	end
	if model then
		local ok, cf, size = pcall(model.GetBoundingBox, model)
		if ok then
			local extent = 0.5 * (
				math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z
			)
			topY = math.max(topY, cf.Position.Y + extent)
		end
	end
	return topY - target.Position.Y + GUI_HEIGHT * 0.5 + 0.2
end

local function refreshStack(target)
	local stack = stacks[target]
	if not stack then return end
	local baseOffset = topOffset(target)
	for index, entry in stack do
		if entry.Gui.Parent then
			entry.Gui.StudsOffsetWorldSpace = Vector3.new(0, baseOffset + (index - 1) * STACK_STEP, 0)
		end
	end
end

local function removeEntry(target, entry)
	local stack = stacks[target]
	if not stack then return end
	local index = table.find(stack, entry)
	if index then table.remove(stack, index) end
	if entry.Gui then entry.Gui:Destroy() end
	if entry.Anchor then entry.Anchor:Destroy() end
	if #stack == 0 then stacks[target] = nil else refreshStack(target) end
end

remote.OnClientEvent:Connect(function(target, amount, hitPosition)
	amount = tonumber(amount)
	if not amount or amount ~= amount or math.abs(amount) == math.huge or amount <= 0 or amount > 1000000000 then return end
	local temporaryAnchor
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") or not target:IsDescendantOf(workspace) then
		if typeof(hitPosition) ~= "Vector3" then return end
		temporaryAnchor = Instance.new("Part")
		temporaryAnchor.Name = "DamageNumberAnchor"
		temporaryAnchor.Size = Vector3.one * 0.1
		temporaryAnchor.Position = hitPosition
		temporaryAnchor.Transparency = 1
		temporaryAnchor.Anchored = true
		temporaryAnchor.CanCollide = false
		temporaryAnchor.CanTouch = false
		temporaryAnchor.CanQuery = false
		temporaryAnchor.Parent = workspace
		target = temporaryAnchor
	end

	local stack = stacks[target] or {}
	stacks[target] = stack
	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageNumber"
	gui.Adornee = target
	gui.Size = UDim2.fromScale(3.36, 0.78)
	gui.SizeOffset = Vector2.zero
	gui.StudsOffsetWorldSpace = Vector3.new(0, topOffset(target) + #stack * STACK_STEP, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Parent = playerGui

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Arcade
	text.TextScaled = true
	local amountText = ("%.2f"):format(amount):gsub("0+$", ""):gsub("%.$", "")
	text.Text = "-" .. amountText .. " HP"
	text.TextColor3 = Color3.fromRGB(255, 78, 72)
	text.TextStrokeColor3 = Color3.fromRGB(40, 0, 0)
	text.TextStrokeTransparency = 0
	text.TextTransparency = 1
	text.Parent = gui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 1
	constraint.MaxTextSize = 22
	constraint.Parent = text

	local entry = { Gui = gui, Text = text, Anchor = temporaryAnchor }
	table.insert(stack, entry)
	refreshStack(target)
	TweenService:Create(text, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	task.delay(0.72, function()
		if gui.Parent then
			TweenService:Create(text, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
		task.delay(0.3, removeEntry, target, entry)
	end)
end)

RunService.RenderStepped:Connect(function()
	for target in stacks do
		if target.Parent then refreshStack(target) end
	end
end)
