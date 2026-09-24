return function(gui, shared, require)
	gui.Enabled = true
	gui.Dialog.Visible = true
	gui.Dialog.Nameplate.Speaker.Text = "MOLE"
	gui.Dialog.Body.Text = "Hey, rookie! Grab your cart and head to the mine — ore pays the bills."
	gui.Dialog.Continue.Visible = true
	gui.Task.Visible = true
	gui.Task.Position = UDim2.new(0.5, 0, 1, -170)
	gui.Task.Title.Text = "FILL YOUR CART"
	gui.Task.Body.Text = "Mine ore until the cart is 85% full."
end
