--------------------------------------------------------------------------------
-- PromptWatchdog (LocalScript) v20.104 — ПРОМПТЫ НЕ ПРОПАДАЮТ НАВСЕГДА.
-- Несколько катсцен (апгрейд, острова, шахта) выключают все промпты через
-- ProximityPromptService.Enabled и потом возвращают сохранённое значение.
-- Если сцены наложились (или оборвались - например, игрока с тележкой
-- выбросило физикой), одна из них могла «вернуть» уже выключенное состояние,
-- и промпты (сундук, НПС, тележка) оставались невидимыми до перезахода.
-- Сторож: промпты выключены дольше MAX_OFF секунд, а игрок не в шахте и не
-- в апгрейде - включаем обратно. После респавна - тоже.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local MAX_OFF = 15

local offSince = nil

local function busy()
	return player:GetAttribute("MineExpeditionActive") == true
		or player:GetAttribute("UpgradeInProgress") == true
		or player:GetAttribute("CutsceneActive") == true
end

player.CharacterAdded:Connect(function()
	task.wait(1)
	if not busy() then ProximityPromptService.Enabled = true end
end)

-- v20.139: жёсткий предел - даже если флаг «занят» завис (сцена оборвалась),
-- дольше HARD_MAX секунд промпты выключенными не остаются
local HARD_MAX = 60
local hardSince = nil

while true do
	task.wait(1)
	if ProximityPromptService.Enabled then
		offSince = nil
		hardSince = nil
	elseif busy() and player:GetAttribute("MineExpeditionActive") ~= true and os.clock() - (hardSince or os.clock()) >= HARD_MAX then
		ProximityPromptService.Enabled = true
		hardSince = nil
		offSince = nil
	elseif busy() then
		hardSince = hardSince or os.clock()
		offSince = os.clock()
	else
		offSince = offSince or os.clock()
		if os.clock() - offSince >= MAX_OFF then
			ProximityPromptService.Enabled = true
			offSince = nil
		end
	end
end
