--------------------------------------------------------------------------------
-- BuildMobBillboardTemplates
-- Запусти целиком через Studio Command Bar.
-- Создаёт редактируемые шаблоны экранных BillboardGui в StarterGui.
-- В игре GoblinBillboard.client.lua клонирует их и меняет только данные.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local old = StarterGui:FindFirstChild("MobBillboardTemplates")
if old then old:Destroy() end

local templates = Instance.new("ScreenGui")
templates.Name = "MobBillboardTemplates"
templates.Enabled = false
templates.ResetOnSpawn = false
templates.IgnoreGuiInset = true
templates.DisplayOrder = 19
templates.Parent = StarterGui

local TEMPLATE_PIXELS = Vector2.new(200, 41)
local TEMPLATE_STUDS = Vector2.new(6, 1.23)

local function frame(parent, name, size, position)
	local object = Instance.new("Frame")
	object.Name = name
	object.Size = size
	object.Position = position or UDim2.fromScale(0, 0)
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.Parent = parent
	return object
end

local function text(parent, name, size, position, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position or UDim2.fromScale(0, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 1
	label.AutomaticSize = Enum.AutomaticSize.None
	label.SizeConstraint = Enum.SizeConstraint.RelativeXY
	label.Text = ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Arcade
	label.TextSize = textSize or 14
	label.TextScaled = false
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

local function buildTemplate(name, boulder)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromScale(TEMPLATE_STUDS.X, TEMPLATE_STUDS.Y)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Enabled = false
	gui.Parent = templates

	if boulder then
		local icon = Instance.new("ImageLabel")
		icon.Name = "BoulderIcon"
		icon.Size = UDim2.fromOffset(38, 38)
		icon.Position = UDim2.fromOffset(1, 1)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = Config.Boulders.IconImage or ""
		icon.Parent = gui
		text(icon, "IconPlaceholder", UDim2.fromScale(1, 1), nil, 14).Text = "B"
	else
		local icon = Instance.new("ImageLabel")
		icon.Name = "GoblinIcon"
		icon.Size = UDim2.fromOffset(38, 38)
		icon.Position = UDim2.fromOffset(1, 1)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = gui
		text(icon, "IconPlaceholder", UDim2.fromScale(1, 1), nil, 14).Text = "G"
	end

	local info = frame(gui, "Info", UDim2.fromOffset(156, 38), UDim2.fromOffset(42, 1))
	local title = text(info, "Title", UDim2.new(1, -12, 0, 19), UDim2.fromOffset(6, 1), 14)
	title.RichText = true
	local healthBack = frame(info, "HealthBack", UDim2.new(1, -12, 0, 14), UDim2.new(0, 6, 1, -18))
	healthBack.BackgroundTransparency = 0.15
	healthBack.BackgroundColor3 = Color3.fromRGB(7, 8, 9)
	healthBack.ClipsDescendants = true
	local fill = frame(healthBack, "Fill", UDim2.fromScale(1, 1))
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = Color3.fromRGB(104, 207, 80)
	text(healthBack, "Health", UDim2.fromScale(1, 1), nil, 14)

	-- BillboardGui Scale is measured in studs. Remove every pixel offset so the
	-- complete layout shrinks naturally with distance instead of staying huge.
	local function convertChildrenToScale(parent, parentPixels)
		for _, child in parent:GetChildren() do
			if child:IsA("GuiObject") then
				local oldSize = child.Size
				local oldPosition = child.Position
				local childPixels = Vector2.new(
					parentPixels.X * oldSize.X.Scale + oldSize.X.Offset,
					parentPixels.Y * oldSize.Y.Scale + oldSize.Y.Offset
				)
				child.Size = UDim2.fromScale(
					oldSize.X.Scale + oldSize.X.Offset / parentPixels.X,
					oldSize.Y.Scale + oldSize.Y.Offset / parentPixels.Y
				)
				child.Position = UDim2.fromScale(
					oldPosition.X.Scale + oldPosition.X.Offset / parentPixels.X,
					oldPosition.Y.Scale + oldPosition.Y.Offset / parentPixels.Y
				)
				if child:IsA("TextLabel") then
					local constraint = Instance.new("UITextSizeConstraint")
					constraint.MaxTextSize = child.TextSize
					constraint.MinTextSize = 1
					constraint.Parent = child
					child.TextScaled = true
				end
				convertChildrenToScale(child, childPixels)
			end
		end
	end
	convertChildrenToScale(gui, TEMPLATE_PIXELS)
end

buildTemplate("GoblinTemplate", false)
buildTemplate("BoulderTemplate", true)

print("MobBillboardTemplates created in StarterGui. Edit GoblinTemplate/BoulderTemplate in Studio.")
