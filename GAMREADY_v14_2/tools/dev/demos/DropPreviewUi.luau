return function(gui, shared, require)
	local panel = gui.Panel
	local templates = panel.Templates
	local rarities = { { "COMMON", Color3.fromRGB(200, 200, 200), "60%", "1 in 2" }, { "RARE", Color3.fromRGB(80, 160, 255), "25%", "1 in 4" },
		{ "EPIC", Color3.fromRGB(180, 90, 255), "10%", "1 in 10" }, { "LEGENDARY", Color3.fromRGB(255, 200, 60), "4%", "1 in 25" }, { "MYTHIC", Color3.fromRGB(255, 70, 90), "1%", "1 in 100" } }
	for i, r in rarities do
		local row = templates.RowTemplate:Clone()
		row.LayoutOrder = i
		row.Title.Text = ({ "STONE", "AMETHYST", "RUBY", "GOLD NUGGET", "VOID CRYSTAL" })[i]
		row.Rarity.Text = r[1]; row.Rarity.TextColor3 = r[2]
		row.Chance.Text = r[3]; row.OneIn.Text = r[4]
		row.Bar.BackgroundColor3 = r[2]
		row.SkinStroke.Color = r[2]:Lerp(Color3.new(0, 0, 0), 0.35)
		row.Track.Fill.Size = UDim2.fromScale(1 - i * 0.17, 1)
		if i == 5 then row.Select.Enabled = true; row.Select.Color = r[2] end
		row.Parent = panel.Rows
	end
	for i, name in { "STONE", "IRON", "GOLD", "DIAMOND", "VOID" } do
		local chip = templates.ChipTemplate:Clone()
		chip.LayoutOrder = i
		chip.Caption.Text = name
		chip.Parent = panel.Types
	end
	panel.TitleBar.Title.Text = "STONE GEODE DROPS"
	panel.Detail.Rarity.Text = "MYTHIC"; panel.Detail.Rarity.TextColor3 = Color3.fromRGB(255, 70, 90)
	panel.Detail.ItemName.Text = "VOID CRYSTAL"
	panel.Detail.Chance.Text = "1%  ·  1 in 100"
	panel.Detail.Desc.Text = "A crystal from the deepest caves. Earns a lot on your podium."
	panel.Detail.SkinStroke.Color = Color3.fromRGB(255, 70, 90)
	panel.Detail.Glow.BackgroundColor3 = Color3.fromRGB(255, 70, 90)
	panel.Footer.Text = "1 reward per geode   ·   Skins drop only from chests"
end
