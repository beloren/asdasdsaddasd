--------------------------------------------------------------------------------
-- RevealCards (v18) — КАРТОЧКИ ОТКРЫТИЯ для жеод и сундуков (только клиент).
--
-- Карточки вылетают снизу рубашкой вверх, по очереди трясутся (чем реже
-- предмет — тем сильнее, рамка уже подсвечивается цветом редкости),
-- переворачиваются со вспышкой и открывают 3D-превью награды, название,
-- подробность и шанс «1 in N». Бейджи: NEW! / DUPLICATE / 💖 HEART.
-- Legendary и Mythic — затемнение, вращающиеся лучи за карточкой, вспышка.
-- Клик или тап — пропустить/закрыть; закрываются и сами.
--
--   RevealCards.Show(items, { Title = "EPIC CHEST", Color = Color3 })
--   RevealCards.Push(item, opts) — по одной (подбор капель жеоды): всё, что
--                                  пришло за 0.35 с, покажется одной пачкой.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemPreview = require(ReplicatedStorage.Shared.ItemPreview)
local DropTables = require(ReplicatedStorage.Shared.DropTables)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local okSfx, UiSfx = pcall(require, ReplicatedStorage.Shared.UiSfx)

local RevealCards = {}

-- v20: вид карточек и экрана — Shared.UiBuilders.RevealCardsUi
-- (StarterGui/RevealCards, правится в Studio).
local RevealBuilder = require(ReplicatedStorage.Shared.UiBuilders.RevealCardsUi)
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local CARD_W, CARD_H, GAP = RevealBuilder.CARD_W, RevealBuilder.CARD_H, RevealBuilder.GAP
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 6 }

local function sfx(name)
	if okSfx then pcall(UiSfx.play, name) end
end

local function rarityColor(rarity)
	return Config.RarityColors[rarity or ""] or (Config.Relics and Config.Relics.RarityColors and Config.Relics.RarityColors[rarity or ""]) or Color3.fromRGB(205, 205, 205)
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 14)
	c.Parent = parent
	return c
end

--------------------------------------------------------------------------------
-- ТЕКСТЫ КАРТОЧКИ
--------------------------------------------------------------------------------
local function titleOf(item)
	if item.Kind == "Skin" then
		local d = Config.Skins.Definitions[item.SkinId]
		return d and d.DisplayName or "Skin"
	elseif item.Kind == "Charm" then
		local c = Config.Potions.Types[item.Charm]
		return c and c.DisplayName or "Charm"
	elseif item.Kind == "Money" then
		return item.Amount and ("$" .. NumberFormat.abbreviate(item.Amount)) or (item.Title or item.Text or "Cash")
	elseif item.Kind == "Relic" then
		local r = Config.Relics and Config.Relics.Types[item.RelicId]
		return r and r.DisplayName or (item.Text or "Relic")
	elseif item.Kind == "PrestigePoint" then
		return "Prestige Point"
	end
	return item.Title or item.Text or "Reward"
end

local function detailOf(item)
	local kind = item.Kind
	if kind == "Ore" or kind == "Crystal" then
		if item.MutationNames then return item.MutationNames end
		if item.Upgraded and item.Level then return ("UPGRADED → LV %d"):format(item.Level) end
		if item.IncomePerMinute then return ("+$%s/SEC"):format(NumberFormat.perSecond(item.IncomePerMinute)) end
		return "PODIUM CRYSTAL"
	elseif kind == "Money" then
		return item.Jackpot and "JACKPOT!" or "CASH"
	elseif kind == "Essence" then
		return "APPLY AT YOUR PODIUM"
	elseif kind == "Heart" then
		return ("NEXT GEODE x%d REWARDS"):format(Config.Geodes.Heart and Config.Geodes.Heart.Rewards or 3)
	elseif kind == "Skin" then
		if item.Duplicate then return item.Amount and ("DUPLICATE → $" .. NumberFormat.abbreviate(item.Amount)) or "DUPLICATE" end
		return "NEW PICKAXE SKIN!"
	elseif kind == "Charm" then
		local c = Config.Potions.Types[item.Charm]
		local b = c and Config.Buffs[c.Buff]
		return b and b.DisplayName or "CHARM"
	elseif kind == "PrestigePoint" then
		return "+1 POINT"
	elseif kind == "Relic" then
		return "RELIC!"
	elseif kind == "Junk" then
		return (tonumber(item.Value) or 0) > 0 and ("JUNK · $" .. NumberFormat.abbreviate(item.Value)) or "JUNK · WORTHLESS"
	elseif kind == "Buff" then
		return "TEMPORARY BUFF"
	end
	return ""
