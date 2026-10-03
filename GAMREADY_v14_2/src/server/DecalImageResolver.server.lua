--------------------------------------------------------------------------------
-- DecalImageResolver (v20.169) — ДЕКАЛЬ -> КАРТИНКА.
--
-- Часть ID в Config (Config.DecalAssets) - это ДЕКАЛИ (тип 13), а не
-- картинки (тип 1). В Studio, если вставить ID декали в поле Image, Studio
-- сама подменяет его на ID картинки, а скрипт так не умеет: по
-- rbxassetid://<декаль> ImageLabel пустой.
--
-- Здесь сервер при старте открывает каждую декаль (InsertService:LoadAsset -
-- разрешено для ассетов владельца игры), достаёт из неё настоящий ID
-- картинки и кладёт в ReplicatedStorage.ImageIdMap атрибутом
-- [<ID декали>] = <ID картинки>. Config.ImageUri на клиенте и сервере
-- берёт ID оттуда. В Output печатается готовый список: впиши его в
-- Config.ImageIdOverrides, и игре больше не нужно ничего вычислять.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local map = ReplicatedStorage:FindFirstChild("ImageIdMap")
if not map then
	map = Instance.new("Folder")
	map.Name = "ImageIdMap"
	map.Parent = ReplicatedStorage
end

local function imageIdFromDecal(decalId)
	local ok, model = pcall(InsertService.LoadAsset, InsertService, decalId)
	if not ok or not model then return nil, model end
	local found = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Decal") or d:IsA("Texture") then
			found = tonumber(tostring(d.Texture):match("(%d+)%s*$"))
			if found then break end
		end
	end
	model:Destroy()
	return found
end

local lines = {}
local pending = 0
for decalId in Config.DecalAssets or {} do
	local overrides = Config.ImageIdOverrides or {}
	if not overrides[decalId] then
		pending += 1
		task.spawn(function()
			local imageId, err = imageIdFromDecal(decalId)
			if imageId then
				map:SetAttribute(tostring(decalId), imageId)
				table.insert(lines, ("\t[%d] = %d,"):format(decalId, imageId))
			else
				warn("[DecalImageResolver] не удалось открыть декаль " .. decalId .. ": " .. tostring(err))
			end
			pending -= 1
			if pending == 0 and #lines > 0 then
				table.sort(lines)
				print("[DecalImageResolver] Настоящие ID картинок. Скопируй в Config.ImageIdOverrides:\n" .. table.concat(lines, "\n"))
			end
		end)
	end
end
