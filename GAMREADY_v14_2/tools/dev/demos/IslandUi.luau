return function(gui, shared, require)
	local panel = gui.Panel
	local cards = panel.Content.GridView.Cards
	local data = { { "SMELTER", "🔥", Color3.fromRGB(255, 120, 60), "✔ OWNED  LV 2/5", true }, { "CRYSTAL ISLE", "💎", Color3.fromRGB(120, 200, 255), "$25K", false },
		{ "GOLD ISLE", "🪙", Color3.fromRGB(255, 210, 70), "$120K", false }, { "VOID ISLE", "🌌", Color3.fromRGB(170, 90, 255), "Needs Gold Isle", false } }
	for i, d in data do
		local card = panel.Templates.Card:Clone()
		card.LayoutOrder = i
		card.Title.Text = d[1]; card.Icon.Text = d[2]; card.Chip.Text.Text = d[4]
		card.SkinStroke.Color = d[3]
		card.BackgroundColor3 = Color3.fromRGB(30, 30, 34):Lerp(d[3], d[5] and 0.1 or 0.28)
		card.Lock.Visible = i == 4
		card.Parent = cards
	end
	panel.Content.GridView.Footer.Text = "PRESTIGE LOCKED — unlock every island first."
	panel.Content.GridView.Footer.TextColor3 = Color3.fromRGB(255, 158, 60)
end