end

local function badgeOf(item)
	if item.Kind == "Skin" and item.New then return "NEW!", Color3.fromRGB(80, 220, 110) end
	if item.Kind == "Skin" and item.Duplicate then return "DUPLICATE", Color3.fromRGB(120, 120, 140) end
	if item.Kind == "Heart" then return "💖 HEART", Color3.fromRGB(255, 90, 170) end
	if item.FromHeart then return "💖 x3", Color3.fromRGB(255, 90, 170) end
	if (item.Kind == "Ore" or item.Kind == "Crystal") and item.Upgraded then return "LEVEL UP", Color3.fromRGB(90, 180, 255) end
	return nil
end

--------------------------------------------------------------------------------
-- ЭКРАН
--------------------------------------------------------------------------------
local gui, dim, row, header, hint, scaleObj, cardTemplate
local function ensureGui()
	if gui and gui.Parent then return end
	gui = require(ReplicatedStorage.Shared.UiRegistry).Get("RevealCards")
	gui.Enabled = false
	dim = gui:WaitForChild("Dimmer")
	dim.Visible = true
	local holder = gui:WaitForChild("Holder")
	scaleObj = holder:WaitForChild("Scale")
	header = holder:WaitForChild("Header")
	row = holder:WaitForChild("Row")
	hint = holder:WaitForChild("Hint")
	cardTemplate = gui:WaitForChild("Templates"):WaitForChild("Card")
end

local function fitScale(count)
	local camera = workspace.CurrentCamera
	local v = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local width = count * (CARD_W + GAP) + 40
	return math.min(1, (v.X - 20) / width, (v.Y - 40) / (CARD_H + 140))
end

--------------------------------------------------------------------------------
-- ОДНА КАРТОЧКА
--------------------------------------------------------------------------------
local function buildCard(item, index, count)
	local color = rarityColor(item.Rarity)
	local slot = cardTemplate:Clone()
	slot.Visible = true -- шаблоны в Templates скрыты
	slot.Name = "Card" .. index
	local x = (index - (count + 1) / 2) * (CARD_W + GAP)
	slot.Position = UDim2.new(0.5, x, 0.5, 0)
	slot.Parent = row
	local pop = slot:WaitForChild("Pop")

	-- Лучи за карточкой (Legendary+) — цвет редкости.
	local rays = slot:WaitForChild("Rays")
	for _, ray in rays:GetChildren() do
		if ray:IsA("GuiObject") then ray.BackgroundColor3 = color end
	end

	local flipper = slot:WaitForChild("Flipper")
	local back = flipper:WaitForChild("Back")
	local backStroke = back:FindFirstChild("SkinStroke") or Instance.new("UIStroke", back)
	local front = flipper:WaitForChild("Front")
	local frontStroke = front:FindFirstChild("SkinStroke")
	if frontStroke then frontStroke.Color = color end
	local band = front:FindFirstChild("Band")
	if band then band.BackgroundColor3 = color end
	local viewport = front:WaitForChild("Preview")
	front.Rarity.Text = (item.Rarity or ""):upper()
	front.Rarity.TextColor3 = color
	front.Title.Text = titleOf(item):upper()
	front.Detail.Text = detailOf(item)
	front.Chance.Text = DropTables.OneIn(item.Chance)
	local badgeText, badgeColor = badgeOf(item)
	local badge = front:FindFirstChild("Badge")
	if badge then
		badge.Visible = badgeText ~= nil
		if badgeText then
			UiKit.Tint(badge, badgeColor:Lerp(Color3.new(0, 0, 0), 0.35))
			local badgeStroke = badge:FindFirstChild("SkinStroke")
			if badgeStroke then badgeStroke.Color = badgeColor end
			badge.Text.Text = badgeText
		end
	end
	return { Slot = slot, Pop = pop, Flipper = flipper, Back = back, BackStroke = backStroke, Front = front,
		Rays = rays, Viewport = viewport, Item = item, Color = color, Rank = RARITY_RANK[item.Rarity or ""] or 1 }
