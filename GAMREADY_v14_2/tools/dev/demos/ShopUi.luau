return function(gui, shared, require)
	local Config = require(shared.Config)
	local UiKit = require(shared.UiKit)
	local ShopUi = require(shared.UiBuilders.ShopUi)
	gui.Panel.Visible = true
	gui.Dimmer.Visible = true
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
			card.SkinStroke.Thickness = 2
			card.BackgroundColor3 = UiKit.Theme.Skins.Card.Color:Lerp(accent.Main, 0.22)
			card.Tint.Color = UiKit.Seq(accent.Main, accent.Dark or accent.Main)
			card.IconHolder.PlaceholderIcon.Emoji.Text = item.Title:match("^([^%w%s]+)") or "🛒"
			card.Description.Text = Config.Shop.Descriptions[item.Id] or ""
			card.PriceButton.Caption.Text = "R$ " .. tostring(item.PriceRobux)
		end
	end
	for _, tab in Config.Shop.Tabs do
		local container = gui.Panel:FindFirstChild("Cards_" .. tab, true)
		local n = math.min(counts[tab] or 0, 3)
		local missing = n == 0 and 2 or n % 2
		for i = 1, missing do
			local e = gui.EmptyCardTemplate:Clone(); e.Visible = true; e.LayoutOrder = 1000 + i; e.Parent = container
		end
	end
	local chain = gui.Panel:FindFirstChild("Chain", true)
	local titles = { "$1.2K", "$6K", "$18K" }
	for i = 1, 3 do
		local step = chain["Step" .. i]
		step.Title.Text = titles[i]
		step.IconHolder.Icon.Emoji.Text = i == 1 and "🎁" or "💰"
		step.Button.Caption.Text = i == 1 and "Claim" or ("R$ " .. ({ 0, 25, 59 })[i])
		if i > 1 then UiKit.SetButtonVariant(step.Button, "Yellow"); step.Button.BackgroundTransparency = 0.5 end
	end
	local big = gui.Panel:FindFirstChild("BigCard", true)
	big.Subtitle.Text = "$40K  ·  BEST VALUE!"
	big.Button.Caption.Text = "R$ 119"
	big.RaysHolder.Rays.Rotation = 10
end
