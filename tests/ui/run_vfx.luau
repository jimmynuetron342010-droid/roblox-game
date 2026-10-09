--[[
	VFX + animation run (Lune): executes the real VFXController, all 10 weapon effects, every
	ability visual kind, impacts, soul orbs and the client AnimationController/AnimatorCore on a
	rig holding each weapon — against strict mock Instances validated by the Roblox API dump.

	  lune run tests/ui/run_vfx.luau

	Fails on any runtime error, invalid property/method use, wrong value type, or if effects
	never emit particles / never clean up their pooled parts.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Env = require("./Env")
local MockInstance = require("./MockInstance")

local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3
local Enum = roblox.Enum

local env = Env.new({ Real3D = true })
local R = env.Loader.RequirePath
local PreviewRig = R("ReplicatedStorage.Modules.Rig.PreviewRig")
local WeaponBuilder = R("ReplicatedStorage.Modules.WeaponBuilder")
local WeaponConfig = R("ReplicatedStorage.Modules.WeaponConfig")
local VFXController = R("ReplicatedStorage.Modules.VFXController")
local Client = "StarterPlayer.StarterPlayerScripts.Client.Controllers."
local VFXClient = R(Client .. "VFXClient")
local AnimationController = R(Client .. "AnimationController")

local failures = {}
local function check(condition: any, message: string)
	print((condition and "  ✓ " or "  ✗ ") .. message)
	if not condition then
		table.insert(failures, message)
	end
end

-- ── A player character: R15 rig + Humanoid + Animator ────────────────────────
local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
rig.Name = env.Player.Name
local humanoid = rig:FindFirstChildOfClass("Humanoid") or MockInstance.new("Humanoid", rig)
humanoid.MaxHealth = 100
humanoid.Health = 100
humanoid.HipHeight = 2
MockInstance.Override(humanoid, "GetState", function()
	return Enum.HumanoidStateType.Running
end)
local animator = MockInstance.new("Animator", humanoid)
MockInstance.Override(animator, "LoadAnimation", function(_, animation)
	local track =
		{ Length = 1, IsPlaying = false, Priority = Enum.AnimationPriority.Core, Looped = false, Animation = animation }
	function track.Play(self)
		self.IsPlaying = true
	end
	function track.Stop(self)
		self.IsPlaying = false
	end
	function track.AdjustWeight() end
	function track.AdjustSpeed() end
	return track
end)
rig.Parent = env.Workspace
MockInstance.SetInternal(env.Player, "Character", rig)
-- An enemy target for impacts / homing / roots.
local dummy = PreviewRig.Build({ Origin = CFrame.new(0, 3, -12) })
dummy.Name = "Dummy"
local enemies = MockInstance.new("Folder", env.Workspace)
enemies.Name = "Enemies"
dummy.Parent = enemies

-- ── Boot the client systems that own 3D work ─────────────────────────────────
VFXClient:Init()
VFXClient:Start()
AnimationController:Init()
AnimationController:Start()
env.Player.CharacterAdded:Fire(rig)
env:Wait(0.2)
check(AnimationController.Get(rig) ~= nil, "AnimationController tracks the R15 character")
check(env.Workspace:FindFirstChild("ClientVFX", true) ~= nil, "VFXController created its effect containers")

local activeKinds = {}
local function pooledCount(): number
	local folder = env.Workspace:FindFirstChild("ClientVFX", true)
	local active = 0
	if folder then
		for _, d in folder:GetDescendants() do
			-- Released pool parts are parked far away (VFXController FAR); emitter hosts stay put.
			if d:IsA("BasePart") and d:GetAttribute("PoolKind") and d.CFrame.Position.Magnitude < 5000 then
				active += 1
				activeKinds[d:GetAttribute("PoolKind")] = (activeKinds[d:GetAttribute("PoolKind")] or 0) + 1
			end
		end
	end
	return active
end

-- ── Every weapon: equip, idle/walk, every attack (animation + effect) ─────────
for _, id in WeaponConfig.Order do
	local weapon = WeaponConfig.Weapons[id]
	for _, form in weapon.FormOrder or { false } do
		local label = form and (id .. "-" .. form) or id
		local before = #MockInstance.Errors
		local emittedBefore = MockInstance.Emitted
		WeaponBuilder.Equip(rig, id, { Form = form or nil, Drawn = true })
		rig:SetAttribute("WeaponDrawn", true)
		env:Wait(0.15)
		local config = WeaponConfig.Resolve(id, form or nil)
		local attacks = table.clone(config.Moveset.M1)
		table.insert(attacks, config.Moveset.Z)
		table.insert(attacks, config.Moveset.X)
		for _, attackId in attacks do
			local attack = WeaponConfig.Attacks[attackId]
			env.FireClient("CombatFX", {
				Type = "Attack",
				Character = rig,
				WeaponId = id,
				AttackId = attackId,
				Duration = attack.Duration,
				Direction = Vector3.new(0, 0, -1),
			})
			env:Wait(attack.Duration + 0.1)
			env.FireClient("CombatFX", {
				Type = "Impacts",
				ImpactType = config.ImpactType,
				Positions = { Vector3.new(0, 3, -10), Vector3.new(1, 2, -11) },
				Direction = Vector3.new(0, 0, -1),
			})
		end
		check(#MockInstance.Errors == before, label .. ": equip, idle and every attack + impact run cleanly")
		check(MockInstance.Emitted > emittedBefore, label .. ": its attacks emitted particles")
	end
end

-- ── Ability visuals (every kind) with server-shaped payloads ──────────────────
local abilityPayload = {
	Character = rig,
	Origin = Vector3.new(0, 3.8, 0),
	Position = Vector3.new(0, 0.5, -10),
	Direction = Vector3.new(0, 0, -1),
	Radius = 12,
	Duration = 1.2,
	Delay = 0.6,
	Color = Color3.fromRGB(150, 90, 255),
	Speed = 60,
	Range = 40,
	Count = 3,
	Target = dummy:FindFirstChild("HumanoidRootPart"),
	From = Vector3.new(0, 3, 0),
	To = Vector3.new(0, 3, -8),
	Aftershock = 8,
	Rate = 20,
}
for _, kind in
	{
		"Telegraph",
		"Slam",
		"Judgment",
		"Buff",
		"Heal",
		"Blink",
		"Pulse",
		"Cone",
		"AreaBlast",
		"Well",
		"Projectile",
		"Construct",
		"MasteryUp",
		"Dash",
		"Wrap",
		"Rooted",
	}
do
	local before = #MockInstance.Errors
	local payload = table.clone(abilityPayload)
	payload.Type = "Ability"
	payload.Kind = kind
	env.FireClient("CombatFX", payload)
	env:Wait(0.25)
	check(#MockInstance.Errors == before, "ability visual " .. kind)
end
env.FireClient("CombatFX", { Type = "MasteryUp", Character = rig, Race = "Shinigami" })
env.FireClient("CombatFX", { Type = "BlackBlood", Character = rig })
env.FireClient(
	"CombatFX",
	{ Type = "Dash", Character = rig, Origin = Vector3.new(0, 3, 0), Direction = Vector3.new(1, 0, 0) }
)
env.FireClient(
	"CombatFX",
	{ Type = "EnemyDeath", Position = Vector3.new(0, 3, -12), Killer = env.Player.UserId, Boss = true }
)
env.FireClient("CombatFX", { Type = "Gesture", Character = rig, Action = "Hurt", Duration = 0.4 })
env.FireClient("DamageFeedback", { Kind = "Taken", Amount = 12 })
env:Wait(2.5)

-- Settings applied to the VFX system at runtime.
VFXController.SetQuality("Low")
VFXController.SetReducedMotion(true)
VFXController.SetCameraShake(false)
env.FireClient(
	"CombatFX",
	{ Type = "Ability", Kind = "Slam", Position = Vector3.new(0, 0.5, -6), Radius = 10, Aftershock = 6 }
)
env:Wait(0.5)
VFXController.SetQuality("High")
VFXController.SetReducedMotion(false)

-- Everything spawned must be released back to the pools once effects finish.
env:Wait(3)
local leftover = pooledCount()
local kinds = {}
for kind, count in activeKinds do
	table.insert(kinds, kind .. "=" .. count)
end
check(
	leftover == 0,
	string.format("effects release every pooled part when done (%d still out: %s)", leftover, table.concat(kinds, ", "))
)
WeaponBuilder.Unequip(rig)
env:Wait(0.2)
check(rig:FindFirstChild(WeaponBuilder.EquippedName) == nil, "unequip removes the weapon model")

task.wait(0.1)
print("")
for _, err in MockInstance.Errors do
	table.insert(failures, "runtime error: " .. err)
end
if #failures > 0 then
	print(string.format("%d problem(s):", #failures))
	local seen = {}
	for _, failure in failures do
		local key = string.sub(failure, 1, 300)
		if not seen[key] then
			seen[key] = true
			print("  - " .. key)
		end
	end
	process.exit(1)
end
print(string.format("VFX run passed (%d particles emitted)", MockInstance.Emitted))
process.exit(0)
