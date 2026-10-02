--------------------------------------------------------------------------------
-- OnboardingAnalyticsService (v20.150) — АНАЛИТИКА ОБУЧЕНИЯ И УДЕРЖАНИЯ.
-- Всё уходит в Roblox Analytics (Creator Hub → твоя игра → Analytics):
--
--  • Onboarding (Funnels → Onboarding): каждый шаг основного обучения
--    1..N + шаг «Complete». Видно, на каком шаге отваливается больше всего.
--  • Funnels → Tutorial_<Глава>: то же для каждой главы (острова, престиж...).
--  • Custom events (Custom → Events), value - секунды:
--      TutorialStepTime   сколько игрок провёл на шаге до выполнения
--                         (Field01 = шаг, Field02 = глава/Main)
--      TutorialStepStuck  игрок висит на шаге дольше StuckSeconds (раз на шаг)
--      TutorialSkipped    нажал SKIP (Field01 = шаг)
--      TutorialQuit       ВЫШЕЛ ИЗ ИГРЫ ВО ВРЕМЯ ОБУЧЕНИЯ: value = секунды на
--                         шаге, Field01 = шаг, Field02 = ПРИЧИНА, Field03 = фаза
--      SessionEnd         выход любого игрока: value = длина сессии,
--                         Field01 = стадия (Tutorial:..., Chapter:..., Free),
--                         Field02 = причина, Field03 = пещера (Cave N)
--      HintShown / HintDone  короткие подсказки механик (Field01 = подсказка)
--  ПРИЧИНЫ (Field02):
--      Idle       не двигался дольше IdleSeconds перед выходом (AFK/ушёл)
--      Stuck      провёл на одном шаге дольше StuckSeconds (не понял, что делать)
--      Minigame   вышел во время мини-игры шахты
--      EarlyLeave вся сессия короче EarlySeconds (не зацепило с первых минут)
--      Quit       обычный выход
-- Настройки - Config.Analytics.
--------------------------------------------------------------------------------
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local OnboardingAnalyticsService = {}
local Services
local records = {} -- [player] = { JoinedAt, LastMoveAt, LastPos, Step = {...} }

local function cfg()
	return Config.Analytics or {}
end
local function enabled()
	return cfg().Enabled ~= false
end

local function fields(a, b, c)
	local out = {}
	local keys = Enum.AnalyticsCustomFieldKeys
	if a ~= nil then out[keys.CustomField01.Name] = tostring(a) end
	if b ~= nil then out[keys.CustomField02.Name] = tostring(b) end
	if c ~= nil then out[keys.CustomField03.Name] = tostring(c) end
	return out
end

local function custom(player, name, value, a, b, c)
	if not enabled() then return end
	local ok, err = pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, name, value or 1, fields(a, b, c))
	if not ok and cfg().Debug then warn("[OnboardingAnalytics] " .. name .. ": " .. tostring(err)) end
	if cfg().Debug then print(("[OnboardingAnalytics] %s %s value=%s %s/%s/%s"):format(player.Name, name, tostring(value), tostring(a), tostring(b), tostring(c))) end
end

local function stepKey(chapter, index, stepId)
	return ("%s:%d:%s"):format(chapter or "Main", index or 0, tostring(stepId or "?"))
end

local function record(player)
	local r = records[player]
	if not r then
		r = { JoinedAt = os.clock(), LastMoveAt = os.clock() }
		records[player] = r
	end
	return r
end

-- ВХОД В ШАГ ---------------------------------------------------------------------
function OnboardingAnalyticsService:StepEntered(player, chapter, index, stepId, count, phase)
	local r = record(player)
	local key = stepKey(chapter, index, stepId)
	if r.Step and r.Step.Key == key then
		r.Step.Phase = phase or r.Step.Phase
		return
	end
	r.Step = { Key = key, Chapter = chapter, Index = index, Id = stepId, EnteredAt = os.clock(), Phase = phase, StuckLogged = false }
	if not enabled() then return end
	local data = Services.DataService:GetGeodeData(player)
	if chapter == nil then
		-- воронка онбординга: каждый шаг - один раз за жизнь профиля
		local logged = data and tonumber(data.AnalyticsOnboardingStep) or 0
		if index > logged then
			pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, index, tostring(stepId))
			if data then data.AnalyticsOnboardingStep = index end
		end
	else
		local logged = data and type(data.AnalyticsChapterSteps) == "table" and tonumber(data.AnalyticsChapterSteps[chapter]) or 0
		if index > logged then
			pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, player, "Tutorial_" .. chapter,
				tostring(player.UserId) .. "_" .. chapter, index, tostring(stepId))
			if data then
				if type(data.AnalyticsChapterSteps) ~= "table" then data.AnalyticsChapterSteps = {} end
				data.AnalyticsChapterSteps[chapter] = index
			end
		end
	end
