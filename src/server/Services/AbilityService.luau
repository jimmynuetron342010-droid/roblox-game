--[[
	AbilityService
	Executes abilities on the server: racial (C), role technique (V), Kishin Awakening (B).
	Every ability: validated slot -> resolved by build (race/role/school, mastery stage) ->
	Soul Energy cost (with synchronization / Arcane Mastery discounts) -> cooldown (with capped
	Cooldown Reduction) -> effect. Visuals are broadcast; damage uses CombatService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local AbilityConfig = require(Modules.Config.AbilityConfig)
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local MagicConfig = require(Modules.Config.MagicConfig)
local ProjectileController = require(Modules.ProjectileController)
local RaceConfig = require(Modules.Config.RaceConfig)
local StatCalculator = require(Modules.Core.StatCalculator)
local Validate = require(Modules.Core.Validate)

local Server = script.Parent.Parent
local FXBroadcast = require(Server.Core.FXBroadcast)
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)
local RemoteGuard = require(Server.Core.RemoteGuard)

local AbilityService = {}

local DataService, StatService, StatusService, CombatService, PartnerService, MadnessService, EnemyService

type PlayerAbilityState = { Cooldowns: { [string]: number }, LastCast: number }
local states: { [Player]: PlayerAbilityState } = {}

local function state(player: Player): PlayerAbilityState
	local s = states[player]
	if not s then
		s = { Cooldowns = {}, LastCast = -math.huge }
		states[player] = s
	end
	return s
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-4 and f.Unit or Vector3.new(0, 0, -1)
end

-- Which ability does this slot resolve to for this build? Returns (abilityId, stage, reason).
function AbilityService.ResolveSlot(profile, slot: string): (string?, number, string?)
	local raceId = profile.Race.Active
	local stage = 1
	if raceId ~= "" and profile.Race.Progress[raceId] then
		stage = profile.Race.Progress[raceId].Stage
	end
	if slot == "C" then
		local race = RaceConfig.ById[raceId]
		if not race then
			return nil, stage, "NoRace"
		end
		if not race.AbilityId then
			return nil, stage, "NoAbility"
		end
		if stage < race.AbilityUnlockStage then
			return nil, stage, "Locked"
		end
		return race.AbilityId, stage, nil
	elseif slot == "V" then
		local role = CombatRoleConfig.ById[profile.Loadout.Role]
		if not role then
			return nil, stage, "NoRole"
		end
		return role.TechniqueId, 1, nil
	elseif slot == "B" then
		if not profile.Unlocks.KishinAwakening then
			return nil, stage, "Locked"
		end
		return "KishinAwakening", 1, nil
	end
	return nil, stage, "BadSlot"
end

local function broadcast(payload, position: Vector3)
	FXBroadcast.Broadcast(payload, position)
end

local function abilityDamage(caster, target, base: number, ability, abilityId: string, extra)
	local info = {
		Base = base,
		Tags = ability.Tags,
		AbilityId = abilityId,
		Direction = extra and extra.Direction or nil,
		Knockback = extra and extra.Knockback or nil,
		Stagger = extra and extra.Stagger or 0.15,
		Status = extra and extra.Status or nil,
	}
	return CombatService:ApplyDamage(caster, target, info)
end

-- Picks the nearest valid target in front of the caster.
local function nearestTarget(caster, direction: Vector3, range: number, coneDegrees: number?)
	local best, bestDistance = nil, math.huge
	local cosLimit = math.cos(math.rad((coneDegrees or 120) / 2))
	for _, target in CombatService:AllCombatants() do
		if CombatService:CanDamage(caster, target) then
			local offset = target.Root.Position - caster.Root.Position
			local distance = offset.Magnitude
			if distance <= range and (distance < 4 or flat(offset):Dot(flat(direction)) >= cosLimit) and distance < bestDistance then
				best, bestDistance = target, distance
			end
		end
	end
	return best
end

local function clampTargetPosition(caster, targetPosition: Vector3?, direction: Vector3, range: number): Vector3
	local origin = caster.Root.Position
	local wanted = Validate.Position(targetPosition) or (origin + flat(direction) * math.min(range, 18))
	local offset = wanted - origin
	if offset.Magnitude > range then
		wanted = origin + offset.Unit * range
	end
	return wanted
end

-- ── Spell / ability kinds ──────────────────────────────────────────────────────
local Kinds = {}

Kinds.SelfBuff = function(ctx)
	local player, params, id = ctx.Player, ctx.Params, ctx.AbilityId
	local modifiers = params.Modifiers or {}
	StatService:AddBuff(player, id, params.Duration, modifiers, params.DamageBuff, params.DamageBuffTags, {
		Lifesteal = params.Lifesteal,
	})
	if params.StaminaRestore then
		StatService:RestoreStamina(player, params.StaminaRestore)
	end
	if params.Cleanse then
		StatusService:Cleanse(ctx.Caster.Model)
	end
	broadcast({ Type = "Ability", Kind = "Buff", Character = ctx.Caster.Model, Color = AbilityConfig.Colors[id], Duration = params.Duration }, ctx.Caster.Root.Position)
	return true
end

Kinds.MeterBuff = function(ctx)
	local player = ctx.Player
	local params = ctx.Params
	if (player:GetAttribute("Resonance") or 0) < params.MeterMax then
		return false, "MeterNotFull"
	end
	player:SetAttribute("Resonance", 0)
	return Kinds.SelfBuff(ctx)
end

Kinds.HealOverTime = function(ctx)
	local player, params = ctx.Player, ctx.Params
	local humanoid = ctx.Caster.Humanoid
	StatService:AddBuff(player, ctx.AbilityId, params.Duration, params.Modifiers)
	if params.CleansePoison then
		StatusService:Cleanse(ctx.Caster.Model, { "Burn", "Cursed" })
	end
	local total = humanoid.MaxHealth * params.HealFraction
	local ticks = math.max(1, math.floor(params.Duration / 0.25))
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(0.25)
			if humanoid.Health <= 0 then
				return
			end
			local amount = total / ticks
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
			GameEvents.Fire(player, "Healed", { Amount = amount })
		end
	end)
	broadcast({ Type = "Ability", Kind = "Heal", Character = ctx.Caster.Model, Duration = params.Duration, Color = AbilityConfig.Colors[ctx.AbilityId] }, ctx.Caster.Root.Position)
	return true
