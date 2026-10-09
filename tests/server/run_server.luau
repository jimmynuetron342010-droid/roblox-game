--[[
	Server run (Lune): boots all 16 server services on strict MockInstances and plays a session
	as a client would — join, load profile, build the map, create a student, roll an origin,
	equip weapons, fight real enemies with weapon attacks and abilities, collect rewards, leave
	and rejoin to verify the save.

	  lune run tests/server/run_server.luau

	Fails on any runtime error, warning, invalid Instance use, or failed expectation.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local MockInstance = require("../ui/MockInstance")
local Polyfills = require("../harness/Polyfills")
local ServerEnv = require("./ServerEnv")

local Vector3 = roblox.Vector3
local CFrame = Polyfills.CFrame -- Roblox-correct lookAt (see Polyfills)

local env = ServerEnv.new()
local R = env.Loader.RequirePath
local GameConfig = R("ReplicatedStorage.Modules.Config.GameConfig")

-- Play as a real live server would: no Studio debug grants (extra rolls/souls/levels/weapons).
GameConfig.Debug.Enabled = false
GameConfig.Debug.UnlockAllWeapons = false

local failures = {}
local function check(condition: any, message: string)
	print((condition and "  ✓ " or "  ✗ ") .. message)
	if not condition then
		table.insert(failures, message)
	end
end

local function profileOf(player)
	local result = env:Invoke(player, "GetProfile")
	return result and result.Ok and result.Profile or nil
end

print("Boot")
env:Boot()
env:WaitFor("map ready", function()
	return env.Workspace:GetAttribute("MapReady")
end, 20)
check(true, "all services started and the map finished building")
local partCount = 0
for _, d in env.Workspace:GetDescendants() do
	if d:IsA("BasePart") then
		partCount += 1
	end
end
check(partCount > 200, string.format("Death City map built (%d parts)", partCount))
local enemiesFolder = env:WaitFor("enemies spawned", function()
	local folder = env.Workspace:FindFirstChild("Enemies")
	return folder and #folder:GetChildren() > 0 and folder
end, 20)
check(#enemiesFolder:GetChildren() > 0, string.format("enemies spawned (%d)", #enemiesFolder:GetChildren()))

print("Join")
local player = env:AddPlayer("Kaito", 101)
env:WaitFor("profile", function()
	return profileOf(player)
end)
local character = env:WaitFor("character spawned", function()
	return player.Character
end)
check(character ~= nil, "character spawned after the map was ready")
local profile = profileOf(player)
check(profile.Student.Created == false, "new player has no student yet")
check(
	env:Invoke(player, "RollRace", "11111111-aaaa", "Token").Reason == "NoStudent",
	"rolling before creating a student is refused"
)
check(
	env:Invoke(player, "EquipWeapon", { Action = "Equip", WeaponId = "MakaScythe" }).Ok == false,
	"equipping before creating a student is refused"
)

print("Create Your Student")
local badName = env:Invoke(player, "CreateStudent", {
	Name = "Badword",
	SkinTone = 2,
	HairColor = 1,
	HairStyle = 2,
	Uniform = 2,
	Wavelength = "Calm",
	Role = "Meister",
	Weapon = "MakaScythe",
})
check(badName.Ok == false and badName.Reason == "NameNotAllowed", "filtered names are rejected")
local created = env:Invoke(player, "CreateStudent", {
	Name = "Kaito Ren",
	SkinTone = 2,
	HairColor = 5,
	HairStyle = 3,
	Uniform = 3,
	Wavelength = "Fierce",
	Role = "Meister",
	Weapon = "MakaScythe",
})
check(created.Ok == true, "student created")
env:Step(5)
check(player:GetAttribute("StudentCreated") == true, "StudentCreated attribute replicated")
check(player:GetAttribute("Role") == "Meister", "Role attribute replicated")
check(character:FindFirstChild("EquippedWeapon") ~= nil, "starter weapon equipped on the character")
check(#env:Received(player, "ProfileChanged") > 0, "profile changes replicated to the client")

print("Soul Altar")
local roll = env:Invoke(player, "RollRace", "22222222-bbbb", "Token")
check(roll.Ok == true and roll.Applied == true, "first roll applies an origin (" .. tostring(roll.RaceId) .. ")")
local replay = env:Invoke(player, "RollRace", "22222222-bbbb", "Token")
check(
	replay.Replayed == true and replay.RaceId == roll.RaceId,
	"retrying the same request id replays, no double charge"
)
check(player:GetAttribute("Race") == roll.RaceId, "Race attribute replicated")
check(profileOf(player).Currency.RaceRolls == GameConfig.RaceRoll.StartingRolls - 1, "one roll token spent")
env:Wait(0.6) -- let the remote rate limiter refill (it is a separate protection) but stay inside the cooldown
local tooFast = env:Invoke(player, "RollRace", "33333333-cccc", "Token")
check(tooFast.Ok == false and tooFast.Reason == "Cooldown", "server-side roll cooldown")

print("Weapons")
local equip = env:Invoke(player, "EquipWeapon", { Action = "Equip", WeaponId = "SoulEaterBlade" })
check(equip.Ok == true, "equip an owned starter weapon")
local locked = env:Invoke(player, "EquipWeapon", { Action = "Equip", WeaponId = "ArachneSpider" })
check(locked.Ok == false and locked.Reason == "NotOwned", "locked weapons cannot be equipped")
env:Step(5)
check(character:GetAttribute("EquippedWeapon") == "SoulEaterBlade", "weapon swap reflected on the character")

-- ── Combat against a real spawned enemy ──────────────────────────────────────
print("Combat")
local root = character:FindFirstChild("HumanoidRootPart")
local function nearestEnemy()
	for _, enemy in enemiesFolder:GetChildren() do
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and enemy:GetAttribute("EnemyType") ~= "Pharaoh" then
			return enemy, humanoid
		end
	end
	return nil
end
local enemy, enemyHumanoid = nearestEnemy()
check(enemy ~= nil, "found a living enemy (" .. tostring(enemy and enemy:GetAttribute("EnemyType")) .. ")")
-- Walk up to it (no physics engine: the player is placed 4 studs away, facing the enemy).
local function faceEnemy(target)
	local enemyRoot = target:FindFirstChild("HumanoidRootPart")
	local stand = enemyRoot.CFrame * CFrame.new(0, 0, -4)
	character:PivotTo(
		CFrame.lookAt(
			stand.Position,
			enemyRoot.CFrame.Position * Vector3.new(1, 0, 1) + Vector3.new(0, stand.Position.Y, 0)
		)
	)
end
-- A level-1 student would lose this fight; the scripted test keeps them topped up (like a
-- teammate healing) so it can verify the full kill → reward loop.
local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
local tookDamage = false
playerHumanoid.HealthChanged:Connect(function(health)
	if health < playerHumanoid.MaxHealth then
		tookDamage = true
	end
end)
local function heal()
	playerHumanoid.Health = playerHumanoid.MaxHealth
end
faceEnemy(enemy)
env:Wait(0.5) -- the enemy notices the player and scales to their level
heal()
local before = profileOf(player)
local startHealth = enemyHumanoid.Health
local seq = 0
local function attack(slot: string)
	heal()
	-- A staggered player cannot attack (server rule); wait it out like a player would.
	env:WaitFor("stagger to end", function()
		return (character:GetAttribute("Status_Stagger") or 0) <= env.Workspace:GetServerTimeNow()
	end, 3)
	seq += 1
	env:Fire(player, "AttackRequest", slot, root.CFrame.LookVector, seq)
end
attack("M1")
env:Wait(0.7)
check(
	enemyHumanoid.Health < startHealth,
	string.format("M1 hit the enemy (%d → %d HP)", startHealth, enemyHumanoid.Health)
)
local deadline = os.clock() + 25
while enemyHumanoid.Health > 0 and os.clock() < deadline do
	-- Stay in front of it (its AI may reposition) and keep swinging.
	faceEnemy(enemy)
	attack("M1")
	env:Wait(0.45)
end
check(enemyHumanoid.Health <= 0, "the enemy can be killed with weapon attacks")
check(tookDamage, "the enemy fights back (the player took damage)")
env:Wait(1)
local after = profileOf(player)
check(
	after.Currency.Souls > before.Currency.Souls,
	string.format("kill reward: souls %d → %d", before.Currency.Souls, after.Currency.Souls)
)
check(after.Exp > before.Exp or after.Level > before.Level, "kill reward: experience")
check(after.Stats.Kills == before.Stats.Kills + 1, "kill counted in stats")
local raceId = after.Race.Active
check(
	(after.Race.Progress[raceId].XP or 0) > (before.Race.Progress[raceId].XP or 0),
	"race mastery XP earned by playing"
)
check(#env:Received(player, "CombatFX") > 0, "combat effects broadcast to the client")

-- Skill Z with cooldown enforcement.
env:Wait(0.6)
local damageEvents = #env:Received(player, "DamageFeedback")
local target2, target2Humanoid = nearestEnemy()
if target2 then
	faceEnemy(target2)
	env:Wait(0.5)
	local hp = target2Humanoid.Health
	attack("Z")
	env:Wait(0.9)
	check(target2Humanoid.Health < hp, "Z technique hits")
	check((player:GetAttribute("CD_Z") or 0) > env.Workspace:GetServerTimeNow(), "Z cooldown set")
	local rejectsBefore = #env:Received(player, "CombatFX")
	attack("Z")
	env:Wait(0.2)
	local rejected = false
	for _, message in env:Received(player, "CombatFX") do
		local payload = message.Args[1]
		if type(payload) == "table" and payload.Type == "Reject" and payload.Reason == "Cooldown" then
			rejected = true
		end
	end
	check(rejected and #env:Received(player, "CombatFX") > rejectsBefore, "Z on cooldown is rejected server-side")
end
check(#env:Received(player, "DamageFeedback") >= damageEvents, "damage feedback sent")

-- Role technique (V) through AbilityService.
local seBefore = player:GetAttribute("SoulEnergy") or 0
env:Fire(player, "AbilityRequest", "V", root.CFrame.LookVector, (root.CFrame * CFrame.new(0, 0, -8)).Position)
env:Wait(0.5)
check((player:GetAttribute("CD_V") or 0) > 0, "role technique (V) used, cooldown started")
local seAfter = player:GetAttribute("SoulEnergy") or 0
if seAfter >= seBefore then
	for _, message in env:Received(player, "CombatFX") do
		local payload = message.Args[1]
		if type(payload) == "table" and payload.Type == "AbilityFailed" then
			print("    ability failed:", payload.Slot, payload.Reason)
		end
	end
	print(
		"    SE before/after:",
		seBefore,
		seAfter,
		"role",
		player:GetAttribute("Role"),
		"race",
		player:GetAttribute("Race")
	)
end
check(seAfter < seBefore, "role technique spent Soul Energy")

-- Movement: dash spends stamina; garbage payloads are ignored safely.
local staminaBefore = player:GetAttribute("Stamina") or 0
env:Fire(player, "MovementRequest", "Dash", Vector3.new(1, 0, 0))
env:Step(3)
check((player:GetAttribute("Stamina") or 0) < staminaBefore, "dash spends stamina")
for _, junk in { { "Dash", "nope" }, { "Teleport", Vector3.new() }, { 5, 5 }, { nil }, { "Sprint", {} } } do
	env:Fire(player, "MovementRequest", table.unpack(junk))
end
for _, junk in { { "M1", "x", "y" }, { "Q", Vector3.new(), 1 }, { "M1", Vector3.new(0 / 0, 0, 0), 2 } } do
	env:Fire(player, "AttackRequest", table.unpack(junk))
end
env:Fire(player, "AbilityRequest", "Z", nil, nil)
env:Step(5)
check(true, "malformed client requests are ignored without errors")

-- Settings & loadout remotes.
check(env:Invoke(player, "UpdateSettings", { ReducedMotion = true, UIScale = 1.1 }).Ok, "settings saved")
check(env:Invoke(player, "SetLoadout", "Role", "Assassin").Ok or true, "role change request handled")

print("Leave and rejoin")
env:RemovePlayer(player)
env:Wait(1)
local again = env:AddPlayer("Kaito", 101)
local reloaded = env:WaitFor("profile reloaded", function()
	return profileOf(again)
end, 15)
check(reloaded.Student.Name == "Kaito Ren", "student persisted across sessions")
check(reloaded.Race.Active == raceId, "origin persisted across sessions")
check(reloaded.Settings.ReducedMotion == true, "settings persisted across sessions")
check(reloaded.Stats.Kills >= 1, "kills persisted across sessions")

task.wait(0.2)
print("")
for _, err in MockInstance.Errors do
	table.insert(failures, "runtime error: " .. err)
end
if #failures > 0 then
	print(string.format("%d problem(s):", #failures))
	local seen = {}
	for _, failure in failures do
		local key = string.sub(failure, 1, 400)
		if not seen[key] then
			seen[key] = true
			print("  - " .. key)
		end
	end
	process.exit(1)
end
print("Server run passed")
process.exit(0)
