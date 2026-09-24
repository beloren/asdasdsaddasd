--------------------------------------------------------------------------------
-- Sfx
-- Единая точка воспроизведения звуков. Все айдишники — в Config.Sounds.
-- Sound создаётся сервером внутри BasePart → 3D-звук слышат все рядом.
-- Все звуки идут через один SoundGroup "SFX" (SoundService) — клиент
-- (меню настроек, src/client) может локально приглушить звук, просто
-- поменяв SoundGroup.Volume у себя — серверный Instance от этого не
-- меняется, другие игроки ничего не замечают.
--------------------------------------------------------------------------------

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundVariation = require(ReplicatedStorage.Shared.SoundVariation)

local Sfx = {}

local sfxGroup = SoundService:FindFirstChild("SFX")
if not sfxGroup then
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFX"
	sfxGroup.Parent = SoundService
end

-- name — ключ из Config.Sounds, parent — BasePart (точка звука в мире)
function Sfx.play(name, parent)
	local entry = Config.Sounds[name]
	if parent and parent:IsA("Model") then
		parent = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
	end
	if not entry or not parent or not parent.Parent then
		return
	end
	local soundId = SoundVariation.Select(name, entry)
	if not soundId then return end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = entry.Volume or 0.5
	sound.RollOffMaxDistance = 140
	sound.SoundGroup = sfxGroup
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 6)
end

-- Зацикленный звук для длительных состояний (например "тележку реально
-- везут") — в отличие от Sfx.play, НЕ самоуничтожается через Debris и не
-- запускается сразу: возвращает Sound с Looped=true, Playing=false,
-- вызывающий код сам включает/выключает через .Playing.
function Sfx.createLoop(name, parent)
	local entry = Config.Sounds[name]
	if parent and parent:IsA("Model") then
		parent = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
	end
	if not entry or not parent then
		return nil
	end
	local soundId = SoundVariation.Canonical(entry)
	if not soundId then return nil end
	local sound = Instance.new("Sound")
	sound.Name = name .. "Loop"
	sound.SoundId = soundId
	sound.Volume = entry.Volume or 0.5
	sound.Looped = true
	sound.RollOffMinDistance = entry.RollOffMinDistance or 10
	sound.RollOffMaxDistance = entry.RollOffMaxDistance or 140
	sound.SoundGroup = sfxGroup
	sound.Parent = parent
	return sound
end

return Sfx
