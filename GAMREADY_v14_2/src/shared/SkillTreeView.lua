--------------------------------------------------------------------------------
-- SkillTreeView (v20.143) — общий клиентский «движок» полноэкранных деревьев
-- (UpgradeTreeUi у Experienced Miner, IslandTreeUi у Island Keeper; вид -
-- билдер UiBuilders/SkillTreeUi). Сам ничего не знает о покупках: вызывающий
-- скрипт кладёт узлы и линии, красит их и показывает карточку.
--
--   local view = SkillTreeView.new(gui, { OnClose = fn })
--   view:Clear()
--   local node = view:Node("Mine3", "Tier", Vector2.new(0, -300), onClick)
--   view:Link(Vector2.zero, Vector2.new(0, -300), color)
--   view:Paint("Mine3", { Color = c, Caption = "3", Price = "$100", Name = "CAVE" })
--   view:ShowCard("Mine3", { Title, Level, Text, Buy = { Text, Variant, OnClick }, More = {...} })
--   view:Open() / view:Close()
-- Координаты узлов - пиксели от центра дерева (при Zoom = 1).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(ReplicatedStorage.Shared.UiKit)
local TreeReveal = require(ReplicatedStorage.Shared.TreeReveal)

local SkillTreeView = {}
SkillTreeView.__index = SkillTreeView

local CANVAS = 6000
local ORIGIN = CANVAS / 2
local INK = Color3.fromRGB(12, 14, 22)

local function isPhone()
	local camera = workspace.CurrentCamera
	return camera and (camera.ViewportSize.X < 700 or camera.ViewportSize.Y < 450)
end

local function within(gui, position)
	if not (gui and gui.Visible) then return false end
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return position.X >= p.X and position.Y >= p.Y and position.X <= p.X + s.X and position.Y <= p.Y + s.Y
end

function SkillTreeView.new(gui, opts)
	opts = opts or {}
	local self = setmetatable({}, SkillTreeView)
	self.Gui = gui
	self.Viewport = gui:WaitForChild("Viewport")
	self.Canvas = self.Viewport:WaitForChild("Canvas")
	self.Zoom = self.Canvas:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", self.Canvas)
	self.Templates = gui:WaitForChild("Templates")
	self.Card = gui:WaitForChild("Card")
	self.BigClose = gui:FindFirstChild("BigClose")
	self.Money = gui:FindFirstChild("Money")
	self.Title = gui:FindFirstChild("Title")
	self.Hint = gui:FindFirstChild("Hint")
	self.Nodes = {}
	self.Links = {}
	self.Backdrop = gui:FindFirstChild("Backdrop")
	self.BackdropTarget = self.Backdrop and self.Backdrop.BackgroundTransparency or 0.5
	self.Sequencing = false
	self.SeqToken = 0
	self.Pan = Vector2.zero
	self.ZoomValue = 1
	self.OnClose = opts.OnClose
	self.LockName = opts.LockName or gui.Name
	self.Selected = nil
	self.Bounds = { Min = Vector2.new(-300, -300), Max = Vector2.new(300, 300) }

	self.Canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	self.Canvas.Size = UDim2.fromOffset(CANVAS, CANVAS)
	self.Card.Visible = false
	local openSize = self.Card:GetAttribute("OpenSize")
	self.CardSize = typeof(openSize) == "Vector2" and openSize or Vector2.new(self.Card.Size.X.Offset, self.Card.Size.Y.Offset)
	local cardScale = self.Card:FindFirstChild("CardScale") or Instance.new("UIScale")
	cardScale.Name = "CardScale"
	cardScale.Parent = self.Card
	self.CardScale = cardScale

	local cardClose = self.Card:FindFirstChild("Close")
	if cardClose then
		cardClose.Activated:Connect(function() self:HideCard() end)
	end
	if self.BigClose then
		self.BigClose.Activated:Connect(function() self:Close(true) end)
	end
	local buy = self.Card:FindFirstChild("Buy")
	if buy then
		buy.Activated:Connect(function()
			local handler = self.CardBuy
			if handler then handler() end
		end)
	end
	local more = self.Card:FindFirstChild("More")
	if more then
		more.Activated:Connect(function()
			local handler = self.CardMore
			if handler then handler() end
		end)
	end
	self:_bindInput()
	self:_applyPan()
	-- v20.146: дерево спрятал кто-то другой (экран загрузки) - закрываемся
	-- целиком, чтобы не держать игрока на месте
	self.Opened = false
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if self.Opened and not gui.Enabled then self:Close(true) end
	end)
	return self