end

Kinds.Projectile = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local origin = caster.Root.Position + Vector3.new(0, 0.8, 0)
	local direction = ctx.Direction
	local chained = 0
	local function onTarget(target)
		local isBoss = target.Enemy and target.Enemy.Def.IsBoss
		local status
		if isBoss then
			status = { Name = "Slow", Duration = params.BossSlowDuration, Magnitude = params.BossSlow, Source = ctx.AbilityId }
		else
			status = { Name = "Root", Duration = target.Player and params.PlayerRootDuration or params.RootDuration, Source = ctx.AbilityId }
		end
		abilityDamage(caster, target, params.Damage, ctx.Ability, ctx.AbilityId, { Status = status })
		if params.DefenseShred and params.DefenseShred > 0 then
			StatusService:Apply(target.Model, "Cursed", { Duration = 4, Magnitude = params.DefenseShred, Source = ctx.AbilityId })
		end
		broadcast({ Type = "Ability", Kind = "Rooted", Character = target.Model, Duration = status.Duration }, target.Root.Position)
		if chained < (params.Chains or 0) then
			chained += 1
			local nextTarget = nil
			for _, other in CombatService:QueryCircle(caster, target.Root.Position, 14) do
				if other.Model ~= target.Model then
					nextTarget = other
					break
				end
			end
			if nextTarget then
				onTarget(nextTarget)
			end
		end
	end
	ProjectileController.Simulate({
		Origin = origin,
		Direction = direction,
		Speed = params.Speed,
		Range = params.Range,
		Radius = 1,
		Ignore = { caster.Model },
		OnHit = function(result)
			local target = CombatService:GetCombatant(result.Instance:FindFirstAncestorOfClass("Model"))
			if target and CombatService:CanDamage(caster, target) then
				onTarget(target)
			end
			return false
		end,
	})
	broadcast({ Type = "Ability", Kind = "Wrap", Character = caster.Model, Origin = origin, Direction = direction, Speed = params.Speed, Range = params.Range }, origin)
	return true
