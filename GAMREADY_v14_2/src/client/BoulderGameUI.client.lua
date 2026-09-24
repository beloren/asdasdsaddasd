--------------------------------------------------------------------------------
-- BoulderGameUI (LocalScript) — мини-игра валунов (Config.BoulderGame).
-- Сервер (RockService) присылает "Open"/"Update"/"Close". Панель стоит
-- СПРАВА от валуна на экране. Клик/тап/R2 = удар: клиент шлёт позицию
-- бегунка, сервер сверяет её со своей траекторией и ставит оценку.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)

local cfg = Config.BoulderGame
if not (cfg and cfg.Enabled) then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("BoulderGameUi") -- v20: StarterGui/BoulderGameUi или сборка билдером
if not gui or (tonumber(gui:GetAttribute("BuilderVersion")) or 0) < (cfg.UiVersion or 1) then
	if gui then gui:Destroy() end
	gui = require(ReplicatedStorage.Shared.BoulderGameUiBuilder).Build()
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false

local panel = gui:WaitForChild("Panel")
local track = panel:WaitForChild("Track")
local goodZone = track:WaitForChild("GoodZone")
local perfectZone = track:WaitForChild("PerfectZone")
local runner = track:WaitForChild("Runner")
local title = panel:FindFirstChild("Title")
local progress = panel:FindFirstChild("Progress")
local progressFill = progress and progress:FindFirstChild("Fill")
local progressCount = progress and progress:FindFirstChild("Count")
local verdict = panel:FindFirstChild("Verdict")
local hint = panel:FindFirstChild("Hint")
local resultLabel = gui:FindFirstChild("Result")
local autoScale = panel:FindFirstChild("AutoScale")

-- Картинки из билдера: задан Image — прячем «запасную» плашку.
local trackImage = track:FindFirstChild("TrackImage")
if trackImage and trackImage:IsA("ImageLabel") and trackImage.Image ~= "" then
	track.BackgroundTransparency = 1
end
local runnerImage = runner:FindFirstChild("RunnerImage")
if runnerImage and runnerImage:IsA("ImageLabel") and runnerImage.Image ~= "" then
	runner.BackgroundTransparency = 1
end
if hint then hint.Text = tr("CLICK TO STRIKE") end

local remote = ReplicatedStorage.Shared:WaitForChild("BoulderGameEvent", 30)
if not remote then
	warn("[BoulderGameUI] BoulderGameEvent не появился — мини-игра валунов отключена на клиенте.")
	return
end

local session = nil -- { Boulder, Need, Progress, Speed, Zones, StartedAt, LastStrike }

local function runnerAt(elapsed, speed)
	local phase = (elapsed * speed) % 1
	return phase < 0.5 and phase * 2 or (1 - phase) * 2
end

-- Значение бегунка 0 = низ полосы, 1 = верх; в UI Y растёт вниз.
local function placeZone(zoneFrame, minValue, maxValue)
	zoneFrame.Position = UDim2.new(zoneFrame.Position.X.Scale, zoneFrame.Position.X.Offset, 1 - maxValue, 0)
	zoneFrame.Size = UDim2.new(zoneFrame.Size.X.Scale, zoneFrame.Size.X.Offset, maxValue - minValue, 0)
end

local function applyZones(zones)
	if not zones then return end
	placeZone(goodZone, zones.GoodMin, zones.GoodMax)
	placeZone(perfectZone, zones.PerfectMin, zones.PerfectMax)
end

local function applyProgress()
	if not session then return end
	local value = math.clamp(session.Progress or 0, 0, 1)
	if progressFill then
		TweenService:Create(progressFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(value, 1) }):Play()
	end
	if progressCount then
		progressCount.Text = ("%d/%d"):format(math.min(session.Need, math.floor(value * session.Need + 0.5)), session.Need)
	end
end

