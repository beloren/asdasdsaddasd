local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage.Shared.Config)
local tradeRemote = ReplicatedStorage.Shared:WaitForChild("RubbleCrystalTradeRequest")

local giftPrompt
local giftTarget
local function clearGiftPrompt()
	if giftPrompt then giftPrompt:Destroy() end
	giftPrompt = nil
	giftTarget = nil
end

local function nearestGiftTarget()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local nearest, nearestDistance
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			local distance = otherRoot and (otherRoot.Position - root.Position).Magnitude
			if distance and distance <= 12 and (not nearestDistance or distance < nearestDistance) then
				nearest = otherPlayer
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function refreshGiftPrompt()
	local target = (player:GetAttribute("CarryingCrystal") or "") ~= "" and nearestGiftTarget() or nil
	if target == giftTarget and giftPrompt and giftPrompt.Parent then return end
	clearGiftPrompt()
	if not target then return end
	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	giftTarget = target
	giftPrompt = Instance.new("ProximityPrompt")
	giftPrompt.Name = "GiftCrystalPrompt"
	giftPrompt.ActionText = "GIFT CRYSTAL"
	giftPrompt.ObjectText = target.DisplayName
	giftPrompt.HoldDuration = 0.7
	giftPrompt.MaxActivationDistance = 12
	giftPrompt.ClickablePrompt = true
	giftPrompt.KeyboardKeyCode = Enum.KeyCode.E
	giftPrompt.RequiresLineOfSight = false
	giftPrompt.Style = Enum.ProximityPromptStyle.Custom
	giftPrompt.Parent = root
	giftPrompt.Triggered:Connect(function()
		if giftTarget == target and (player:GetAttribute("CarryingCrystal") or "") ~= "" then
			tradeRemote:FireServer(target)
		end
	end)
end

player:GetAttributeChangedSignal("CarryingCrystal"):Connect(refreshGiftPrompt)
RunService.Heartbeat:Connect(refreshGiftPrompt)

-- v20: ячейка кристалла — Shared.UiBuilders.RubbleCrystalUi
-- (StarterGui/RubbleCrystalHotbar), стоит над хотбаром и ничего не сдвигает.
local crystalHotbar = require(ReplicatedStorage.Shared.UiRegistry).Get("RubbleCrystalHotbar")
local crystalSlot = crystalHotbar:WaitForChild("Slot", 10)
local crystalIcon = crystalSlot and crystalSlot:WaitForChild("Icon", 5)
local crystalPlaceholder = crystalSlot and crystalSlot:WaitForChild("Placeholder", 5)
if not (crystalSlot and crystalIcon and crystalPlaceholder) then
	warn("[RubbleCrystalUI] RubbleCrystalHotbar/Slot неполон — карточка кристалла не будет показываться (передача и поза рук работают).")
	crystalSlot = nil
end

local ARM_RAISE_TRANSFORM = CFrame.Angles(math.rad(-165), 0, 0) -- см. примечание ниже
local POSE_LERP_SPEED = 12 -- скорость сглаживания подъёма/опускания рук

local posedJoints = {} -- [Model] = { Right = Motor6D, Left = Motor6D, Progress = number }

local function watchPlayerPose(targetPlayer)
	local function onCharacter(character)
		-- WaitForChild (не FindFirstChild) — на случай, если суставы рига
		-- ещё не успели полностью прогрузиться в момент CharacterAdded.
		local torso = character:WaitForChild("Torso", 5)
		local right = torso and torso:WaitForChild("Right Shoulder", 5)
		local left = torso and torso:WaitForChild("Left Shoulder", 5)
		if not (right and right:IsA("Motor6D") and left and left:IsA("Motor6D")) then return end
		posedJoints[character] = { Right = right, Left = left, Progress = 0 }
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then posedJoints[character] = nil end
		end)
	end
	targetPlayer.CharacterAdded:Connect(onCharacter)
	if targetPlayer.Character then onCharacter(targetPlayer.Character) end
end

for _, otherPlayer in Players:GetPlayers() do watchPlayerPose(otherPlayer) end
Players.PlayerAdded:Connect(watchPlayerPose)

-- ПРИМЕЧАНИЕ: угол подобран приблизительно (нет возможности проверить
-- визуально без Studio) — если руки поднимаются не совсем "над головой",
-- подправьте градус по X в ARM_RAISE_TRANSFORM выше на глаз в редакторе.
-- Используем RunService.Stepped, а не RenderStepped — ровно то же событие,
-- которым уже пользуется проверенный IK хвата за тележку
-- (CustomCartUI.client.lua) для постоянной перезаписи Motor6D.Transform.
-- Максимальная консистентность с уже работающей в игре техникой.
-- ВАЖНО: Transform трогаем ТОЛЬКО пока реально несём кристалл или ещё не
-- закончили переход обратно вниз. Раньше "иначе сбросить в identity"
-- срабатывало КАЖДЫЙ кадр, даже когда кристалла в руках уже давно нет —
-- а обычная ходьба/покой сама постоянно меняет тот же Transform (взмах
-- руками при шаге). Мы это перебивали обратно в identity каждый кадр,
-- поэтому руки казались "замороженными" всегда, а не только при переноске.
-- Теперь как только переход вниз завершён (target=0 и Progress уже 0) —
-- просто НЕ трогаем Transform вообще, отдавая полный контроль обратно
-- штатной анимации ходьбы/покоя.
RunService.Stepped:Connect(function(_, deltaTime)
	for character, record in posedJoints do
		if not character.Parent then
			posedJoints[character] = nil
		else
			local owner = Players:GetPlayerFromCharacter(character)
			local target = (owner and owner:GetAttribute("CarryingCrystal") or "") ~= "" and 1 or 0
			if target == 1 or record.Progress > 0.002 then
				record.Progress = record.Progress + (target - record.Progress) * math.min(1, deltaTime * POSE_LERP_SPEED)
				if target == 0 and record.Progress <= 0.002 then
					-- Последний кадр перехода — вернули руки в нейтраль и
					-- со следующего кадра полностью отпускаем Transform.
					record.Progress = 0
					record.Right.Transform = CFrame.new()
					record.Left.Transform = CFrame.new()
				else
					local pose = CFrame.new():Lerp(ARM_RAISE_TRANSFORM, record.Progress)
					record.Right.Transform = pose
					record.Left.Transform = pose
				end
			end
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local oreId = player:GetAttribute("CarryingCrystal") or ""
	if crystalSlot then
		crystalSlot.Visible = oreId ~= ""
		if oreId ~= "" then
			local info = Config.Geodes.Ores[oreId]
			local imageId = info and info.ImageId
			if imageId and imageId ~= 0 then
				crystalIcon.Image = "rbxassetid://" .. tostring(imageId)
				crystalIcon.ImageColor3 = Color3.new(1, 1, 1)
				crystalPlaceholder.Visible = false
			else
				crystalIcon.Image = ""
				crystalPlaceholder.Visible = true
				crystalPlaceholder.TextColor3 = info and info.Color or Color3.fromRGB(230, 230, 235)
			end
			local stroke = crystalSlot:FindFirstChild("SkinStroke")
			if stroke and info and info.Color then stroke.Color = info.Color end
		end
	end
end)