end

Kinds.DelayedArea = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local potency = ctx.Potency
	local center = clampTargetPosition(caster, ctx.TargetPosition, ctx.Direction, params.Range)
	local isJudgment = ctx.AbilityId == "DeathsAuthority"
	broadcast({
		Type = "Ability",
		Kind = isJudgment and "Judgment" or "AreaBlast",
		Character = caster.Model,
		Position = center,
		Radius = params.Radius,
		Delay = params.Delay,
		Color = if isJudgment then nil else Color3.fromRGB(120, 220, 130),
	}, center)
	task.delay(params.Delay, function()
		local function blast(scale: number)
			for _, target in CombatService:QueryCircle(caster, center, params.Radius) do
				local status = nil
				if params.JudgedDuration and params.JudgedDuration > 0 then
					status = { Name = "Judged", Duration = params.JudgedDuration, Magnitude = 0.1, Source = ctx.AbilityId }
				elseif params.Slow then
					status = { Name = "Slow", Duration = params.SlowDuration, Magnitude = params.Slow, Source = ctx.AbilityId }
				end
				abilityDamage(caster, target, params.Damage * potency * scale, ctx.Ability, ctx.AbilityId, {
					Status = status,
					Stagger = 0.3,
					Knockback = 8,
					Direction = target.Root.Position - center,
				})
			end
		end
		blast(1)
		for i = 1, params.Aftershocks or 0 do
			task.delay(i * 0.35, function()
				blast(0.4)
				broadcast({ Type = "Ability", Kind = "Pulse", Position = center, Radius = params.Radius, Color = Color3.fromRGB(240, 240, 255) }, center)
			end)
		end
	end)
	return true
end

Kinds.TelegraphedSlam = function(ctx)
	local params, caster, player = ctx.Params, ctx.Caster, ctx.Player
	local position = caster.Root.Position
	caster.Model:SetAttribute("MovementLock", workspace:GetServerTimeNow() + params.WindUp)
	StatService:UpdateWalkSpeed(player)
	broadcast({ Type = "Ability", Kind = "Telegraph", Character = caster.Model, Position = position, Radius = params.Radius, Duration = params.WindUp }, position)
	EnemyService:OnTelegraph(position, params.Radius, params.WindUp)
	task.delay(params.WindUp, function()
		caster.Model:SetAttribute("MovementLock", nil)
		StatService:UpdateWalkSpeed(player)
		if caster.Humanoid.Health <= 0 then
			return
		end
		if StatusService:Has(caster.Model, "Stagger") then
			-- Counterplay: interrupting the wind-up cancels the slam (half cooldown refund).
			Notifier.Send(player, "Colossus Slam interrupted!", "Warning")
			local s = state(player)
			s.Cooldowns[ctx.AbilityId] = os.clock() + (s.Cooldowns[ctx.AbilityId] - os.clock()) * 0.5
			return
		end
		local center = caster.Root.Position
		for _, target in CombatService:QueryCircle(caster, center, params.Radius) do
			abilityDamage(caster, target, params.Damage, ctx.Ability, ctx.AbilityId, {
				Knockback = params.Knockback,
				Direction = target.Root.Position - center,
				Stagger = 0.6,
			})
		end
		broadcast({ Type = "Ability", Kind = "Slam", Character = caster.Model, Position = center, Radius = params.Radius, Aftershock = params.AftershockRadius ~= 0 and params.AftershockRadius or nil }, center)
		if params.AftershockRadius and params.AftershockRadius > 0 then
			task.delay(0.35, function()
				for _, target in CombatService:QueryCircle(caster, center, params.AftershockRadius) do
					abilityDamage(caster, target, params.Damage * 0.35, ctx.Ability, ctx.AbilityId, { Stagger = 0.2 })
				end
			end)
		end
	end)
	return true
end

