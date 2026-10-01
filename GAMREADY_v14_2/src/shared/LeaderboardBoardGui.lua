--------------------------------------------------------------------------------
-- LeaderboardBoardGui (v20.117) — ДЕРЕВЯННАЯ ТАБЛИЦА ТОПА на доске стенда.
-- Одна функция рисования на всех: сервер (LeaderboardService) рисует
-- настоящий топ, tools/BuildLeaderboardStands - пример в Studio, поэтому в
-- Studio видно ровно то же, что в игре.
--
--   LeaderboardBoardGui.Board(part, spec, entries, opts)
--     spec    = { Key, Title, Color, Prefix }
--     entries = { { Name = "Nick", Value = 123 }, ... }   (до 10)
--     opts    = { Format = function(spec, value) -> string, Status = "текст вместо строк", Face }
--   LeaderboardBoardGui.Plate(part, spec, nameText, valueText, face)
--
-- Контракт имён (LeaderboardSelfRow дорисовывает строку игрока):
--   SurfaceGui "LeaderboardGui" (CanvasSize 700x1000) → Frame "Background"
--     → "Header", "Row1".."Row10", (клиент) "YouRow"
--   SurfaceGui "PlateGui" → Frame "Frame" → "NameText", "ValueText"
--------------------------------------------------------------------------------
local WorldUi = require(script.Parent.WorldUi)

local LeaderboardBoardGui = {}

local WOOD = Color3.fromRGB(150, 92, 48)
local WOOD_DARK = Color3.fromRGB(96, 56, 28)
local PLANK = Color3.fromRGB(205, 136, 78)
local OUTLINE = Color3.fromRGB(40, 22, 10)
local RANK_COLORS = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(215, 218, 226), Color3.fromRGB(240, 150, 70) }
LeaderboardBoardGui.Colors = { Wood = WOOD, WoodDark = WOOD_DARK, Plank = PLANK, Outline = OUTLINE }

local function woodLabel(parent, text, color, props)
	local label = WorldUi.Text(nil, "Text", "Number")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	for key, value in props or {} do label[key] = value end
	local stroke = label:FindFirstChildWhichIsA("UIStroke") or Instance.new("UIStroke")
	stroke.Enabled = true
	stroke.Thickness = 3
	stroke.Color = OUTLINE
	stroke.Parent = label
	label.Parent = parent
	return label
end
LeaderboardBoardGui.Label = woodLabel

local function plank(parent, position, size, color)
	local frame = Instance.new("Frame")
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color or PLANK
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = WOOD_DARK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end
LeaderboardBoardGui.Plank = plank

function LeaderboardBoardGui.Board(part, spec, entries, opts)
	opts = opts or {}
	local old = part:FindFirstChild("LeaderboardGui")
	if old then old:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = opts.Face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(700, 1000)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui:SetAttribute("StatKey", spec.Key)
	gui:SetAttribute("StatColor", spec.Color)
	gui.Parent = part

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = WOOD
	background.BorderSizePixel = 0
	background.Parent = gui

	local header = plank(background, UDim2.new(0, 16, 0, 12), UDim2.new(1, -32, 0, 104), WOOD_DARK:Lerp(WOOD, 0.4))
	header.Name = "Header"
	woodLabel(header, spec.Title, spec.Color, { Size = UDim2.new(1, -24, 1, -16), Position = UDim2.fromOffset(12, 8) })

	entries = entries or {}
	local status = opts.Status or (#entries == 0 and "NO PLAYERS YET" or nil)
	if status then
		woodLabel(background, status, Color3.new(1, 1, 1), {
			Position = UDim2.new(0, 30, 0, 300), Size = UDim2.new(1, -60, 0, 80),
		})
		return gui
	end

	local format = opts.Format or function(s, value) return (s.Prefix or "") .. tostring(value) end
	for rank, entry in entries do
		local row = plank(background, UDim2.new(0, 16, 0, 128 + (rank - 1) * 74), UDim2.new(1, -32, 0, 64))
		row.Name = "Row" .. rank
		local badge = plank(row, UDim2.fromOffset(6, 6), UDim2.fromOffset(52, 52), RANK_COLORS[rank] or Color3.fromRGB(245, 245, 245))
		badge.Name = "Rank"
		local badgeText = WorldUi.Text(nil, "Text", "Number")
		badgeText.BackgroundTransparency = 1
		badgeText.Size = UDim2.fromScale(1, 1)
		badgeText.Text = tostring(rank)
		badgeText.TextColor3 = Color3.fromRGB(25, 20, 15)
		badgeText.TextScaled = true
		local badgeStroke = badgeText:FindFirstChildWhichIsA("UIStroke")
		if badgeStroke then badgeStroke.Enabled = false end
		badgeText.Parent = badge
		woodLabel(row, entry.Name, Color3.new(1, 1, 1), {
			Position = UDim2.fromOffset(70, 8), Size = UDim2.new(1, -270, 1, -16),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		woodLabel(row, format(spec, entry.Value), spec.Color, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0, 190, 1, -20),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	return gui
end

-- Табличка «#1 ник / значение» на постаменте - тоже дерево.
function LeaderboardBoardGui.Plate(part, spec, nameText, valueText, face)
	local gui = part:FindFirstChild("PlateGui")
	local frame = gui and gui:FindFirstChild("Frame")
	if not (gui and frame and frame:GetAttribute("Wood")) then
		if gui then gui:Destroy() end
		gui = Instance.new("SurfaceGui")
		gui.Name = "PlateGui"
		gui.Face = face or Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(460, 140)
		gui.LightInfluence = 0
		gui.Parent = part
		frame = plank(gui, UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -8), WOOD)
		frame.Name = "Frame"
		frame:SetAttribute("Wood", true)
		local name = woodLabel(frame, "", Color3.new(1, 1, 1), { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0.55, -6) })
		name.Name = "NameText"
		local value = woodLabel(frame, "", Color3.new(1, 1, 1), { Position = UDim2.new(0, 10, 0.55, 0), Size = UDim2.new(1, -20, 0.45, -8) })
		value.Name = "ValueText"
	end
	frame.NameText.Text = nameText
	frame.ValueText.Text = valueText
	frame.ValueText.TextColor3 = spec.Color
	return gui
end

return LeaderboardBoardGui
