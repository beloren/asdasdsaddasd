--------------------------------------------------------------------------------
-- AssetPreloader (LocalScript) v20.106 — ЗАГРУЗКА АССЕТОВ ПОСЛЕ КАТСЦЕНЫ.
-- Катсцена при входе грузит только своё (звук, логотип - MoonAnimationTest)
-- и стартует сразу. Всё остальное (модели и эффекты ReplicatedStorage.Assets,
-- картинки интерфейса, звуки) догружается здесь, когда катсцена кончилась
-- (атрибут IntroActive снят) - небольшими порциями, без подвисаний.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local BATCH = 40

local CONTENT = {
	Decal = true, Texture = true, MeshPart = true, SpecialMesh = true, Sound = true, Animation = true,
	ImageLabel = true, ImageButton = true, ParticleEmitter = true, Beam = true, Trail = true, SurfaceAppearance = true,
}

-- Ждём конца катсцены (не больше 60 с - на случай, если её нет).
local waited = 0
task.wait(1)
while player:GetAttribute("IntroActive") == true and waited < 60 do
	task.wait(0.5)
	waited += 0.5
end

local queue = {}
local function collect(root)
	if not root then return end
	for _, d in root:GetDescendants() do
		if CONTENT[d.ClassName] then table.insert(queue, d) end
	end
end
collect(ReplicatedStorage:FindFirstChild("Assets"))
collect(player:FindFirstChild("PlayerGui"))
collect(SoundService)

for index = 1, #queue, BATCH do
	local batch = table.move(queue, index, math.min(index + BATCH - 1, #queue), 1, {})
	pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
	task.wait(0.05)
end
