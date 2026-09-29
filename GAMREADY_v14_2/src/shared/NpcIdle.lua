--------------------------------------------------------------------------------
-- v20.96: ПОСТОЯННАЯ СТОЙКА НПС (Config.NpcIdleAnimations[key]).
-- В модель НПС (и в плейсхолдер, и в твою) кладётся Animation "IdleAnimation"
-- с этим ID. Если в модели есть Humanoid или AnimationController - стойка
-- крутится по кругу всё время. У плейсхолдера (кубики без скелета) анимации
-- нет - заменишь его своей моделью-ригом, и стойка заиграет сама.
-- Своя Animation "IdleAnimation" внутри твоей модели главнее конфига.
--------------------------------------------------------------------------------
local Config = require(script.Parent.Config)

local NpcIdle = {}

local function uri(id)
	if not id or id == 0 or id == "" or id == "0" or id == "rbxassetid://0" then return nil end
	id = tostring(id)
	return id:match("^rbxassetid://") and id or "rbxassetid://" .. id
end

-- Детали на суставах отпускаем (иначе Animator их не сдвинет), корень держим.
local function freeJoints(model, host)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local jointed = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			if d.Part1 then jointed[d.Part1] = true end
		end
	end
	for part in jointed do
		if part ~= root and part:IsDescendantOf(model) then part.Anchored = false end
	end
	if root then root.Anchored = true end
	local humanoid = host:IsA("Humanoid") and host or nil
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
end

-- key - имя в Config.NpcIdleAnimations. Возвращает трек или nil.
function NpcIdle.Play(model, key)
	if not model then return nil end
	local anim = model:FindFirstChild("IdleAnimation")
	if not (anim and anim:IsA("Animation") and anim.AnimationId ~= "") then
		local id = uri(Config.NpcIdleAnimations and Config.NpcIdleAnimations[key])
		if not id then return nil end
		anim = Instance.new("Animation")
		anim.Name = "IdleAnimation"
		anim.AnimationId = id
		anim.Parent = model
	end
	local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildWhichIsA("Humanoid", true) or model:FindFirstChildWhichIsA("AnimationController", true)
	if not host then return nil end
	local ok, track = pcall(function()
		freeJoints(model, host)
		local animator = host:FindFirstChildOfClass("Animator") or Instance.new("Animator", host)
		local loaded = animator:LoadAnimation(anim)
		loaded.Looped = true
		loaded.Priority = Enum.AnimationPriority.Idle
		loaded:Play(0.2)
		return loaded
	end)
	return ok and track or nil
end

return NpcIdle