local GRADE_VIEW = {
	Perfect = { Text = "PERFECT!", Color = Color3.fromRGB(255, 215, 70) },
	Good = { Text = "GOOD", Color = Color3.fromRGB(120, 255, 150) },
	Miss = { Text = "MISS", Color = Color3.fromRGB(255, 110, 110) },
}

local function popVerdict(grade)
	if not verdict then return end
	local view = GRADE_VIEW[grade] or GRADE_VIEW.Miss
	verdict.Text = tr(view.Text)
	verdict.TextColor3 = view.Color
	local pop = verdict:FindFirstChild("Pop")
	if pop then
		pop.Scale = 1.5
		TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local resultToken = 0
local function showResult(text, color)
	if not resultLabel or not text then return end
	resultToken += 1
	local token = resultToken
	resultLabel.Text = tr(text)
	if typeof(color) == "Color3" then resultLabel.TextColor3 = color end
	resultLabel.Visible = true
	local pop = resultLabel:FindFirstChild("Pop")
	if pop then
		pop.Scale = 1.6
		TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(1.6, function()
		if resultToken == token then resultLabel.Visible = false end
	end)
end

local function close()
	session = nil
	panel.Visible = false
end

--------------------------------------------------------------------------------
-- v9: КРАСИВЫЙ ДРОП. Итог крупно, под ним плашки наград по одной, из валуна
-- фонтан монет к верху экрана. Вид — BoulderGameUiBuilder (DropCard,
-- RewardTemplate, CoinTemplate).
--------------------------------------------------------------------------------
local dropCard = gui:FindFirstChild("DropCard")
local dropTitle = dropCard and dropCard:FindFirstChild("Title")
local dropRow = dropCard and dropCard:FindFirstChild("Row")
local rewardTemplate = dropCard and dropCard:FindFirstChild("RewardTemplate")
local coinTemplate = gui:FindFirstChild("CoinTemplate")
local OUTLINE = Color3.fromRGB(12, 14, 22)

local dropToken = 0
local function coinFountain(worldPosition, count)
	local camera = workspace.CurrentCamera
	if not (camera and coinTemplate) then return end
	local origin
	if typeof(worldPosition) == "Vector3" then
		local screen, onScreen = camera:WorldToViewportPoint(worldPosition)
		if onScreen then origin = Vector2.new(screen.X, screen.Y) end
	end
	local viewport = camera.ViewportSize
	origin = origin or Vector2.new(viewport.X * 0.5, viewport.Y * 0.55)
	local target = Vector2.new(viewport.X * 0.5, 40)
	for i = 1, count do
		local coin = coinTemplate:Clone()
		coin.Name = "Coin"
		coin.Visible = true
		coin.Position = UDim2.fromOffset(origin.X, origin.Y)
		coin.Parent = gui
		local angle = math.rad(-90 + (math.random() - 0.5) * 140)
		local burst = origin + Vector2.new(math.cos(angle), math.sin(angle)) * (60 + math.random() * 90)
		task.delay((i - 1) * 0.03, function()
			local up = TweenService:Create(coin, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(burst.X, burst.Y), Rotation = math.random(-90, 90) })
			up:Play()
			up.Completed:Wait()
			task.wait(0.1 + math.random() * 0.15)
			local fly = TweenService:Create(coin, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X + (math.random() - 0.5) * 40, target.Y),
				Size = UDim2.fromOffset(18, 18),
				TextTransparency = 0.3,
			})
			fly:Play()
			fly.Completed:Wait()
			coin:Destroy()
		end)
	end
end