end

-- ПЕРЕТАСКИВАНИЕ И МАСШТАБ ------------------------------------------------
function SkillTreeView:_applyPan()
	local zoom = self.ZoomValue
	local min, max = self.Bounds.Min, self.Bounds.Max
	-- центр дерева может уехать не дальше краёв содержимого
	local limitX = math.max(math.abs(min.X), math.abs(max.X)) * zoom
	local limitY = math.max(math.abs(min.Y), math.abs(max.Y)) * zoom
	self.Pan = Vector2.new(math.clamp(self.Pan.X, -limitX, limitX), math.clamp(self.Pan.Y, -limitY, limitY))
	self.Canvas.Position = UDim2.new(0.5, self.Pan.X, 0.5, self.Pan.Y)
	self.Zoom.Scale = zoom
end

function SkillTreeView:SetZoom(value)
	self.ZoomValue = math.clamp(value, 0.35, 1.6)
	self:_applyPan()
	if self.Selected and self.Card.Visible then self:_placeCard(self.Selected) end
end

function SkillTreeView:_bindInput()
	local dragging, dragStart, panStart, dragInput = false, nil, nil, nil
	local pinchStart = nil
	self.DragMoved = false
	UserInputService.InputBegan:Connect(function(input)
		if not self.Gui.Enabled then return end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if within(self.Card, pos) or within(self.BigClose, pos) then return end
		if dragging then return end
		dragging, dragStart, panStart, dragInput = true, pos, self.Pan, input
		self.DragMoved = false
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not self.Gui.Enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if not within(self.Card, Vector2.new(input.Position.X, input.Position.Y)) then
				self:SetZoom(self.ZoomValue + input.Position.Z * 0.08)
			end
			return
		end
		if not dragging or pinchStart then return end
		if input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
			if delta.Magnitude > 8 then self.DragMoved = true end
			if self.DragMoved then
				self.Pan = panStart + delta
				self:_applyPan()
				if self.Card.Visible then self:HideCard() end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			task.defer(function() self.DragMoved = false end)
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if not self.Gui.Enabled then return end
		if state == Enum.UserInputState.Begin then pinchStart = self.ZoomValue end
		if pinchStart then self:SetZoom(pinchStart * scale) end
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			pinchStart = nil
			dragging = false
		end
	end)
end

-- УЗЛЫ И ЛИНИИ ----------------------------------------------------------------
function SkillTreeView:Clear()
	for _, child in self.Canvas:GetChildren() do
		if not child:IsA("UIScale") then child:Destroy() end
	end
	table.clear(self.Nodes)
	table.clear(self.Links)
	self.Bounds = { Min = Vector2.new(-300, -300), Max = Vector2.new(300, 300) }
end

function SkillTreeView:_grow(pos)
	local pad = 160
	self.Bounds.Min = Vector2.new(math.min(self.Bounds.Min.X, pos.X - pad), math.min(self.Bounds.Min.Y, pos.Y - pad))
	self.Bounds.Max = Vector2.new(math.max(self.Bounds.Max.X, pos.X + pad), math.max(self.Bounds.Max.Y, pos.Y + pad))
end

