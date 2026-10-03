--------------------------------------------------------------------------------
-- ResolveDecalIds (v20.169) — Studio → View → Command Bar → вставить → Enter.
--
-- Для каждого ID из Config.DecalAssets (это ДЕКАЛИ, а не картинки) находит
-- настоящий ID картинки и печатает готовый блок. Скопируй его из Output в
-- Config.ImageIdOverrides (src/shared/Config.lua) или просто скинь в чат.
-- То же самое делает сервер при каждом запуске игры (DecalImageResolver),
-- этот скрипт - чтобы вписать ID навсегда.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local Config = require(ReplicatedStorage.Shared.Config:Clone())

local out, failed = {}, {}
for decalId in Config.DecalAssets do
	local ok, model = pcall(InsertService.LoadAsset, InsertService, decalId)
	local imageId
	if ok and model then
		for _, d in model:GetDescendants() do
			if d:IsA("Decal") or d:IsA("Texture") then
				imageId = tonumber(tostring(d.Texture):match("(%d+)%s*$"))
				if imageId then break end
			end
		end
		model:Destroy()
	end
	if imageId then
		table.insert(out, ("\t[%d] = %d,"):format(decalId, imageId))
	else
		table.insert(failed, tostring(decalId))
	end
end
table.sort(out)
print("Config.ImageIdOverrides = {\n" .. table.concat(out, "\n") .. "\n}")
if #failed > 0 then warn("Не удалось открыть: " .. table.concat(failed, ", ")) end
