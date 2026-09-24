--------------------------------------------------------------------------------
-- HudIconBounce
-- Применяет IconBounce (см. src/shared/IconBounce.lua) к иконкам в HUD —
-- монетке (MoneyPill), ребёрту (RebirthPill), кирке в хотбаре
-- (HotbarUi/PickaxeSlot, который становится щитом при переноске тележки).
-- Каждая иконка прыгает и
-- увеличивается на свою случайную паузу — не синхронно, чтобы не выглядело
-- как единый механический тик.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IconBounce = require(ReplicatedStorage.Shared.IconBounce)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hud = playerGui:WaitForChild("Hud", 5)
if hud then
	local moneyPill = hud:FindFirstChild("MoneyPill", true)
	local rebirthPill = hud:FindFirstChild("RebirthPill", true)
	local moneyIcon = moneyPill and moneyPill:FindFirstChild("Icon", true)
	local rebirthIcon = rebirthPill and rebirthPill:FindFirstChild("Icon", true)
	if moneyIcon then IconBounce.Apply(moneyIcon) end
	if rebirthIcon then IconBounce.Apply(rebirthIcon) end
end

local hotbar = playerGui:WaitForChild("HotbarUi", 5)
if hotbar then
	local slot = hotbar:FindFirstChild("PickaxeSlot", true)
	local slotIcon = slot and slot:FindFirstChild("Preview", true)
	if slotIcon then IconBounce.Apply(slotIcon) end
end
