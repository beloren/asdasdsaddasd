--------------------------------------------------------------------------------
-- LikeGoalService (v16) — ТАБЛО ЦЕЛЕЙ ПО ЛАЙКАМ (см. Config.LikeGoals).
--
-- Табло в мире у спавна: прогресс-бар «лайков сейчас / следующая цель» и
-- список целей с ✔/🔒. Достигнутая цель Code показывает промокод, Event
-- включает ивент для всех (GetEventMultiplier читает MonetizationService).
-- Число лайков скрипт прочитать не может — Config.LikeGoals.CurrentLikes
-- обновляется вручную (и игра публикуется заново).
--
-- Своя деталь: Workspace/LikeGoalBoard (Part). SurfaceGui кладётся на её
-- грань Front. Нет детали — ставится плейсхолдер-щит у SpawnLocation.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LikeBoardGui = require(ReplicatedStorage.Shared.LikeBoardGui)

local LikeGoalService = {}
local CFG = Config.LikeGoals or { Goals = {} }

local function parseDate(value)
	if typeof(value) == "number" then return value end
	if typeof(value) ~= "string" then return nil end
	local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then return nil end
	local ok, dateTime = pcall(DateTime.fromUniversalTime, tonumber(year), tonumber(month), tonumber(day), 23, 59, 59)
	return ok and dateTime.UnixTimestamp or nil
end

local function likes()
	return math.max(0, math.floor(tonumber(CFG.CurrentLikes) or 0))
end

local function reached(goal)
	return likes() >= (tonumber(goal.Likes) or math.huge)
end

local function eventActive(goal)
	if not (CFG.Enabled and goal.Kind == "Event" and reached(goal)) then return false end
	local endsAt = parseDate(goal.EndsAt)
	return endsAt == nil or os.time() <= endsAt
end

-- Множитель активного ивента данного вида (Money / Luck). 1 — ивента нет.
function LikeGoalService:GetEventMultiplier(eventKind)
	local multiplier = 1
	for _, goal in CFG.Goals or {} do
		if goal.Event == eventKind and eventActive(goal) then
			multiplier = math.max(multiplier, tonumber(goal.Multiplier) or 1)
		end
	end
	return multiplier
end

--------------------------------------------------------------------------------
-- ТАБЛО
--------------------------------------------------------------------------------
local function findBoardPart()
	local part = workspace:FindFirstChild("LikeGoalBoard", true)
	if part and part:IsA("BasePart") then return part end
	local board = part and part:IsA("Model") and part:FindFirstChild("Board", true)
	if board and board:IsA("BasePart") then return board end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local base = spawn and spawn.CFrame or CFrame.new(0, 0, 0)
	part = Instance.new("Part")
	part.Name = "LikeGoalBoard"
	part.Anchored = true
	part.Size = Vector3.new(12, 9, 0.6)
	part.Color = Color3.fromRGB(40, 36, 52)
	part.Material = Enum.Material.SmoothPlastic
	-- Рядом со спавном, лицом (Front) к нему.
	local position = base.Position + base.RightVector * 14 + Vector3.new(0, 5.5, 0)
	part.CFrame = CFrame.lookAt(position, Vector3.new(base.Position.X, position.Y, base.Position.Z))
	part.Parent = workspace
	return part
end

-- v20.122: табло рисует общий билдер Shared.LikeBoardGui (дерево, как топы) -
-- tools/BuildLikeBoard.lua показывает в Studio ровно то же.
function LikeGoalService:_buildBoard()
	local part = findBoardPart()
	-- своя модель-стенд из tools/BuildLikeBoard: доска - деталь "Board" внутри
	if part:IsA("Model") then part = part:FindFirstChild("Board", true) or part end
	LikeBoardGui.Draw(part, CFG, likes(), { EventActive = eventActive })
end

function LikeGoalService:Init(_services) end

function LikeGoalService:Start()
	if not CFG.Enabled then return end
	local ok, err = pcall(function() self:_buildBoard() end)
	if not ok then warn("[LikeGoalService] Табло не построено:", err) end
	-- Ивенты с EndsAt гаснут сами — раз в минуту перерисовываем табло.
	task.spawn(function()
		while true do
			task.wait(60)
			pcall(function() self:_buildBoard() end)
		end
	end)
	-- Атрибуты активных ивентов (для HUD и отладки).
	for _, goal in CFG.Goals or {} do
		if eventActive(goal) then
			workspace:SetAttribute("LikeEvent_" .. tostring(goal.Event), tonumber(goal.Multiplier) or 2)
		end
	end
end

return LikeGoalService