-- kind: "Root" | "Tier" | "Star" | "Final" (шаблон <kind>Node)
function SkillTreeView:Node(id, kind, pos, onClick)
	local template = self.Templates:FindFirstChild(kind .. "Node") or self.Templates:WaitForChild("TierNode")
	local node = template:Clone()
	node.Name = "Node_" .. id
	-- v20.166: своё наведение (HoverScale ниже) вместо общего GlobalUiHover
	node:SetAttribute("DisableGlobalHover", true)
	for _, child in node:GetChildren() do
		if child:IsA("UIScale") then child:Destroy() end
	end
	node.Visible = true
	node.AnchorPoint = Vector2.new(0.5, 0.5)
	node.Position = UDim2.fromOffset(ORIGIN + pos.X, ORIGIN + pos.Y)
	node.ZIndex = 5
	node.Parent = self.Canvas
	local shape = node:FindFirstChild("Shape")
	local entry = {
		Id = id, Kind = kind, Pos = pos, Holder = node, Shape = shape,
		Stroke = shape and shape:FindFirstChildWhichIsA("UIStroke"),
		BaseRotation = shape and shape.Rotation or 0, BaseSize = node.Size,
		Hidden = false, Late = false, Revealed = false,
	}
	node:SetAttribute("RevealSize", node.Size)
	node.Visible = false
	self.Nodes[id] = entry
	self:_grow(pos)
	if node:IsA("GuiButton") then
		node.Activated:Connect(function()
			if self.DragMoved then return end
			if onClick then onClick(id) end
		end)
		-- v20.166: наведение - узел плавно подрастает, нажатие - чуть
		-- проседает, ушёл курсор/отпустил палец - возвращается. Отдельный
		-- UIScale, чтобы не спорить с анимациями размера (появление, улучшение).
		local hoverScale = Instance.new("UIScale")
		hoverScale.Name = "HoverScale"
		hoverScale.Parent = node
		local hovered, pressed = false, false
		local function refreshScale()
			local target = pressed and 0.92 or (hovered and 1.15 or 1)
			local style = (hovered and not pressed) and Enum.EasingStyle.Back or Enum.EasingStyle.Quad
			TweenService:Create(hoverScale, TweenInfo.new(pressed and 0.07 or 0.16, style, Enum.EasingDirection.Out), { Scale = target }):Play()
		end
		node.MouseEnter:Connect(function()
			hovered = true
			refreshScale()
		end)
		node.MouseLeave:Connect(function()
			hovered, pressed = false, false
			refreshScale()
		end)
		node.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressed = true
				refreshScale()
			end
		end)
		node.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressed = false
				-- на телефоне наведения нет: после тапа узел возвращается к 1
				if input.UserInputType == Enum.UserInputType.Touch then hovered = false end
				refreshScale()
			end
		end)
	end
	return node, entry
end

-- fromId/toId (необязательно): линия видна, только когда видны оба узла,
-- и вырастает вместе с появлением узла toId.
function SkillTreeView:Link(a, b, color, name, fromId, toId)
	local delta = b - a
	local line = self.Templates:WaitForChild("Link"):Clone()
	line.Name = name or "Link"
	line.Visible = true
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset(ORIGIN + (a.X + b.X) / 2, ORIGIN + (a.Y + b.Y) / 2)
	line.Size = UDim2.fromOffset(delta.Magnitude, line.Size.Y.Offset > 0 and line.Size.Y.Offset or 8)
	line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	line.ZIndex = 3
	if color then line.BackgroundColor3 = color end
	line.Visible = false
	line.Parent = self.Canvas
	table.insert(self.Links, { Line = line, A = a, B = b, Length = delta.Magnitude, From = fromId, To = toId, Shown = false })
	return line
end

-- ПОЯВЛЕНИЕ -------------------------------------------------------------------
-- линия «вырастает» от узла-родителя к новому узлу
function SkillTreeView:_growLink(link, delay)
	local line = link.Line
	local thickness = line.Size.Y.Offset > 0 and line.Size.Y.Offset or 8
	local dir = link.Length > 0 and (link.B - link.A) / link.Length or Vector2.zero
	local value = Instance.new("NumberValue")
	local function place(len)
		local mid = link.A + dir * (len / 2)
		line.Position = UDim2.fromOffset(ORIGIN + mid.X, ORIGIN + mid.Y)
		line.Size = UDim2.fromOffset(len, thickness)
	end
	place(0)
	line.Visible = true
	value.Changed:Connect(place)
	task.delay(delay or 0, function()
		if not line.Parent then value:Destroy() return end
		local tween = TweenService:Create(value, TweenInfo.new(TreeReveal.Settings().LineSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = link.Length })
		tween.Completed:Connect(function() value:Destroy() end)
		tween:Play()
	end)