local function showDropCard(resultText, resultColor, rewards, worldPosition)
	if not (dropCard and dropRow and rewardTemplate) then
		showResult(resultText, resultColor)
		return
	end
	dropToken += 1
	local token = dropToken
	for _, child in dropRow:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	if dropTitle then
		dropTitle.Text = tr(resultText or "")
		if typeof(resultColor) == "Color3" then dropTitle.TextColor3 = resultColor end
	end
	local scale = dropCard:FindFirstChild("Pop")
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local fitScale = math.clamp(viewport.X / 1000, 0.65, 1.1)
	dropCard.Visible = true
	if scale then
		scale.Scale = 0.3
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fitScale }):Play()
	end

	local coins = 0
	for index, reward in rewards or {} do
		if reward.Kind == "Money" then coins += 10 end
		local chip = rewardTemplate:Clone()
		chip.Name = "Reward" .. index
		chip.LayoutOrder = index
		chip.Visible = true
		chip.Icon.Text = reward.Icon or "✨"
		chip.Label.Text = tostring(reward.Text or "")
		if typeof(reward.Color) == "Color3" then chip.Label.TextColor3 = reward.Color end
		local chipScale = chip:FindFirstChild("Pop")
		if chipScale then chipScale.Scale = 0 end
		chip.Parent = dropRow
		task.delay(0.15 + index * 0.12, function()
			if chipScale then
				TweenService:Create(chipScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			local glow = chip:FindFirstChild("Glow")
			if glow and typeof(reward.Color) == "Color3" then
				glow.Color = reward.Color
				TweenService:Create(glow, TweenInfo.new(0.6), { Color = OUTLINE }):Play()
			end
		end)
	end
	if coins > 0 then coinFountain(worldPosition, math.min(30, coins)) end

	task.delay(2.8, function()
		if dropToken ~= token then return end
		if scale then
			local out = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
			out:Play()
			out.Completed:Wait()
		end
		if dropToken == token then dropCard.Visible = false end
	end)
end

--------------------------------------------------------------------------------
-- v14: ТЯЖЁЛЫЙ УДАР. Клик → ЗАМАХ (FOV чуть сужается, на полосе остаётся
-- «призрак» — где ты попал) → через ImpactDelay КОНТАКТ: хитстоп (поза
-- персонажа замирает на долю секунды), FOV-панч, тряска камеры, трещины на
-- валуне разгораются. Сила всего этого — по оценке (Config.BoulderGame:
-- HitStop/FovKick/CameraShake). Финальный удар — слоу-мо: камера наезжает
-- и держит кадр FinalPause, потом валун разлетается.
--------------------------------------------------------------------------------
local RunService_ = RunService
local shakeAmp, shakeUntil = 0, 0
local camShake, camShakeUntil, camShakeTotal = 0, 0, 0.3
local fovTween = nil

local function camera_()
	return workspace.CurrentCamera
end

local function baseFov()
	return session and session.BaseFov or (camera_() and camera_().FieldOfView) or 70
end

local function tweenFov(value, seconds, style)
	local camera = camera_()
	if not camera then return end
	if fovTween then fovTween:Cancel() end
	fovTween = TweenService:Create(camera, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = value })
	fovTween:Play()
end

-- Тряска камеры поверх камеры Roblox: смещение применяется ПОСЛЕ модуля
-- камеры каждый кадр и затухает.
RunService_:BindToRenderStep("BoulderHeavyShake", Enum.RenderPriority.Camera.Value + 1, function()
	local now = os.clock()
	if now >= camShakeUntil or camShake <= 0 then return end
	local camera = camera_()
	if not camera then return end
	local falloff = (camShakeUntil - now) / camShakeTotal
	local amp = camShake * falloff
	camera.CFrame = camera.CFrame * CFrame.new((math.random() * 2 - 1) * amp, (math.random() * 2 - 1) * amp, 0)
		* CFrame.Angles(0, 0, math.rad((math.random() * 2 - 1) * amp * 2))
end)

local function shakeCamera(amount, seconds)
	camShake = math.max(camShake * (camShakeUntil > os.clock() and 1 or 0), amount)
	camShakeTotal = seconds
	camShakeUntil = os.clock() + seconds
end

