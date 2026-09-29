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

-- v20.98: ОТПУСКАЕМ ВСЁ, ЧТО ДЕРЖИТСЯ НА СУСТАВАХ. Раньше отпускались
-- только детали на Motor6D - а ручки аксессуаров (шляпы, волосы), сохранённые
-- заякоренными, через AccessoryWeld держали ГОЛОВУ на месте: тело шевелилось,
-- голова нет. Теперь обходим все соединения (Motor6D, Weld, AccessoryWeld,
-- WeldConstraint) от корня: всё, что к нему прицеплено, не заякорено и
-- невесомо; заякорен только корень.
local function freeJoints(model, host)
	local root = model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
	if not root then return end
	local links = {}
	local function link(a, b)
		if not (a and b) then return end
		links[a] = links[a] or {}
		links[b] = links[b] or {}
		table.insert(links[a], b)
		table.insert(links[b], a)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("RigidConstraint") then
			if d:IsA("RigidConstraint") then
				link(d.Attachment0 and d.Attachment0.Parent, d.Attachment1 and d.Attachment1.Parent)
			else
				link(d.Part0, d.Part1)
			end
		end
	end
	local seen, queue = { [root] = true }, { root }
	while #queue > 0 do
		local part = table.remove(queue)
		for _, other in links[part] or {} do
			if not seen[other] and other:IsA("BasePart") and other:IsDescendantOf(model) then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	for part in seen do
		if part ~= root then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
		end
	end
	root.Anchored = true
	if host:IsA("Humanoid") then
		host.WalkSpeed = 0
		host.JumpPower = 0
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
