--[[
	VFXClient
	Turns server CombatFX messages into animations and effects on this client:
	  Attack   -> play the attacker's animation + the attack's VFX (other players only; the
	              attacker predicted its own)
	  Impacts  -> Effect 10 (weapon impact) at server-confirmed hit points
	  Ability / Gesture / Dash / MasteryUp / BlackBlood / EnemyDeath -> ability visuals
	  Knockback / Reject / AbilityFailed / Notice -> local gameplay feedback
	Purely cosmetic: nothing here can change health, damage or rewards.
]]

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Net = require(Modules.Core.Net)
local RaceConfig = require(Modules.Config.RaceConfig)
local RarityConfig = require(Modules.Config.RarityConfig)
local Signal = require(Modules.Core.Signal)
local VFXController = require(Modules.VFXController)
local WeaponConfig = require(Modules.WeaponConfig)

local AnimationController = require(script.Parent.AnimationController)

local VFXClient = {}

VFXClient.Knockback = Signal.new() -- (velocity)
VFXClient.Rejected = Signal.new() -- (seq, reason)
VFXClient.AbilityFailed = Signal.new() -- (slot, reason)
VFXClient.Notice = Signal.new() -- (text)

local player = Players.LocalPlayer

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end

-- Plays an attack's configured effect (used for local prediction and remote players).
function VFXClient.PlayAttack(
	character: Model,
	weaponId: string,
	attackId: string,
	duration: number,
	direction: Vector3
)
	local attack = WeaponConfig.Attacks[attackId]
	if not attack or not attack.VFX then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local weapon = character:FindFirstChild("EquippedWeapon")
	local params = {
		Character = character,
		Weapon = weapon,
		WeaponId = weaponId,
		AttackId = attackId,
		Attack = attack,
		Duration = duration,
		Direction = direction,
		Params = attack.VFX.Params,
	}
	local first = attack.Hits[1]
	if attack.VFX.Effect == "ShurikenThrow" and first and root then
		params.Projectile = { Speed = first.Speed, Range = first.Range, Count = first.Count, Spread = first.Spread }
		params.Origin = root.Position + Vector3.new(0, 0.8, 0) + flat(direction) * 1.5
		params.Delay = first.Time * (duration / attack.Duration)
	end
	if attack.VFX.Effect == "GroundSlam" and root then
		params.Params = table.clone(attack.VFX.Params or {})
		params.Params.Radius = params.Params.Radius or (first and first.Radius)
	end
	VFXController.Play(attack.VFX.Effect, params)
	local weaponConfig = WeaponConfig.Weapons[weaponId]
	if weaponConfig and weaponConfig.Sounds and root then
		VFXController.Sound(weaponConfig.Sounds.Swing or weaponConfig.Sounds.Shot, root.Position, 0.5)
	end
end

function VFXClient.Dash(character: Model, origin: Vector3, direction: Vector3)
	VFXController.Play("Ability", { Kind = "Dash", Character = character, Origin = origin, Direction = direction })
end

-- Red Kishin Egg soul rising from a defeated enemy and flying to the killer.
local function soulOrb(position: Vector3, killerId: number, boss: boolean)
	local orb = VFXController.AcquirePart("SoulOrb", function()
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		return p
	end)
	local size = boss and 2.2 or 1.2
	orb.Size = Vector3.new(size, size * 1.25, size)
	orb.Color = Color3.fromRGB(230, 40, 50)
	orb.Transparency = 0.1
	local killer = Players:GetPlayerByUserId(killerId)
	local t = 0
	local start = position
	VFXController.AddTask(function(dt)
		t += dt
		local character = killer and killer.Character
		local target = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local rise = start + Vector3.new(0, 3 + math.sin(t * 6) * 0.2, 0)
		local p
		if t < 0.7 or not target then
			p = start:Lerp(rise, math.min(t / 0.7, 1))
		else
			local alpha = math.min((t - 0.7) / 0.45, 1)
			p = rise:Lerp((target :: BasePart).Position, alpha * alpha)
		end
		orb.CFrame = CFrame.new(p) * CFrame.Angles(0, t * 4, 0)
		VFXController.Emit("Soul", CFrame.new(p), 1, { Color = ColorSequence.new(Color3.fromRGB(255, 80, 90)) })
		if t >= 1.15 or (t >= 0.7 and not target) then
			if target then
				VFXController.Flash((target :: BasePart).Position, Color3.fromRGB(255, 80, 90), 2, 8, 0.2)
			end
			VFXController.ReleasePart(orb)
			return false
		end
		return true
	end)
end

local handlers = {}

handlers.Attack = function(payload)
	local character = payload.Character
	local attack = WeaponConfig.Attacks[payload.AttackId]
	if not character or not attack then
		return
	end
	AnimationController.PlayAction(character, attack.Animation, payload.Duration)
	VFXClient.PlayAttack(character, payload.WeaponId, payload.AttackId, payload.Duration, payload.Direction)
end

handlers.Impacts = function(payload)
	local direction = payload.Direction or Vector3.new(0, 0, -1)
	for _, position in payload.Positions or {} do
		VFXController.Play("WeaponImpact", {
			ImpactType = payload.ImpactType,
			Position = position,
			Normal = -flat(direction),
			Direction = direction,
		})
	end
end

handlers.Ability = function(payload)
	VFXController.Play("Ability", payload)
end

handlers.Gesture = function(payload)
	AnimationController.PlayAction(payload.Character, payload.Action, payload.Duration or 0.7)
end

handlers.Dash = function(payload)
	VFXController.Play(
		"Ability",
		{ Kind = "Dash", Character = payload.Character, Origin = payload.Origin, Direction = payload.Direction }
	)
end

handlers.MasteryUp = function(payload)
	local race = RaceConfig.ById[payload.Race]
	local color = race and RarityConfig.Tiers[race.Rarity].Color or nil
	VFXController.Play("Ability", { Kind = "MasteryUp", Character = payload.Character, Color = color })
end

handlers.BlackBlood = function(payload)
	VFXController.Play(
		"Ability",
		{ Kind = "Buff", Character = payload.Character, Color = Color3.fromRGB(20, 16, 24), Duration = 5, Rate = 26 }
	)
end

handlers.EnemyDeath = function(payload)
	if payload.Position then
		soulOrb(payload.Position, payload.Killer or 0, payload.Boss == true)
	end
end

handlers.Knockback = function(payload)
	if typeof(payload.Velocity) == "Vector3" then
		VFXClient.Knockback:Fire(payload.Velocity)
	end
end

handlers.Reject = function(payload)
	VFXClient.Rejected:Fire(payload.Seq, payload.Reason)
end

handlers.AbilityFailed = function(payload)
	VFXClient.AbilityFailed:Fire(payload.Slot, payload.Reason)
end

handlers.Notice = function(payload)
	VFXClient.Notice:Fire(payload.Text)
end

function VFXClient:Init()
	VFXController.Init()
end

function VFXClient:Start()
	Net.Event("CombatFX").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local handler = handlers[payload.Type]
		if handler then
			local ok, err = pcall(handler, payload)
			if not ok then
				warn("[VFXClient] " .. tostring(payload.Type) .. ": " .. tostring(err))
			end
		end
	end)
	-- Flinch on taking damage (only when nothing else is playing).
	Net.Event("DamageFeedback").OnClientEvent:Connect(function(payload)
		if payload.Kind == "Taken" and player.Character then
			local entry = AnimationController.Get(player.Character)
			if entry and not entry.Animator.Action then
				AnimationController.PlayAction(player.Character, "Hurt", 0.35)
			end
		end
	end)
end

return VFXClient
