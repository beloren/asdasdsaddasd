--------------------------------------------------------------------------------
-- ShiftLock (Script) v19.3 — СТАНДАРТНЫЙ ROBLOX SHIFT LOCK НА SHIFT.
--
-- Включает штатный Shift Lock всем игрокам, даже если в StarterPlayer
-- галочка EnableMouseLockOption выключена (Player.DevEnableMouseLock
-- перекрывает её для конкретного игрока).
--
-- Пока игрок держит тележку, Shift Lock временно выключается: поворотом с
-- тележкой рулит сервер (CartService), и шифтлок начинал бы с ним драться.
-- Отпустил тележку — Shift Lock снова доступен. Не нужно — поставь
-- DISABLE_WHILE_CARRYING_CART = false.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local DISABLE_WHILE_CARRYING_CART = true

pcall(function() StarterPlayer.EnableMouseLockOption = true end)

local function refresh(player)
	local carrying = player:GetAttribute("CarryingCart") == true
	player.DevEnableMouseLock = not (DISABLE_WHILE_CARRYING_CART and carrying)
end

local function setup(player)
	refresh(player)
	player:GetAttributeChangedSignal("CarryingCart"):Connect(function() refresh(player) end)
end

for _, player in Players:GetPlayers() do setup(player) end
Players.PlayerAdded:Connect(setup)