end

local function nodeShown(self, id)
	if id == nil then return true end
	local entry = self.Nodes[id]
	return entry ~= nil and entry.Revealed
end

-- показать узел (с анимацией - пузырёк + линии к нему вырастают)
function SkillTreeView:_reveal(entry, delay, animate)
	entry.Revealed = true
	for _, link in self.Links do
		if not link.Shown and link.To == entry.Id and nodeShown(self, link.From) then
			link.Shown = true
			if animate then self:_growLink(link, delay) else link.Line.Visible = true end
		end
	end
	if animate then
		TreeReveal.Pop(entry.Holder, (delay or 0) + (TreeReveal.Settings().LineSeconds * 0.6))
	else
		entry.Holder.Size = entry.BaseSize
		entry.Holder.Visible = true
	end
end

function SkillTreeView:_hide(entry)
	entry.Revealed = false
	entry.Holder.Visible = false
	for _, link in self.Links do
		if link.To == entry.Id or link.From == entry.Id then
			link.Shown = false
			link.Line.Visible = false
		end
	end
end

-- привести видимость к желаемой (после Paint); новые узлы - с анимацией
function SkillTreeView:_syncVisibility()
	if self.Sequencing or not self.Gui.Enabled then return end
	local order = {}
	for _, entry in self.Nodes do
		if entry.Hidden and entry.Revealed then
			self:_hide(entry)
		elseif not entry.Hidden and not entry.Revealed then
			table.insert(order, entry)
		end
	end
	table.sort(order, function(a, b) return a.Pos.Magnitude < b.Pos.Magnitude end)
	local s = TreeReveal.Settings()
	for index, entry in order do
		self:_reveal(entry, (index - 1) * s.Stagger * 2, true)
	end
	-- линии между уже видимыми узлами (например, к финалу от второй звезды)
	for _, link in self.Links do
		if not link.Shown and nodeShown(self, link.From) and nodeShown(self, link.To) then
			link.Shown = true
			self:_growLink(link, 0)
		end
	end
end

-- ОТКРЫТИЕ ПО ОЧЕРЕДИ: центр → затемнение → купленные узлы → доступные
function SkillTreeView:_playOpening()
	self.SeqToken += 1
	local token = self.SeqToken
	self.Sequencing = true
	local s = TreeReveal.Settings()
	for _, entry in self.Nodes do
		entry.Revealed = false
		entry.Holder.Visible = false
	end
	for _, link in self.Links do
		link.Shown = false
		link.Line.Visible = false
	end
	if self.Backdrop then TreeReveal.Darken(self.Backdrop, self.BackdropTarget, s.DarkenDelay) end
	local root = self.Nodes.Root
	if root then
		root.Revealed = true
		TreeReveal.Pop(root.Holder, 0, s.RootSeconds)
	end
	local early, late = {}, {}
	for _, entry in self.Nodes do
		if entry ~= root and not entry.Hidden then
			table.insert(entry.Late and late or early, entry)
		end
	end
	local function byDistance(a, b) return a.Pos.Magnitude < b.Pos.Magnitude end
	table.sort(early, byDistance)
	table.sort(late, byDistance)
	local t = s.FirstDelay
	local times = {}
	local function schedule(list)
		for _, entry in list do
			local at = t
			table.insert(times, at)
			task.delay(at, function()
				if self.SeqToken ~= token or not self.Gui.Enabled then return end
				self:_reveal(entry, 0, true)
			end)
			t += s.Stagger
		end
	end
	schedule(early)
	t += s.LateGap
	schedule(late)
	-- кнопки и надписи окна - после бОльшей части веток
	local chrome = { self.Title, self.Money, self.Hint, self.BigClose }
	TreeReveal.Chrome(chrome, TreeReveal.ChromeTime(times, s.FirstDelay) + s.PopSeconds * 0.5, token, function() return self.SeqToken end)
	task.delay(t + s.PopSeconds, function()
		if self.SeqToken ~= token then return end
		self.Sequencing = false
		self:_syncVisibility()
	end)
