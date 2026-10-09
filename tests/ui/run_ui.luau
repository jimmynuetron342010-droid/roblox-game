--[[
	UI walkthrough (Lune): boots the real client UI against the simulated server and plays through
	every screen like a player would, asserting behaviour and saving a snapshot of the GUI tree at
	each step for tests/ui/render_ui.mjs.

	  lune run tests/ui/run_ui.luau [desktop|laptop|tablet|phone] [outDir]

	Fails (exit 1) on any runtime error raised by game code, on any strict-Instance violation
	(invalid member, wrong type, read-only write), or on a failed expectation.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Env = require("./Env")
local GuiExport = require("./GuiExport")
local MockInstance = require("./MockInstance")

local PROFILES = {
	desktop = { Size = { 1920, 1080 }, Inset = 58 },
	laptop = { Size = { 1366, 768 }, Inset = 58 },
	tablet = { Size = { 1180, 820 }, Inset = 58, Touch = true },
	phone = { Size = { 844, 390 }, Inset = 58, Touch = true },
}

local profileName = process.args[1] or "desktop"
local outRoot = process.args[2] or "tests/renders/out/ui"
local profile = PROFILES[profileName]
assert(profile, "unknown profile " .. profileName)
local outDir = outRoot .. "/" .. profileName
if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)

-- Camera.ViewportSize is the whole screen; the GUI area excludes the Roblox top bar (GetGuiInset).
local viewport = roblox.Vector2.new(profile.Size[1], profile.Size[2])
local env = Env.new({ Viewport = viewport, Inset = profile.Inset, Touch = profile.Touch })
local server = env.Server
local UIController = env.Loader.RequirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIController")

local failures = {}
local step = 0
local function check(condition: any, message: string)
	if not condition then
		table.insert(failures, string.format("[%s] %s", profileName, message))
		print("  ✗ " .. message)
	else
		print("  ✓ " .. message)
	end
end

local function snapshot(name: string)
	step += 1
	env.Step(2)
	local gui = env:Gui()
	local file = string.format("%s/%02d_%s.json", outDir, step, name)
	fs.writeFile(
		file,
		serde.encode("json", {
			name = name,
			profile = profileName,
			viewport = profile.Size,
			inset = profile.Inset,
			gui = GuiExport.Node(gui),
		})
	)
	print(string.format("  📸 %02d_%s", step, name))
end

local function screenVisible(name: string): boolean
	local gui = env:Gui()
	for _, layer in { "Menus", "Overlay" } do
		local node = gui[layer]:FindFirstChild(name)
		if node and node.Visible then
			return true
		end
	end
	return false
end

local function closeMenu()
	UIController.Close()
	env.Step(2)
end

print(
	string.format(
		"UI walkthrough — %s (%dx%d%s)",
		profileName,
		profile.Size[1],
		profile.Size[2],
		profile.Touch and ", touch" or ""
	)
)

-- ── Boot ──────────────────────────────────────────────────────────────────────
env:RunScript("StarterPlayer.StarterPlayerScripts.Client.Main")
env:WaitFor("SoulEaterUI", function()
	return env:Gui()
end)

-- ── Create Your Student ───────────────────────────────────────────────────────
print("Create Your Student")
env:WaitFor("creator opens for a new player", function()
	return screenVisible("StudentCreator")
end)
check(screenVisible("StudentCreator"), "creator opens automatically for a new player")
check(not env:Gui().HUD.Visible, "HUD is hidden behind the creator")
snapshot("creator_empty")

local nameBox
for _, d in env:Gui():GetDescendants() do
	if d:IsA("TextBox") then
		nameBox = d
	end
end
check(nameBox ~= nil, "name field exists")
env:Type(nameBox, "ab")
check(env:FindText("Name must be", true) ~= nil, "too-short name shows an inline error")
env:Type(nameBox, "9lives")
check(env:FindText("must start with a letter", true) ~= nil, "name starting with a digit shows an inline error")
env:Type(nameBox, string.rep("x", 30))
check(#nameBox.Text <= 16, "name is capped at 16 characters while typing")
env:Type(nameBox, "Kaito Ren")
check(env:FindText("Name must", true) == nil, "valid name clears the error")
env:ClickText("Crimson", true)
env:ClickText("Pigtails", true)
env:ClickText("Crescent Night", true)
env:ClickText("Fierce", true)
env:ClickText("Assassin", true)
env:ClickText("Twin Pistols", true)
snapshot("creator_filled")

-- Cannot escape the creator before enrolling.
env.UserInputService.InputBegan:Fire(
	{ KeyCode = roblox.Enum.KeyCode.Escape, UserInputType = roblox.Enum.UserInputType.Keyboard },
	false
)
env.Step(2)
UIController.Open("Stats")
env.Step(2)
check(
	screenVisible("StudentCreator") and not screenVisible("Stats"),
	"creator cannot be closed or bypassed before enrolling"
)

-- Double submit sends one request.
local before = #server.Calls
local enroll = env:FindButton("Enroll", true)
enroll.Activated:Fire()
enroll.Activated:Fire()
env:WaitFor("creator closes after enrolling", function()
	return not screenVisible("StudentCreator")
end)
local creates = 0
for i = before + 1, #server.Calls do
	if server.Calls[i].Name == "CreateStudent" then
		creates += 1
	end
end
check(creates == 1, "double-clicking Enroll sends exactly one CreateStudent request")
check(
	server.Profile.Student.Name == "Kaito Ren" and server.Profile.Loadout.Role == "Assassin",
	"server saved the chosen name and role"
)
check(server.Profile.Loadout.Weapon == "TwinPistols", "server saved the starter weapon")
env:WaitFor("HUD visible", function()
	return env:Gui().HUD.Visible
end)
env:Wait(0.3)
snapshot("hud_new_student")

-- ── Soul Altar ────────────────────────────────────────────────────────────────
print("Soul Altar")
local prompt = MockInstance.new("ProximityPrompt")
prompt:SetAttribute("OpensUI", "RaceRoll")
env.ProximityPromptService.PromptTriggered:Fire(prompt, env.Player)
env:WaitFor("altar opens from the prompt", function()
	return screenVisible("RaceRoll")
end)
check(env:FindText("Probability Table", true) ~= nil, "probability table is visible before rolling")
check(env:FindText("Total: 100%", true) ~= nil, "odds add up to 100%")
check(
	env:FindText("40%", true) ~= nil and env:FindText("1%", true) ~= nil,
	"exact odds are shown (Human 40% … Golem 1%)"
)
snapshot("altar_idle")

server.ForceRace = "Witch"
env:ClickText("Roll — 1 Race Roll", true)
env:Wait(0.9)
snapshot("altar_buildup")
env:WaitFor("first reveal", function()
	return env:FindButton("Continue", true)
end, 10)
check(server.Profile.Race.Active == "Witch", "first roll is applied immediately")
check(env:FindText("NEW DISCOVERY", true) ~= nil, "new races are flagged as discoveries")
check(env:FindText("Skip", true) == nil, "skip is not offered before the first full reveal")
snapshot("altar_reveal_first")
env:ClickText("Continue", true)
env:WaitFor("SeenRollAnimation saved", function()
	return server.Profile.Settings.SeenRollAnimation == true
end)
check(true, "first full reveal unlocks fast reveal (SeenRollAnimation saved)")

-- Invest in Witch, then roll a Mythic to get the keep / replace decision with hold-to-confirm.
server.Profile.Race.Progress.Witch.XP = 420
server:Push()
env:Wait(1.1)
server.ForceRace = "Shinigami"
env:ClickText("Roll — 250 Souls", true)
env:WaitFor("decision", function()
	return env:FindButton("Hold to replace", true)
end, 10)
check(env:FindText("Replace Witch with Shinigami?", true) ~= nil, "comparison panel names both races")
check(env:FindText("mastery (Stage I) is saved", true) ~= nil, "players are told their mastery is kept")
check(server.Profile.Race.Active == "Witch", "nothing changes until the player confirms")
snapshot("altar_decision")
local replace = env:FindButton("Hold to replace", true)
env:Hold(replace, 0.4)
check(server.Profile.Race.Active == "Witch", "a short press does not replace an invested race")
env:Hold(replace, 1.5)
env:WaitFor("replace resolves", function()
	return server.Profile.Race.Active == "Shinigami"
end)
check(server.Profile.Race.Progress.Witch.XP == 420, "Witch mastery progress is preserved after replacing")
env:Wait(0.3)
snapshot("altar_after_replace")

-- Retry safety: the same request id is never charged twice.
local rolls = server.Profile.Currency.RaceRolls
local replay = server:Invoke("RollRace", server.Calls[#server.Calls - 1].Args[1], "Souls")
check(
	replay.Replayed == true and server.Profile.Currency.RaceRolls == rolls,
	"replayed request id returns the same result without charging"
)

-- Fast reveal + same race (Soul Echo).
closeMenu()
UIController.Open("Settings")
env:WaitFor("settings", function()
	return screenVisible("Settings")
end)
snapshot("settings")
local fastRow = env:FindText("Fast race reveal", true)
local fastToggle = env:FindButton("^OFF$", false, fastRow.Parent)
env:Click(fastToggle)
env:WaitFor("FastReveal saved", function()
	return server.Profile.Settings.FastReveal == true
end)
check(true, "fast reveal can be turned on after the first reveal")
closeMenu()
UIController.Open("RaceRoll")
env:Wait(1.1)
server.ForceRace = "Shinigami"
local started = os.clock()
env:ClickText("Roll — 1 Race Roll", true)
env:WaitFor("echo reveal", function()
	return env:FindButton("Continue", true)
end, 10)
check(os.clock() - started < 1.6, string.format("fast reveal is quick (%.2fs)", os.clock() - started))
check(env:FindText("Soul Echo", true) ~= nil, "rolling your current race grants a Soul Echo instead of a reroll")
snapshot("altar_soul_echo")
env:ClickText("Continue", true)

-- Not enough currency.
server.Profile.Currency.RaceRolls = 0
server.Profile.Currency.Souls = 10
server:Push()
env:Wait(1.1)
env:ClickText("Roll — 1 Race Roll", true)
env:WaitFor("error message", function()
	return env:FindText("Not enough currency", true)
end)
check(true, "insufficient currency shows a clear message")
snapshot("altar_no_currency")
closeMenu()

-- Give the student some progress for the remaining screens.
server.Profile.Level = 16
server.Profile.Currency.RaceRolls = 2
server.Profile.Currency.Souls = 1450
server.Profile.Exp = 410
for _, id in server.WeaponConfig.Order do
	if (server.WeaponConfig.Weapons[id].UnlockLevel or 1) <= 16 then
		server.Profile.Weapons.Owned[id] = true
	end
end
server.Profile.Weapons.Mastery.TwinPistols = 450
server.Profile.Race.Progress.Shinigami = { XP = 900, Stage = 1, Objectives = { S2a = 3 } }
server.Profile.Quests.Progress = 2
server:Push()
env:Wait(0.3)
snapshot("hud_progress")

-- ── Menus ─────────────────────────────────────────────────────────────────────
print("Menus")
UIController.Open("RaceIndex")
env:WaitFor("index", function()
	return screenVisible("RaceIndex")
end)
check(env:FindText("Discovered 2 / 9", true) ~= nil, "index counts discovered races")
snapshot("race_index")
env:ClickText("Lore", true)
snapshot("race_index_lore")
closeMenu()

UIController.Open("Stats")
env:WaitFor("stats", function()
	return env:FindText("Max Health", true)
end)
snapshot("stats")
closeMenu()

env.AddPlayer(
	"Partner",
	2002,
	{ StudentCreated = true, Wavelength = "Gentle", Race = "DemonWeapon", Role = "PartnerWeapon" }
)
UIController.Open("Skills")
env:WaitFor("skills", function()
	return screenVisible("Skills")
end)
snapshot("skills_abilities")
env:ClickText("Role & Magic", true)
snapshot("skills_build")
local techCard = env:FindText("Wavelength Technician", true)
env:Click(env:FindButton("Choose", true, techCard.Parent.Parent))
env:WaitFor("role saved", function()
	return server.Profile.Loadout.Role == "Technician"
end)
check(true, "role can be changed from Skills")
env:ClickText("Resonance", true)
snapshot("skills_resonance")
env:ClickText("Kishin Path", true)
snapshot("skills_kishin")
closeMenu()

UIController.Open("Inventory")
env:WaitFor("inventory", function()
	return screenVisible("Inventory")
end)
snapshot("inventory")
UIController.Open("Inventory", { WeaponId = "TsubakiForms" })
env:ClickText("Equip", true)
env:WaitFor("tsubaki equipped", function()
	return server.Profile.Loadout.Weapon == "TsubakiForms"
end)
env:Wait(0.2)
env:ClickText("Kusarigama", true)
env:WaitFor("form saved", function()
	return server.Profile.Loadout.TsubakiForm == "Kusarigama"
end)
check(true, "Tsubaki forms can be switched from the inventory")
env:Wait(0.2)
snapshot("inventory_tsubaki")
closeMenu()

UIController.Open("Settings")
env:ClickText("Edit student", true)
env:WaitFor("creator edit mode", function()
	return screenVisible("StudentCreator") and env:FindButton("Save Appearance", true)
end)
check(env:FindButton("Close", true) ~= nil, "edit mode can be closed")
snapshot("creator_edit")
env:ClickText("Close", true)
env:WaitFor("creator closed", function()
	return not screenVisible("StudentCreator")
end)
check(env:Gui().HUD.Visible, "HUD returns after closing the creator")

if profile.Touch then
	local mobile = env:Gui().HUD:FindFirstChild("MobileControls")
	check(mobile ~= nil and mobile.Visible, "touch controls are shown on touch devices")
	snapshot("hud_touch")
end

-- ── Report ────────────────────────────────────────────────────────────────────
task.wait(0.2)
print("")
for _, err in MockInstance.Errors do
	table.insert(failures, "runtime error: " .. err)
end
if #failures > 0 then
	print(string.format("%d problem(s):", #failures))
	for _, failure in failures do
		print("  - " .. failure)
	end
	process.exit(1)
end
print(string.format("UI walkthrough passed (%s, %d snapshots)", profileName, step))
process.exit(0)
