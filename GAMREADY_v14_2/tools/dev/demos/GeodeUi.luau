return function(gui, shared, require)
	gui.Enabled = true
	local vault = gui.VaultPanel
	vault.Visible = true
	for _, name in { "BuyGeodesPanel", "PodiumPanel", "OpeningOverlay", "OpenCountMenu" } do
		local p = gui:FindFirstChild(name)
		if p then p.Visible = false end
	end
	local grid = vault.GeodeGrid
	for i, d in { { "JADE GEODE", Color3.fromRGB(90, 200, 120), "x3" }, { "RUBY GEODE", Color3.fromRGB(230, 70, 80), "x1" } } do
		local card = grid.GeodeCardTemplate:Clone()
		card.Name = "G" .. i -- после FindFirstChild("Name") ниже
		card.Visible = true
		card:FindFirstChild("Name").Text = d[1]
		card.Count.Text = d[3]
		card:FindFirstChild("Icon", true).BackgroundColor3 = d[2]
		card:FindFirstChild("Icon", true).BackgroundTransparency = 0
		card.Parent = grid
	end
	vault.DropInfoPanel.Visible = true
end
