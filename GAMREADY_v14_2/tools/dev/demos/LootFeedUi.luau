return function(gui, shared, require)
	local colors = { Color3.fromRGB(80, 160, 255), Color3.fromRGB(180, 90, 255), Color3.fromRGB(255, 200, 60) }
	for i, t in { "+1 Amethyst", "+1 Void Shard", "+$12.4K" } do
		local card = gui.Templates.CardTemplate:Clone()
		card.LayoutOrder = i
		card.Body.Title.Text = t
		card.Body.Title.TextColor3 = colors[i]:Lerp(Color3.new(1, 1, 1), 0.25)
		card.Body.Sub.Text = ({ "RARE", "EPIC", "LEGENDARY" })[i]
		card.Body.SkinStroke.Color = colors[i]
		card.Body.Strip.BackgroundColor3 = colors[i]
		card.Body.Emoji.Text = ({ "💎", "🔮", "💰" })[i]
		card.Body.Shine.Visible = false
		card.Parent = gui.Feed
	end
	gui.Banner.Visible = true
	gui.Banner.Title.Text = "LEGENDARY DROP!"
	gui.Banner.Text.Text = "Golden Geode"
end
