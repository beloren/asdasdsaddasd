--------------------------------------------------------------------------------
-- LootBeamFX (LocalScript) — ВСПЫШКА ПОЯВЛЕНИЯ РЕДКОГО ЛУТА (v20.35).
--
-- Раньше над редким кристаллом висел столб света, пока тот лежал. Теперь —
-- ОДИН эффект в момент, когда кусок приземлился (shared/RevealVfx).
--
-- Сервер помечает лут атрибутом LootBeamColor (Color3): редкая руда из
-- валунов (в т.ч. золотого), кристаллы с мутацией. Свой эффект —
-- ReplicatedStorage.Assets (можно в подпапке VFX):
--   Reveal_Mutation      — у руды с мутацией;
--   Reveal_<Редкость>    — Reveal_Rare, Reveal_Epic, Reveal_Legendary, Reveal_Mythic;
--   RevealVFX            — общий для всех.
-- Нет ни одного — встроенный плейсхолдер (сила по редкости).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RevealVfx = require(ReplicatedStorage.Shared.RevealVfx)

local LANDING_DELAY = 0.8 -- кусок вылетает из валуна по дуге — ждём приземления
local played = setmetatable({}, { __mode = "k" })

local function rootOf(instance)
	if instance:IsA("BasePart") then return instance end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("Root", true) or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function reveal(instance)
	if played[instance] then return end
	local color = instance:GetAttribute("LootBeamColor")
	if typeof(color) ~= "Color3" then return end
	played[instance] = true
	task.delay(LANDING_DELAY, function()
		local root = instance.Parent and rootOf(instance)
		if not root then return end
		local rarity = instance:GetAttribute("CrystalRarity")
		local mutations = instance:GetAttribute("CrystalMutations") or instance:GetAttribute("Mutations")
		local names = {}
		if typeof(mutations) == "string" and mutations ~= "" then table.insert(names, "Reveal_Mutation") end
		if typeof(rarity) == "string" then table.insert(names, "Reveal_" .. rarity) end
		table.insert(names, "RevealVFX")
		RevealVfx.Play(names, root.Position, {
			Color = color,
			Power = (typeof(rarity) == "string" and RevealVfx.RarityPower[rarity]) or 4,
		})
	end)
end

local function watch(instance)
	if instance:GetAttribute("LootBeamColor") ~= nil then
		reveal(instance)
	end
end

for _, instance in workspace:GetDescendants() do
	-- Уже лежащий при заходе лут — без вспышки (он появился не сейчас).
	if instance:GetAttribute("LootBeamColor") ~= nil then played[instance] = true end
end
workspace.DescendantAdded:Connect(function(instance)
	task.defer(watch, instance)
end)
