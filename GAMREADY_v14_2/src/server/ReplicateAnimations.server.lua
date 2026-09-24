local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local saves = ServerStorage:WaitForChild("MoonAnimator2Saves")

local replicatedSaves = ReplicatedStorage:FindFirstChild("MoonAnimator2Saves")
if not replicatedSaves then
    replicatedSaves = Instance.new("Folder")
    replicatedSaves.Name = "MoonAnimator2Saves"
    replicatedSaves.Parent = ReplicatedStorage

    for _, animation in saves:GetChildren() do
        if animation:IsA("StringValue") then
            animation:Clone().Parent = replicatedSaves
        end
    end
end
