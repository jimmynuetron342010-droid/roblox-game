--[[
	InputController
	One place for every gameplay binding across keyboard/mouse, gamepad and touch.
	Other controllers subscribe to named actions; touch buttons (MobileControls) call Trigger().

	Action        Keyboard/Mouse   Gamepad
	Attack        Mouse1           R2
	SkillZ        Z                L1
	SkillX        X                R1
	SkillC        C                Y
	SkillV        V                B
	Kishin        B                DPad Up
	Dash          Q                L2
	Sprint        LeftShift (hold) L3 (toggle)
	Perception    G                DPad Down
	Holster       E                DPad Left
	Form          T                DPad Right
	Menu          M                Select / View
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Signal = require(Modules.Core.Signal)

local InputController = {}

InputController.Action = Signal.new() -- (actionName, isDown)
InputController.Blocked = false -- set while full-screen menus are open

local BINDINGS = {
	Attack = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
	SkillZ = { Enum.KeyCode.Z, Enum.KeyCode.ButtonL1 },
	SkillX = { Enum.KeyCode.X, Enum.KeyCode.ButtonR1 },
	SkillC = { Enum.KeyCode.C, Enum.KeyCode.ButtonY },
	SkillV = { Enum.KeyCode.V, Enum.KeyCode.ButtonB },
	Kishin = { Enum.KeyCode.B, Enum.KeyCode.DPadUp },
	Dash = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL2 },
	Sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
	Perception = { Enum.KeyCode.G, Enum.KeyCode.DPadDown },
	Holster = { Enum.KeyCode.E, Enum.KeyCode.DPadLeft },
	Form = { Enum.KeyCode.T, Enum.KeyCode.DPadRight },
	Menu = { Enum.KeyCode.M, Enum.KeyCode.ButtonSelect },
}

-- Actions that still work while a menu is open.
local MENU_SAFE = { Menu = true }

InputController.Bindings = BINDINGS

local sprintToggled = false

function InputController.Trigger(action: string, isDown: boolean)
	if InputController.Blocked and not MENU_SAFE[action] then
		return
	end
	InputController.Action:Fire(action, isDown)
end

local function handler(actionName: string, state: Enum.UserInputState, input: InputObject)
	local isDown = state == Enum.UserInputState.Begin
	if state ~= Enum.UserInputState.Begin and state ~= Enum.UserInputState.End then
		return Enum.ContextActionResult.Pass
	end
	if actionName == "Attack" and input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Don't swing when clicking UI buttons or while the Roblox menu is open.
		if GuiService.MenuIsOpen then
			return Enum.ContextActionResult.Pass
		end
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui and isDown then
			local position = input.Position
			for _, gui in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
				if gui:IsA("GuiButton") and gui.Visible and gui.Active then
					return Enum.ContextActionResult.Pass
				end
			end
		end
	end
	if actionName == "Sprint" and input.KeyCode == Enum.KeyCode.ButtonL3 then
		if isDown then
			sprintToggled = not sprintToggled
			InputController.Trigger("Sprint", sprintToggled)
		end
		return Enum.ContextActionResult.Sink
	end
	InputController.Trigger(actionName, isDown)
	return Enum.ContextActionResult.Pass
end

function InputController:Init() end

function InputController:Start()
	for action, inputs in BINDINGS do
		ContextActionService:BindActionAtPriority("SE_" .. action, function(_, state, input)
			return handler(action, state, input)
		end, false, Enum.ContextActionPriority.Medium.Value, table.unpack(inputs))
	end
	-- Sprint stops when the stick returns to rest or the window loses focus.
	UserInputService.WindowFocusReleased:Connect(function()
		InputController.Trigger("Sprint", false)
	end)
end

function InputController.IsGamepad(): boolean
	return UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

function InputController.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return InputController
