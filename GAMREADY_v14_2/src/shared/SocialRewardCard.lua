--------------------------------------------------------------------------------
-- SocialRewardCard (v17) — общий вид окон «награда за избранное» и «награда
-- за группу». Заменяет старые большие окна с подарком-коробкой.
--
-- СТИЛЬ: та же деревянная плашка с кремовым текстом, что и уведомления
-- (ToastUiBuilder), только крупнее. Сверху падает, пружинит и висит по
-- центру-верху экрана; фон затемняется слегка, игра остаётся видна.
--
-- ЧТО НА КАРТОЧКЕ (коротко и ясно):
--   ┌──────────── FREE REWARD ────────────┐
--   │ ⭐  FAVORITE = FREE REWARD       [X] │
--   │ [⛏ Void Pickaxe] [💎 3x Crystal]     │  ← что получишь
--   │ 👍 LIKE THE GAME!  ▓▓▓▓░░ 37/50      │  ← большой призыв на лайк
--   │    at 50 👍: free Rare Chest code     │     + прогресс цели лайков
--   │ [      ⭐ FAVORITE & CLAIM      ]     │  ← одна кнопка
--   └──────────────────────────────────────┘
--
-- Контракт имён для остальных скриптов не меняется: ScreenGui с именем из
-- opts.GuiName, внутри Frame "Dimmer" и Frame "Card" (их проверяют
-- ModalDimmerGuard / CustomCartUI / MiningRhythmUI). Кнопка действия
-- называется opts.ActionName (FavoriteButton / JoinGroupButton).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Card = {}
Card.VERSION = 17

local CREAM = Color3.fromRGB(255, 244, 214)
local WOOD = Color3.fromRGB(122, 78, 42)
local WOOD_DARK = Color3.fromRGB(58, 34, 16)
local WOOD_INNER = Color3.fromRGB(96, 60, 30)
local GREEN = Color3.fromRGB(96, 200, 72)
local GREEN_DARK = Color3.fromRGB(30, 80, 20)
local LIKE_BLUE = Color3.fromRGB(70, 160, 255)
local LIKE_BLUE_DARK = Color3.fromRGB(20, 60, 120)

local CARD_W, CARD_H = 380, 268

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, contextual)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = CREAM
	l.ZIndex = 4
	for key, value in props do l[key] = value end
	l.Parent = parent
	stroke(l, WOOD_DARK, 2, true)
	return l
end

-- Прогресс лайков: следующая недостигнутая цель из Config.LikeGoals.
function Card.likeGoal()
	local goals = Config.LikeGoals
	if not goals or goals.Enabled == false then return nil end
	local current = math.max(0, math.floor(tonumber(goals.CurrentLikes) or 0))
	local previous = 0
	for _, goal in goals.Goals or {} do
		local need = tonumber(goal.Likes) or 0
		if current < need then
			return { Current = current, Target = need, From = previous, Text = goal.Text or "" }
		end
		previous = need
	end
	return nil
end

