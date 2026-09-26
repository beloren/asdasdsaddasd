--------------------------------------------------------------------------------
-- StaggerFX (LocalScript) — клиентская часть PvP v2 (см. Config.Stagger,
-- CombatService). Сервер решает ВСЁ (шкала, рагдолл, выпадение, награда);
-- здесь только картинка:
--   • шкала оглушения + значок WANTED над головой КАЖДОГО игрока — из
--     шаблона StarterGui/CombatUi/StaggerTemplate (tools/BuildAllUI.lua),
--     данные — атрибуты игрока Stagger / Ragdolled / StaggerImmune / Bounty;
--   • свой рагдолл: Humanoid → Physics + импульс отлёта (физикой своего
--     персонажа владеет именно этот клиент), подъём — GettingUp;
--   • парирование: импульс отскока;
--   • комбо-счётчик и надписи KNOCKDOWN!/CLASH! у атакующего.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Localization = require(ReplicatedStorage.Shared.Localization)
local Sfx = require(ReplicatedStorage.Shared.Sfx) -- v16: звук приземления после взрыва

local cfg = Config.Stagger
if not (cfg and cfg.Enabled) then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

--------------------------------------------------------------------------------
-- ШАБЛОН ИНТЕРФЕЙСА: копия StarterGui/CombatUi из билдера; если её нет или
-- она старее Config.Stagger.UiVersion — собираем тем же модулем сами.
--------------------------------------------------------------------------------
local combatGui = require(ReplicatedStorage.Shared.UiRegistry).Get("CombatUi") -- v20: StarterGui/CombatUi или сборка билдером
local wantedVersion = cfg.UiVersion or 1
if not combatGui or (tonumber(combatGui:GetAttribute("BuilderVersion")) or 0) < wantedVersion then
	if combatGui then combatGui:Destroy() end
	local builderModule = ReplicatedStorage.Shared:FindFirstChild("CombatUiBuilder")
	if not builderModule then
		warn("[StaggerFX] Нет ни StarterGui/CombatUi, ни Shared.CombatUiBuilder - интерфейс PvP не показывается.")
		return
	end
	combatGui = require(builderModule).Build()
	combatGui.Parent = playerGui
end
combatGui.ResetOnSpawn = false

local template = combatGui:WaitForChild("StaggerTemplate")
local comboFrame = combatGui:WaitForChild("ComboCounter")
local popupFrame = combatGui:WaitForChild("Popup")

--------------------------------------------------------------------------------
-- ШКАЛА НАД ГОЛОВОЙ
--------------------------------------------------------------------------------
local PIP_NORMAL = Color3.fromRGB(255, 170, 60)
local PIP_DANGER = Color3.fromRGB(255, 70, 60)
local billboards = {} -- [Player] = { Gui, Pips = { Fill... }, State, Wanted, WantedText }

local function buildBillboard(plr, head)
	local gui = template:Clone()
	gui.Name = "Stagger_" .. plr.UserId
	gui.Adornee = head
	gui.Enabled = false
	local bar = gui:FindFirstChild("Bar")
	local pipTemplate = bar and bar:FindFirstChild("PipTemplate")
	local pips = {}
	if pipTemplate then
		local count = math.max(1, cfg.Pips or 4)
		for index = 1, count do
			local pip = pipTemplate:Clone()
			pip.Name = "Pip" .. index
			pip.LayoutOrder = index
			pip.Size = UDim2.new(1 / count, -3, 1, 0)
			pip.Visible = true
			pip.Parent = bar
			pips[index] = pip:FindFirstChild("Fill")
		end
	end
	local wanted = gui:FindFirstChild("Wanted")
	local wantedIcon = wanted and wanted:FindFirstChild("Icon")
	if wantedIcon and wantedIcon:IsA("ImageLabel") and wantedIcon.Image ~= "" then
		wantedIcon.Visible = true
	end
	gui.Parent = playerGui
	return {
		Gui = gui,
		Bar = bar,
		Pips = pips,
		State = gui:FindFirstChild("State"),
		Wanted = wanted,
		WantedText = wanted and wanted:FindFirstChild("Text"),
		HasIcon = wantedIcon and wantedIcon.Visible,
	}