Kinds.Cone = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local bonus = ctx.Potency
	if ctx.AbilityId == "WavelengthStrike" and PartnerService:GetSync(ctx.Player) then
		bonus *= params.SyncedBonus
	end
	for _, target in CombatService:QueryArc(caster, ctx.Direction, params.Range, params.Angle, 8) do
		local status = nil
		if params.Burn then
			status = { Name = "Burn", Duration = params.BurnDuration, TickDamage = params.Burn, Source = ctx.AbilityId }
		end
		abilityDamage(caster, target, params.Damage * bonus, ctx.Ability, ctx.AbilityId, {
			Status = status,
			Direction = ctx.Direction,
			Knockback = 10,
			Stagger = 0.3,
		})
	end
	broadcast({
		Type = "Ability",
		Kind = ctx.AbilityId == "EmberBurst" and "Cone" or "Pulse",
		Character = caster.Model,
		Position = caster.Root.Position + flat(ctx.Direction) * 4,
		Radius = params.Range * 0.5,
		Color = AbilityConfig.Colors[ctx.AbilityId],
	}, caster.Root.Position)
	return true
end

Kinds.Blink = function(ctx)
	local params, caster, player = ctx.Params, ctx.Caster, ctx.Player
	local from = caster.Root.Position
	local target = nearestTarget(caster, ctx.Direction, params.Range, 140)
	local destination: CFrame
	if target then
		local behind = target.Root.CFrame * CFrame.new(0, 0, 3.5)
		destination = CFrame.lookAt(behind.Position, target.Root.Position)
	else
		local params2 = RaycastParams.new()
		params2.FilterType = Enum.RaycastFilterType.Exclude
		params2.FilterDescendantsInstances = { caster.Model }
		local dir = flat(ctx.Direction)
		local hit = workspace:Raycast(from, dir * params.Range, params2)
		local distance = hit and math.max(0, (hit.Position - from).Magnitude - 2) or params.Range
		destination = CFrame.lookAt(from + dir * distance, from + dir * (distance + 1))
	end
	caster.Model:PivotTo(destination)
	StatService:AddBuff(player, "ShadowStepNext", params.BuffWindow, {}, params.NextHitBuff)
	broadcast({ Type = "Ability", Kind = "Blink", Character = caster.Model, From = from, To = destination.Position }, from)
	return true
end

Kinds.SelfArea = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	for _, target in CombatService:QueryCircle(caster, caster.Root.Position, params.Radius) do
		abilityDamage(caster, target, params.Damage * ctx.Potency, ctx.Ability, ctx.AbilityId, {
			Stagger = params.Stagger,
			Knockback = 14,
			Direction = target.Root.Position - caster.Root.Position,
		})
	end
	broadcast({ Type = "Ability", Kind = "Pulse", Character = caster.Model, Radius = params.Radius, Color = AbilityConfig.Colors[ctx.AbilityId] }, caster.Root.Position)
	return true
end

Kinds.HomingProjectiles = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local origin = caster.Root.Position + Vector3.new(0, 1.2, 0)
	local target = nearestTarget(caster, ctx.Direction, params.Range, 160)
	for i = 1, params.Count do
		local spread = (i - (params.Count + 1) / 2) * math.rad(14)
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, spread) * flat(ctx.Direction)
		task.delay((i - 1) * 0.08, function()
			ProjectileController.Simulate({
				Origin = origin,
				Direction = dir,
				Speed = params.Speed,
				Range = params.Range,
				Radius = 0.8,
				Ignore = { caster.Model },
				Homing = target and { Target = target.Model, Turn = params.Turn } or nil,
				OnHit = function(result)
					local hit = CombatService:GetCombatant(result.Instance:FindFirstAncestorOfClass("Model"))
					if hit and CombatService:CanDamage(caster, hit) then
						abilityDamage(caster, hit, params.Damage * ctx.Potency, ctx.Ability, ctx.AbilityId, { Stagger = 0.15 })
					end
					return false
				end,
			})
			broadcast({
				Type = "Ability",
				Kind = "Projectile",
				Character = caster.Model,
				Origin = origin,
				Direction = dir,
				Speed = params.Speed,
				Range = params.Range,
				Target = target and target.Model or nil,
				Turn = params.Turn,
				Color = Color3.fromRGB(170, 110, 255),
			}, origin)
		end)
	end
	return true
end

