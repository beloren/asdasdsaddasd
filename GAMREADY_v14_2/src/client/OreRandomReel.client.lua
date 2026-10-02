--------------------------------------------------------------------------------
-- OreRandomReel (v20.131) — ЛЕНТА РАНДОМ-БОКСА РУДЫ.
-- Сервер (OreUnlockService) после тряски коробки шлёт "RandomReel":
--   { Group, Ores = {ключи}, Result, Variant, Seconds, Hold }.
-- Колонка карточек с 3D-превью руды (чёрная обводка, все 4 вариации каждой
-- руды коробки) едет сверху вниз как барабан - замедляется, чуть
-- проскакивает, дразнит соседней карточкой и встаёт на выпавшую руду.
-- Потом сервер сам показывает карточку «новая руда в шахте».
-- Вид - StarterGui/OreRandomReelUi (UiBuilders.OreRandomReelUi).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local remote = ReplicatedStorage.Shared:WaitForChild("OreUnlockFx", 30)
if not remote then return end
local OrePreview = require(ReplicatedStorage.Shared.OrePreview)
local UiKit = require(ReplicatedStorage.Shared.UiKit)

local player = Players.LocalPlayer
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("OreRandomReelUi")
if not gui then return end
gui.Enabled = false

local reel = gui:WaitForChild("Reel")
local strip = reel:WaitForChild("Strip")
local rays = reel:FindFirstChild("Rays")
local reelScale = reel:FindFirstChild("Scale") or UiKit.Scale(reel, "Scale", 1)
local title = gui:FindFirstChild("Title")
local resultLabel = gui:FindFirstChild("Result")
local dim = gui:FindFirstChild("Dim")
local template = gui:WaitForChild("Templates"):WaitForChild("Card")

local function sfx(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end

local BASE_H = reel.Size.Y.Offset > 0 and reel.Size.Y.Offset or 430
local function layout()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	reelScale.Scale = math.clamp((view.Y - 150) / BASE_H, 0.45, 1.1)
	local k = reelScale.Scale
	if title then title.Position = UDim2.new(0.5, 0, 0.5, -BASE_H * k / 2 - 6) end
	if resultLabel then resultLabel.Position = UDim2.new(0.5, 0, 0.5, BASE_H * k / 2 + 6) end
end

local function rarityColor(rarity)
	return (Config.RarityColors and Config.RarityColors[rarity]) or Color3.fromRGB(200, 200, 200)
end

local function makeCard(oreKey, variant)
	local ore = Config.OreByKey[oreKey]
	local card = template:Clone()
	card.Visible = true
	local rarity = Config.OreBaseRarity(oreKey)
	local color = rarityColor(rarity)
	local stroke = card:FindFirstChild("SkinStroke") or card:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = color end
	if card.Image == "" then card.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.6) end
	local name = card:FindFirstChild("OreName")
	if name then
		name.Text = (ore and ore.DisplayName or oreKey):upper()
		name.TextColor3 = color
	end
	local variantLabel = card:FindFirstChild("Variant")
	local info = Config.OreVariants and Config.OreVariants[variant]
	if variantLabel then variantLabel.Text = info and info.DisplayName or tostring(variant) end
	local holder = card:FindFirstChild("Model") or card
	pcall(OrePreview.Mount, holder, { Ore = oreKey, Variant = variant })
	card.Parent = strip
	return card
end

local playing = 0