-- opts: GuiName, ActionName, Accent (Color3), HeaderIcon, Title, ActionText
function Card.Build(playerGui, opts)
	local old = playerGui:FindFirstChild(opts.GuiName)
	if old and old:GetAttribute("RewardCardVersion") ~= Card.VERSION then
		old:Destroy()
	elseif old then
		return old
	end
	-- Старый ассет из StarterGui может скопироваться позже — убираем дубль.
	local gui = Instance.new("ScreenGui")
	gui.Name = opts.GuiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("RewardCardVersion", Card.VERSION)
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == opts.GuiName and child ~= gui then
			task.defer(function() child:Destroy() end)
		end
	end)

	local dimmer = Instance.new("TextButton")
	dimmer.Name = "Dimmer"
	dimmer.Text = ""
	dimmer.AutoButtonColor = false
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 1
	dimmer.BorderSizePixel = 0
	dimmer.ZIndex = 1
	dimmer.Visible = false
	dimmer.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.42)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = WOOD
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = 2
	card.Parent = gui
	card:SetAttribute("CardWidth", CARD_W)
	card:SetAttribute("CardHeight", CARD_H)
	corner(card, UDim.new(0, 18))
	stroke(card, WOOD_DARK, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 170, 150))
	gradient.Parent = card
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = card
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -12, 1, -12)
	inner.BackgroundColor3 = WOOD_INNER
	inner.BackgroundTransparency = 0.35
	inner.BorderSizePixel = 0
	inner.ZIndex = 2
	inner.Parent = card
	corner(inner, UDim.new(0, 14))

	-- Лента «FREE REWARD» над карточкой.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Position = UDim2.new(0.5, 0, 0, 0)
	ribbon.Size = UDim2.fromOffset(170, 30)
	ribbon.BackgroundColor3 = opts.Accent
	ribbon.ZIndex = 5
	ribbon.Parent = card
	corner(ribbon, UDim.new(1, 0))
	stroke(ribbon, WOOD_DARK, 3)
	label(ribbon, {
		Text = "🎁 FREE REWARD", Size = UDim2.new(1, -16, 1, -8), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), TextColor3 = Color3.new(1, 1, 1), ZIndex = 6,
	})

	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = Color3.fromRGB(225, 70, 70)
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.AutoButtonColor = true
	close.ZIndex = 7
	close.Parent = card
	corner(close, UDim.new(1, 0))
	stroke(close, WOOD_DARK, 3)

	-- Заголовок.
	label(card, {
		Name = "Title", Text = ("%s  %s"):format(opts.HeaderIcon or "", opts.Title or ""),
		Position = UDim2.fromOffset(18, 22), Size = UDim2.new(1, -36, 0, 30),
	})

	-- Что дают: две «фишки».
	local chips = Instance.new("Frame")
	chips.Name = "Rewards"
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.fromOffset(16, 58)
	chips.Size = UDim2.new(1, -32, 0, 42)
	chips.ZIndex = 3
	chips.Parent = card
	local chipsLayout = Instance.new("UIListLayout")
	chipsLayout.FillDirection = Enum.FillDirection.Horizontal
	chipsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipsLayout.Padding = UDim.new(0, 8)
	chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipsLayout.Parent = chips
	local chipLabels = {}
	for index = 1, 2 do
		local chip = Instance.new("Frame")
		chip.Name = "Chip" .. index
		chip.LayoutOrder = index
		chip.Size = UDim2.new(0.5, -4, 1, 0)
		chip.BackgroundColor3 = CREAM
		chip.ZIndex = 3
		chip.Parent = chips
		corner(chip, UDim.new(0, 12))
		stroke(chip, WOOD_DARK, 2.5)
		local chipText = label(chip, {
			Name = "Text", Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -14, 1, -12), TextColor3 = WOOD_DARK,
		})
		chipText:FindFirstChildOfClass("UIStroke"):Destroy()
		chipLabels[index] = chipText
	end

	-- Большой призыв на лайк.
	local likeBox = Instance.new("Frame")
	likeBox.Name = "LikeBox"
	likeBox.Position = UDim2.fromOffset(16, 110)
	likeBox.Size = UDim2.new(1, -32, 0, 76)
	likeBox.BackgroundColor3 = LIKE_BLUE
	likeBox.ZIndex = 3
	likeBox.Parent = card
	corner(likeBox, UDim.new(0, 14))
	stroke(likeBox, LIKE_BLUE_DARK, 3)
	local likeGradient = Instance.new("UIGradient")
	likeGradient.Rotation = 90
	likeGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 200, 255))
	likeGradient.Parent = likeBox
	local thumb = Instance.new("TextLabel")
	thumb.Name = "Thumb"
	thumb.BackgroundTransparency = 1
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.new(0, 36, 0.5, 0)
	thumb.Size = UDim2.fromOffset(56, 56)
	thumb.Text = "👍"
	thumb.TextScaled = true
	thumb.ZIndex = 5
	thumb.Parent = likeBox
	local likeTitle = label(likeBox, {
		Name = "LikeTitle", Text = "LIKE THE GAME!", Position = UDim2.fromOffset(70, 6),
		Size = UDim2.new(1, -80, 0, 26), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.new(1, 1, 1),
	})
	likeTitle:FindFirstChildOfClass("UIStroke").Color = LIKE_BLUE_DARK
	local barBack = Instance.new("Frame")
	barBack.Name = "LikeBar"
	barBack.Position = UDim2.fromOffset(70, 36)
	barBack.Size = UDim2.new(1, -80, 0, 14)
	barBack.BackgroundColor3 = LIKE_BLUE_DARK
	barBack.ZIndex = 4
	barBack.Parent = likeBox
	corner(barBack, UDim.new(1, 0))
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 225, 70)
	barFill.ZIndex = 5
	barFill.Parent = barBack
	corner(barFill, UDim.new(1, 0))
	local barText = label(barBack, {
		Name = "Count", Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 1, 2), TextColor3 = Color3.new(1, 1, 1), ZIndex = 6,
	})
	barText:FindFirstChildOfClass("UIStroke").Color = LIKE_BLUE_DARK
	local likeGoalText = label(likeBox, {
		Name = "GoalText", Text = "", Position = UDim2.fromOffset(70, 52), Size = UDim2.new(1, -80, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1),
	})
	likeGoalText:FindFirstChildOfClass("UIStroke").Color = LIKE_BLUE_DARK

	-- Кнопка действия.
	local action = Instance.new("TextButton")
	action.Name = opts.ActionName
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.new(0.5, 0, 1, -14)
	action.Size = UDim2.new(1, -32, 0, 54)
	action.BackgroundColor3 = GREEN
	action.AutoButtonColor = true
	action.Text = ""
	action.ZIndex = 4
	action.Parent = card
	corner(action, UDim.new(1, 0))
	stroke(action, GREEN_DARK, 3.5)
	local actionScale = Instance.new("UIScale")
	actionScale.Name = "Pulse"
	actionScale.Parent = action
	local caption = label(action, {
		Name = "Caption", Text = opts.ActionText or "CLAIM", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 1, -14), TextColor3 = Color3.new(1, 1, 1), ZIndex = 5,
	})
	caption:FindFirstChildOfClass("UIStroke").Color = GREEN_DARK

	return gui