Kinds.AreaHeal = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local recipients = {}
	for _, player in Players:GetPlayers() do
		local c = CombatService:GetCombatant(player.Character)
		if c and (c.Root.Position - caster.Root.Position).Magnitude <= params.Radius then
			table.insert(recipients, c)
		end
	end
	local ticks = math.floor(params.Duration / 0.25)
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(0.25)
			for _, c in recipients do
				if c.Humanoid.Health > 0 then
					local amount = c.Humanoid.MaxHealth * params.HealFraction * ctx.Potency / ticks
					c.Humanoid.Health = math.min(c.Humanoid.MaxHealth, c.Humanoid.Health + amount)
					GameEvents.Fire(ctx.Player, "Healed", { Amount = amount })
				end
			end
		end
	end)
	broadcast({ Type = "Ability", Kind = "Heal", Character = caster.Model, Radius = params.Radius, Duration = params.Duration, Color = Color3.fromRGB(255, 190, 110) }, caster.Root.Position)
	return true
end

Kinds.PullArea = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local center = clampTargetPosition(caster, ctx.TargetPosition, ctx.Direction, params.Range)
	broadcast({ Type = "Ability", Kind = "Well", Character = caster.Model, Position = center, Radius = params.Radius, Duration = params.Duration }, center)
	local ticks = math.floor(params.Duration / 0.25)
	task.spawn(function()
		for _ = 1, ticks do
			for _, target in CombatService:QueryCircle(caster, center, params.Radius) do
				local toward = center - target.Root.Position
				if toward.Magnitude > 1 then
					local pull = Vector3.new(toward.X, 0, toward.Z).Unit * params.Pull
					if target.Player then
						FXBroadcast.To(target.Player, { Type = "Knockback", Velocity = pull })
					elseif not target.Enemy.Def.IsBoss then
						target.Root.AssemblyLinearVelocity = Vector3.new(pull.X, target.Root.AssemblyLinearVelocity.Y, pull.Z)
					end
				end
				abilityDamage(caster, target, params.Damage * ctx.Potency / ticks, ctx.Ability, ctx.AbilityId, { Stagger = 0 })
			end
			task.wait(0.25)
		end
	end)
	return true
end

Kinds.Summon = function(ctx)
	local params, caster = ctx.Params, ctx.Caster
	local position = caster.Root.Position + flat(ctx.Direction) * 4
	broadcast({ Type = "Ability", Kind = "Construct", Character = caster.Model, Position = position, Duration = params.Duration }, position)
	task.spawn(function()
		local elapsed = 0
		while elapsed < params.Duration and caster.Humanoid.Health > 0 do
			task.wait(params.Interval)
			elapsed += params.Interval
			local muzzle = position + Vector3.new(0, 2.3, 0)
			local best, bestDistance = nil, params.Range
			for _, target in CombatService:QueryCircle(caster, position, params.Range) do
				local d = (target.Root.Position - position).Magnitude
				if d < bestDistance then
					best, bestDistance = target, d
				end
			end
			if best then
				local dir = (best.Root.Position - muzzle).Unit
				abilityDamage(caster, best, params.Damage * ctx.Potency, ctx.Ability, ctx.AbilityId, { Stagger = 0.1 })
				broadcast({ Type = "Ability", Kind = "Projectile", Origin = muzzle, Direction = dir, Speed = 140, Range = bestDistance, Color = Color3.fromRGB(80, 200, 255), Character = caster.Model }, muzzle)
			end
		end
	end)
	return true
end

Kinds.School = function(ctx)
	local profile = ctx.Profile
	local school = MagicConfig.ById[profile.Loadout.School]
	if not school then
		return false, "NoSchool"
	end
	local spell, spellParams = AbilityConfig.Resolve(school.SpellId, 1)
	if not spell then
		return false, "NoSpell"
	end
	local sub = table.clone(ctx)
	sub.AbilityId = school.SpellId
	sub.Ability = spell
	sub.Params = spellParams
	sub.Potency = ctx.Params.Potency or 1
	local handler = Kinds[spell.Kind]
	if not handler then
		return false, "BadSpell"
	end
	return handler(sub)
end

