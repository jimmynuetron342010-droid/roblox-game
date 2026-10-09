--[[
	MobileControls
	Touch buttons arranged around the thumb, left of Roblox's own jump button (bottom-right) and away
	from the thumbstick (bottom-left). Every button routes through InputController.Trigger so touch
	behaves exactly like keyboard/gamepad (including combat blocking while menus are open).
	  * Attack supports press-and-hold (charged combos), like holding the mouse.
	  * Skill buttons show the same cooldown sweep as the HUD.
	  * Only shown while the last input was touch; hidden while any menu is open.
	  * Utility row (top-center): Perception, Draw/Holster, Form (Tsubaki only), Kishin (once
	    unlocked), and ☰ which opens the HUD menu column.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AbilitySlots = require(Modules.Core.AbilitySlots)

local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)

local Components = require(script.Parent.Components)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)
local UIController = require(script.Parent.UIController)

local MobileControls = {}

local player = Players.LocalPlayer
local root: Frame? = nil
local cooldowns: { [string]: { Fill: Frame, Total: number } } = {}
local extras: { [string]: GuiObject } = {}
local lastTouch: boolean? = nil

-- Big round button that forwards press/release to an InputController action.
local function actionButton(
	parent: Instance,
	action: string,
	text: string,
	center: Vector2,
	size: number,
	color: Color3?
)
	local button = Components.New("TextButton", {
		Name = action,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, center.X, 1, center.Y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color or Theme.Colors.InkLight,
		BackgroundTransparency = 0.25,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Display,
		TextSize = math.floor(size * 0.36),
		Selectable = false,
		Parent = parent,
	})
	Components.Corner(UDim.new(1, 0)).Parent = button
	local stroke = Components.Stroke(Theme.Colors.Gold, 2, 0.35)
	stroke.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			scale.Scale = 0.92
			stroke.Transparency = 0
			InputController.Trigger(action, true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			scale.Scale = 1
			stroke.Transparency = 0.35
			InputController.Trigger(action, false)
		end
	end)
	return button
end

local function withCooldown(button: GuiObject, slot: string)
	local fill = Components.New("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})
	Components.Corner(UDim.new(1, 0)).Parent = fill
	cooldowns[slot] = { Fill = fill, Total = 0.01 }
end

local function smallButton(parent: Instance, name: string, text: string, order: number, onTap: () -> ())
	local button = Components.Button(text, onTap, {
		Name = name,
		Size = UDim2.fromOffset(52, 52),
		LayoutOrder = order,
		TextSize = 20,
		BackgroundTransparency = 0.2,
		Selectable = false,
		Parent = parent,
	}, "Ghost")
	return button
end

local function tap(action: string)
	return function()
		InputController.Trigger(action, true)
		InputController.Trigger(action, false)
	end
end

local function updateVisibility()
	if not root then
		return
	end
	local touch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
		or (
			UserInputService.TouchEnabled
			and not UserInputService.KeyboardEnabled
			and not UserInputService.GamepadEnabled
		)
	root.Visible = touch and not UIController.IsOpen() and HUD.Root ~= nil and HUD.Root.Visible
	if touch ~= lastTouch then
		lastTouch = touch
		HUD.UseTouchLayout(touch)
	end
end

local function refreshExtras()
	local profile = ClientState.Profile
	local character = player.Character
	if extras.Form then
		extras.Form.Visible = character ~= nil and character:GetAttribute("EquippedWeapon") == "TsubakiForms"
	end
	if extras.Kishin then
		extras.Kishin.Visible = profile ~= nil and AbilitySlots.Resolve(profile, "B") ~= nil
	end
end

function MobileControls.Mount(layer: Frame)
	if not UserInputService.TouchEnabled then
		return
	end
	root = Components.New("Frame", {
		Name = "MobileControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = layer,
	})
	local frame = root :: Frame

	-- Thumb cluster (offsets from the bottom-right corner): an arc around Attack that stays left of
	-- and above Roblox's jump button, and below the quest/wallet panels.
	actionButton(frame, "Attack", "⚔", Vector2.new(-205, -105), 100, Theme.Colors.RedDark)
	withCooldown(actionButton(frame, "SkillZ", "Z", Vector2.new(-318, -66), 62), "Z")
	withCooldown(actionButton(frame, "SkillX", "X", Vector2.new(-308, -170), 62), "X")
	withCooldown(actionButton(frame, "SkillC", "C", Vector2.new(-212, -222), 62), "C")
	withCooldown(actionButton(frame, "SkillV", "V", Vector2.new(-104, -200), 62), "V")
	actionButton(frame, "Dash", "»", Vector2.new(-412, -66), 58, Theme.Colors.InkLighter)
	actionButton(frame, "Sprint", "⇧", Vector2.new(-404, -162), 52, Theme.Colors.InkLighter)

	-- Utility row (top-center: free space between the vitals and the quest panel).
	local row = Components.New("Frame", {
		Name = "MobileUtility",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(300, 52),
		Parent = frame,
	})
	local list = Components.List(Enum.FillDirection.Horizontal, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = row
	smallButton(row, "Perception", "👁", 1, tap("Perception"))
	smallButton(row, "Holster", "⚔↕", 2, tap("Holster"))
	extras.Form = smallButton(row, "Form", "⟳", 3, tap("Form"))
	extras.Kishin = smallButton(row, "Kishin", "B", 4, tap("Kishin"))
	smallButton(row, "Menu", "☰", 5, function()
		HUD.ToggleMenu()
	end)

	UserInputService.LastInputTypeChanged:Connect(updateVisibility)
	UIController.Changed:Connect(updateVisibility)
	ClientState.ProfileChanged:Connect(refreshExtras)
	player.CharacterAdded:Connect(function(character)
		character:GetAttributeChangedSignal("EquippedWeapon"):Connect(refreshExtras)
		refreshExtras()
	end)
	if player.Character then
		player.Character:GetAttributeChangedSignal("EquippedWeapon"):Connect(refreshExtras)
	end
	refreshExtras()
	updateVisibility()

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / 15 then
			return
		end
		accumulator = 0
		updateVisibility()
		if not frame.Visible then
			return
		end
		local now = workspace:GetServerTimeNow()
		for slot, entry in cooldowns do
			local remaining = (player:GetAttribute("CD_" .. slot) or 0) - now
			if remaining > 0 then
				entry.Total = math.max(entry.Total, remaining)
				entry.Fill.Size = UDim2.fromScale(1, remaining / entry.Total)
			else
				entry.Total = 0.01
				entry.Fill.Size = UDim2.fromScale(1, 0)
			end
		end
	end)
end

return MobileControls