local function play(payload)
	local group = payload.Ores
	if type(group) ~= "table" or #group == 0 then return end
	local result = payload.Result
	if not Config.OreByKey[result] then return end
	playing += 1
	local token = playing
	local cfg = Config.OreRandomBox or {}
	local seconds = tonumber(payload.Seconds) or cfg.ReelSeconds or 3.6
	local hold = tonumber(payload.Hold) or cfg.HoldSeconds or 1.6
	local count = math.max(10, cfg.ReelCards or 22)
	local targetIndex = count - 3
	local rng = Random.new()

	for _, child in strip:GetChildren() do child:Destroy() end
	layout()
	gui.Enabled = true
	if rays then rays.Visible = false end
	if resultLabel then resultLabel.TextTransparency = 1 end
	if dim then
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
	end

	-- карточки: все руды коробки во всех 4 вариациях по кругу (перемешаны),
	-- выпавшая - на targetIndex, сразу за ней - «дразнилка» (другая руда)
	local pool = {}
	for _, key in group do
		if Config.OreByKey[key] then
			for v = 1, #(Config.OreVariants or { 1, 2, 3, 4 }) do table.insert(pool, { key, v }) end
		end
	end
	local function shuffled()
		local copy = table.clone(pool)
		for i = #copy, 2, -1 do
			local j = rng:NextInteger(1, i)
			copy[i], copy[j] = copy[j], copy[i]
		end
		return copy
	end
	local order = {}
	while #order < count do
		for _, entry in shuffled() do table.insert(order, entry) end
	end
	order[targetIndex] = { result, tonumber(payload.Variant) or 2 }
	local resultRank = table.find(Config.RarityOrder, Config.OreBaseRarity(result)) or 1
	for _, key in group do
		local rank = table.find(Config.RarityOrder, Config.OreBaseRarity(key)) or 1
		if key ~= result and rank >= resultRank then
			order[targetIndex + 1] = { key, rng:NextInteger(3, 4) }
			break
		end
	end

	local cards = {}
	for i = 1, count do
		local entry = order[i]
		local card = makeCard(entry[1], entry[2])
		cards[i] = card
	end
	local cardH = template.Size.Y.Offset > 0 and template.Size.Y.Offset or 150
	local spacing = cardH * 1.12
	local startY = (targetIndex - 1) * spacing + BASE_H * 0.4
	local winner = cards[targetIndex]
	local winnerColor = rarityColor(Config.OreBaseRarity(result))

	local started = os.clock()
	local lastTick
	local landed = false
	local function easeOutBack(a)
		local c1 = 1.25
		local c3 = c1 + 1
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end

	local conn
	conn = RunService.RenderStepped:Connect(function()
		if token ~= playing then conn:Disconnect() return end
		local t = os.clock() - started
		local offset -- сколько ещё ехать до цели (px), >0 - цель выше центра
		if t < seconds then
			local a = t / seconds
			offset = startY * (1 - a) ^ 5 - spacing * 0.3 * math.sin(math.clamp((a - 0.75) / 0.25, 0, 1) * math.pi / 2)
		else
			local a = math.clamp((t - seconds) / 0.45, 0, 1)
			offset = -spacing * 0.3 * (1 - easeOutBack(a))
		end
		local tickIndex = math.floor(offset / spacing + 0.5)
		if tickIndex ~= lastTick then
			lastTick = tickIndex
			if t < seconds then sfx("ReelTick") end
		end
		for i, card in cards do
			local y = (i - targetIndex) * spacing + offset
			card.Position = UDim2.new(0.5, 0, 0.5, y)
			-- барабан: к краям окна карточка меньше и бледнее
			local k = math.clamp(math.abs(y) / (BASE_H * 0.55), 0, 1.3)
			local drum = card:FindFirstChild("Drum")
			local pop = 1
			if landed and card == winner then
				local since = t - seconds - 0.45
				pop = 1 + 0.12 * math.sin(math.clamp(since / 0.3, 0, 1) * math.pi) + 0.06
			end
			if drum then drum.Scale = (1 - 0.32 * k * k) * pop end
			card.Visible = math.abs(y) < BASE_H * 0.62
			local alpha = math.clamp(k * k * 0.9, 0, 1)
			if landed and card ~= winner then alpha = math.max(alpha, math.clamp((t - seconds - 0.45) / 0.3, 0, 1)) end
			card.ImageTransparency = alpha
			card.BackgroundTransparency = card.Image == "" and math.max(0.15, alpha) or 1
			for _, d in card:GetDescendants() do
				if d:IsA("TextLabel") then d.TextTransparency = alpha
				elseif d:IsA("ViewportFrame") then d.ImageTransparency = alpha
				elseif d:IsA("UIStroke") then d.Transparency = alpha end
			end
		end
		if not landed and t >= seconds + 0.45 then
			landed = true
			local rank = table.find(Config.RarityOrder, Config.OreBaseRarity(result)) or 1
			sfx(rank >= 5 and "OreRevealEpic" or rank >= 3 and "OreRevealRare" or "ReelWin")
			if rays then
				UiKit.PaintBackdrop(rays, Config.OreBaseRarity(result), winnerColor:Lerp(Color3.new(1, 1, 1), 0.25), 0.15)
				rays.Visible = true
			end
			if resultLabel then
				local ore = Config.OreByKey[result]
				resultLabel.Text = (ore.DisplayName or result):upper() .. "!"
				resultLabel.TextColor3 = winnerColor
				TweenService:Create(resultLabel, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
			end
		end
		if rays and rays.Visible then rays.Rotation = (t * 25) % 360 end
		if landed and t >= seconds + 0.45 + hold then
			conn:Disconnect()
			if dim then TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play() end
			if resultLabel then TweenService:Create(resultLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
			for _, card in cards do card.Visible = false end
			if rays then rays.Visible = false end
			task.delay(0.32, function()
				if token == playing then
					gui.Enabled = false
					for _, child in strip:GetChildren() do child:Destroy() end
				end
			end)
		end
	end)
end

remote.OnClientEvent:Connect(function(action, payload)
	if action ~= "RandomReel" or typeof(payload) ~= "table" then return end
	local ok, err = pcall(play, payload)
	if not ok then
		warn("[OreRandomReel] " .. tostring(err))
		gui.Enabled = false
	end
end)

local camera = workspace.CurrentCamera
if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
