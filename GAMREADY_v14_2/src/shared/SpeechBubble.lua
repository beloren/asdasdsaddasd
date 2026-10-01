--------------------------------------------------------------------------------
-- SpeechBubble (v20.114) — реплика над головой персонажа, как на скамейке
-- («bruh...»): выскакивает с пружинкой, печатается по букве, висит и гаснет.
-- Только клиент. Вид и тайминги по умолчанию - Config.BenchChatter.
--   SpeechBubble.Say(character, "what happened..?", { Offset = 5, Hold = 2 })
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Config)
local WorldUi = require(script.Parent.WorldUi)

local SpeechBubble = {}
local tokens = setmetatable({}, { __mode = "k" })

function SpeechBubble.Clear(character, name)
	local head = character and character:FindFirstChild("Head")
	local old = head and head:FindFirstChild(name or "SpeechBubble")
	if old then old:Destroy() end
end

function SpeechBubble.Say(character, text, opts)
	opts = opts or {}
	local cfg = Config.BenchChatter or {}
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local name = opts.Name or "SpeechBubble"
	SpeechBubble.Clear(character, name)
	local token = (tokens[character] or 0) + 1
	tokens[character] = token

	local width = opts.Width or cfg.WidthStuds or 9
	local height = opts.Height or cfg.HeightStuds or 1.5
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = head
	gui.Size = UDim2.new(width * 0.6, 0, height * 0.6, 0)
	gui.StudsOffset = Vector3.new(0, opts.Offset or cfg.HeightOffset or 2.4, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = opts.AlwaysOnTop == true
	gui.MaxDistance = cfg.MaxDistance or 70
	gui.ResetOnSpawn = false
	gui.Parent = head

	local label = WorldUi.Text(gui, "Line", "Heading")
	label.TextScaled = true
	label.TextColor3 = opts.Color or cfg.TextColor or Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.MaxVisibleGraphemes = 0

	TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(width, 0, height, 0),
	}):Play()

	task.spawn(function()
		local count = utf8.len(text) or #text
		local perChar = opts.SecondsPerLetter or cfg.SecondsPerLetter or 0.06
		for i = 1, count do
			if tokens[character] ~= token or not gui.Parent then return end
			label.MaxVisibleGraphemes = i
			local char = utf8.char(utf8.codepoint(text, utf8.offset(text, i)))
			task.wait((char == "." or char == "," or char == "!" or char == "?") and perChar * 3 or perChar)
		end
		label.MaxVisibleGraphemes = -1
		task.wait(opts.Hold or cfg.HoldSeconds or 4)
		if tokens[character] ~= token or not gui.Parent then return end
		local fade = TweenInfo.new(0.4)
		TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		for _, stroke in label:GetDescendants() do
			if stroke:IsA("UIStroke") then TweenService:Create(stroke, fade, { Transparency = 1 }):Play() end
		end
		task.wait(0.4)
		if gui.Parent then gui:Destroy() end
	end)
	return gui
end

return SpeechBubble
