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
	self.Nodes = {}
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
	}
	self.Nodes[id] = entry
	self:_grow(pos)
	if node:IsA("GuiButton") then
		node.Activated:Connect(function()
			if self.DragMoved then return end
			if onClick then onClick(id) end
		end)
		node.MouseEnter:Connect(function()
			TweenService:Create(node, TweenInfo.new(0.1), { Size = UDim2.fromOffset(entry.BaseSize.X.Offset * 1.08, entry.BaseSize.Y.Offset * 1.08) }):Play()
		end)
		node.MouseLeave:Connect(function()
			TweenService:Create(node, TweenInfo.new(0.1), { Size = entry.BaseSize }):Play()
		end)
	end
	return node, entry
end

function SkillTreeView:Link(a, b, color, name)
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
	line.Parent = self.Canvas
	return line
end

local function setText(holder, name, value)
	if value == nil then return end
	local label = holder:FindFirstChild(name)
	if label and label:IsA("TextLabel") then label.Text = value end
end

-- props: Color, Caption, Price, Level, Name, Icon, Selected, Pulse
function SkillTreeView:Paint(id, props)
	local entry = self.Nodes[id]
	if not entry then return end
	local shape = entry.Shape
	if shape and props.Color then
		if shape.Image ~= "" then shape.ImageColor3 = props.Color else shape.BackgroundColor3 = props.Color end
	end
	setText(entry.Holder, "Caption", props.Caption)
	setText(entry.Holder, "Price", props.Price)
	setText(entry.Holder, "Level", props.Level)
	setText(entry.Holder, "Name", props.Name)
	setText(entry.Holder, "Icon", props.Icon)
	entry.Pulse = props.Pulse == true
	self:_paintSelection(entry)
end

function SkillTreeView:_paintSelection(entry)
	if entry.Stroke then
		local selected = self.Selected == entry.Id
		entry.Stroke.Color = selected and Color3.new(1, 1, 1) or INK
		entry.Stroke.Thickness = selected and 5 or 3
	end
end

function SkillTreeView:Select(id)
	self.Selected = id
	for _, entry in self.Nodes do self:_paintSelection(entry) end
end

-- пульс узлов, которые можно купить прямо сейчас (вызывать из Heartbeat)
function SkillTreeView:Step(t)
	if not self.Gui.Enabled then return end
	for _, entry in self.Nodes do
		if entry.Stroke and self.Selected ~= entry.Id then
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
	if self.Gui.Enabled then return end
	if isPhone() and self.ZoomValue == 1 then self.ZoomValue = 0.6 end
	self.Pan = Vector2.zero
	self:_applyPan()
	self.Gui.Enabled = true
	pcall(function() require(ReplicatedStorage.Shared.MovementLock).Lock(self.LockName, 600) end)
end

function SkillTreeView:Close(fromButton)
	if not self.Gui.Enabled then return end
	self.Gui.Enabled = false
	self:HideCard()
	pcall(function() require(ReplicatedStorage.Shared.MovementLock).Unlock(self.LockName) end)
	if fromButton and self.OnClose then self.OnClose() end
end

function SkillTreeView:IsOpen()
	return self.Gui.Enabled
end

function SkillTreeView:SetMoney(text)
	if self.Money then self.Money.Text = text or "" end
end

return SkillTreeView
