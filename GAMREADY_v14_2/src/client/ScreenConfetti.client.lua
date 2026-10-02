--------------------------------------------------------------------------------
-- ScreenConfetti (LocalScript) v20.150 — КОНФЕТТИ НА ЭКРАНЕ.
-- Разноцветные квадратики вылетают снизу/из центра, кувыркаются и падают.
-- Сервер шлёт ScreenConfetti: "Small" - выполнен шаг обучения, "Big" -
-- пройдена глава/обучение/подсказка с наградой. Локально можно вызвать
-- через BindableEvent Shared.ScreenConfettiLocal:Fire("Big").
-- Настройки - Config.Confetti.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CFG = Config.Confetti or {}
local COLORS = CFG.Colors or {
	Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 200, 60), Color3.fromRGB(110, 230, 120),
	Color3.fromRGB(90, 180, 255), Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 140, 210),
}

local gui = Instance.new("ScreenGui")
gui.Name = "ScreenConfetti"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 900
gui:SetAttribute("CinematicKeep", true)
gui.Parent = playerGui

local pieces = {} -- { Frame, Pos, Vel, Spin, Life, MaxLife }
local GRAVITY = CFG.Gravity or 900

local function burst(size)
	if CFG.Enabled == false then return end
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local big = size == "Big"
	local count = big and (CFG.BigCount or 90) or (CFG.SmallCount or 36)
	local phoneScale = math.clamp(view.X / 1280, 0.6, 1)
	for i = 1, count do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = math.random(7, big and 15 or 12) * phoneScale
		frame.Size = UDim2.fromOffset(s, s * (math.random() < 0.5 and 1 or 0.55))
		frame.BackgroundColor3 = COLORS[math.random(1, #COLORS)]
		frame.Parent = gui
		-- большие - из двух нижних углов веером, маленькие - из центра снизу
		local origin, vel
		if big then
			local left = i % 2 == 0
			origin = Vector2.new(left and view.X * 0.08 or view.X * 0.92, view.Y * 0.95)
			local angle = math.rad(left and math.random(-75, -35) or math.random(-145, -105))
			local speed = math.random(700, 1150) * phoneScale
			vel = Vector2.new(math.cos(angle), math.sin(angle)) * speed
		else
			origin = Vector2.new(view.X * 0.5 + math.random(-60, 60), view.Y * 0.62)
			local angle = math.rad(math.random(-140, -40))
			local speed = math.random(380, 720) * phoneScale
			vel = Vector2.new(math.cos(angle), math.sin(angle)) * speed
		end
		local life = (big and 2.6 or 1.8) + math.random() * 0.8
		table.insert(pieces, { Frame = frame, Pos = origin, Vel = vel, Spin = math.random(-540, 540), Rot = math.random(0, 360), Life = life, MaxLife = life, Wobble = math.random() * 6 })
	end
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(big and "QuestComplete" or "QuestProgress") end)
end

RunService.RenderStepped:Connect(function(dt)
	if #pieces == 0 then return end
	for index = #pieces, 1, -1 do
		local p = pieces[index]
		p.Life -= dt
		if p.Life <= 0 then
			p.Frame:Destroy()
			table.remove(pieces, index)
		else
			-- сопротивление воздуха + гравитация + лёгкое покачивание
			p.Vel = Vector2.new(p.Vel.X * (1 - dt * 1.4), p.Vel.Y * (1 - dt * 0.6) + GRAVITY * dt)
			p.Pos += (p.Vel + Vector2.new(math.sin(os.clock() * 4 + p.Wobble) * 40, 0)) * dt
			p.Rot += p.Spin * dt
			p.Frame.Position = UDim2.fromOffset(p.Pos.X, p.Pos.Y)
			p.Frame.Rotation = p.Rot
			local fade = math.clamp(p.Life / 0.5, 0, 1)
			p.Frame.BackgroundTransparency = 1 - fade
		end
	end
end)

local remote = ReplicatedStorage.Shared:WaitForChild("ScreenConfetti", 60)
if remote then remote.OnClientEvent:Connect(burst) end
local localEvent = ReplicatedStorage.Shared:FindFirstChild("ScreenConfettiLocal") or Instance.new("BindableEvent")
localEvent.Name = "ScreenConfettiLocal"
localEvent.Parent = ReplicatedStorage.Shared
localEvent.Event:Connect(burst)
