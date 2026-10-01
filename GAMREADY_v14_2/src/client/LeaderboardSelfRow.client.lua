--------------------------------------------------------------------------------
-- LeaderboardSelfRow (LocalScript) v20.106 — СВОЯ СТРОКА ВНИЗУ ДОСКИ ТОПА.
-- Как на референсе: под топ-10 каждой доски - отдельная доска с ником
-- игрока и его значением. Значения кладёт сервер (LeaderboardService,
-- атрибуты LbValue_<Key>); доска видна только этому игроку.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldUi = require(ReplicatedStorage.Shared.WorldUi)

local player = Players.LocalPlayer
local PLANK = Color3.fromRGB(205, 136, 78)
local WOOD_DARK = Color3.fromRGB(96, 56, 28)

local boards = {}

local function label(parent, text, color, props)
	local l = WorldUi.Text(nil, "Text", "Number")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	for k, v in props do l[k] = v end
	local stroke = l:FindFirstChildWhichIsA("UIStroke") or Instance.new("UIStroke")
	stroke.Enabled = true
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(40, 22, 10)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function ensureRow(gui)
	local background = gui:FindFirstChild("Background")
	if not background then return end
	local row = background:FindFirstChild("YouRow")
	if not row then
		row = Instance.new("Frame")
		row.Name = "YouRow"
		row.AnchorPoint = Vector2.new(0.5, 1)
		row.Position = UDim2.new(0.5, 0, 1, -14)
		row.Size = UDim2.new(1, -32, 0, 84)
		row.BackgroundColor3 = PLANK:Lerp(WOOD_DARK, 0.25)
		row.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = WOOD_DARK
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = row
		row.Parent = background
		label(row, player.Name, Color3.new(1, 1, 1), {
			Name = "NameText", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(0.55, -20, 1, -24),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		label(row, "", Color3.new(1, 1, 1), {
			Name = "ValueText", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 14), Size = UDim2.new(0.45, -20, 1, -28),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	local key = gui:GetAttribute("StatKey")
	local color = gui:GetAttribute("StatColor")
	local value = row:FindFirstChild("ValueText")
	if value then
		value.Text = tostring(player:GetAttribute("LbValue_" .. tostring(key)) or "-")
		if typeof(color) == "Color3" then value.TextColor3 = color end
	end
end

local function track(instance)
	if instance:IsA("SurfaceGui") and instance.Name == "LeaderboardGui" then
		boards[instance] = true
		task.defer(ensureRow, instance)
	end
end
for _, d in workspace:GetDescendants() do track(d) end
workspace.DescendantAdded:Connect(track)

while true do
	task.wait(1)
	for gui in boards do
		if gui.Parent then ensureRow(gui) else boards[gui] = nil end
	end
end