-- ЗАМЕДЛЕНИЕ АНИМАЦИИ (v14.1). Пока идёт удар, ВСЕ анимации персонажа
-- играют в slow-mo: замах — медленно (AnimSlow.Windup), в момент контакта —
-- стоп-кадр (HitStop), после — плавный разгон (AnimSlow.Recover), финальный
-- удар — почти замирание на всю паузу (AnimSlow.Final). Скорость держится
-- покадрово, поэтому замедляется и взмах, который запустил сервер чуть позже.
local animScale, animScaleUntil = 1, 0
local scaledTracks = {} -- [track] = исходная скорость
local function setAnimScale(scale, duration)
	animScale = scale
	animScaleUntil = os.clock() + math.max(0, duration)
end
RunService_.RenderStepped:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	if os.clock() < animScaleUntil then
		for _, track in animator:GetPlayingAnimationTracks() do
			if scaledTracks[track] == nil then
				scaledTracks[track] = track.Speed ~= 0 and track.Speed or 1
			end
			track:AdjustSpeed(scaledTracks[track] * animScale)
		end
	elseif next(scaledTracks) then
		for track, speed in scaledTracks do
			if track.IsPlaying then track:AdjustSpeed(speed) end
		end
		table.clear(scaledTracks)
	end
end)

local function hitStop(seconds)
	local slow = cfg.AnimSlow or {}
	setAnimScale(0, seconds)
	task.delay(seconds, function()
		setAnimScale(slow.Recover or 0.55, slow.RecoverSeconds or 0.2)
	end)
end

-- Необязательная анимация тяжёлого замаха (Config.BoulderGame.StrikeAnimationId).
local strikeAnimation = nil
local function playStrikeAnimation()
	local id = tonumber(cfg.StrikeAnimationId) or 0
	if id == 0 then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	if not strikeAnimation then
		strikeAnimation = Instance.new("Animation")
		strikeAnimation.AnimationId = "rbxassetid://" .. tostring(id)
	end
	local ok, track = pcall(animator.LoadAnimation, animator, strikeAnimation)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.05)
	end
end

-- «Призрак» — метка на полосе, где ты попал (бегунок убегает дальше).
local function dropGhost(value)
	local ghost = runner:Clone()
	ghost.Name = "Ghost"
	for _, child in ghost:GetChildren() do
		if child:IsA("UIScale") then child:Destroy() end
	end
	ghost.Position = UDim2.new(runner.Position.X.Scale, runner.Position.X.Offset, 1 - value, 0)
	ghost.ZIndex = runner.ZIndex - 1
	ghost.Parent = track
	local function fade(instance)
		local props = {}
		if instance:IsA("GuiObject") then props.BackgroundTransparency = 1 end
		if instance:IsA("ImageLabel") then props.ImageTransparency = 1 end
		if instance:IsA("TextLabel") then props.TextTransparency = 1 end
		if next(props) then TweenService:Create(instance, TweenInfo.new(0.6), props):Play() end
	end
	fade(ghost)
	for _, d in ghost:GetDescendants() do fade(d) end
	task.delay(0.65, function() ghost:Destroy() end)
end

