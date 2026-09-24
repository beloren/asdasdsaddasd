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
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Card = {}
Card.VERSION = 20

local CARD_W, CARD_H = 400, 290

-- Настройки двух окон (их же использует tools/BuildAllUI.lua).
Card.PRESETS = {
	GroupRewardUi = {
		GuiName = "GroupRewardUi",
		ActionName = "JoinGroupButton",
		Accent = Color3.fromRGB(70, 140, 230),
		HeaderIcon = "👥",
		Title = "JOIN GROUP = MORE CASH",
		ActionText = "👥 JOIN & CLAIM",
	},
	LikeRewardUi = {
		GuiName = "LikeRewardUi",
		ActionName = "FavoriteButton",
		Accent = Color3.fromRGB(235, 90, 130),
		HeaderIcon = "⭐",
		Title = "FAVORITE = FREE REWARD",
		ActionText = "⭐ FAVORITE & CLAIM",
	},
}

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

-- Собирает ScreenGui (без родителя) в едином стиле UiKit.
-- opts: GuiName, ActionName, Accent (Color3), HeaderIcon, Title, ActionText
function Card.BuildGui(opts)
	local accent = UiKit.Accent(opts.Accent or Theme.Accents.Blue.Main)
	local gui = UiKit.Screen(opts.GuiName, { DisplayOrder = 40, Enabled = false })
	gui:SetAttribute("RewardCardVersion", Card.VERSION)

	local dimmer = UiKit.Dimmer(gui)
	dimmer.BackgroundTransparency = 1

	local card = UiKit.Plate(gui, "Card", "Panel", {
		_Accent = accent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Visible = false,
		ZIndex = 2,
	})
	card.BackgroundTransparency = 0.15
	card:SetAttribute("CardWidth", CARD_W)
	card:SetAttribute("CardHeight", CARD_H)
	UiKit.Scale(card, "Fit", 1)

	-- Лента «FREE REWARD» над карточкой.
	local ribbon = UiKit.Plate(card, "Ribbon", "Pill", {
		_Accent = accent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(190, 32),
		BackgroundColor3 = accent.Main,
		BackgroundTransparency = 0,
		ZIndex = 5,
	})
	UiKit.Text(ribbon, "Label", "🎁 FREE REWARD", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 1, -8),
		ZIndex = 6,
	})

	UiKit.CloseButton(card, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 7,
	})

	UiKit.TitleText(card, "Title", ("%s  %s"):format(opts.HeaderIcon or "", opts.Title or ""), accent, {
		Position = UDim2.fromOffset(18, 24),
		Size = UDim2.new(1, -60, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})

	-- Что дают: две «фишки».
	local chips = UiKit.Group(card, "Rewards", {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 0, 44),
		ZIndex = 3,
	})
	UiKit.List(chips, { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) })
	for index = 1, 2 do
		local chip = UiKit.Card(chips, "Chip" .. index, Theme.Accents.Gold, {
			LayoutOrder = index,
			Size = UDim2.new(0.5, -4, 1, 0),
			ZIndex = 3,
		})
		UiKit.Text(chip, "Text", "", {
			_Style = "Heading",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -14, 1, -12),
			TextColor3 = Theme.Colors.Money,
			ZIndex = 4,
		})
	end

	-- Большой призыв на лайк.
	local likeBox = UiKit.Card(card, "LikeBox", Theme.Accents.Blue, {
		Position = UDim2.fromOffset(16, 118),
		Size = UDim2.new(1, -32, 0, 80),
		ZIndex = 3,
	})
	UiKit.Text(likeBox, "Thumb", "👍", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 36, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		ZIndex = 5,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(likeBox, "LikeTitle", "LIKE THE GAME!", {
		_Style = "Title",
		Position = UDim2.fromOffset(70, 6),
		Size = UDim2.new(1, -80, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Accents.Blue.Light,
		ZIndex = 4,
	})
	local bar = UiKit.Bar(likeBox, "LikeBar", "Gold", {
		Position = UDim2.fromOffset(70, 38),
		Size = UDim2.new(1, -80, 0, 14),
		ZIndex = 4,
	})
	UiKit.Text(bar, "Count", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 1, 4),
		ZIndex = 6,
	})
	UiKit.Text(likeBox, "GoalText", "", {
		_Style = "Small",
		Position = UDim2.fromOffset(70, 56),
		Size = UDim2.new(1, -80, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})

	-- Кнопка действия.
	local action = UiKit.Button(card, opts.ActionName, opts.ActionText or "CLAIM", "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -32, 0, 56),
		ZIndex = 4,
		_TextStyle = "Title",
	})
	UiKit.Scale(action, "Pulse", 1)
	return gui
end

function Card.BuildGroup()
	return Card.BuildGui(Card.PRESETS.GroupRewardUi)
end

function Card.BuildLike()
	return Card.BuildGui(Card.PRESETS.LikeRewardUi)
end

-- Клиент: экран из StarterGui (tools/BuildAllUI.lua) или собранный на лету.
function Card.Build(playerGui, opts)
	local ok, UiRegistry = pcall(require, script.Parent.UiRegistry)
	if ok and UiRegistry.Entry(opts.GuiName) then
		local gui = UiRegistry.Get(opts.GuiName)
		if gui and gui:FindFirstChild("Card") and gui.Card:FindFirstChild(opts.ActionName) then
			return gui
		end
		if gui then gui:Destroy() end
	end
	local old = playerGui:FindFirstChild(opts.GuiName)
	if old then old:Destroy() end
	local gui = Card.BuildGui(opts)
	gui.Parent = playerGui
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