end

local function refreshBillboard(plr)
	local entry = billboards[plr]
	if not entry or not entry.Gui.Parent then return end
	local stagger = tonumber(plr:GetAttribute("Stagger")) or 0
	local ragdolled = plr:GetAttribute("Ragdolled") == true
	local immune = plr:GetAttribute("StaggerImmune") == true
	local bounty = tonumber(plr:GetAttribute("Bounty")) or 0

	local count = #entry.Pips
	for index, fill in entry.Pips do
		if fill then
			local amount = math.clamp(stagger * count - (index - 1), 0, 1)
			fill.Size = UDim2.fromScale(amount, 1)
			fill.BackgroundColor3 = stagger >= (count - 1) / count and PIP_DANGER or PIP_NORMAL
		end
	end
	if entry.Bar then
		entry.Bar.Visible = stagger > 0 or ragdolled
	end
	if entry.State then
		entry.State.Visible = ragdolled
	end
	if entry.Wanted then
		entry.Wanted.Visible = bounty > 0 and not ragdolled
		if entry.WantedText then
			entry.WantedText.Text = (entry.HasIcon and "" or "💰 ") .. "$" .. NumberFormat.abbreviate(bounty)
		end
	end
	entry.Gui.Enabled = stagger > 0 or ragdolled or bounty > 0
	-- Неуязвимость после подъёма — шкала полупрозрачная.
	for _, fill in entry.Pips do
		if fill then fill.BackgroundTransparency = immune and not ragdolled and 0.6 or 0 end
	end
end

local function attachTo(plr, character)
	local old = billboards[plr]
	if old and old.Gui then old.Gui:Destroy() end
	billboards[plr] = nil
	local head = character:WaitForChild("Head", 5)
	if not head or not character.Parent then return end
	billboards[plr] = buildBillboard(plr, head)
	refreshBillboard(plr)
end

local function watchPlayer(plr)
	for _, attribute in { "Stagger", "Ragdolled", "StaggerImmune", "Bounty" } do
		plr:GetAttributeChangedSignal(attribute):Connect(function() refreshBillboard(plr) end)
	end
	plr.CharacterAdded:Connect(function(character) attachTo(plr, character) end)
	if plr.Character then task.spawn(attachTo, plr, plr.Character) end
end

for _, plr in Players:GetPlayers() do watchPlayer(plr) end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(plr)
	local entry = billboards[plr]
	if entry and entry.Gui then entry.Gui:Destroy() end
	billboards[plr] = nil
end)

--------------------------------------------------------------------------------
-- ЭФФЕКТЫ ЭКРАНА
--------------------------------------------------------------------------------
local shakeToken = 0
local function cameraShake(strength, seconds)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	shakeToken += 1
	local token = shakeToken
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if token ~= shakeToken or elapsed >= seconds or not humanoid.Parent then
			connection:Disconnect()
			if humanoid.Parent and token == shakeToken then humanoid.CameraOffset = Vector3.zero end
			return
		end
		local fade = 1 - elapsed / seconds
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2 * strength * fade,
			(math.random() - 0.5) * 2 * strength * fade,
			0
		)
	end)
end

local function fovPunch(amount)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local base = camera.FieldOfView
	camera.FieldOfView = base - amount
	TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
end

local popupToken = 0
local function showPopup(title, subtitle, color, seconds)
	popupToken += 1
	local token = popupToken
	local titleLabel = popupFrame:FindFirstChild("Title")
	local subtitleLabel = popupFrame:FindFirstChild("Subtitle")
	if titleLabel then
		titleLabel.Text = title
		if color then titleLabel.TextColor3 = color end
	end
	if subtitleLabel then subtitleLabel.Text = subtitle or "" end
	popupFrame.Visible = true
	local pop = popupFrame:FindFirstChild("Pop")
	if pop then
		pop.Scale = 1.5
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(seconds or 1.6, function()
		if popupToken == token then popupFrame.Visible = false end
	end)
end

