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

local CARD_W, CARD_H, GAP = 170, 236, 16
local INK = Color3.fromRGB(12, 10, 20)
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

local function stroke(parent, thickness, color, contextual)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or INK
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do l[k] = v end
	l.Parent = parent
	stroke(l, 2, INK, true)
	return l
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
local gui, dim, row, header, hint, scaleObj
local function ensureGui()
	if gui and gui.Parent then return end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "RevealCards"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 70
	gui.Enabled = false
	gui.Parent = playerGui

	dim = Instance.new("TextButton")
	dim.Name = "Dimmer"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Parent = gui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.52)
	holder.Size = UDim2.fromOffset(1100, 340)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	scaleObj = Instance.new("UIScale")
	scaleObj.Parent = holder

	header = text(holder, {
		Name = "Header", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(600, 40), Text = "",
	})
	row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.55)
	row.Size = UDim2.fromOffset(1100, CARD_H)
	row.Parent = holder
	hint = text(holder, {
		Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 18),
		Size = UDim2.fromOffset(300, 22), Text = "TAP TO CONTINUE", TextTransparency = 1,
		TextColor3 = Color3.fromRGB(220, 220, 230),
	})
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
	local slot = Instance.new("Frame")
	slot.Name = "Card" .. index
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	local x = (index - (count + 1) / 2) * (CARD_W + GAP)
	slot.Position = UDim2.new(0.5, x, 0.5, 0)
	slot.Size = UDim2.fromOffset(CARD_W, CARD_H)
	slot.Parent = row
	local pop = Instance.new("UIScale")
	pop.Parent = slot

	-- Лучи за карточкой (Legendary+).
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(CARD_H * 1.7, CARD_H * 1.7)
	rays.BackgroundTransparency = 1
	rays.Visible = false
	rays.ZIndex = 0
	rays.Parent = slot
	for i = 1, 8 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, 26, 1, 0)
		ray.Rotation = i * 22.5
		ray.BackgroundColor3 = color
		ray.BackgroundTransparency = 0.55
		ray.BorderSizePixel = 0
		ray.ZIndex = 0
		ray.Parent = rays
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ray
	end

	local flipper = Instance.new("Frame")
	flipper.Name = "Flipper"
	flipper.AnchorPoint = Vector2.new(0.5, 0.5)
	flipper.Position = UDim2.fromScale(0.5, 0.5)
	flipper.Size = UDim2.fromScale(1, 1)
	flipper.BackgroundTransparency = 1
	flipper.ZIndex = 2
	flipper.Parent = slot

	-- РУБАШКА
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(38, 32, 62)
	back.ZIndex = 2
	back.Parent = flipper
	corner(back, 16)
	local backStroke = stroke(back, 4, Color3.fromRGB(90, 80, 130))
	local backGrad = Instance.new("UIGradient")
	backGrad.Rotation = 60
	backGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 200))
	backGrad.Parent = back
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -22, 1, -22)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 3
	inner.Parent = back
	corner(inner, 12)
	stroke(inner, 2, Color3.fromRGB(120, 110, 170))
	text(back, { Text = "?", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(90, 110), ZIndex = 4, TextColor3 = Color3.fromRGB(230, 220, 255) })

	-- ЛИЦО
	local front = Instance.new("Frame")
	front.Name = "Front"
	front.Size = UDim2.fromScale(1, 1)
	front.BackgroundColor3 = Color3.fromRGB(26, 24, 38)
	front.Visible = false
	front.ZIndex = 2
	front.Parent = flipper
	corner(front, 16)
	stroke(front, 4, color)
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0.62, 0)
	band.BackgroundColor3 = color
	band.ZIndex = 2
	band.Parent = front
	corner(band, 16)
	local bandGrad = Instance.new("UIGradient")
	bandGrad.Rotation = 90
	bandGrad.Transparency = NumberSequence.new(0.35, 1)
	bandGrad.Parent = band
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(8, 22)
	viewport.Size = UDim2.new(1, -16, 0, 120)
	viewport.ZIndex = 3
	viewport.Parent = front
	text(front, { Name = "Rarity", Text = (item.Rarity or ""):upper(), Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 16), TextColor3 = color, ZIndex = 4 })
	text(front, { Name = "Title", Text = titleOf(item):upper(), Position = UDim2.fromOffset(8, 146),
		Size = UDim2.new(1, -16, 0, 30), ZIndex = 4 })
	text(front, { Name = "Detail", Text = detailOf(item), Position = UDim2.fromOffset(8, 178),
		Size = UDim2.new(1, -16, 0, 20), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 225, 130), ZIndex = 4 })
	local oneIn = DropTables.OneIn(item.Chance)
	text(front, { Name = "Chance", Text = oneIn, Position = UDim2.fromOffset(8, 204),
		Size = UDim2.new(1, -16, 0, 16), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(170, 170, 190), ZIndex = 4 })
	local badgeText, badgeColor = badgeOf(item)
	if badgeText then
		local badge = text(front, { Name = "Badge", Text = badgeText, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(110, 26), BackgroundTransparency = 0,
			BackgroundColor3 = badgeColor, ZIndex = 6, Rotation = -4 })
		corner(badge, 13)
		stroke(badge, 2, INK)
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
	header.TextColor3 = opts and opts.Color or Color3.new(1, 1, 1)
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
