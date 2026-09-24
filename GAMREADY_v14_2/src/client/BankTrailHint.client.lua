local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей
local remote = ReplicatedStorage.Shared:WaitForChild("BankTrailHintEvent")
local cleanupCurrent

local function showGuide(cargoKind)
	if cleanupCurrent then cleanupCurrent() end
	local sellZone = workspace:FindFirstChild("SellZone", true)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not sellZone or not sellZone:IsA("BasePart") or not hrp then return end

	local startAttachment = Instance.new("Attachment")
	startAttachment.Name = "BankTrailStart"
	startAttachment.Parent = hrp
	local target = Instance.new("Part")
	target.Name = "BankTrailTarget"
	target.Size = Vector3.one * 0.2
	target.Position = sellZone.Position + Vector3.new(0, sellZone.Size.Y * 0.5 + 0.15, 0)
	target.Transparency = 1
	target.Anchored = true
	target.CanCollide = false
	target.CanTouch = false
	target.CanQuery = false
	target.Parent = workspace
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = target

	local beam = Instance.new("Beam")
	beam.Name = "BankTrailHint"
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(Config.Tutorial.TrailColor)
	beam.Width0 = Config.Tutorial.TrailWidth
	beam.Width1 = Config.Tutorial.TrailWidth
	beam.Texture = "rbxassetid://" .. tostring(Config.Tutorial.TrailTextureId)
	beam.TextureLength = Config.Tutorial.TrailTextureLength
	beam.TextureSpeed = Config.Tutorial.TrailScrollSpeed
	beam.Parent = target

	local arrow = Instance.new("BillboardGui")
	arrow.Name = "BankTrailArrow"
	arrow.Adornee = sellZone
	arrow.Size = UDim2.fromScale(2.4, 1.2)
	arrow.StudsOffsetWorldSpace = Vector3.new(0, sellZone.Size.Y * 0.5 + 3, 0)
	arrow.AlwaysOnTop = true
	arrow.MaxDistance = 250
	arrow.Parent = player:WaitForChild("PlayerGui")
	local arrowText = WorldUi.Text(nil, "Text", "Number")
	arrowText.Size = UDim2.fromScale(1, 1)
	arrowText.BackgroundTransparency = 1
	arrowText.TextScaled = true
	arrowText.Text = "BANK"
	arrowText.Size = UDim2.fromScale(1, 0.55)
	-- v20.9: стрелка под надписью — фигура (символа ▼ в шрифтах Roblox нет).
	require(ReplicatedStorage.Shared.UiKit).Shape(arrow, "Arrow", "ChevronDown", {
		Color = Config.Tutorial.TrailColor,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.42),
	})
	arrowText.TextColor3 = Config.Tutorial.TrailColor
	arrowText.Parent = arrow

	local connection
	local active = true
	local function cleanup()
		if not active then return end
		active = false
		if connection then connection:Disconnect() end
		startAttachment:Destroy()
		target:Destroy()
		arrow:Destroy()
		if cleanupCurrent == cleanup then cleanupCurrent = nil end
	end
	cleanupCurrent = cleanup
	local startedAt = os.clock()
	connection = RunService.Heartbeat:Connect(function()
		local currentCharacter = player.Character
		local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
		local carrying = cargoKind == "Rubble" and player:GetAttribute("CarryingCrystal") ~= ""
			or cargoKind == "Hand" and (player:GetAttribute("HandOreCount") or 0) > 0
		if not currentRoot or startAttachment.Parent ~= currentRoot or not carrying or os.clock() - startedAt > 60 then cleanup(); return end
		local localPosition = sellZone.CFrame:PointToObjectSpace(currentRoot.Position)
		if math.abs(localPosition.X) <= sellZone.Size.X * 0.5
			and math.abs(localPosition.Y) <= sellZone.Size.Y * 0.5 + 4
			and math.abs(localPosition.Z) <= sellZone.Size.Z * 0.5 then cleanup() end
	end)
end

remote.OnClientEvent:Connect(showGuide)
