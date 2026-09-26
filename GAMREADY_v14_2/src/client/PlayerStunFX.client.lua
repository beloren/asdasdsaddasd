--------------------------------------------------------------------------------
-- PlayerStunFX (LocalScript) v20.43 — ЭФФЕКТ ОГЛУШЕНИЯ НАД ИГРОКОМ, пока он
-- в рагдолле (атрибут игрока Ragdolled, ставит CombatService). Видят все.
--
-- Эффект тот же, что у гоблинов: ReplicatedStorage.stunvfx (Attachment с
-- ParticleEmitter'ами) — клон вешается на голову. Нет ассета — встроенные
-- «звёздочки»: три неоновых шарика кружат над головой.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FX_NAME = "PlayerStunFx"
local active = {} -- [player] = { Attachment?, Stars = {parts}, Head }

local function clear(plr)
	local entry = active[plr]
	active[plr] = nil
	if not entry then return end
	if entry.Attachment then entry.Attachment:Destroy() end
	for _, star in entry.Stars do star:Destroy() end
end

local function start(plr)
	clear(plr)
	local character = plr.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then return end
	local entry = { Head = head, Stars = {} }
	local source = ReplicatedStorage:FindFirstChild("stunvfx")
	if source and source:IsA("Attachment") then
		local vfx = source:Clone()
		vfx.Name = FX_NAME
		vfx.Position = Vector3.new(0, head.Size.Y * 0.5 + 1.2, 0)
		vfx.Orientation = Vector3.new(0, 0, 90) -- как у гоблинов (GoblinService)
		vfx.Parent = head
		for _, d in vfx:GetDescendants() do
			if d:IsA("ParticleEmitter") then d.Enabled = true end
		end
		entry.Attachment = vfx
	else
		for i = 1, 3 do
			local star = Instance.new("Part")
			star.Name = FX_NAME
			star.Shape = Enum.PartType.Ball
			star.Size = Vector3.one * 0.35
			star.Material = Enum.Material.Neon
			star.Color = Color3.fromRGB(255, 225, 90)
			star.Anchored, star.CanCollide, star.CanQuery, star.CanTouch, star.CastShadow = true, false, false, false, false
			star.Parent = workspace.CurrentCamera
			entry.Stars[i] = star
		end
	end
	active[plr] = entry
end

local function watch(plr)
	local function refresh()
		if plr:GetAttribute("Ragdolled") == true then start(plr) else clear(plr) end
	end
	plr:GetAttributeChangedSignal("Ragdolled"):Connect(refresh)
	plr.CharacterAdded:Connect(function() clear(plr) end)
	refresh()
end

for _, plr in Players:GetPlayers() do watch(plr) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(clear)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for plr, entry in active do
		if not entry.Head.Parent then
			clear(plr)
		elseif #entry.Stars > 0 then
			local center = entry.Head.Position + Vector3.new(0, entry.Head.Size.Y * 0.5 + 0.9, 0)
			for i, star in entry.Stars do
				local angle = t * 4 + i * (math.pi * 2 / #entry.Stars)
				star.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 0.9, math.sin(t * 6 + i) * 0.12, math.sin(angle) * 0.9))
			end
		end
	end
end)
