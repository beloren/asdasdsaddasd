local SoundVariation = {}

local random = Random.new()
local lastByName = {}

local function validId(id)
	return typeof(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

function SoundVariation.Select(name, definition)
	if not definition then return nil end
	local choices = {}
	local seen = {}
	local function add(id)
		if validId(id) and not seen[id] then
			seen[id] = true
			table.insert(choices, id)
		end
	end
	add(definition.Id)
	for _, id in definition.Variants or {} do add(id) end
	if #choices == 0 then return nil end
	if #choices > 1 and lastByName[name] then
		for index = #choices, 1, -1 do
			if choices[index] == lastByName[name] then table.remove(choices, index) end
		end
	end
	local selected = choices[random:NextInteger(1, #choices)]
	lastByName[name] = selected
	return selected
end

function SoundVariation.Canonical(definition)
	return definition and validId(definition.Id) and definition.Id or nil
end

return SoundVariation