end

local function setText(holder, name, value)
	if value == nil then return end
	local label = holder:FindFirstChild(name)
	if label and label:IsA("TextLabel") then label.Text = value end
end

-- props: Color, Caption, Price, Level, Name, Icon, Pulse,
--        Hidden (узел ещё не открыт - не показывать), Late (доступен, но не
--        куплен - при открытии появляется последним)
function SkillTreeView:Paint(id, props)
	local entry = self.Nodes[id]
	if not entry then return end
	-- v20.161: пока узел «перерождается» (тряска -> сжатие), новый вид
	-- копится и применяется в момент, когда узел выскакивает обратно.
	if entry.Morphing then
		entry.Pending = entry.Pending or {}
		for k, v in props do entry.Pending[k] = v end
		return
	end
	local prev = entry.State or {}
	local merged = table.clone(prev)
	for k, v in props do merged[k] = v end
	entry.PrevState, entry.State, entry.PaintedAt = prev, merged, os.clock()
	self:_applyPaint(entry, props)
end

-- v20.164: ПОДЛОЖКИ ПО СОСТОЯНИЮ И ВЕТКЕ (Config.TreePlates).
-- props.PlateState: "Owned" (куплено - фон своей ветки props.Branch),
-- "Star" (звезда-улучшение), "Buy" (можно купить), "NoMoney" (не хватает),
-- "Locked" (закрыто), "Prestige" (нужен престиж).
function SkillTreeView:_plateFor(entry, props)
	local state = props.PlateState
	if state == nil then return nil end
	local Config = require(ReplicatedStorage.Shared.Config)
	local plates = Config.TreePlates or {}
	local id
	if state == "Owned" then
		local perGui = plates[self.Gui.Name]
		id = perGui and perGui[props.Branch or ""]
		if (tonumber(id) or 0) == 0 and entry.Kind == "Star" then id = plates.Star end
	else
		id = plates[state]
	end
	id = tonumber(id) or 0
	return id > 0 and ("rbxassetid://" .. id) or nil
end

function SkillTreeView:_setPlate(entry, image)
	local shape = entry.Shape
	if not shape then return end
	if image then
		if not entry.PlateOn then
			-- запоминаем исходный вид шаблона, чтобы вернуть без картинки
			entry.PlateBackup = {
				Image = shape.Image, Rotation = shape.Rotation,
				BackgroundTransparency = shape.BackgroundTransparency, ImageColor3 = shape.ImageColor3,
				ScaleType = shape.ScaleType,
			}
			entry.PlateOn = true
		end
		shape.Image = image
		shape.ImageColor3 = Color3.new(1, 1, 1)
		shape.ImageTransparency = 0
		shape.BackgroundTransparency = 1
		shape.ScaleType = Enum.ScaleType.Fit
		shape.Rotation = 0
		entry.BaseRotation = 0
		for _, d in shape:GetChildren() do
			if d:IsA("UIStroke") or d:IsA("UICorner") or d:IsA("UIGradient") then d.Enabled = false end
		end
	elseif entry.PlateOn and entry.PlateBackup then
		for k, v in entry.PlateBackup do shape[k] = v end
		entry.BaseRotation = entry.PlateBackup.Rotation
		for _, d in shape:GetChildren() do
			if d:IsA("UIStroke") or d:IsA("UICorner") or d:IsA("UIGradient") then d.Enabled = true end
		end
		entry.PlateOn = false
	end
end