end

function OnboardingAnalyticsService:PhaseChanged(player, phase)
	local r = records[player]
	if r and r.Step then r.Step.Phase = phase end
end

-- ШАГ ВЫПОЛНЕН --------------------------------------------------------------------
function OnboardingAnalyticsService:StepFinished(player)
	local r = records[player]
	local step = r and r.Step
	if not step then return end
	custom(player, "TutorialStepTime", math.floor(os.clock() - step.EnteredAt + 0.5), step.Key, step.Chapter or "Main")
end

function OnboardingAnalyticsService:Skipped(player)
	local r = records[player]
	local step = r and r.Step
	custom(player, "TutorialSkipped", step and math.floor(os.clock() - step.EnteredAt + 0.5) or 0, step and step.Key or "?", step and step.Chapter or "Main")
	if r then r.Step = nil end
end

-- ОБУЧЕНИЕ / ГЛАВА ЗАКОНЧЕНЫ ------------------------------------------------------
function OnboardingAnalyticsService:Completed(player, chapter, count, rewarded)
	local r = records[player]
	if r then r.Step = nil end
	if not enabled() then return end
	local data = Services.DataService:GetGeodeData(player)
	local finalStep = (tonumber(count) or 0) + 1
	if chapter == nil then
		local logged = data and tonumber(data.AnalyticsOnboardingStep) or 0
		if finalStep > logged then
			pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, finalStep, rewarded and "Complete" or "Skipped")
			if data then data.AnalyticsOnboardingStep = finalStep end
		end
	else
		pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, player, "Tutorial_" .. chapter,
			tostring(player.UserId) .. "_" .. chapter, finalStep, rewarded and "Complete" or "Skipped")
	end
	custom(player, "TutorialCompleted", math.floor(os.clock() - (r and r.JoinedAt or os.clock())), chapter or "Main", rewarded and "Complete" or "Skipped")
end

function OnboardingAnalyticsService:Hint(player, event, hintId)
	custom(player, event, 1, hintId)
end

-- ПРИЧИНА УХОДА -------------------------------------------------------------------
local function reasonFor(player, r)
	local now = os.clock()
	local c = cfg()
	if player:GetAttribute("MineExpeditionActive") == true then return "Minigame" end
	if now - (r.LastMoveAt or now) > (c.IdleSeconds or 45) then return "Idle" end
	if r.Step and now - r.Step.EnteredAt > (c.StuckSeconds or 150) then return "Stuck" end
	if now - r.JoinedAt < (c.EarlySeconds or 120) then return "EarlyLeave" end
	return "Quit"
end

function OnboardingAnalyticsService:Init(services)
	Services = services
end

function OnboardingAnalyticsService:Start()
	-- движение игрока (для «Idle») и «застрял на шаге»
	task.spawn(function()
		while true do
			task.wait(2)
			for player, r in records do
				if player.Parent then
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then
						if not r.LastPos or (root.Position - r.LastPos).Magnitude > 2 then
							r.LastMoveAt = os.clock()
						end
						r.LastPos = root.Position
					end
					local step = r.Step
					if step and not step.StuckLogged and os.clock() - step.EnteredAt > (cfg().StuckSeconds or 150) then
						step.StuckLogged = true
						custom(player, "TutorialStepStuck", math.floor(os.clock() - step.EnteredAt), step.Key, step.Chapter or "Main", step.Phase)
					end
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player) record(player) end)
	for _, player in Players:GetPlayers() do record(player) end
	Players.PlayerRemoving:Connect(function(player)
		local r = records[player]
		records[player] = nil
		if not r then return end
		local reason = reasonFor(player, r)
		local session = math.floor(os.clock() - r.JoinedAt + 0.5)
		local stage = "Free"
		if r.Step then
			stage = (r.Step.Chapter and ("Chapter:" .. r.Step.Chapter) or "Tutorial") .. ":" .. r.Step.Key
			custom(player, "TutorialQuit", math.floor(os.clock() - r.Step.EnteredAt + 0.5), r.Step.Key, reason, r.Step.Phase or "?")
		end
		local cave = player:GetAttribute("MineTier")
		custom(player, "SessionEnd", session, stage, reason, "Cave " .. tostring(cave or "?"))
	end)
end

return OnboardingAnalyticsService
