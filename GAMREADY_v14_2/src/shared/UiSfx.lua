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
	sound.SoundGroup = group
	sound.Parent = group or SoundService
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
end

return UiSfx
