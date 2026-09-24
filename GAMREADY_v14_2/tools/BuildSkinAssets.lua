-- Standalone Studio builder for replaceable example skin models.
-- Replaces only assets listed below in ReplicatedStorage/Assets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local OWNED = {
	"Skin_Pickaxe_BigWooden", "Skin_Pickaxe_Crystal", "Skin_Pickaxe_Love", "Skin_Pickaxe_Radioactive", "Skin_Pickaxe_VoidFixed",
	"Skin_Cart_Miner", "Skin_Cart_Royal", "Skin_Cart_Industrial", "Skin_Cart_Frost", "Skin_Cart_Obsidian",
	"Skin_Pickaxe_Amethyst", "Skin_Pickaxe_CactusSword", "Skin_Pickaxe_Fish", "Skin_Pickaxe_TungTungStick", "Skin_Pickaxe_BigMole", "Skin_Pickaxe_DevSword",
	"Skin_Pickaxe_GoldSword", "Skin_Pickaxe_GoldKunai",
	"Skin_Cart_Amber", "Skin_Cart_Topaz", "Skin_Cart_Jade", "Skin_Cart_Onyx", "Skin_Cart_Aurora", "Skin_Cart_Nebula",
}
for _, name in OWNED do
	local old = Assets:FindFirstChild(name)
	if old then old:Destroy() end
end

local function part(name, size, color, cframe, material, transparency)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = color
	item.CFrame = cframe
	item.Material = material or Enum.Material.SmoothPlastic
	item.Transparency = transparency or 0
	item.Anchored = true
	item.CanCollide = false
	return item
end

local function pickaxe(name, color, glow)
	local model = Instance.new("Model")
	model.Name = name
	local root = part("SkinRoot", Vector3.new(0.2, 0.2, 0.2), color, CFrame.new(), nil, 1)
	root.Parent = model
	model.PrimaryPart = root
	part("Shaft", Vector3.new(0.36, 3.8, 0.36), color, CFrame.new(0, 1.5, 0), Enum.Material.Wood).Parent = model
	part("Head", Vector3.new(3.2, 0.5, 0.65), glow, CFrame.new(0, 3.25, 0), Enum.Material.Neon).Parent = model
	model.Parent = Assets
end

local function cart(name, bodyColor, trimColor)
	local model = Instance.new("Model")
	model.Name = name
	local root = part("SkinRoot", Vector3.new(0.2, 0.2, 0.2), bodyColor, CFrame.new(), nil, 1)
	root.Parent = model
	model.PrimaryPart = root
	part("Body", Vector3.new(7.5, 0.7, 5.5), bodyColor, CFrame.new(0, 0.15, 0), Enum.Material.Metal).Parent = model
	for _, z in { -2.6, 2.6 } do part("Trim", Vector3.new(7.8, 1.7, 0.35), trimColor, CFrame.new(0, 1, z), Enum.Material.Neon).Parent = model end
	for _, x in { -3.6, 3.6 } do part("Trim", Vector3.new(0.35, 1.7, 5.3), trimColor, CFrame.new(x, 1, 0), Enum.Material.Neon).Parent = model end
	model.Parent = Assets
end

pickaxe("Skin_Pickaxe_BigWooden", Color3.fromRGB(85, 45, 25), Color3.fromRGB(255, 95, 35))
pickaxe("Skin_Pickaxe_Crystal", Color3.fromRGB(35, 65, 95), Color3.fromRGB(90, 225, 255))
pickaxe("Skin_Pickaxe_Love", Color3.fromRGB(120, 170, 205), Color3.fromRGB(190, 245, 255))
pickaxe("Skin_Pickaxe_Radioactive", Color3.fromRGB(45, 75, 38), Color3.fromRGB(125, 255, 80))
pickaxe("Skin_Pickaxe_VoidFixed", Color3.fromRGB(28, 20, 42), Color3.fromRGB(185, 75, 255))
cart("Skin_Cart_Miner", Color3.fromRGB(75, 70, 62), Color3.fromRGB(255, 175, 55))
cart("Skin_Cart_Royal", Color3.fromRGB(65, 35, 105), Color3.fromRGB(255, 215, 70))
cart("Skin_Cart_Industrial", Color3.fromRGB(65, 75, 82), Color3.fromRGB(110, 225, 135))
cart("Skin_Cart_Frost", Color3.fromRGB(70, 130, 165), Color3.fromRGB(190, 245, 255))
cart("Skin_Cart_Obsidian", Color3.fromRGB(30, 28, 38), Color3.fromRGB(220, 80, 255))

-- Новые скины, привязанные к 6 новым типам жеод (см. Config.Skins.Definitions).
pickaxe("Skin_Pickaxe_Amethyst", Color3.fromRGB(90, 55, 20), Color3.fromRGB(255, 165, 60))
pickaxe("Skin_Pickaxe_CactusSword", Color3.fromRGB(20, 70, 68), Color3.fromRGB(60, 220, 210))
pickaxe("Skin_Pickaxe_Fish", Color3.fromRGB(25, 70, 48), Color3.fromRGB(70, 220, 140))
pickaxe("Skin_Pickaxe_TungTungStick", Color3.fromRGB(24, 20, 30), Color3.fromRGB(150, 100, 220))
pickaxe("Skin_Pickaxe_BigMole", Color3.fromRGB(70, 35, 70), Color3.fromRGB(255, 140, 220))
pickaxe("Skin_Pickaxe_DevSword", Color3.fromRGB(35, 15, 55), Color3.fromRGB(190, 90, 255))
pickaxe("Skin_Pickaxe_GoldSword", Color3.fromRGB(120, 75, 15), Color3.fromRGB(255, 220, 70))
pickaxe("Skin_Pickaxe_GoldKunai", Color3.fromRGB(95, 60, 15), Color3.fromRGB(255, 235, 90))
cart("Skin_Cart_Amber", Color3.fromRGB(90, 60, 30), Color3.fromRGB(255, 165, 60))
cart("Skin_Cart_Topaz", Color3.fromRGB(25, 80, 78), Color3.fromRGB(60, 220, 210))
cart("Skin_Cart_Jade", Color3.fromRGB(28, 78, 52), Color3.fromRGB(70, 220, 140))
cart("Skin_Cart_Onyx", Color3.fromRGB(26, 22, 34), Color3.fromRGB(150, 100, 220))
cart("Skin_Cart_Aurora", Color3.fromRGB(75, 40, 78), Color3.fromRGB(255, 140, 220))
cart("Skin_Cart_Nebula", Color3.fromRGB(38, 18, 60), Color3.fromRGB(190, 90, 255))

print("[BuildSkinAssets] 24 replaceable example skin models created in ReplicatedStorage/Assets.")
