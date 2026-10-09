--[[
	CombatService
	Authoritative combat. Clients only *request* attacks ("I pressed M1 aiming here"); the server:
	  1. validates the request (alive, not staggered, weapon equipped, combo step, cooldowns, stamina)
	  2. times every hit itself (scaled by the attacker's Attack Speed)
	  3. finds targets with server positions (arc / circle / line / projectile / hitscan / ticks)
	  4. computes damage through StatCalculator (additive pool + capped multiplicative buffs) and the
	     target's mitigation, then applies stagger, knockback, statuses and gameplay events
	Visuals are broadcast separately (FXBroadcast) and never decide anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local AbilityConfig = require(Modules.Config.AbilityConfig)
local GameConfig = require(Modules.Config.GameConfig)
local ProjectileController = require(Modules.ProjectileController)
local StatCalculator = require(Modules.Core.StatCalculator)
local Validate = require(Modules.Core.Validate)
local WeaponConfig = require(Modules.WeaponConfig)

local Server = script.Parent.Parent
local FXBroadcast = require(Server.Core.FXBroadcast)
local GameEvents = require(Server.Core.GameEvents)
local Net = require(Modules.Core.Net)
local RemoteGuard = require(Server.Core.RemoteGuard)

local CombatService = {}

local DataService, StatService, StatusService, WeaponService, PartnerService, MadnessService, EnemyService, MapService

local damageFeedback: RemoteEvent

export type Combatant = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	Enemy: any?,
}

type AttackState = {
	Step: number,
	LastM1End: number,
	BusyUntil: number,
	Cooldowns: { [string]: number },
	UndyingReadyAt: number,
}

local attackStates: { [Player]: AttackState } = {}
local enemies: { [Model]: any } = {}

local function state(player: Player): AttackState
	local s = attackStates[player]
	if not s then
		s = { Step = 0, LastM1End = -math.huge, BusyUntil = 0, Cooldowns = {}, UndyingReadyAt = 0 }
		attackStates[player] = s
	end
	return s
end

-- ── Combatants ────────────────────────────────────────────────────────────────
function CombatService:RegisterEnemy(model: Model, enemy)
	enemies[model] = enemy
	model.Destroying:Connect(function()
		enemies[model] = nil
	end)
end

function CombatService:UnregisterEnemy(model: Model)
	enemies[model] = nil
end

function CombatService:GetCombatant(model: Instance?): Combatant?
	if not model or not model:IsA("Model") then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	local enemy = enemies[model]
	if not player and not enemy then
		return nil
	end
	return { Model = model, Humanoid = humanoid, Root = root :: BasePart, Player = player, Enemy = enemy }
end

function CombatService:AllCombatants(): { Combatant }
	local list = {}
	for _, player in Players:GetPlayers() do
		local c = self:GetCombatant(player.Character)
		if c then
			table.insert(list, c)
		end
	end
	for model in enemies do
		local c = self:GetCombatant(model)
		if c then
			table.insert(list, c)
		end
	end
	return list
end

function CombatService:StatsOf(c: Combatant)
	if c.Player then
		return StatService:Get(c.Player)
	end
	return c.Enemy.Stats
end

-- Can `attacker` damage `target`? (no self damage, PvP only inside PvP zones)
function CombatService:CanDamage(attacker: Combatant, target: Combatant): boolean
	if attacker.Model == target.Model then
		return false
	end
	if attacker.Enemy and target.Enemy then
		return false
	end
	if attacker.Player and target.Player then
		if GameConfig.Combat.PvP.Mode ~= "Zones" then
			return false
		end
		return MapService:IsPvPZone(attacker.Root.Position) and MapService:IsPvPZone(target.Root.Position)
	end
	return true
end

-- ── Spatial queries ───────────────────────────────────────────────────────────
local BODY_RADIUS = 1.4

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-4 and f.Unit or Vector3.new(0, 0, -1)
end

function CombatService:QueryArc(attacker: Combatant, direction: Vector3, range: number, angle: number, height: number): { Combatant }
	local out = {}
	local origin = attacker.Root.Position
	local forward = flat(direction)
	local cosLimit = math.cos(math.rad(math.min(angle, 360) / 2))
	for _, target in self:AllCombatants() do
		if self:CanDamage(attacker, target) then
			local offset = target.Root.Position - origin
			local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if distance - BODY_RADIUS <= range + GameConfig.Combat.MeleeLeniency and math.abs(offset.Y) <= height then
				if angle >= 360 or distance < 3 or flat(offset):Dot(forward) >= cosLimit then
					table.insert(out, target)
				end
			end
		end
	end
	return out
end

function CombatService:QueryCircle(attacker: Combatant?, center: Vector3, radius: number, height: number?): { Combatant }
	local out = {}
	for _, target in self:AllCombatants() do
		if not attacker or self:CanDamage(attacker, target) then
			local offset = target.Root.Position - center
			if Vector3.new(offset.X, 0, offset.Z).Magnitude - BODY_RADIUS <= radius and math.abs(offset.Y) <= (height or 10) then
				table.insert(out, target)
			end
		end
	end
	return out
end

function CombatService:QueryLine(attacker: Combatant, a: Vector3, b: Vector3, width: number): { Combatant }
	local out = {}
	local ab = b - a
	local lengthSq = math.max(ab:Dot(ab), 1e-4)
	for _, target in self:AllCombatants() do
		if self:CanDamage(attacker, target) then
			local p = target.Root.Position
			local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
			local closest = a + ab * t
			if (p - closest).Magnitude - BODY_RADIUS <= width / 2 then
				table.insert(out, target)
			end
		end
	end
	return out
end

-- ── Damage ────────────────────────────────────────────────────────────────────
export type DamageInfo = {
	Base: number,
	Tags: { [string]: boolean },
	Ranged: boolean?,
	Poison: boolean?,
	TrueDamage: boolean?,
	Stagger: number?,
	Knockback: number?,
	Direction: Vector3?,
	WeaponId: string?,
	AttackId: string?,
	AbilityId: string?,
	Status: { Name: string, Duration: number, Magnitude: number?, Source: string?, TickDamage: number? }?,
	NoEvents: boolean?,
}

local function attackerMultiplier(attacker: Combatant, tags)
	if attacker.Enemy then
		return 1
	end
	local player = attacker.Player :: Player
	local values = StatService:GetValues(player)
	local buffs = StatService:DamageBuffs(player, tags)
	local sync = PartnerService:DamageMultiplier(player)
	if sync ~= 1 then
		table.insert(buffs, sync)
	end
	local madness = MadnessService:OutgoingMultiplier(player)
	if madness ~= 1 then
		table.insert(buffs, madness)
	end
	local multiplier = StatCalculator.DamageMultiplier(values, tags, buffs)
	return multiplier * StatusService:OutgoingMultiplier(attacker.Model)
end

local function mitigate(target: Combatant, raw: number, info: DamageInfo): number
	local stats = CombatService:StatsOf(target)
	if not stats then
		return raw
	end
	local shred = StatusService:DefenseShred(target.Model)
	local effective = stats
	if shred > 0 then
		effective = table.clone(stats)
		effective.DamageReduction = StatCalculator.DamageReductionFromDefense(stats.Values.Defense * (1 - shred), stats.Level or 1)
	end
	local damage = StatCalculator.Mitigate(raw, effective, { Ranged = info.Ranged, Poison = info.Poison, TrueDamage = info.TrueDamage })
	if target.Player then
		damage *= MadnessService:IncomingMultiplier(target.Player)
	end
	return damage
end

local function feedback(player: Player?, payload)
	if player and player.Parent then
		damageFeedback:FireClient(player, payload)
	end
end

-- Returns the damage actually dealt.
function CombatService:ApplyDamage(attacker: Combatant, target: Combatant, info: DamageInfo): number
	if target.Humanoid.Health <= 0 or StatusService:Has(target.Model, "Invulnerable") then
		return 0
	end
	local raw = info.Base * attackerMultiplier(attacker, info.Tags)
	local damage = math.max(1, math.floor(mitigate(target, raw, info) + 0.5))
	local humanoid = target.Humanoid
	local before = humanoid.Health

	-- Zombie: Undying Persistence (strict: >25% health before the hit, long cooldown).
	if target.Player and damage >= before then
		local profile = DataService:GetProfile(target.Player)
		local s = state(target.Player)
		if profile and profile.Race.Active == "Zombie" and before > humanoid.MaxHealth * 0.25 and os.clock() >= s.UndyingReadyAt then
			s.UndyingReadyAt = os.clock() + 180
			damage = math.floor(before - 1)
			StatusService:Apply(target.Model, "Invulnerable", { Duration = 1.5, Source = "UndyingPersistence" })
			GameEvents.Fire(target.Player, "UndyingTriggered", {})
			FXBroadcast.Broadcast({ Type = "Ability", Kind = "Buff", Character = target.Model, Color = Color3.fromRGB(150, 255, 150), Duration = 1.5 }, target.Root.Position)
		end
	end

	humanoid.Health = math.max(0, before - damage)
	local dealt = before - humanoid.Health

	if attacker.Player then
		StatService:TagCombat(attacker.Player)
	end
	if target.Player then
		StatService:TagCombat(target.Player)
		MadnessService:OnDamaged(target.Player, humanoid.Health / humanoid.MaxHealth)
	end

	-- Stagger (reduced by Interrupt Resistance) and knockback (reduced by Knockback Resistance).
	local targetValues = (CombatService:StatsOf(target) or { Values = {} }).Values
	if info.Stagger and info.Stagger > 0 then
		local duration = info.Stagger * (1 - (targetValues.InterruptResistance or 0))
		if target.Enemy and target.Enemy.Def.IsBoss then
			duration *= 0.3
		end
		StatusService:Apply(target.Model, "Stagger", { Duration = duration, Source = info.AttackId })
	end
	if info.Knockback and info.Knockback > 0 and info.Direction then
		local strength = info.Knockback * (1 - (targetValues.KnockbackResistance or 0))
		local velocity = flat(info.Direction) * strength + Vector3.new(0, strength * 0.25, 0)
		if target.Player then
			FXBroadcast.To(target.Player, { Type = "Knockback", Velocity = velocity })
		elseif not (target.Enemy and target.Enemy.Def.IsBoss) then
			target.Root.AssemblyLinearVelocity += velocity
		end
	end
	if info.Status then
		local s = info.Status
		local applied = StatusService:Apply(target.Model, s.Name, {
			Duration = s.Duration,
			Magnitude = s.Magnitude,
			Source = s.Source,
			Applier = attacker.Model,
			ApplierStats = attacker.Player and StatService:GetValues(attacker.Player) or nil,
			TargetStats = targetValues,
			TickDamage = s.TickDamage,
		})
		if applied > 0 and attacker.Player then
			GameEvents.Fire(attacker.Player, "StatusApplied", { Status = s.Name, Source = s.Source })
		end
	end

	-- Gameplay events, sustain and meters.
	if attacker.Player and not info.NoEvents then
		local player = attacker.Player
		local tags = info.Tags
		GameEvents.Fire(player, "DamageDealt", { Amount = dealt, Magic = tags.Magic == true, Ranged = info.Ranged == true })
		if tags.Weapon and info.WeaponId then
			GameEvents.Fire(player, "WeaponHit", {
				WeaponId = info.WeaponId,
				Melee = tags.Melee == true,
				Surge = StatService:HasBuff(player, "ResonanceSurge"),
			})
			CombatService:AddResonance(player)
		end
		if info.AbilityId then
			GameEvents.Fire(player, "AbilityHit", { AbilityId = info.AbilityId })
		end
		local beast = StatService:GetBuffData(player, "BeastShift")
		if beast and beast.Lifesteal and beast.Lifesteal > 0 and tags.Melee then
			local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if own and own.Health > 0 then
				own.Health = math.min(own.MaxHealth, own.Health + dealt * beast.Lifesteal)
				GameEvents.Fire(player, "Healed", { Amount = dealt * beast.Lifesteal })
			end
		end
		if StatService:HasBuff(player, "ShadowStepNext") then
			StatService:RemoveBuff(player, "ShadowStepNext")
		end
	end
	if target.Player then
		GameEvents.Fire(target.Player, "DamageTaken", { Amount = dealt, Ranged = info.Ranged == true })
	end
	if target.Enemy then
		target.Enemy:OnDamaged(attacker, dealt)
	end

	local position = target.Root.Position + Vector3.new(0, 1.5, 0)
	feedback(attacker.Player, { Target = target.Model, Amount = dealt, Position = position, Kind = info.Tags.Magic and "Magic" or "Hit" })
	feedback(target.Player, { Target = target.Model, Amount = dealt, Position = position, Kind = "Taken" })

	if humanoid.Health <= 0 and before > 0 then
		CombatService:OnKilled(attacker, target, info)
	end
	return dealt
end

function CombatService:OnKilled(attacker: Combatant, target: Combatant, info: DamageInfo)
	if target.Enemy then
		EnemyService:OnKilled(target.Enemy, attacker, info)
	end
	if attacker.Player and target.Player then
		FXBroadcast.To(attacker.Player, { Type = "Notice", Text = "Defeated " .. target.Player.DisplayName })
	end
end

-- Demon Weapon: Resonance meter builds on weapon hits (faster while synchronized).
function CombatService:AddResonance(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile or profile.Race.Active ~= "DemonWeapon" or StatService:HasBuff(player, "ResonanceSurge") then
		return
	end
	local stage = (profile.Race.Progress.DemonWeapon or { Stage = 1 }).Stage
	local _, params = AbilityConfig.Resolve("ResonanceSurge", stage)
	local gain = params.MeterPerHit * (PartnerService:GetSync(player) and params.SyncedMeterMultiplier or 1)
	local current = player:GetAttribute("Resonance") or 0
	player:SetAttribute("Resonance", math.min(params.MeterMax, current + gain))
end

-- ── Weapon attacks ────────────────────────────────────────────────────────────
local function impactFX(config, positions: { Vector3 }, direction: Vector3)
	if #positions == 0 then
		return
	end
	FXBroadcast.Broadcast({
		Type = "Impacts",
		ImpactType = config.ImpactType,
		Positions = positions,
		Direction = direction,
	}, positions[1])
end

local function resolveHit(_player: Player, attacker: Combatant, config, attackId: string, attack, hit, direction: Vector3, startPosition: Vector3, attackSpeed: number)
	local character = attacker.Model
	local humanoid = attacker.Humanoid
	if humanoid.Health <= 0 or not character.Parent or StatusService:Has(character, "Stagger") then
		return
	end
	local root = attacker.Root
	local tags = attack.Tags
	local function damageInfo()
		return {
			Base = hit.Damage,
			Tags = tags,
			Ranged = attack.Ranged == true,
			Stagger = hit.Stagger,
			Knockback = hit.Knockback,
			Direction = direction,
			WeaponId = config.Id,
			AttackId = attackId,
		}
	end
	local function strike(targets: { Combatant })
		local positions = {}
		for _, target in targets do
			local dealt = CombatService:ApplyDamage(attacker, target, damageInfo())
			if dealt > 0 then
				table.insert(positions, target.Root.Position + Vector3.new(0, 0.6, 0) - flat(direction) * 0.8)
			end
		end
		impactFX(config, positions, direction)
	end

	local shape = hit.Shape
	if shape == "Arc" then
		strike(CombatService:QueryArc(attacker, direction, hit.Range, hit.Angle, hit.Height))
	elseif shape == "Circle" then
		local center = root.Position + flat(direction) * (hit.Offset or 0)
		strike(CombatService:QueryCircle(attacker, center, hit.Radius, 8))
	elseif shape == "Line" then
		local endPoint = root.Position + flat(direction) * 3
		if (endPoint - startPosition).Magnitude > hit.Length + 6 then
			endPoint = startPosition + (endPoint - startPosition).Unit * (hit.Length + 6)
		end
		strike(CombatService:QueryLine(attacker, startPosition, endPoint, hit.Width))
	elseif shape == "Ticks" then
		for k = 0, hit.Count - 1 do
			task.delay(k * hit.Interval / attackSpeed, function()
				if humanoid.Health > 0 and not StatusService:Has(character, "Stagger") then
					strike(CombatService:QueryArc(attacker, direction, hit.Range, hit.Angle, 7))
				end
			end)
		end
	elseif shape == "Projectile" then
		local spec = WeaponConfig.Projectiles[hit.Projectile] or {}
		local count = hit.Count or 1
		local spread = math.rad(hit.Spread or 0)
		local origin = root.Position + Vector3.new(0, 0.8, 0) + flat(direction) * 1.5
		for i = 1, count do
			local offset = count > 1 and (i - (count + 1) / 2) * spread or 0
			local dir = CFrame.fromAxisAngle(Vector3.yAxis, offset) * direction
			ProjectileController.Simulate({
				Origin = origin,
				Direction = dir,
				Speed = hit.Speed,
				Range = hit.Range,
				Radius = spec.Radius or 0.8,
				Ignore = { character },
				OnHit = function(result)
					local model = result.Instance:FindFirstAncestorOfClass("Model")
					local target = CombatService:GetCombatant(model)
					if target and CombatService:CanDamage(attacker, target) then
						CombatService:ApplyDamage(attacker, target, damageInfo())
					end
					return false
				end,
			})
		end
	elseif shape == "Hitscan" then
		local spread = math.rad(hit.Spread or 0)
		local jitter = CFrame.Angles((math.random() - 0.5) * spread, (math.random() - 0.5) * spread, 0)
		local side = hit.Hand == "Left" and -0.7 or 0.7
		local origin = (root.CFrame * CFrame.new(side, 0.6, -1.2)).Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(origin, (jitter * direction).Unit * hit.Range, params)
		if result then
			local target = CombatService:GetCombatant(result.Instance:FindFirstAncestorOfClass("Model"))
			if target and CombatService:CanDamage(attacker, target) then
				CombatService:ApplyDamage(attacker, target, damageInfo())
			end
		end
	end
end

local function reject(player: Player, seq: number, reason: string)
	FXBroadcast.To(player, { Type = "Reject", Seq = seq, Reason = reason })
end

local function onAttack(player: Player, slot: any, aim: any, seq: any)
	if slot ~= "M1" and slot ~= "Z" and slot ~= "X" then
		return
	end
	if not Validate.Integer(seq, 0, 1e9) then
		return
	end
	local attacker = CombatService:GetCombatant(player.Character)
	if not attacker then
		return
	end
	local direction = Validate.Direction(aim) or attacker.Root.CFrame.LookVector
	direction = Vector3.new(direction.X, math.clamp(direction.Y, -0.6, 0.6), direction.Z).Unit
	if StatusService:Has(attacker.Model, "Stagger") then
		return reject(player, seq, "Staggered")
	end
	local weaponId, config = WeaponService:GetEquipped(player)
	if not weaponId or not config then
		return reject(player, seq, "NoWeapon")
	end
	if not WeaponService:IsDrawn(player) then
		WeaponService:SetDrawn(player, true)
	end
	local s = state(player)
	local now = os.clock()
	if now < s.BusyUntil - 0.12 then
		return reject(player, seq, "Busy")
	end
	local attackId: string
	if slot == "M1" then
		if now - s.LastM1End <= (config.ComboWindow or 0.8) then
			s.Step = s.Step % #config.Moveset.M1 + 1
		else
			s.Step = 1
		end
		attackId = config.Moveset.M1[s.Step]
	else
		attackId = config.Moveset[slot]
		if (s.Cooldowns[slot] or 0) > now then
			return reject(player, seq, "Cooldown")
		end
	end
	local attack = WeaponConfig.Attacks[attackId]
	if not attack then
		return reject(player, seq, "BadAttack")
	end
	local values = StatService:GetValues(player)
	local attackSpeed = math.max(values.AttackSpeed or 1, 0.5)
	if not StatService:SpendStamina(player, attack.Stamina or 0) then
		return reject(player, seq, "Stamina")
	end
	local duration = attack.Duration / attackSpeed
	s.BusyUntil = now + duration * 0.85
	if slot == "M1" then
		s.LastM1End = now + duration
	end
	if attack.Cooldown then
		local cooldown = StatCalculator.Cooldown(attack.Cooldown, values)
		s.Cooldowns[slot] = now + cooldown
		player:SetAttribute("CD_" .. slot, workspace:GetServerTimeNow() + cooldown)
	end
	StatService:TagCombat(player)

	FXBroadcast.Broadcast({
		Type = "Attack",
		Character = attacker.Model,
		WeaponId = weaponId,
		Form = config.Form,
		AttackId = attackId,
		Slot = slot,
		Duration = duration,
		Direction = direction,
	}, attacker.Root.Position, player)

	local startPosition = attacker.Root.Position
	for _, hit in attack.Hits do
		task.delay(hit.Time / attackSpeed, resolveHit, player, attacker, config, attackId, attack, hit, direction, startPosition, attackSpeed)
	end
	return nil
end

function CombatService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
	StatusService = registry.StatusService
	WeaponService = registry.WeaponService
	PartnerService = registry.PartnerService
	MadnessService = registry.MadnessService
	EnemyService = registry.EnemyService
	MapService = registry.MapService
	damageFeedback = Net.Event("DamageFeedback")
end

function CombatService:Start()
	RemoteGuard.OnEvent("AttackRequest", GameConfig.Combat.MaxAttackRequestRate, GameConfig.Combat.MaxAttackRequestRate, onAttack)
	Players.PlayerRemoving:Connect(function(player)
		attackStates[player] = nil
	end)
	-- Burn and other damage-over-time statuses.
	StatusService.DamageTick = function(model, amount, status)
		local target = CombatService:GetCombatant(model)
		local source = status.Applier and CombatService:GetCombatant(status.Applier)
		if target and amount > 0 then
			local attacker = source or target
			CombatService:ApplyDamage(attacker, target, { Base = amount, Tags = { Magic = true }, Poison = true, TrueDamage = false, NoEvents = true })
		end
	end
end

-- Test/debug helper: current combo step and cooldowns.
function CombatService:GetAttackState(player: Player)
	return state(player)
end

return CombatService
