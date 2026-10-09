--[[
	UIController
	Owns the ScreenGui, the responsive scale, and menu routing:
	  * one modal menu at a time (gameplay input is blocked while it is open)
	  * gamepad: the first button of a menu is selected automatically; B / Esc closes
	  * ProximityPrompts with an "OpensUI" attribute open the matching menu
	  * UI scale follows the viewport (phone -> TV) times the player's UI Scale setting
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Signal = require(Modules.Core.Signal)

local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)

local Theme = require(script.Parent.Theme)

local UIController = {}

local player = Players.LocalPlayer
local screens: { [string]: any } = {}
local openName: string? = nil

UIController.Gui = nil :: ScreenGui?
UIController.Layers = {} :: { [string]: Frame }
UIController.Changed = Signal.new() -- (openScreenName?) fired whenever a menu opens or closes

-- Screen area available to the ScreenGui (IgnoreGuiInset = false excludes the top bar).
local function guiArea(): Vector2
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return Vector2.new(viewport.X, math.max(viewport.Y - inset.Y, 1))
end

local function computeScale(): number
	local area = guiArea()
	local base = math.min(area.X / 1280, area.Y / 662)
	local userScale = ClientState.Profile and ClientState.Profile.Settings.UIScale or 1
	-- Phones get a floor so 14px text never renders below ~10pt; TVs are capped to avoid
	-- giant panels. Short screens switch screens to their compact layouts instead.
	return math.clamp(base, 0.7, 1.35) * userScale
end

-- Size of every layer in "design pixels" (what screens lay themselves out in).
function UIController.DesignSize(): Vector2
	return guiArea() / computeScale()
end

-- Phones in landscape and other short screens: screens drop optional decoration.
function UIController.IsCompact(): boolean
	return UIController.DesignSize().Y < 600
end

function UIController.Register(name: string, screen)
	screens[name] = screen
end

function UIController.IsOpen(name: string?): boolean
	if name then
		return openName == name
	end
	return openName ~= nil
end

local function firstSelectable(root: Instance): GuiObject?
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("GuiButton")
			and descendant.Visible
			and descendant.Selectable
			and descendant.Name ~= "Close"
		then
			return descendant
		end
	end
	return nil
end

function UIController.Open(name: string, args: any?)
	local screen = screens[name]
	if not screen then
		return
	end
	-- A screen that cannot be dismissed (first-time student creation) cannot be replaced either.
	local current = openName and screens[openName]
	if current and openName ~= name and current.Closable == false then
		return
	end
	if openName and openName ~= name then
		UIController.Close(openName)
	end
	openName = name
	InputController.Blocked = screen.BlocksInput ~= false
	screen:Open(args)
	UIController.Changed:Fire(name)
	if UserInputService.GamepadEnabled and screen.Root then
		task.defer(function()
			GuiService.SelectedObject = firstSelectable(screen.Root)
		end)
	end
end

function UIController.Close(name: string?)
	local target = name or openName
	if not target then
		return
	end
	local screen = screens[target]
	if screen then
		screen:Close()
	end
	if openName == target then
		openName = nil
		GuiService.SelectedObject = nil
		-- Unblock on the next frame so the key that closed the menu (gamepad B is also the V skill)
		-- does not trigger a gameplay action as well.
		task.defer(function()
			if openName == nil then
				InputController.Blocked = false
			end
		end)
		UIController.Changed:Fire(nil)
	end
end

-- Screens call this to close themselves so routing state stays consistent.
function UIController.CloseSelf(name: string)
	if openName == name then
		UIController.Close(name)
	elseif screens[name] then
		screens[name]:Close()
	end
end

function UIController.Toggle(name: string, args: any?)
	if openName == name then
		UIController.Close(name)
	else
		UIController.Open(name, args)
	end
end

function UIController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SoulEaterUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")
	UIController.Gui = gui
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = gui
	for index, layer in { "HUD", "Menus", "Overlay", "Toasts" } do
		local frame = Instance.new("Frame")
		frame.Name = layer
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.ZIndex = index * 10
		frame.Parent = gui
		UIController.Layers[layer] = frame
	end
	local function rescale()
		local s = computeScale()
		scale.Scale = s
		-- Layers are sized in "design pixels" so scaled content still fills the screen.
		for _, layer in UIController.Layers do
			layer.Size = UDim2.fromScale(1 / s, 1 / s)
		end
	end
	rescale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	ClientState.ProfileChanged:Connect(rescale)
	Theme.ReducedMotion = ClientState.ReducedMotion
end

function UIController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local target = prompt:GetAttribute("OpensUI")
		if type(target) == "string" and target ~= "" then
			UIController.Open(target, { WeaponId = prompt:GetAttribute("WeaponId") })
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed) then
			if openName and screens[openName] and screens[openName].Closable ~= false then
				UIController.Close()
			end
		end
	end)
	InputController.Action:Connect(function(action, isDown)
		if action == "Menu" and isDown then
			if openName then
				if screens[openName] and screens[openName].Closable ~= false then
					UIController.Close()
				end
			else
				UIController.Open("Stats")
			end
		end
	end)
end

return UIController
