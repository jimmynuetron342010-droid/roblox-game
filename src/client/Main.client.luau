--[[
	Client bootstrap (StarterPlayerScripts.Client.Main)
	1. Init every controller, then Start them (each isolated with pcall so one failure cannot take
	   the whole client down; errors are printed with the controller name).
	2. Build the UI: HUD, toasts, damage numbers, touch controls and every menu screen.
	3. First-time players are sent straight into "Create Your Student", which cannot be closed or
	   bypassed until the server confirms the student exists.
]]

local Controllers = script.Parent.Controllers
local UIFolder = script.Parent.UI

local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)
local VFXClient = require(Controllers.VFXClient)
local AnimationController = require(Controllers.AnimationController)
local WeaponClient = require(Controllers.WeaponClient)
local PerceptionController = require(Controllers.PerceptionController)

local UIController = require(UIFolder.UIController)
local HUD = require(UIFolder.HUD)
local Notifications = require(UIFolder.Notifications)
local DamageNumbers = require(UIFolder.DamageNumbers)
local MobileControls = require(UIFolder.MobileControls)

local Screens = UIFolder.Screens
local StudentCreator = require(Screens.StudentCreator)
local RaceRollUI = require(Screens.RaceRollUI)
local RaceIndexUI = require(Screens.RaceIndexUI)
local StatsUI = require(Screens.StatsUI)
local SkillsUI = require(Screens.SkillsUI)
local InventoryUI = require(Screens.InventoryUI)
local SettingsUI = require(Screens.SettingsUI)

local controllers = {
	{ "ClientState", ClientState },
	{ "InputController", InputController },
	{ "VFXClient", VFXClient },
	{ "AnimationController", AnimationController },
	{ "WeaponClient", WeaponClient },
	{ "PerceptionController", PerceptionController },
	{ "UIController", UIController },
}

for _, entry in controllers do
	local ok, err = pcall(entry[2].Init, entry[2])
	if not ok then
		warn(string.format("[Client] %s:Init failed: %s", entry[1], tostring(err)))
	end
end

-- ── UI ────────────────────────────────────────────────────────────────────────
local layers = UIController.Layers
HUD.Mount(layers.HUD)
Notifications.Mount(layers.Toasts)
DamageNumbers.Mount()

local creator = StudentCreator.new(layers.Overlay)
local altar = RaceRollUI.new(layers.Overlay)
-- Full-screen experiences hide the HUD while they are showing.
creator.OnVisibility = function(visible: boolean)
	HUD.SetVisible(not visible)
end
altar.OnVisibility = function(visible: boolean)
	HUD.SetVisible(not visible)
end

UIController.Register("StudentCreator", creator)
UIController.Register("RaceRoll", altar)
UIController.Register("RaceIndex", RaceIndexUI.new(layers.Menus))
UIController.Register("Stats", StatsUI.new(layers.Menus))
UIController.Register("Skills", SkillsUI.new(layers.Menus))
UIController.Register("Inventory", InventoryUI.new(layers.Menus))
UIController.Register("Settings", SettingsUI.new(layers.Menus))

MobileControls.Mount(layers.HUD)

for _, entry in controllers do
	task.spawn(function()
		local ok, err = pcall(entry[2].Start, entry[2])
		if not ok then
			warn(string.format("[Client] %s:Start failed: %s", entry[1], tostring(err)))
		end
	end)
end

-- ── First-time flow ───────────────────────────────────────────────────────────
-- Re-checked on every profile update so the creator also reappears if the player somehow closes
-- it before the server confirms (e.g. network hiccup), and never shows once a student exists.
local function ensureStudent(profile)
	if not profile then
		return
	end
	if not profile.Student.Created and not creator.Enrolled then
		if not UIController.IsOpen("StudentCreator") then
			UIController.Open("StudentCreator")
		end
	end
end

ClientState.ProfileChanged:Connect(ensureStudent)
task.spawn(function()
	ensureStudent(ClientState:WaitForProfile())
end)