local comboToken = 0
local function showCombo(count)
	comboToken += 1
	local token = comboToken
	local countLabel = comboFrame:FindFirstChild("Count")
	local caption = comboFrame:FindFirstChild("Caption")
	if countLabel then countLabel.Text = "x" .. tostring(count) end
	if caption then caption.Text = tr("HITS") end
	comboFrame.Visible = count >= 2
	local pop = comboFrame:FindFirstChild("Pop")
	if pop then
		pop.Scale = 1.35
		TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(cfg.ComboWindow or 3, function()
		if comboToken == token then comboFrame.Visible = false end
	end)
end

--------------------------------------------------------------------------------
-- СВОЙ РАГДОЛЛ / ИМПУЛЬСЫ
--------------------------------------------------------------------------------
local function ownParts()
	local character = player.Character
	return character, character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

local ragdollToken = 0
local function endOwnRagdoll(token)
	if token and token ~= ragdollToken then return end
	local _, humanoid = ownParts()
	if humanoid and humanoid.Health > 0 then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- v16 (K2): пыль и звук, когда подброшенный взрывом игрок падает на землю.
local function watchLanding(root, token)
	local started = os.clock()
	local airborne = false
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if token ~= ragdollToken or not root.Parent or os.clock() - started > 6 then
			connection:Disconnect()
			return
		end
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -4, 0), params)
		if not hit then
			airborne = true
			return
		end
		if airborne and root.AssemblyLinearVelocity.Y <= 1 then
			connection:Disconnect()
			local dust = Instance.new("Part")
			dust.Anchored = true
			dust.CanCollide = false
			dust.CanQuery = false
			dust.Transparency = 1
			dust.Size = Vector3.one * 0.2
			dust.CFrame = CFrame.new(hit.Position)
			dust.Parent = workspace
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(Color3.fromRGB(170, 150, 120))
			emitter.Size = NumberSequence.new(1.2, 3)
			emitter.Transparency = NumberSequence.new(0.3, 1)
			emitter.Lifetime = NumberRange.new(0.5, 0.9)
			emitter.Speed = NumberRange.new(6, 12)
			emitter.SpreadAngle = Vector2.new(180, 10)
			emitter.Rate = 0
			emitter.Parent = dust
			emitter:Emit(18)
			game:GetService("Debris"):AddItem(dust, 1.5)
			Sfx.play("RagdollLand", dust)
			cameraShake(0.35, 0.2)
		end
	end)
end

local function startOwnRagdoll(impulse, seconds, blast)
	local _, humanoid, root = ownParts()
	if not (humanoid and root) then return end
	ragdollToken += 1
	local token = ragdollToken
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local function launch()
		if token ~= ragdollToken or not root.Parent then return end
		if typeof(impulse) == "Vector3" then
			root.AssemblyLinearVelocity = impulse
			local spin = blast and (tonumber(blast.Spin) or 10) or 6
			root.AssemblyAngularVelocity = Vector3.new(
				(math.random() * 2 - 1) * spin, (math.random() * 2 - 1) * spin * 0.4, (math.random() * 2 - 1) * spin)
		end
		if blast then watchLanding(root, token) end
	end
	if blast and (tonumber(blast.HitStop) or 0) > 0 then
		-- «Замирание» (hitstop): персонаж на миг застывает, потом улетает.
		root.Anchored = true
		fovPunch(8)
		task.delay(blast.HitStop, function()
			if root.Parent then root.Anchored = false end
			launch()
		end)
	else
		launch()
	end
	-- Страховка: даже если атрибут Ragdolled не придёт, встаём сами.
	task.delay((seconds or cfg.RagdollSeconds) + 1.5, function() endOwnRagdoll(token) end)
end

