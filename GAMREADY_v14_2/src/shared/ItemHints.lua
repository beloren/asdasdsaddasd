--------------------------------------------------------------------------------
-- ItemHints (v20.5) — короткая подсказка «что это и как пользоваться» для
-- любого предмета в руке (кроме руды): название, что делает, как применить.
-- Показывает GearHud.client.lua плашкой GearUi/AimHint над хотбаром.
--
--   ItemHints.For(heldKey) → { Title, Color, What, How } или nil
--   ItemHints.Pickaxe(tier) → то же для кирки
-- Тексты — английские (перевод через Localization на клиенте).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PlaceableCatalog = require(ReplicatedStorage.Shared.PlaceableCatalog)

local ItemHints = {}

local WHITE = Color3.new(1, 1, 1)

-- Свои тексты можно задать в Config.ItemHints[key] = { What = "...", How = "..." }.
local function override(key, hint)
	local custom = Config.ItemHints and Config.ItemHints[key]
	if type(custom) == "table" then
		hint.What = custom.What or hint.What
		hint.How = custom.How or hint.How
		hint.Title = custom.Title or hint.Title
	end
	return hint
end

local function minutes(seconds)
	seconds = tonumber(seconds) or 0
	if seconds >= 60 then return ("%d min"):format(math.floor(seconds / 60 + 0.5)) end
	return ("%d sec"):format(seconds)
end

function ItemHints.For(key)
	if typeof(key) ~= "string" or key == "" then return nil end

	-- Динамит — коротко (по запросу).
	local dynamite = Config.Dynamite and Config.Dynamite.Types[key]
	if dynamite then
		return override(key, {
			Title = dynamite.DisplayName, Color = dynamite.Color or WHITE,
			What = "Blasts boulders and knocks players",
			How = "Click to throw · click a boulder to plant",
		})
	end

	local chestRarity = key:match("^Chest_(%a+)$")
	if chestRarity then
		local chest = Config.Chests and Config.Chests.Types[chestRarity]
		return override(key, {
			Title = (chest and chest.DisplayName) or (chestRarity .. " Chest"), Color = (chest and chest.Color) or WHITE,
			What = "Opens after a timer with loot inside",
			How = "Click the ground of your base to place",
		})
	end

	local potion = Config.Potions and Config.Potions.Types[key]
	if potion then
		return override(key, {
			Title = potion.DisplayName, Color = potion.Color or WHITE,
			What = ("Temporary boost for %s"):format(minutes(potion.Seconds)),
			How = "Click to drink",
		})
	end

	local mutationId = key:match("^Essence_(%a+)$")
	if mutationId and Config.Mutations[mutationId] then
		local mutation = Config.Mutations[mutationId]
		return override(key, {
			Title = (mutation.DisplayName or mutationId) .. " Essence", Color = mutation.Color or WHITE,
			What = ("Adds %s to a crystal on your podium"):format(mutation.DisplayName or mutationId),
			How = "Go to your podium and press APPLY ESSENCE",
		})
	end

	local relicId = key:match("^Relic:([%w]+):")
	if relicId then
		local relic = Config.Relics and Config.Relics.Types[relicId]
		if relic then
			return override(key, {
				Title = relic.DisplayName, Color = relic.Color or WHITE,
				What = ("Trophy: +%d%% sell income while placed"):format(math.floor((relic.IncomeBonus or 0) * 100 + 0.5)),
				How = "Click your base to place · R to rotate",
			})
		end
	end

	local placeable = PlaceableCatalog.Info(key)
	if placeable then
		local what = placeable.Kind == "Totem" and PlaceableCatalog.EffectText(placeable) or "Decoration for your base"
		return override(key, {
			Title = placeable.DisplayName, Color = placeable.TierColor or placeable.Color or WHITE,
			What = what,
			How = "Click your base to place · R to rotate",
		})
	end

	if key == ((Config.CartPackage and Config.CartPackage.GearKey) or "CartPackage") then
		return override(key, {
			Title = "Cart Package", Color = Color3.fromRGB(120, 210, 255),
			What = "Your mining cart, still packed",
			How = "Click the ground at your base to unpack it",
		})
	end
	return nil
end

function ItemHints.Pickaxe(tier)
	local info = Config.PickaxeTiers and Config.PickaxeTiers[tonumber(tier) or 1]
	return override("Pickaxe", {
		Title = (info and info.DisplayName) or ("Pickaxe T" .. tostring(tier or 1)),
		Color = (info and info.VfxColor) or Color3.fromRGB(255, 215, 90),
		What = "Breaks boulders, hits players and carts",
		How = "Click to swing",
	})
end

return ItemHints
