--------------------------------------------------------------------------------
-- OreUnlockFx (v20.109) — открыл коробку руды: карточка
-- «NEW ORE APPEARED IN THE MINE!» (RevealCards) + искры на игроке.
-- v20.114: перед этим - «Opening»: над игроком реплика (у всех клиентов),
-- у самого игрока трясётся экран, пока коробка трясётся над головой.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local remote = ReplicatedStorage.Shared:WaitForChild("OreUnlockFx", 30)
if not remote then return end

local player = Players.LocalPlayer

-- Тряска экрана: смещение поверх камеры (RenderStep после Camera), каждый
-- кадр снимается, если камеру никто не пересчитал - не накапливается.
local shakeUntil, shakePower = 0, 0
local written, writtenOffset = nil, CFrame.identity
RunService:BindToRenderStep("OreBoxShake", Enum.RenderPriority.Camera.Value + 4, function()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local current = camera.CFrame
	local base = (written and current == written) and current * writtenOffset:Inverse() or current
	local now = os.clock()
	if now >= shakeUntil or camera.CameraType ~= Enum.CameraType.Custom then
		if written and current == written then camera.CFrame = base end
		written, writtenOffset = nil, CFrame.identity
		return
	end
	-- нарастает к концу (вот-вот откроется)
	local left = shakeUntil - now
	local power = shakePower * math.clamp(1.4 - left * 0.4, 0.4, 1.4)
	local t = now * 40
	local offset = CFrame.new(math.sin(t) * power * 0.25, math.cos(t * 1.3) * power * 0.25, 0)
		* CFrame.Angles(0, 0, math.sin(t * 0.7) * power * 0.02)
	local target = base * offset
	writtenOffset = offset
	camera.CFrame = target
	written = target
end)

local function playerFrom(payload)
	local who = payload.Player
	return typeof(who) == "Instance" and who:IsA("Player") and who or nil
end

remote.OnClientEvent:Connect(function(action, payload)
	if typeof(payload) ~= "table" then return end
	if action == "Opening" then
		local who = playerFrom(payload)
		local character = who and who.Character
		if character then
			local okBubble, SpeechBubble = pcall(require, ReplicatedStorage.Shared.SpeechBubble)
			if okBubble then
				pcall(SpeechBubble.Say, character, tostring(payload.Line or "what happened..?"), {
					Name = "OreBoxBubble", Offset = 6.2, Hold = math.max(0.6, (tonumber(payload.Seconds) or 1.8) - 0.6),
				})
			end
		end
		if who == player then
			shakeUntil = os.clock() + (tonumber(payload.Seconds) or 1.8)
			shakePower = (Config.MineRework and Config.MineRework.OpenShake) or 0.35
			local okSfx, UiSfx = pcall(require, ReplicatedStorage.Shared.UiSfx)
			if okSfx then pcall(UiSfx.play, "UiButtonClick") end
		end
		return
	end
	if action == "Opened" then
		local who = playerFrom(payload)
		if who == player then shakeUntil = 0 end
		-- хлопок коробки: щепки цвета дерева у всех клиентов
		local box = who and workspace:FindFirstChild("HeldOreBoxVisual_" .. who.UserId)
		local position = box and box:GetPivot().Position
		if position then
			local ore = Config.OreByKey[payload.Ore]
			for i = 1, 10 do
				local chip = Instance.new("Part")
				chip.Size = Vector3.new(0.3, 0.3, 0.3)
				chip.Color = i % 3 == 0 and (ore and ore.Color or Color3.new(1, 1, 1)) or Color3.fromRGB(150, 98, 52)
				chip.Material = Enum.Material.SmoothPlastic
				chip.TopSurface = Enum.SurfaceType.Studs
				chip.CanCollide = false
				chip.CanQuery = false
				chip.CanTouch = false
				chip.Position = position
				chip.AssemblyLinearVelocity = Vector3.new(math.random(-12, 12), math.random(10, 20), math.random(-12, 12))
				chip.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
				chip.Parent = workspace
				game:GetService("Debris"):AddItem(chip, 1.5)
			end
		end
		return
	end
	if action ~= "Unlocked" then return end
	local ore = Config.OreByKey[payload.Ore]
	if not ore then return end
	local rarity = payload.Rarity or "Common"
	local ok, RevealCards = pcall(require, ReplicatedStorage.Shared.RevealCards)
	if ok and RevealCards then
		pcall(RevealCards.Show, { {
			Kind = "Ore", OreId = payload.Ore, Variant = 2, Rarity = rarity,
			Title = ore.DisplayName,
			MutationNames = payload.Boost and ("DROPS x%.2f MORE OFTEN"):format(payload.Boost)
				or ("NEXT DIG: x%d GUARANTEED!"):format(payload.Guaranteed or 3),
		} }, { Title = payload.Boost and "ORE BOOSTED!" or "NEW ORE APPEARED IN THE MINE!", Color = Config.RarityColors[rarity] or ore.Color })
	end
	local okVfx, AssetVfx = pcall(require, ReplicatedStorage.Shared.AssetVfx)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if okVfx and AssetVfx and root then
		pcall(AssetVfx.AttachTo, "Sparkles", root, { Color = ore.Color, Duration = 3 })
	end
end)