end

--------------------------------------------------------------------------------
-- ПОКАЗ ПАЧКИ
--------------------------------------------------------------------------------
local queue = {}
local running = false
local skipRequested = false
local cleanups = {}

local function tween(obj, time, goal, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function wait(seconds)
	local t = 0
	while t < seconds and not skipRequested do
		t += task.wait()
	end
end

local function burst(card)
	for i = 1, 14 do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.45)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = i % 3 == 0 and Color3.new(1, 1, 1) or card.Color
		dot.ZIndex = 8
		dot.Parent = card.Slot
		corner(dot, 4)
		local angle = (i / 14) * math.pi * 2 + math.random() * 0.4
		local distance = 90 + math.random() * 60
		tween(dot, 0.55, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.45, math.sin(angle) * distance),
			BackgroundTransparency = 1, Size = UDim2.fromOffset(3, 3),
		})
		task.delay(0.6, function() dot:Destroy() end)
	end
end

local function flip(card)
	local shake = (card.Rank - 1) / 5 -- 0..1
	-- Тряска с подсветкой рамки цветом редкости («что-то редкое!»).
	local duration = 0.18 + shake * 0.55
	local started = os.clock()
	tween(card.BackStroke, duration, { Color = card.Color, Thickness = 4 + shake * 4 })
	if shake > 0.4 then sfx("GeodeTap") end
	while os.clock() - started < duration and not skipRequested do
		local k = (os.clock() - started) / duration
		local amp = (2 + shake * 9) * k
		card.Flipper.Position = UDim2.new(0.5, (math.random() - 0.5) * amp * 2, 0.5, (math.random() - 0.5) * amp)
		card.Flipper.Rotation = (math.random() - 0.5) * amp * 0.8
		RunService.RenderStepped:Wait()
	end
	card.Flipper.Position = UDim2.fromScale(0.5, 0.5)
	card.Flipper.Rotation = 0
	-- Переворот: сжать по X → сменить сторону → развернуть.
	local half = skipRequested and 0.05 or 0.11
	tween(card.Flipper, half, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
	card.Back.Visible = false
	card.Front.Visible = true
	table.insert(cleanups, ItemPreview.Mount(card.Viewport, card.Item, { Spin = true, Tilt = 14 }))
	tween(card.Flipper, half * 1.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	card.Pop.Scale = 1.18
	tween(card.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	burst(card)
	if card.Rank >= 5 then
		sfx("GeodeReveal")
		card.Rays.Visible = true
		card.Rays.Rotation = 0
		task.spawn(function()
			while card.Rays.Parent do
				card.Rays.Rotation += 0.6
				RunService.RenderStepped:Wait()
			end
		end)
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = card.Color
		flash.BackgroundTransparency = 0.4
		flash.ZIndex = 1
		flash.Parent = gui
		tween(flash, 0.5, { BackgroundTransparency = 1 })
		task.delay(0.55, function() flash:Destroy() end)
	elseif card.Rank >= 3 then
		sfx("UiSuccess")
	else
		sfx("UiButtonClick")
	end
end

local function clear()
	for _, fn in cleanups do pcall(fn) end
	cleanups = {}
	for _, child in row:GetChildren() do child:Destroy() end
end

local function runBatch(items, opts)
	ensureGui()
	clear()
	skipRequested = false
	local count = #items
	local best = 1
	for _, item in items do best = math.max(best, RARITY_RANK[item.Rarity or ""] or 1) end
	gui.Enabled = true
	scaleObj.Scale = fitScale(count)
	header.Text = opts and opts.Title or ""
	local headerColor = opts and opts.Color or UiKit.Theme.Accents.Gold.Main
	local headerGradient = header:FindFirstChild("TextGradient")
	if headerGradient then
		headerGradient.Color = UiKit.Seq(headerColor:Lerp(Color3.new(1, 1, 1), 0.55), headerColor)
	else
		header.TextColor3 = headerColor
	end
	header.TextTransparency = 1
	tween(header, 0.3, { TextTransparency = 0 })
	hint.TextTransparency = 1
	dim.BackgroundTransparency = 1
	tween(dim, 0.3, { BackgroundTransparency = best >= 5 and 0.35 or 0.6 })

	local cards = {}
	for index, item in items do
		local card = buildCard(item, index, count)
		local target = card.Slot.Position
		card.Slot.Position = target + UDim2.fromScale(0, 1.4)
		card.Slot.Rotation = (math.random() - 0.5) * 16
		task.delay((index - 1) * 0.07, function()
			tween(card.Slot, 0.45, { Position = target, Rotation = 0 }, Enum.EasingStyle.Back)
		end)
		cards[index] = card
	end
	wait(0.45 + count * 0.07)
	for _, card in cards do
		flip(card)
		wait(0.12)
	end
	tween(hint, 0.3, { TextTransparency = 0.2 })
	skipRequested = false
	wait(2.2 + count * 0.35)
	-- Уезжают вверх.
	for index, card in cards do
		task.delay((index - 1) * 0.04, function()
			tween(card.Slot, 0.3, { Position = card.Slot.Position - UDim2.fromScale(0, 1.2) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end)
	end
	tween(dim, 0.3, { BackgroundTransparency = 1 })
	tween(header, 0.25, { TextTransparency = 1 })
	tween(hint, 0.25, { TextTransparency = 1 })
	task.wait(0.4)
	clear()
	gui.Enabled = false
end

local function pump()
	if running then return end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local batch = table.remove(queue, 1)
			local ok, err = pcall(runBatch, batch.Items, batch.Opts)
			if not ok then
				warn("[RevealCards]", err)
				if gui then gui.Enabled = false end
			end
		end
		running = false
	end)
end

function RevealCards.Show(items, opts)
	if type(items) ~= "table" or #items == 0 then return end
	ensureGui()
	if not dim:GetAttribute("Wired") then
		dim:SetAttribute("Wired", true)
		dim.Activated:Connect(function() skipRequested = true end)
	end
	-- Не больше 6 карточек за раз — остальное следующей пачкой.
	local chunk = {}
	for _, item in items do
		table.insert(chunk, item)
		if #chunk == 6 then
			table.insert(queue, { Items = chunk, Opts = opts })
			chunk = {}
		end
	end
	if #chunk > 0 then table.insert(queue, { Items = chunk, Opts = opts }) end
	pump()
end

local pending, pendingOpts, pendingToken = {}, nil, 0
function RevealCards.Push(item, opts)
	if type(item) ~= "table" then return end
	table.insert(pending, item)
	pendingOpts = opts or pendingOpts
	pendingToken += 1
	local token = pendingToken
	task.delay(0.35, function()
		if token ~= pendingToken or #pending == 0 then return end
		local items = pending
		pending = {}
		RevealCards.Show(items, pendingOpts)
	end)
end

return RevealCards