-- Подсветка трещин изнутри по CrackProgress валуна.
local crackHighlight = nil
local function applyCrackGlow(boulder)
	if not boulder then return end
	local value = tonumber(boulder:GetAttribute("CrackProgress")) or 0
	local stage = 0
	for index, threshold in cfg.CrackStages or {} do
		if value >= threshold then stage = index end
	end
	if stage == 0 then
		if crackHighlight then crackHighlight:Destroy() crackHighlight = nil end
		return
	end
	if not crackHighlight or crackHighlight.Parent ~= boulder then
		if crackHighlight then crackHighlight:Destroy() end
		crackHighlight = Instance.new("Highlight")
		crackHighlight.Name = "CrackGlow"
		crackHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
		crackHighlight.FillColor = Color3.fromRGB(255, 140, 50)
		crackHighlight.OutlineColor = Color3.fromRGB(255, 210, 120)
		crackHighlight.FillTransparency = 1
		crackHighlight.OutlineTransparency = 1
		crackHighlight.Parent = boulder
	end
	local stages = math.max(1, #(cfg.CrackStages or { 1 }))
	TweenService:Create(crackHighlight, TweenInfo.new(0.12), {
		FillTransparency = 0.92 - 0.22 * (stage / stages),
		OutlineTransparency = 0.6 - 0.4 * (stage / stages),
	}):Play()
end

local function impact(grade, final, streak)
	local stop = (cfg.HitStop and cfg.HitStop[grade]) or 0.05
	local kick = (cfg.FovKick and cfg.FovKick[grade]) or 4
	local shake = (cfg.CameraShake and cfg.CameraShake[grade]) or 0.3
	if streak and streak >= 2 then
		kick += math.min(6, streak)
		shake *= 1 + math.min(0.6, streak * 0.12)
	end
	hitStop(stop)
	shakeAmp = math.max(shakeAmp, grade == "Perfect" and 12 or grade == "Good" and 7 or 2)
	shakeUntil = os.clock() + 0.3
	shakeCamera(shake, final and 0.55 or 0.3)
	local base = baseFov()
	if final then
		-- СЛОУ-МО: резкий наезд и удержание кадра, анимация почти замирает.
		tweenFov(base + (cfg.FinalFovDelta or -12), 0.12, Enum.EasingStyle.Quint)
		task.delay(stop, function()
			setAnimScale((cfg.AnimSlow and cfg.AnimSlow.Final) or 0.15, cfg.FinalPause or 0.5)
		end)
	else
		tweenFov(base + kick, 0.05)
		task.delay(0.05 + stop, function()
			if session then tweenFov(base, 0.3) end
		end)
	end
	local pop = runner:FindFirstChildOfClass("UIScale")
	if pop then
		pop.Scale = grade == "Perfect" and 2.1 or grade == "Good" and 1.6 or 1.2
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	if session and session.Boulder then applyCrackGlow(session.Boulder) end
end

local function strike()
	if not session or session.Final then return end
	local now = os.clock()
	if now - (session.LastStrike or 0) < cfg.StrikeCooldown then return end
	session.LastStrike = now
	local value = runnerAt(now - session.StartedAt, session.Speed)
	session.ImpactAt = now + (cfg.ImpactDelay or 0.3)
	remote:FireServer("Strike", value)
	dropGhost(value)
	playStrikeAnimation()
	-- Замах в замедлении — до самого контакта.
	setAnimScale((cfg.AnimSlow and cfg.AnimSlow.Windup) or 0.45, cfg.ImpactDelay or 0.3)
	-- ЗАМАХ: камера чуть «вдыхает».
	tweenFov(baseFov() + (cfg.WindupFovDelta or -4), (cfg.ImpactDelay or 0.3) * 0.9, Enum.EasingStyle.Sine)
	local pop = runner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	pop.Parent = runner
	pop.Scale = 0.8
	TweenService:Create(pop, TweenInfo.new(cfg.ImpactDelay or 0.3), { Scale = 1 }):Play()
	if hint then hint.Visible = false end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not session then return end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		if processed and kind ~= Enum.UserInputType.MouseButton1 then return end
		strike()
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.Space then
		if not processed or input.KeyCode == Enum.KeyCode.ButtonR2 then strike() end
	end
end)

