local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundVariation = require(ReplicatedStorage.Shared.SoundVariation)
local UiSfx = {}

function UiSfx.play(name)
	local soundName = name or "UiButtonClick"
	local definition = Config.Sounds[soundName]
	local soundId = SoundVariation.Select(soundName, definition)
	if not soundId then return end
	local group = SoundService:FindFirstChild("SFX")
	local sound = Instance.new("Sound")
	sound.Name = "Local_" .. soundName
	sound.SoundId = soundId
	sound.Volume = definition.Volume or 0.5
	-- v20.129: высота тона (Pitch) и случайный разброс (PitchJitter) - один
	-- сэмпл звучит по-разному для разных действий и не надоедает
	local pitch = tonumber(definition.Pitch) or 1
	local jitter = tonumber(definition.PitchJitter) or 0
	if jitter > 0 then pitch *= 1 + (math.random() * 2 - 1) * jitter end
	sound.PlaybackSpeed = pitch
	sound.SoundGroup = group
	sound.Parent = group or SoundService
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
end

return UiSfx
