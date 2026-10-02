--------------------------------------------------------------------------------
-- PlayerOutline (v20.131) — ЧЁРНАЯ ОБВОДКА НА КАЖДОМ ИГРОКЕ.
-- Highlight "PlayerOutline" в персонаже: только контур (FillTransparency 1),
-- OutlineColor чёрный, DepthMode Occluded (сквозь стены не виден).
-- Пока на игроке горит обводка щита (ProtectionHighlight) - чёрная гаснет,
-- чтобы не перебивать её. Настройки - Config.PlayerOutline.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local cfg = Config.PlayerOutline or {}
if cfg.Enabled == false then return end

local function setup(character)
	local outline = character:FindFirstChild("PlayerOutline")
	if not (outline and outline:IsA("Highlight")) then
		outline = Instance.new("Highlight")
		outline.Name = "PlayerOutline"
	end
	outline.Adornee = nil -- весь персонаж (родитель)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.FillColor = Color3.fromRGB(255, 0, 0)
	outline.FillTransparency = 1
	outline.OutlineColor = cfg.Color or Color3.new(0, 0, 0)
	outline.OutlineTransparency = cfg.Transparency or 0
	outline.Enabled = true
	outline.Parent = character

	local function syncWithShield()
		local shield = character:FindFirstChild("ProtectionHighlight")
		outline.Enabled = not (shield and shield:IsA("Highlight") and shield.Enabled)
	end
	local shieldConn
	local function watchShield(child)
		if child.Name ~= "ProtectionHighlight" or not child:IsA("Highlight") then return end
		if shieldConn then shieldConn:Disconnect() end
		shieldConn = child:GetPropertyChangedSignal("Enabled"):Connect(syncWithShield)
		syncWithShield()
	end
	for _, child in character:GetChildren() do watchShield(child) end
	character.ChildAdded:Connect(watchShield)
	character.ChildRemoved:Connect(function(child)
		if child.Name == "ProtectionHighlight" then syncWithShield() end
		-- кто-то удалил обводку - вернуть
		if child == outline and character.Parent then
			task.defer(function()
				if character.Parent and not outline.Parent then outline.Parent = character end
			end)
		end
	end)
end

local function onPlayer(player)
	if player.Character then task.spawn(setup, player.Character) end
	player.CharacterAdded:Connect(setup)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do onPlayer(player) end