function SkillTreeView:_applyPaint(entry, props)
	if props.Hidden ~= nil then entry.Hidden = props.Hidden == true end
	if props.Late ~= nil then entry.Late = props.Late == true end
	local shape = entry.Shape
	-- v20.164: готовая цветная подложка (Config.TreePlates) - ставится как
	-- есть, без перекраски; нет подложки - старое поведение (тинт цветом).
	local plate = self:_plateFor(entry, props)
	if shape and plate then
		self:_setPlate(entry, plate)
	elseif shape and props.Color then
		if entry.PlateOn then self:_setPlate(entry, nil) end
		if shape.Image ~= "" then shape.ImageColor3 = props.Color else shape.BackgroundColor3 = props.Color end
	end
	setText(entry.Holder, "Caption", props.Caption)
	setText(entry.Holder, "Price", props.Price)
	setText(entry.Holder, "Level", props.Level)
	setText(entry.Holder, "Name", props.Name)
	self:_paintIcon(entry, props)
	entry.Pulse = props.Pulse == true
	self:_paintSelection(entry)
	if not self.SyncQueued then
		self.SyncQueued = true
		task.defer(function()
			self.SyncQueued = false
			self:_syncVisibility()
		end)
	end
end

-- v20.160: КАРТИНКА ВМЕСТО ЭМОДЗИ. Порядок поиска:
--   1) Config.TreeIcons[<имя окна>][<id узла>]  - картинка конкретного узла;
--   2) props.Icon - число (ID картинки) или "rbxassetid://..." прямо в конфиге
--      вместо эмодзи (Icon = 123456 у перка/улучшения);
--   3) Config.TreeIcons.ByEmoji[<эмодзи>] - одна картинка на все узлы с этим эмодзи.
-- Картинка встаёт на место надписи Icon (у узлов-тиров - на место Caption),
-- надпись прячется. Нет картинки - эмодзи, как раньше.
local function toImage(value)
	if type(value) == "number" then return value > 0 and ("rbxassetid://" .. value) or nil end
	if type(value) == "string" then
		if value:match("^rbxassetid://") or value:match("^rbxthumb://") then return value end
		local n = tonumber(value)
		if n and n > 0 and #value >= 6 then return "rbxassetid://" .. value end
	end
	return nil
end

function SkillTreeView:_paintIcon(entry, props)
	local Config = require(ReplicatedStorage.Shared.Config)
	local icons = Config.TreeIcons or {}
	local perGui = icons[self.Gui.Name]
	local image = toImage(perGui and perGui[entry.Id])
	if not image and props.Icon ~= nil then
		image = toImage(props.Icon) or toImage((icons.ByEmoji or {})[props.Icon])
	end
	local holder = entry.Holder
	local label = holder:FindFirstChild("Icon")
	if not (label and label:IsA("TextLabel")) then label = nil end
	if image then
		local slot = label or holder:FindFirstChild("Caption")
		local pic = holder:FindFirstChild("IconImage")
		if not pic then
			pic = Instance.new("ImageLabel")
			pic.Name = "IconImage"
			pic.BackgroundTransparency = 1
			pic.ScaleType = Enum.ScaleType.Fit
			if slot and slot:IsA("GuiObject") then
				pic.AnchorPoint = slot.AnchorPoint
				pic.Position = slot.Position
				pic.Size = slot.Size
				pic.ZIndex = slot.ZIndex
			else
				pic.AnchorPoint = Vector2.new(0.5, 0.5)
				pic.Position = UDim2.fromScale(0.5, 0.5)
				pic.Size = UDim2.fromScale(0.6, 0.6)
				pic.ZIndex = 7
			end
			pic.Parent = holder
		end
		pic.Image = image
		pic.Visible = true
		if slot and slot:IsA("TextLabel") then slot.Visible = false end
		entry.IconSlot = slot
	else
		local pic = holder:FindFirstChild("IconImage")
		if pic then pic.Visible = false end
		if entry.IconSlot then entry.IconSlot.Visible = true; entry.IconSlot = nil end
		if label and props.Icon ~= nil then label.Text = tostring(props.Icon) end
	end
end

function SkillTreeView:_paintSelection(entry)
	if entry.Stroke then
		local selected = self.Selected == entry.Id
		entry.Stroke.Color = selected and Color3.new(1, 1, 1) or INK
		entry.Stroke.Thickness = selected and 5 or 3
	end
end

