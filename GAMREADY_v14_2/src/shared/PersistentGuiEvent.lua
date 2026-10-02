--------------------------------------------------------------------------------
-- PersistentGuiEvent (v20.138) — BindableEvent в PlayerGui, который ПЕРЕЖИВАЕТ
-- респавн. При смерти Roblox чистит PlayerGui: остаются только ScreenGui/
-- BillboardGui с ResetOnSpawn = false, а Folder/BindableEvent удаляются - и
-- кнопки, которые через них открывали окна, переставали работать.
--   PersistentGuiEvent.Listen("OpenDropPreview", function(...) end)
-- Событие пересоздаётся после каждого респавна, обработчик подключается снова.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")

local PersistentGuiEvent = {}

function PersistentGuiEvent.Listen(name, handler)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local current
	local function ensure()
		if current and current.Parent == playerGui then return end
		local existing = playerGui:FindFirstChild(name)
		if not (existing and existing:IsA("BindableEvent")) then
			existing = Instance.new("BindableEvent")
			existing.Name = name
			existing.Parent = playerGui
		end
		current = existing
		current.Event:Connect(handler)
	end
	ensure()
	player.CharacterAdded:Connect(function()
		task.defer(ensure)
		task.delay(1, ensure)
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			ensure()
		end
	end)
end

return PersistentGuiEvent
