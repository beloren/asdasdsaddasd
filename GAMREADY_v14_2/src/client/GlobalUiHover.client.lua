--------------------------------------------------------------------------------
-- Единый hover-эффект для всех кнопок интерфейса. Новые кнопки, созданные
-- другими LocalScript во время игры, подключаются через DescendantAdded.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

if not UserInputService.MouseEnabled then return end

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local bound = setmetatable({}, { __mode = "k" })
local activeTweens = setmetatable({}, { __mode = "k" })

local HOVER_SCALE = 1.06
local HOVER_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function isTechnicalButton(button)
	if button:GetAttribute("DisableGlobalHover") == true then return true end
	local name = button.Name:lower()
	return name == "dimmer"
		or name:find("backdrop", 1, true) ~= nil
		or name:find("clickcatcher", 1, true) ~= nil
		or name:find("touchtarget", 1, true) ~= nil
		or name:find("tapcatcher", 1, true) ~= nil
end

local function tweenScale(scale, target)
	local previous = activeTweens[scale]
	if previous then previous:Cancel() end
	local tween = TweenService:Create(scale, HOVER_TWEEN, { Scale = target })
	activeTweens[scale] = tween
	tween:Play()
	tween.Completed:Connect(function()
		if activeTweens[scale] == tween then activeTweens[scale] = nil end
	end)
end

local function bind(button)
	if bound[button] or not button:IsA("GuiButton") or isTechnicalButton(button) then return end
	bound[button] = true

	local scale = button:FindFirstChild("GlobalHoverScale")
	if not (scale and scale:IsA("UIScale")) then
		scale = Instance.new("UIScale")
		scale.Name = "GlobalHoverScale"
		scale.Scale = 1
		scale.Parent = button
	end

	button.MouseEnter:Connect(function()
		if button.Visible and button.Active then tweenScale(scale, HOVER_SCALE) end
	end)
	button.MouseLeave:Connect(function()
		tweenScale(scale, 1)
	end)
	button.Destroying:Connect(function()
		local tween = activeTweens[scale]
		if tween then tween:Cancel() end
		activeTweens[scale] = nil
	end)
end

for _, descendant in playerGui:GetDescendants() do bind(descendant) end
playerGui.DescendantAdded:Connect(bind)