end

-- Контроллер: показ/скрытие/обновление. Возвращает таблицу с методами.
function Card.Controller(gui, opts)
	local dimmer = gui:WaitForChild("Dimmer")
	local card = gui:WaitForChild("Card")
	local fit = card:WaitForChild("Fit")
	local action = card:WaitForChild(opts.ActionName)
	local caption = action:WaitForChild("Caption")
	local pulse = action:WaitForChild("Pulse")
	local likeBox = card:WaitForChild("LikeBox")
	local thumb = likeBox:WaitForChild("Thumb")
	local barBack = likeBox:WaitForChild("LikeBar")
	local rewards = card:WaitForChild("Rewards")

	local self = { Gui = gui, Card = card, Action = action, Close = card:WaitForChild("CloseButton"), Dimmer = dimmer, Open = false }
	local token = 0

	local function fitScale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
		return math.min(1, (viewport.X - 24) / CARD_W, (viewport.Y - 40) / (CARD_H + 20))
	end
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if self.Open then fit.Scale = fitScale() end
		end)
	end

	function self.SetCaption(text) caption.Text = text end

	function self.SetRewards(first, second)
		local chip1, chip2 = rewards:FindFirstChild("Chip1"), rewards:FindFirstChild("Chip2")
		chip1:FindFirstChild("Text").Text = first or ""
		chip2:FindFirstChild("Text").Text = second or ""
		chip2.Visible = second ~= nil and second ~= ""
		chip1.Size = chip2.Visible and UDim2.new(0.5, -4, 1, 0) or UDim2.new(1, 0, 1, 0)
	end

	function self.RefreshLikes()
		local goal = Card.likeGoal()
		local fill = barBack:WaitForChild("Fill")
		if goal then
			local span = math.max(1, goal.Target - goal.From)
			fill.Size = UDim2.fromScale(math.clamp((goal.Current - goal.From) / span, 0.04, 1), 1)
			barBack:FindFirstChild("Count").Text = ("%d / %d 👍"):format(goal.Current, goal.Target)
			likeBox:FindFirstChild("GoalText").Text = ("At %d likes: %s"):format(goal.Target, goal.Text)
		else
			fill.Size = UDim2.fromScale(1, 1)
			barBack:FindFirstChild("Count").Text = "THANK YOU! ❤"
			likeBox:FindFirstChild("GoalText").Text = "Your like helps us make updates!"
		end
	end

	local function idleLoop(myToken)
		task.spawn(function()
			local t = 0
			while self.Open and token == myToken do
				local dt = task.wait()
				t += dt
				-- 👍 качается и подпрыгивает, кнопка «дышит».
				thumb.Rotation = math.sin(t * 5) * 14
				thumb.Size = UDim2.fromOffset(56 + math.abs(math.sin(t * 3)) * 10, 56 + math.abs(math.sin(t * 3)) * 10)
				pulse.Scale = 1 + math.sin(t * 4) * 0.035
			end
		end)
	end

	function self.Show()
		token += 1
		local myToken = token
		self.Open = true
		self.RefreshLikes()
		gui.Enabled = true
		dimmer.Visible = true
		dimmer.BackgroundTransparency = 1
		TweenService:Create(dimmer, TweenInfo.new(0.25), { BackgroundTransparency = 0.6 }):Play()
		card.Visible = true
		card.Rotation = -4
		card.Position = UDim2.fromScale(0.5, -0.4)
		local target = fitScale()
		fit.Scale = target * 0.9
		TweenService:Create(card, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.42), Rotation = 0,
		}):Play()
		TweenService:Create(fit, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
		idleLoop(myToken)
	end

	function self.Hide(instant)
		if not self.Open then return end
		token += 1
		local myToken = token
		self.Open = false
		if instant then
			card.Visible = false
			dimmer.Visible = false
			gui.Enabled = false
			return
		end
		TweenService:Create(dimmer, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, -0.4), Rotation = 4,
		}):Play()
		task.delay(0.26, function()
			if token ~= myToken then return end
			card.Visible = false
			dimmer.Visible = false
			gui.Enabled = false
		end)
	end

	-- Короткое «празднование» после получения награды, затем закрытие.
	function self.Celebrate(text)
		caption.Text = text or "CLAIMED! ✔"
		pulse.Scale = 1.15
		TweenService:Create(pulse, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(1.2, function() self.Hide() end)
	end

	return self
end

return Card
