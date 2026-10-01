--------------------------------------------------------------------------------
-- OreUnlockFx (v20.109) — открыл коробку руды: карточка
-- «NEW ORE APPEARED IN THE MINE!» (RevealCards) + искры на игроке.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local remote = ReplicatedStorage.Shared:WaitForChild("OreUnlockFx", 30)
if not remote then return end

remote.OnClientEvent:Connect(function(action, payload)
	if action ~= "Unlocked" or typeof(payload) ~= "table" then return end
	local ore = Config.OreByKey[payload.Ore]
	if not ore then return end
	local rarity = payload.Rarity or "Common"
	local ok, RevealCards = pcall(require, ReplicatedStorage.Shared.RevealCards)
	if ok and RevealCards then
		pcall(RevealCards.Show, { {
			Kind = "Ore", OreId = payload.Ore, Variant = 2, Rarity = rarity,
			Title = ore.DisplayName,
			MutationNames = ("NEXT DIG: x%d GUARANTEED!"):format(payload.Guaranteed or 3),
		} }, { Title = "NEW ORE APPEARED IN THE MINE!", Color = Config.RarityColors[rarity] or ore.Color })
	end
	local okVfx, AssetVfx = pcall(require, ReplicatedStorage.Shared.AssetVfx)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if okVfx and AssetVfx and root then
		pcall(AssetVfx.AttachTo, "Sparkles", root, { Color = ore.Color, Duration = 3 })
	end
end)
