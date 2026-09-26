--------------------------------------------------------------------------------
-- HarvestMobileLayout
-- Запускай ПОСЛЕ того, как подвигал плейсхолдеры из
-- tools/BuildMobileLayoutEditor.lua туда, куда хочешь. Печатает готовый
-- Lua-код в Output — скопируй его целиком и вставь в Config.lua вместо
-- текущего "Config.MobileLayout = {}".
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")

local editor = StarterGui:FindFirstChild("MobileLayoutEditor")
if not editor then
	warn("[HarvestMobileLayout] StarterGui.MobileLayoutEditor не найден - сначала запусти BuildMobileLayoutEditor.lua.")
	return
end

local function formatUDim2(value)
	return ("UDim2.new(%g, %d, %g, %d)"):format(value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
end

local function formatVector2(value)
	return ("Vector2.new(%g, %g)"):format(value.X, value.Y)
end

local lines = { "Config.MobileLayout = {" }
for _, child in editor:GetChildren() do
	if child:IsA("Frame") and child.Name ~= "Instructions" then
		table.insert(lines, ("\t%s = { AnchorPoint = %s, Position = %s, Size = %s },"):format(
			child.Name,
			formatVector2(child.AnchorPoint),
			formatUDim2(child.Position),
			formatUDim2(child.Size)
		))
	end
end
table.insert(lines, "}")

local result = table.concat(lines, "\n")
print("[HarvestMobileLayout] Скопируй всё между линиями ниже и вставь в Config.lua:")
print("--------------------------------------------------------------------------------")
print(result)
print("--------------------------------------------------------------------------------")
