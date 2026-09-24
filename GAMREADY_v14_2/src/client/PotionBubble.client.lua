--------------------------------------------------------------------------------
-- PotionBubble (LocalScript) — БРЫЗГИ ПРИ ПИТЬЕ ЗЕЛЬЯ.
--
-- Саму колбу над головой держат руки игрока — её строит OreCarryPose.client.lua
-- (как руду и коробку тележки) по атрибуту HeldPotion. Здесь — только
-- "бульк": когда сервер ставит игроку PotionDrankAt (GearService:
-- _drinkPotion), у каждого клиента в месте колбы разлетаются капли цвета
-- зелья и расходится светящееся кольцо.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local POTIONS = Config.Potions and Config.Potions.Types or {}

local folder = Instance.new("Folder")
folder.Name = "LocalPotionSplash"
folder.Parent = workspace

local function newDrop(size, color, transparency)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Где колба: модель, которую держит OreCarryPose, а если её уже убрали
-- (последнее зелье снимается с руки в том же серверном шаге) — над головой.
local function flaskPosition(player)
	local held = workspace:FindFirstChild("HeldPotionVisual_" .. player.UserId)
	if held and held:IsA("Model") and held.PrimaryPart then
		return held.PrimaryPart.Position
	end
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	return head and (head.Position + Vector3.new(0, 2.4, 0)) or nil
end

local function splash(player)
	local position = flaskPosition(player)
	if not position then return end
	local info = POTIONS[player:GetAttribute("PotionDrankKey") or ""]
	local color = info and info.Color or Color3.fromRGB(200, 120, 255)
	for _ = 1, 8 do
		local drop = newDrop(Vector3.new(0.3, 0.3, 0.3), color, 0)
		drop.Position = position
		drop.Parent = folder
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.6 + 0.2, math.random() - 0.5).Unit
		local tween = TweenService:Create(drop, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = position + direction * 2.2,
			Size = Vector3.new(0.05, 0.05, 0.05),
			Transparency = 1,
		})
		tween.Completed:Connect(function() drop:Destroy() end)
		tween:Play()
	end
	local ring = newDrop(Vector3.new(0.6, 0.6, 0.6), color, 0.3)
	ring.Position = position
	ring.Parent = folder
	local tween = TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3, 3, 3), Transparency = 1,
	})
	tween.Completed:Connect(function() ring:Destroy() end)
	tween:Play()
end

local function watch(player)
	player:GetAttributeChangedSignal("PotionDrankAt"):Connect(function() splash(player) end)
end

for _, player in Players:GetPlayers() do watch(player) end
Players.PlayerAdded:Connect(watch)
