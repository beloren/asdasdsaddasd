--------------------------------------------------------------------------------
-- LikeBoardGui (v20.122) — БИЛДЕР ТАБЛО ЛАЙКОВ (деревянное, как стенды топов).
-- Одна функция на всех: сервер (LikeGoalService) рисует настоящие цели из
-- Config.LikeGoals, tools/BuildLikeBoard.lua - пример в Studio. Поэтому в
-- Studio видно ровно то же, что в игре.
--
--   LikeBoardGui.Draw(part, goalsCfg, likes, opts)
--     part     - деталь-доска (рисуем на грани opts.Face или Front)
--     goalsCfg - { Title, Subtitle, Goals = { { Likes, Kind, Text, Code, ... } } }
--     likes    - сколько лайков сейчас
--     opts     - { Face, EventActive = function(goal) -> bool }
--
-- Контракт имён (SurfaceGui "LikeGoalGui", CanvasSize 1000x700):
--   Frame "Background" → "Header"(Title), "Subtitle", "Bar"(Fill, Count),
--   "Goal1".."GoalN"(Icon, Likes, Text). Картинки/цвета меняй тут или
--   в Studio через этот модуль - сервер перерисует так же.
--------------------------------------------------------------------------------
local Board = require(script.Parent.LeaderboardBoardGui)
local NumberFormat = require(script.Parent.NumberFormat)

local LikeBoardGui = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local GREEN = Color3.fromRGB(110, 240, 140)
local LOCKED = Color3.fromRGB(215, 205, 190)

local function short(n)
	return NumberFormat.abbreviate(math.floor(tonumber(n) or 0))
end

function LikeBoardGui.Draw(part, goalsCfg, likes, opts)
	opts = opts or {}
	goalsCfg = goalsCfg or {}
	likes = math.max(0, math.floor(tonumber(likes) or 0))
	local old = part:FindFirstChild("LikeGoalGui")
	if old then old:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LikeGoalGui"
	gui.Face = opts.Face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1000, 700)
	gui.LightInfluence = 0
	gui.Parent = part

	local colors = Board.Colors
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = colors.Wood
	background.BorderSizePixel = 0
	background.Parent = gui

	local header = Board.Plank(background, UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 100), colors.WoodDark:Lerp(colors.Wood, 0.4))
	header.Name = "Header"
	local title = Board.Label(header, goalsCfg.Title or "LIKE GOALS", GOLD, { Size = UDim2.new(1, -24, 1, -16), Position = UDim2.fromOffset(12, 8) })
	title.Name = "Title"
	local subtitle = Board.Label(background, (goalsCfg.Subtitle or ""):upper(), Color3.new(1, 1, 1), {
		Position = UDim2.fromOffset(30, 120), Size = UDim2.new(1, -60, 0, 44),
	})
	subtitle.Name = "Subtitle"

	-- Прогресс до следующей цели.
	local nextGoal
	for _, goal in goalsCfg.Goals or {} do
		if likes < (tonumber(goal.Likes) or math.huge) then nextGoal = goal break end
	end
	local target = nextGoal and nextGoal.Likes or math.max(1, likes)
	local bar = Board.Plank(background, UDim2.fromOffset(30, 176), UDim2.new(1, -60, 0, 84), colors.WoodDark)
	bar.Name = "Bar"
	local fill = Board.Plank(bar, UDim2.fromOffset(6, 6), UDim2.new(math.clamp(likes / target, 0.03, 1), -12, 1, -12), GREEN)
	fill.Name = "Fill"
	local count = Board.Label(bar, nextGoal and ("👍 %s / %s"):format(short(likes), short(target))
		or ("👍 %s - ALL GOALS DONE!"):format(short(likes)), Color3.new(1, 1, 1), {
		Size = UDim2.new(1, -24, 1, -16), Position = UDim2.fromOffset(12, 8), ZIndex = 3,
	})
	count.Name = "Count"

	-- Цели.
	local goals = goalsCfg.Goals or {}
	local top, bottom = 280, 690
	local rowH = math.min(96, (bottom - top) / math.max(1, #goals) - 10)
	for index, goal in goals do
		local done = likes >= (tonumber(goal.Likes) or math.huge)
		local row = Board.Plank(background, UDim2.fromOffset(16, top + (index - 1) * (rowH + 10)), UDim2.new(1, -32, 0, rowH),
			done and Color3.fromRGB(120, 170, 90) or colors.Plank)
		row.Name = "Goal" .. index
		local icon = Board.Label(row, done and "✅" or "🔒", Color3.new(1, 1, 1), {
			Position = UDim2.fromOffset(10, 8), Size = UDim2.new(0, rowH - 16, 1, -16),
		})
		icon.Name = "Icon"
		local likesLabel = Board.Label(row, "👍 " .. short(goal.Likes), GOLD, {
			Position = UDim2.fromOffset(rowH, 10), Size = UDim2.new(0, 190, 1, -20),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		likesLabel.Name = "Likes"
		local text = tostring(goal.Text or "")
		if done and goal.Kind == "Code" and goal.Code then
			text = "CODE: " .. tostring(goal.Code)
		elseif done and goal.Kind == "Event" and opts.EventActive then
			text ..= opts.EventActive(goal) and " (ACTIVE!)" or " (ENDED)"
		end
		local textLabel = Board.Label(row, text:upper(), done and Color3.new(1, 1, 1) or LOCKED, {
			Position = UDim2.fromOffset(rowH + 200, 10), Size = UDim2.new(1, -(rowH + 214), 1, -20),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		textLabel.Name = "Text"
	end
	return gui
end

return LikeBoardGui
