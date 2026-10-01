--------------------------------------------------------------------------------
-- WorldRays (v20.118) — КРУТЯЩИЕСЯ ЛУЧИ РЕДКОСТИ в мире (только клиент):
-- та же картинка лучей, что за карточками (UiKit.Backdrop), на BillboardGui
-- чуть позади точки (от камеры). Открытие сундука, разлом валуна и т.п.
--   WorldRays.Play(position, rarity, { Color, Size, Seconds, Lift })
--------------------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local WorldRays = {}

local SIZE_BY_RARITY = { Common = 9, Uncommon = 10, Rare = 11, Epic = 13, Legendary = 15, Mythic = 17 }

function WorldRays.Play(position, rarity, opts)
	opts = opts or {}
	if typeof(position) ~= "Vector3" then return end
	local ok, err = pcall(function()
		local UiKit = require(script.Parent.UiKit)
		local camera = workspace.CurrentCamera
		local away = camera and (position - camera.CFrame.Position) * Vector3.new(1, 0, 1) or Vector3.zero
		away = away.Magnitude > 0.1 and away.Unit or Vector3.zero
		local anchor = Instance.new("Part")
		anchor.Name = "WorldRays"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(position + Vector3.new(0, opts.Lift or 1.6, 0) + away * (opts.Behind or 2))
		anchor.Parent = workspace.CurrentCamera or workspace
		local board = Instance.new("BillboardGui")
		board.Adornee = anchor
		board.LightInfluence = 0
		board.Size = UDim2.fromScale(1, 1)
		board.MaxDistance = 220
		board.Parent = anchor
		local rays = UiKit.Backdrop(board, "Rays", rarity or "Rare", {
			Size = UDim2.fromScale(1, 1), Color = opts.Color, Transparency = 0.1,
		})
		UiKit.Spin(rays, opts.Spin or 45)
		local size = opts.Size or SIZE_BY_RARITY[rarity or ""] or 11
		TweenService:Create(board, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(size, size),
		}):Play()
		local seconds = opts.Seconds or 1.6
		task.delay(seconds, function()
			TweenService:Create(rays, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
		end)
		Debris:AddItem(anchor, seconds + 0.7)
	end)
	if not ok then warn("[WorldRays]", err) end
end

return WorldRays