-- v20.148: «улучшил» - узел раздувается и пружинит обратно, линия к нему
-- на миг становится толще (Config.TreeReveal.BumpScale).
-- v20.161: «УЛУЧШИЛ» - узел трясётся, сжимается и выскакивает уже в
-- новом виде (цвет/уровень своей ветки), линия к нему на миг толще.
-- Если новое состояние пришло с сервера раньше клика-анимации, узел на
-- время тряски показывается в прежнем виде.
function SkillTreeView:Bump(id)
	local entry = self.Nodes[id]
	if not (entry and entry.Revealed) or entry.Morphing then return end
	local node = entry.Holder
	local base = entry.BaseSize
	local cfg = require(ReplicatedStorage.Shared.Config).TreeReveal or {}
	local function scaled(k)
		return UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
	end
	-- новый вид уже нарисован (ответ сервера пришёл раньше) - временно вернуть прежний
	if entry.PrevState and entry.PaintedAt and os.clock() - entry.PaintedAt < 1.5 and next(entry.PrevState) then
		local current = entry.State
		self:_applyPaint(entry, entry.PrevState)
		entry.Pending = table.clone(current)
		entry.State = entry.PrevState
	end
	entry.Morphing = true
	local function sfx(name)
		pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
	end
	local token = (entry.MorphToken or 0) + 1
	entry.MorphToken = token
	task.spawn(function()
		local baseRotation = node.Rotation
		-- 1) тряска
		local shakeTime = tonumber(cfg.UpgradeShakeSeconds) or 0.28
		local started = os.clock()
		local ticks = 0
		while os.clock() - started < shakeTime do
			-- v20.162: три щелчка за тряску
			local due = math.floor((os.clock() - started) / shakeTime * 3)
			if due >= ticks and ticks < 3 then
				ticks += 1
				sfx("TreeShakeTick")
			end
			if entry.MorphToken ~= token or not node.Parent then return end
			local t = (os.clock() - started) / shakeTime
			node.Rotation = baseRotation + math.sin(t * math.pi * 10) * 9 * (1 - t * 0.5)
			task.wait()
		end
		node.Rotation = baseRotation
		-- 2) сжатие
		local shrink = TweenService:Create(node, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = scaled(0.15) })
		sfx("TreeShrink")
		shrink:Play()
		shrink.Completed:Wait()
		if entry.MorphToken ~= token then return end
		-- ответ сервера может ещё не прийти - ждём его чуть-чуть в сжатом виде
		local waited = 0
		while not entry.Pending and waited < 0.6 do
			waited += task.wait()
		end
		entry.Morphing = false
		local pending = entry.Pending
		entry.Pending = nil
		if pending then self:Paint(id, pending) end
		-- 3) выскакивает новый
		node.Size = scaled(0.15)
		local k = tonumber(cfg.BumpScale) or 1.35
		local pop = TweenService:Create(node, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = scaled(k) })
		pop.Completed:Connect(function()
			if entry.MorphToken == token then
				TweenService:Create(node, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Size = base }):Play()
			end
		end)
		pop:Play()
		sfx("TreePop")
		task.delay(0.08, sfx, "TreeChime")
		for _, link in self.Links do
			if link.To == id and link.Shown then
				local line = link.Line
				local thick = line.Size.Y.Offset
				line.Size = UDim2.fromOffset(line.Size.X.Offset, thick * 2)
				TweenService:Create(line, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(line.Size.X.Offset, thick) }):Play()
			end
		end
	end)
end

function SkillTreeView:Select(id)
	self.Selected = id
	for _, entry in self.Nodes do self:_paintSelection(entry) end
end

-- пульс узлов, которые можно купить прямо сейчас (вызывать из Heartbeat)
function SkillTreeView:Step(t)
	if not self.Gui.Enabled then return end
	for _, entry in self.Nodes do
		-- v20.164: у картинки-подложки рамки нет - «можно купить» мерцает яркостью
		if entry.PlateOn and entry.Shape then
			local selected = self.Selected == entry.Id
			local k = entry.Pulse and (0.82 + (math.sin(t * 5) + 1) * 0.09) or 1
			if selected then k = 1 end
			entry.Shape.ImageColor3 = Color3.new(k, k, k)
		end
		if entry.Stroke and self.Selected ~= entry.Id and not entry.PlateOn then
			entry.Stroke.Thickness = entry.Pulse and (3 + (math.sin(t * 5) + 1) * 1.5) or 3
			entry.Stroke.Color = entry.Pulse and Color3.fromRGB(110, 255, 140) or INK
		end
	end
