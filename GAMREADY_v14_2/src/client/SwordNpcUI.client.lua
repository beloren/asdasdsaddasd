local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage.Shared:WaitForChild("SwordNpcRequest")
local dialogToken = 0
local activeNpc
local dialogGui
local dialogText
local distanceConnection
local fullText = ""

local function destroyDialog()
	if dialogGui then dialogGui:Destroy(); dialogGui = nil end
	dialogText = nil
end

local function closeDialog(notifyServer)
	dialogToken += 1
	if distanceConnection then distanceConnection:Disconnect(); distanceConnection = nil end
	if notifyServer and activeNpc then remote:FireServer("Close") end
	activeNpc = nil
	destroyDialog()
end

local function createDialog(npc)
	local root = npc:FindFirstChild("Head", true) or npc.PrimaryPart
	if not root or not root:IsA("BasePart") then return false end
	dialogGui = Instance.new("BillboardGui")
	dialogGui.Name = "ZavtrackDialog"
	dialogGui.Size = UDim2.fromOffset(460, 150)
	dialogGui.StudsOffset = Vector3.new(0, 3.5, 0)
	dialogGui.AlwaysOnTop = true
	dialogGui.MaxDistance = 60
	dialogGui.Parent = root
	dialogText = Instance.new("TextLabel")
	dialogText.Size = UDim2.fromScale(1, 1)
	dialogText.BackgroundTransparency = 1
	dialogText.Font = Enum.Font.Arcade
	dialogText.TextColor3 = Color3.fromRGB(225, 242, 255)
	dialogText.TextStrokeColor3 = Color3.fromRGB(5, 10, 20)
	dialogText.TextStrokeTransparency = 0
	dialogText.TextSize = 23
	dialogText.TextWrapped = true
	dialogText.TextXAlignment = Enum.TextXAlignment.Center
	dialogText.TextYAlignment = Enum.TextYAlignment.Center
	dialogText.Parent = dialogGui
	return true
end

local function typeText(message, token)
	local length = utf8.len(message) or #message
	for index = 1, length do
		if token ~= dialogToken or not dialogText then return false end
		local nextByte = utf8.offset(message, index + 1)
		dialogText.Text = nextByte and message:sub(1, nextByte - 1) or message
		task.wait(0.055)
	end
	return token == dialogToken
end

local function beginDialog(npc)
	closeDialog(false)
	activeNpc = npc
	if not createDialog(npc) then
		closeDialog(true)
		return
	end
	dialogToken += 1
	local token = dialogToken
	fullText = "Hello... you found me. That is truly impressive; you did very well. I am happy you found me. You know, you are the best among everyone I have ever seen. I am giving you Frostmorn... and now... leave me alone!"
	task.spawn(function()
		if typeText(fullText, token) then
			task.wait(0.35)
			if token == dialogToken then remote:FireServer("Claim") end
		end
	end)
	distanceConnection = RunService.Heartbeat:Connect(function()
		local character = player.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		local npcRoot = npc.PrimaryPart
		if not playerRoot or not npcRoot or not npcRoot.Parent or (playerRoot.Position - npcRoot.Position).Magnitude > 14 then
			closeDialog(true)
		end
	end)
end

remote.OnClientEvent:Connect(function(action, npc, result)
	if action == "Begin" then
		beginDialog(npc)
	elseif action == "Result" and dialogText then
		if result == "Granted" then
			dialogText.RichText = true
			dialogText.Text = fullText .. '\n\n<font color="#50AFFF">Frostmorn has been added to your Pickaxe Skins inventory.</font>'
		elseif result == "AlreadyOwned" then
			dialogText.Text = fullText .. "\n\nYou already own Frostmorn."
		elseif result == "MissingAsset" then
			dialogText.Text = "The Frostmorn skin is not ready yet. Check Skin_Frostmorn in Workspace."
		elseif result == "SaveFailed" then
			dialogText.Text = "I could not safely save Frostmorn. Please try again."
		else
			dialogText.Text = "Please try again in a moment."
		end
		task.delay(5, function() closeDialog(false) end)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and activeNpc then closeDialog(true) end
end)