-- v20.44: ГОБЛИНЫ ВЫПНУЛИ ДОМОЙ. Полёт по дуге (квадратичная Безье) к своей
-- базе с кувырками; рагдолл включён сервером, конечности болтаются сами.
local function startOwnKick(payload)
	local _, humanoid, root = ownParts()
	if not (humanoid and root) then return end
	if typeof(payload.From) ~= "Vector3" or typeof(payload.To) ~= "Vector3" then return end
	ragdollToken += 1
	local token = ragdollToken
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local from, to = payload.From, payload.To
	local mid = (from + to) / 2 + Vector3.new(0, tonumber(payload.Arc) or 90, 0)
	local duration = math.max(0.5, tonumber(payload.Seconds) or 2.4)
	local spin = tonumber(payload.Spin) or 9
	local started = os.clock()
	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		if token ~= ragdollToken or not root.Parent then connection:Disconnect() return end
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		local a, b = from:Lerp(mid, t), mid:Lerp(to, t)
		local position = a:Lerp(b, t)
		local velocity = (b - a) * (2 / duration)
		local elapsed = os.clock() - started
		root.CFrame = CFrame.new(position) * CFrame.Angles(elapsed * spin, elapsed * spin * 0.3, elapsed * spin * 0.6)
		root.AssemblyLinearVelocity = velocity
		if t >= 1 then
			connection:Disconnect()
			root.AssemblyLinearVelocity = Vector3.new(0, -30, 0)
			root.AssemblyAngularVelocity = Vector3.zero
			watchLanding(root, token)
			cameraShake(0.7, 0.4)
		end
	end)
	showPopup(tr("KICKED OUT!"), tr("The goblins sent you home"), Color3.fromRGB(255, 150, 70), 2.2)
	cameraShake(0.5, 0.3)
	fovPunch(10)
	task.delay(duration + 4, function() endOwnRagdoll(token) end)
end

player:GetAttributeChangedSignal("Ragdolled"):Connect(function()
	if player:GetAttribute("Ragdolled") ~= true then
		endOwnRagdoll(nil)
	end
end)

local feedbackRemote = ReplicatedStorage.Shared:WaitForChild("CombatFeedbackEvent", 30)
if not feedbackRemote then
	warn("[StaggerFX] CombatFeedbackEvent не появился - эффекты PvP отключены.")
	return
end

feedbackRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local kind = payload.Kind
	if kind == "Hit" then
		showCombo(tonumber(payload.Combo) or 1)
		fovPunch(1.5)
	elseif kind == "Knockdown" then
		showCombo(tonumber(payload.Combo) or 1)
		local parts = {}
		if payload.Ore then
			table.insert(parts, ("+%s $%s"):format(tostring(payload.Ore), NumberFormat.abbreviate(tonumber(payload.OreValue) or 0)))
		end
		if (tonumber(payload.Bounty) or 0) > 0 then
			table.insert(parts, "💰 +$" .. NumberFormat.abbreviate(payload.Bounty))
		end
		showPopup(tr("KNOCKDOWN!"), table.concat(parts, "   "), Color3.fromRGB(255, 120, 70), 1.8)
		cameraShake(0.35, 0.25)
		fovPunch(5)
	elseif kind == "Knocked" then
		startOwnRagdoll(payload.Impulse, payload.Seconds, payload.Blast and payload or nil)
		local subtitle = tr("by {name}", { name = tostring(payload.By or "?") })
		if payload.Ore then
			subtitle ..= "   -" .. tostring(payload.Ore)
		end
		showPopup(tr("KNOCKED DOWN!"), subtitle, Color3.fromRGB(255, 80, 80), 2)
		cameraShake(0.6, 0.45)
	elseif kind == "Kicked" then
		startOwnKick(payload)
	elseif kind == "Hop" then
		-- v20.43: взрыв рядом (щит/безопасная зона) — лёгкий подброс без рагдолла.
		local _, humanoid, root = ownParts()
		if root and typeof(payload.Impulse) == "Vector3" then
			if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
			root.AssemblyLinearVelocity += payload.Impulse
		end
		cameraShake(0.3, 0.2)
	elseif kind == "Clash" then
		local _, _, root = ownParts()
		if root and typeof(payload.Impulse) == "Vector3" then
			root.AssemblyLinearVelocity += payload.Impulse
		end
		showPopup(tr("CLASH!"), tostring(payload.Other or ""), Color3.fromRGB(255, 240, 150), 1.1)
		cameraShake(0.3, 0.2)
		fovPunch(4)
	end
end)