end

-- КАРТОЧКА ----------------------------------------------------------------------
function SkillTreeView:_placeCard(id)
	local entry = self.Nodes[id]
	if not entry then return end
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = isPhone() and 0.72 or 0.9
	self.CardScale.Scale = scale
	local size = self.CardSize * scale
	local holder = entry.Holder
	local center = holder.AbsolutePosition + holder.AbsoluteSize / 2
	local x, y
	if isPhone() then
		x, y = (view.X - size.X) / 2, view.Y - size.Y - 90
	else
		x = center.X + holder.AbsoluteSize.X / 2 + 18
		if x + size.X > view.X - 12 then x = center.X - holder.AbsoluteSize.X / 2 - 18 - size.X end
		y = math.clamp(center.Y - size.Y / 2, 70, view.Y - size.Y - 90)
	end
	self.Card.AnchorPoint = Vector2.zero
	self.Card.Size = UDim2.fromOffset(self.CardSize.X, self.CardSize.Y)
	self.Card.Position = UDim2.fromOffset(math.max(8, x), math.max(8, y))
end

local function paintButton(button, variant, text)
	if not button then return end
	if variant then UiKit.SetButtonVariant(button, variant) end
	local caption = button:FindFirstChild("Caption") or button:FindFirstChild("Text")
	if caption and text then caption.Text = text end
end

-- info: Title, Level, Text, Buy = { Text, Variant, OnClick } | nil, More = { Text, OnClick } | nil
function SkillTreeView:ShowCard(id, info)
	self:Select(id)
	setText(self.Card, "Title", info.Title or "")
	setText(self.Card, "Level", info.Level or "")
	setText(self.Card, "Text", info.Text or "")
	local buy, more = self.Card:FindFirstChild("Buy"), self.Card:FindFirstChild("More")
	if buy then
		buy.Visible = info.Buy ~= nil
		if info.Buy then paintButton(buy, info.Buy.Variant or "Green", info.Buy.Text) end
	end
	if more then
		more.Visible = info.More ~= nil
		if info.More then paintButton(more, info.More.Variant, info.More.Text) end
	end
	self.CardBuy = info.Buy and info.Buy.OnClick or nil
	self.CardMore = info.More and info.More.OnClick or nil
	local wasVisible = self.Card.Visible
	self.Card.Visible = true
	self:_placeCard(id)
	if not wasVisible then
		local target = self.CardScale.Scale
		self.CardScale.Scale = target * 0.85
		TweenService:Create(self.CardScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
end

function SkillTreeView:HideCard()
	self.Card.Visible = false
	self.CardBuy, self.CardMore = nil, nil
	self:Select(nil)
end

function SkillTreeView:CardShownFor()
	return self.Card.Visible and self.Selected or nil
end

-- ОТКРЫТЬ / ЗАКРЫТЬ ----------------------------------------------------------------
function SkillTreeView:Open()
	if self.Opened and self.Gui.Enabled then return end
	if isPhone() and self.ZoomValue == 1 then self.ZoomValue = 0.6 end
	self.Pan = Vector2.zero
	self:_applyPan()
	self.Gui.Enabled = true
	self.Opened = true
	self:_playOpening()
	pcall(function() require(ReplicatedStorage.Shared.MovementLock).Lock(self.LockName, 600, self.Gui) end)
end

function SkillTreeView:Close(fromButton)
	if not self.Opened then return end
	self.Opened = false
	self.Gui.Enabled = false
	self.SeqToken += 1
	self.Sequencing = false
	self:HideCard()
	pcall(function() require(ReplicatedStorage.Shared.MovementLock).Unlock(self.LockName) end)
	if fromButton and self.OnClose then self.OnClose() end
end

function SkillTreeView:IsOpen()
	return self.Opened == true and self.Gui.Enabled
end

function SkillTreeView:SetMoney(text)
	if self.Money then self.Money.Text = text or "" end
end

return SkillTreeView
