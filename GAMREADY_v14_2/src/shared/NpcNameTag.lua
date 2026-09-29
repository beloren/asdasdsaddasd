--------------------------------------------------------------------------------
-- v20.97: ПОДПИСЬ НАД НПС в едином стиле (как у мэра престижа и прокачки):
-- BillboardGui "gui" с TextLabel "name" + "arrow" (+ скрытый "dialog") -
-- вид накладывает клиент (NpcNameStyle). Стандартное имя Humanoid (Roblox
-- пишет над головой ИМЯ МОДЕЛИ) скрывается у всех НПС.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi)

local NpcNameTag = {}

-- Не показывать имя модели над головой (у всех Humanoid внутри модели).
function NpcNameTag.HideHumanoidNames(npc)
	for _, d in npc:GetDescendants() do
		if d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.NameDisplayDistance = 0
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	local own = npc:FindFirstChildOfClass("Humanoid")
	if own then
		own.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function headOf(npc)
	local head = npc:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then return head end
	return npc.PrimaryPart
end

-- Подпись над головой: к голове, над её верхним краем (клиент покачивает
-- StudsOffset вокруг 1.55, как у остальных НПС).
function NpcNameTag.PinToHead(npc, gui)
	local head = headOf(npc)
	if not (head and gui) then return end
	gui.Adornee = head
	gui.ExtentsOffset = Vector3.zero
	gui.ExtentsOffsetWorldSpace = head.Name == "Head" and Vector3.new(0, 1, 0) or Vector3.zero
	gui.StudsOffsetWorldSpace = Vector3.zero
	gui.StudsOffset = Vector3.new(0, 1.55, 0)
end

-- Есть своя подпись (любой BillboardGui с текстом) - не трогаем, только
-- прячем имя Humanoid. Нет - ставим стандартную с текстом text.
function NpcNameTag.Ensure(npc, text)
	NpcNameTag.HideHumanoidNames(npc)
	local gui = npc:FindFirstChild("gui", true)
	if gui and gui:IsA("BillboardGui") and gui:FindFirstChild("name", true) then return gui end
	for _, d in npc:GetDescendants() do
		if d:IsA("BillboardGui") and d:FindFirstChildWhichIsA("TextLabel", true) then return d end
	end
	local head = headOf(npc)
	if not head then return nil end
	local size = (Config.NpcBillboard and Config.NpcBillboard.UpgradeShopNPC) or { SizeWidth = 240, SizeHeight = 90 }
	gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.new(0, size.SizeWidth, 0, size.SizeHeight)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Parent = head
	NpcNameTag.PinToHead(npc, gui)
	local function label(name, labelSize, position)
		local t = WorldUi.Text(nil, "Text", "Heading")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Size = labelSize
		t.Position = position
		t.TextSize = 30
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextWrapped = true
		t.Text = ""
		t.Parent = gui
		return t
	end
	label("name", UDim2.new(1, 0, 0.4, 0), UDim2.new()).Text = string.upper(text or "")
	label("arrow", UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.4, 0)) -- шеврон рисует клиент (NpcNameStyle)
	label("dialog", UDim2.new(1, 0, 1, 0), UDim2.new()).Visible = false
	return gui
end

return NpcNameTag