Kinds.Transformation = function(ctx)
	local params, player = ctx.Params, ctx.Player
	if MadnessService:Get(player) < params.MadnessRequired then
		return false, "NotEnoughMadness"
	end
	StatService:AddBuff(player, "KishinAwakening", params.Duration, params.Modifiers, params.DamageBuff)
	broadcast({ Type = "Ability", Kind = "Buff", Character = ctx.Caster.Model, Color = AbilityConfig.Colors.KishinAwakening, Duration = params.Duration, Rate = 30 }, ctx.Caster.Root.Position)
	local humanoid = ctx.Caster.Humanoid
	task.spawn(function()
		local elapsed = 0
		while elapsed < params.Duration and humanoid.Health > 0 do
			task.wait(0.5)
			elapsed += 0.5
			humanoid.Health = math.max(1, humanoid.Health - humanoid.MaxHealth * params.HealthDrainPerSecond * 0.5)
		end
		MadnessService:Set(player, 0)
	end)
	return true
end

-- ── Request handling ──────────────────────────────────────────────────────────
local function onAbility(player: Player, slot: any, aim: any, targetPosition: any)
	if slot ~= "C" and slot ~= "V" and slot ~= "B" then
		return
	end
	local profile = DataService:GetProfile(player)
	local caster = CombatService:GetCombatant(player.Character)
	if not profile or not caster then
		return
	end
	local function fail(reason: string)
		FXBroadcast.To(player, { Type = "AbilityFailed", Slot = slot, Reason = reason })
	end
	if StatusService:Has(caster.Model, "Stagger") then
		return fail("Staggered")
	end
	local abilityId, stage, reason = AbilityService.ResolveSlot(profile, slot)
	if not abilityId then
		return fail(reason or "Unavailable")
	end
	local ability, params = AbilityConfig.Resolve(abilityId, stage)
	if not ability then
		return fail("Unavailable")
	end
	local s = state(player)
	local now = os.clock()
	if (s.Cooldowns[abilityId] or 0) > now then
		return fail("Cooldown")
	end
	local cost = AbilityConfig.CostFor(abilityId, stage) * PartnerService:CostMultiplier(player)
	if profile.Race.Active == "Sorcerer" and now - s.LastCast < 3 then
		cost *= 0.85 -- Arcane Mastery: magical combos cost less
	end
	if StatService:GetSoulEnergy(player) < cost then
		return fail("SoulEnergy")
	end
	local direction = Validate.Direction(aim) or caster.Root.CFrame.LookVector
	local handler = Kinds[ability.Kind]
	if not handler then
		return fail("Unavailable")
	end
	local ok, success, failReason = pcall(handler, {
		Player = player,
		Profile = profile,
		Caster = caster,
		Ability = ability,
		AbilityId = abilityId,
		Params = params,
		Stage = stage,
		Direction = direction,
		TargetPosition = targetPosition,
		Potency = params.Potency or 1,
	})
	if not ok then
		warn("[AbilityService] " .. abilityId .. " error: " .. tostring(success))
		return fail("Error")
	end
	if not success then
		return fail(failReason or "Unavailable")
	end
	StatService:SpendSoulEnergy(player, cost)
	local cooldown = StatCalculator.Cooldown(ability.Cooldown, StatService:GetValues(player))
	s.Cooldowns[abilityId] = now + cooldown
	s.LastCast = now
	player:SetAttribute("CD_" .. slot, workspace:GetServerTimeNow() + cooldown)
	StatService:TagCombat(player)
	GameEvents.Fire(player, "AbilityUsed", { AbilityId = abilityId })
	FXBroadcast.Broadcast({
		Type = "Gesture",
		Character = caster.Model,
		Action = AbilityConfig.Gestures[abilityId],
		Duration = ability.Kind == "TelegraphedSlam" and (params.WindUp + 0.45) or 0.7,
	}, caster.Root.Position, player)
	return nil
end

function AbilityService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
	StatusService = registry.StatusService
	CombatService = registry.CombatService
	PartnerService = registry.PartnerService
	MadnessService = registry.MadnessService
	EnemyService = registry.EnemyService
end

function AbilityService:Start()
	RemoteGuard.OnEvent("AbilityRequest", 6, 8, onAbility)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

AbilityService.Kinds = Kinds

return AbilityService