RunService.RenderStepped:Connect(function()
	if not session then return end
	local boulder = session.Boulder
	if not boulder or not boulder.Parent then
		close()
		return
	end
	local value = runnerAt(os.clock() - session.StartedAt, session.Speed)
	runner.Position = UDim2.new(runner.Position.X.Scale, runner.Position.X.Offset, 1 - value, 0)

	local camera = workspace.CurrentCamera
	if not camera then return end
	local center, size
	if boulder:IsA("Model") then
		local cf, s = boulder:GetBoundingBox()
		center, size = cf.Position, s
	else
		center, size = boulder.Position, boulder.Size
	end
	local side = center + camera.CFrame.RightVector * (math.max(size.X, size.Z) * 0.6 + 1)
	local screen, onScreen = camera:WorldToViewportPoint(side)
	local viewport = camera.ViewportSize
	if autoScale then
		autoScale.Scale = math.clamp(viewport.Y / 900, 0.6, 1.1)
	end
	local width = panel.AbsoluteSize.X
	local x = onScreen and math.clamp(screen.X + 12, 8, viewport.X - width - 8) or viewport.X - width - 24
	local y = onScreen and math.clamp(screen.Y, viewport.Y * 0.25, viewport.Y * 0.75) or viewport.Y * 0.5
	if os.clock() < shakeUntil then
		local falloff = math.max(0, (shakeUntil - os.clock()) / 0.3)
		x += (math.random() * 2 - 1) * shakeAmp * falloff
		y += (math.random() * 2 - 1) * shakeAmp * falloff
		panel.Rotation = (math.random() * 2 - 1) * shakeAmp * 0.25 * falloff
	elseif panel.Rotation ~= 0 then
		panel.Rotation = 0
		shakeAmp = 0
	end
	panel.Position = UDim2.fromOffset(x, y)
end)

local lootEvent = ReplicatedStorage.Shared:FindFirstChild("LootFeedLocal")
local function feedLoot(rewards)
	lootEvent = lootEvent or ReplicatedStorage.Shared:FindFirstChild("LootFeedLocal")
	if lootEvent and type(rewards) == "table" and #rewards > 0 then
		lootEvent:Fire(rewards)
	end
end

remote.OnClientEvent:Connect(function(action, data)
	data = type(data) == "table" and data or {}
	if action == "Open" then
		local camera = workspace.CurrentCamera
		local keepFov = session and session.BaseFov
		session = {
			Boulder = data.Boulder,
			Need = tonumber(data.Need) or 5,
			Progress = tonumber(data.Progress) or 0,
			Speed = tonumber(data.Speed) or cfg.RunnerCyclesPerSecond,
			StartedAt = os.clock(),
			LastStrike = 0,
			BaseFov = keepFov or (camera and camera.FieldOfView) or 70,
		}
		if title then
			title.Text = data.Golden and "⭐ GOLDEN" or tr("TIER {tier}", { tier = tostring(data.Tier or 1) })
		end
		if verdict then verdict.Text = "" end
		if hint then hint.Visible = true end
		applyZones(data.Zones)
		applyProgress()
		applyCrackGlow(session.Boulder)
		panel.Visible = true
	elseif action == "Update" and session then
		session.Progress = tonumber(data.Progress) or session.Progress
		applyZones(data.Zones)
		local grade = data.Grade
		local streak = tonumber(data.Streak) or 0
		local final = data.Final == true
		if final then session.Final = true end
		local waitFor = math.max(0, (session.ImpactAt or os.clock()) - os.clock())
		task.delay(waitFor, function()
			if not session then return end
			applyProgress()
			popVerdict(grade)
			if verdict and grade == "Perfect" and streak >= 2 then
				verdict.Text = tr("PERFECT!") .. (" x%d"):format(streak)
			end
			impact(grade, final, streak)
		end)
	elseif action == "Close" then
		local fov = session and session.BaseFov
		close()
		if crackHighlight then crackHighlight:Destroy() crackHighlight = nil end
		if fov then tweenFov(fov, 0.45, Enum.EasingStyle.Back) end
		if data.Result then
			showResult(data.Result, data.Color)
			if type(data.Rewards) == "table" then
				feedLoot(data.Rewards)
				local coins = 0
				for _, reward in data.Rewards do
					if reward.Kind == "Money" then coins += 10 end
				end
				if coins > 0 then coinFountain(data.Position, math.min(30, coins)) end
				if #data.Rewards > 0 then shakeCamera(0.5, 0.35) end
			end
		end
	end
end)
