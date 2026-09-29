--------------------------------------------------------------------------------
-- v20.96: ТЕКСТУРА СТАДОВ на всех плейсхолдер-предметах (зелья, амулеты,
-- мусор, тотемы, декор, реликвии, сундуки). Одна настройка на всю игру -
-- Config.StudTexture: вставь свой ID картинки стада, и он появится на
-- каждой грани (Texture "StudTexture"), кроме нижней. Пока ID = 0, объекты
-- Texture уже висят, но пустые (видны классические поверхности Studs).
-- Config.StudTexture.Enabled = false - не вешать вовсе.
-- Свои модели из ReplicatedStorage.Assets не трогаются.
--------------------------------------------------------------------------------
local Config = require(script.Parent.Config)

local StudTexture = {}

local function textureId()
	local cfg = Config.StudTexture
	if not cfg or cfg.Enabled == false then return nil end
	local id = cfg.Id
	if not id or id == 0 or id == "" or id == "0" or id == "rbxassetid://0" then return "" end
	id = tostring(id)
	return id:match("^rbxassetid://") and id or "rbxassetid://" .. id
end

-- Повесить текстуры на одну деталь (невидимые/неоновые/стеклянные пропускаем).
function StudTexture.ApplyPart(part)
	local id = textureId()
	if id == nil or not part:IsA("BasePart") then return end
	if part.Transparency >= 0.9 or part.Material == Enum.Material.Neon or part.Material == Enum.Material.Glass then return end
	if part:IsA("Part") and part.Shape ~= Enum.PartType.Block then return end
	if part:FindFirstChild("StudTexture") then return end
	local cfg = Config.StudTexture
	for _, face in cfg.Faces or { "Top", "Front", "Back", "Left", "Right" } do
		local texture = Instance.new("Texture")
		texture.Name = "StudTexture"
		texture.Texture = id
		texture.Face = Enum.NormalId[face]
		texture.StudsPerTileU = cfg.StudsPerTile or 1
		texture.StudsPerTileV = cfg.StudsPerTile or 1
		texture.Transparency = cfg.Transparency or 0
		texture.Color3 = cfg.Color or Color3.new(1, 1, 1)
		texture.Parent = part
	end
end

-- Повесить на все детали модели.
function StudTexture.Apply(model)
	if not model or not textureId() then return model end
	if model:IsA("BasePart") then StudTexture.ApplyPart(model) end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then StudTexture.ApplyPart(d) end
	end
	return model
end

return StudTexture
