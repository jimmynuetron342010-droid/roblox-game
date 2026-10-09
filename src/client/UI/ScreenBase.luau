--[[
	ScreenBase
	Shared shell for the modal menus (Stats, Skills, Inventory, Race Index, Settings): a centered
	modal sized for the design resolution with a max size for big screens, a soft pop-in that
	respects reduced motion, and a close button routed through UIController so menu state stays
	consistent no matter how the menu was closed (✕, Esc, gamepad B, or opening another menu).
]]

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)
local UIController = require(script.Parent.UIController)

local ScreenBase = {}

function ScreenBase.Modal(name: string, title: string, layer: Instance, size: UDim2?, maxSize: Vector2?)
	local root, content = Components.Modal(title, size or UDim2.fromScale(0.9, 0.88), function()
		UIController.CloseSelf(name)
	end)
	root.Name = name
	local constraint = root:FindFirstChildOfClass("UISizeConstraint")
	if constraint then
		constraint.MaxSize = maxSize or Vector2.new(1120, 680)
	end
	local scale = Instance.new("UIScale")
	scale.Name = "PopScale"
	scale.Parent = root
	root.Parent = layer
	return root, content
end

function ScreenBase.Show(root: GuiObject)
	root.Visible = true
	local scale = root:FindFirstChild("PopScale") :: UIScale?
	if scale and not Theme.ReducedMotion() then
		scale.Scale = 0.94
		Theme.Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

function ScreenBase.Hide(root: GuiObject)
	root.Visible = false
end

-- Removes every child except layouts/paddings/constraints (used when rebuilding lists).
function ScreenBase.ClearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Two-column body: returns (left, right) frames inside a modal's content.
function ScreenBase.Columns(content: Instance, leftWidth: number)
	local left = Components.New(
		"Frame",
		{ Name = "Left", BackgroundTransparency = 1, Size = UDim2.new(leftWidth, -8, 1, 0), Parent = content }
	)
	local right = Components.New("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		Position = UDim2.new(leftWidth, 8, 0, 0),
		Size = UDim2.new(1 - leftWidth, -8, 1, 0),
		Parent = content,
	})
	return left, right
end

return ScreenBase
