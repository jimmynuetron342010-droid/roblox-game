--[[
	Notifications
	Stacked toasts (server Notify events + local combat feedback). Rare/Mythic announcements get
	the rarity color. Short-lived, never block input, capped to keep the screen clean.
]]

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Net = require(Modules.Core.Net)

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local Notifications = {}

local UserInputService = game:GetService("UserInputService")

local list: Frame
local MAX = 4
local counter = 0

local KIND_COLORS = {
	Info = Theme.Colors.TextDim,
	Success = Theme.Colors.Good,
	Warning = Theme.Colors.Bad,
	Reward = Theme.Colors.Gold,
	Rare = Theme.Colors.Gold,
}

function Notifications.Show(text: string, kind: string?, rarity: string?)
	if not list then
		return
	end
	local color = KIND_COLORS[kind or "Info"] or Theme.Colors.TextDim
	if rarity then
		color = Theme.Rarity(rarity).Color
	end
	counter += 1
	local toast = Components.Panel({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.12,
		LayoutOrder = counter, -- newest closest to the anchor edge
	})
	Components.Padding(10, 14).Parent = toast
	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = color
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.Position = UDim2.fromOffset(-10, 0)
	accent.Parent = toast
	Components.Label(text, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = kind == "Info" and Theme.Colors.Text or color,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Body,
		Parent = toast,
	})
	toast.Parent = list
	local items = {}
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	if #items > MAX then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		items[1]:Destroy() -- oldest
	end
	task.delay(kind == "Rare" and 6 or 3.5, function()
		if toast.Parent then
			Theme.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

function Notifications.Mount(layer: Frame)
	list = Instance.new("Frame")
	list.Name = "Toasts"
	list.BackgroundTransparency = 1
	-- Keyboard/gamepad: bottom-center above the weapon line, clear of menu titles and the HUD.
	-- Touch: top-center under the touch utility row, because the bottom belongs to the thumbs.
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	list.AnchorPoint = Vector2.new(0.5, touch and 0 or 1)
	list.Position = touch and UDim2.new(0.5, 0, 0, 78) or UDim2.new(0.5, 0, 1, -56)
	list.Size = UDim2.fromOffset(440, 360)
	list.Parent = layer
	local layout = Components.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = touch and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
	layout.Parent = list
	Net.Event("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Text) == "string" then
			Notifications.Show(payload.Text, payload.Kind, payload.Rarity)
		end
	end)
end

return Notifications
