return function(gui, shared, require)
	local Config = require(shared.Config)
	local UiKit = require(shared.UiKit)
	local ShopUi = require(shared.UiBuilders.ShopUi)
	local template = gui.CardTemplate
	local counts = {}
	for _, item in Config.Shop.Items do
		counts[item.Tab] = (counts[item.Tab] or 0) + 1
		if counts[item.Tab] <= 3 then
			local container = gui.Panel:FindFirstChild("Cards_" .. item.Tab, true)
			local card = template:Clone()
			card.Visible = true
			card.Parent = container
			local accent = UiKit.Accent(ShopUi.TabAccent(item.Tab))
			card.Title.Text = (item.Title:gsub("^[^%w]+%s", ""))
			card.Title.TextGradient.Color = UiKit.Seq(accent.Light, accent.Main)
			card.SkinStroke.Color = accent.Main
			card.Description.Text = Config.Shop.Descriptions[item.Id] or ""
			card.PriceButton.Caption.Text = "R$ " .. tostring(item.PriceRobux)
		end
	end
end
