--[[
	AbilityConfig
	Every non-weapon ability: racial abilities (key C), role techniques (key V), magic school
	variants that drive Witchcraft / Sorcery, and the endgame Kishin transformation (key B).

	All numbers are server-side tuning values. Damage values are *base* damage before
	StatCalculator.DamageMultiplier (attacker) and StatCalculator.Mitigate (target).
	Every ability has a Soul Energy cost and a cooldown so nothing can be spammed.

	`Stages` lets mastery upgrade an ability: Stage II and III entries override fields of the base.
]]

export type Ability = {
	Id: string,
	Name: string,
	Slot: string,
	Kind: string,
	Description: string,
	Cost: number,
	Cooldown: number,
	Tags: { [string]: boolean },
	Params: { [string]: any },
	Stages: { [number]: { Name: string?, Description: string?, Params: { [string]: any }? } }?,
	Lore: string?,
}

local AbilityConfig = {}

local abilities: { Ability } = {
	-- ── Racial abilities (C) ─────────────────────────────────────────────────────
	{
		Id = "AdaptiveFocus",
		Name = "Adaptive Focus",
		Slot = "C",
		Kind = "SelfBuff",
		Description = "Refill half your stamina, cleanse status effects and gain +10% damage for 6s.",
		Cost = 20,
		Cooldown = 30,
		Tags = {},
		Params = {
			Duration = 6,
			StaminaRestore = 0.5,
			Cleanse = true,
			DamageBuff = 1.10,
			Modifiers = {},
		},
		Stages = {
			[3] = {
				Name = "Indomitable Focus",
				Description = "Also grants +25% Defense for the duration.",
				Params = { Modifiers = { { Stat = "Defense", Kind = "Multiplicative", Value = 0.25 } } },
			},
		},
	},
	{
		Id = "ResonanceSurge",
		Name = "Resonance Surge",
		Slot = "C",
		Kind = "MeterBuff",
		Description = "Requires a full Resonance meter (built by landing weapon hits). Weapon attacks deal +15% damage and swing 10% faster for 8s.",
		Cost = 15,
		Cooldown = 20,
		Tags = {},
		Params = {
			MeterMax = 100,
			MeterPerHit = 8,
			SyncedMeterMultiplier = 1.5,
			Duration = 8,
			DamageBuff = 1.15,
			DamageBuffTags = { Weapon = true },
			Modifiers = { { Stat = "AttackSpeed", Kind = "Multiplicative", Value = 0.10 } },
		},
		Stages = {
			[2] = {
				Description = "Lasts 10s and the meter fills 15% faster.",
				Params = { Duration = 10, MeterPerHit = 9.2 },
			},
			[3] = {
				Name = "Death Scythe Surge",
				Description = "Lasts 10s, +20% weapon damage.",
				Params = { Duration = 10, MeterPerHit = 9.2, DamageBuff = 1.20 },
			},
		},
	},
	{
		Id = "BeastShift",
		Name = "Beast Shift",
		Slot = "C",
		Kind = "SelfBuff",
		Description = "For 7s: +12% move speed, +10% melee damage, +10% attack speed and longer dodges.",
		Cost = 25,
		Cooldown = 45,
		Tags = {},
		Params = {
			Duration = 7,
			DamageBuff = 1.10,
			DamageBuffTags = { Melee = true },
			Modifiers = {
				{ Stat = "MoveSpeed", Kind = "Multiplicative", Value = 0.12 },
				{ Stat = "AttackSpeed", Kind = "Multiplicative", Value = 0.10 },
				{ Stat = "DodgeDistance", Kind = "Multiplicative", Value = 0.10 },
			},
			Lifesteal = 0,
		},
		Stages = {
			[2] = {
				Description = "Melee hits during Beast Shift heal 5% of damage dealt.",
				Params = { Lifesteal = 0.05 },
			},
			[3] = {
				Name = "Moonlit Frenzy",
				Description = "Lasts 9s and heals 6% of melee damage dealt.",
				Params = { Duration = 9, Lifesteal = 0.06 },
			},
		},
	},
	{
		Id = "Witchcraft",
		Name = "Witchcraft",
		Slot = "C",
		Kind = "School",
		Description = "Casts the spell of your equipped witchcraft school.",
		Cost = 30,
		Cooldown = 12,
		Tags = { Magic = true, Ability = true },
		Params = { SchoolGroup = "Witch" },
		Stages = {
			[2] = { Description = "Costs 25 Soul Energy.", Params = {} },
			[3] = {
				Name = "High Witchcraft",
				Description = "Costs 25 Soul Energy and school effects are 20% stronger.",
				Params = { Potency = 1.2 },
			},
		},
	},
	{
		Id = "GraveboundRecovery",
		Name = "Gravebound Recovery",
		Slot = "C",
		Kind = "HealOverTime",
		Description = "Heal 30% of Max Health over 3s while taking 15% less damage.",
		Cost = 25,
		Cooldown = 50,
		Tags = {},
		Params = {
			Duration = 3,
			HealFraction = 0.30,
			Modifiers = { { Stat = "Defense", Kind = "Multiplicative", Value = 0.15 } },
			CleansePoison = false,
		},
		Stages = {
			[2] = { Description = "Also cleanses poison and burns.", Params = { CleansePoison = true } },
			[3] = {
				Name = "Grave Rise",
				Description = "Heals 40% and cleanses poison.",
				Params = { HealFraction = 0.40, CleansePoison = true },
			},
		},
	},
	{
		Id = "BindingCurse",
		Name = "Binding Curse",
		Slot = "C",
		Kind = "Projectile",
		Description = "Hurl cursed wrappings that root the first enemy hit (players 0.9s, enemies 1.5s, bosses are slowed instead).",
		Cost = 25,
		Cooldown = 16,
		Tags = { Ability = true },
		Params = {
			Speed = 90,
			Range = 60,
			Damage = 30,
			RootDuration = 1.5,
			PlayerRootDuration = 0.9,
			BossSlow = 0.4,
			BossSlowDuration = 2,
			Projectile = "Wrapping",
			DefenseShred = 0,
			Chains = 0,
		},
		Stages = {
			[2] = { Description = "Cursed targets also lose 15% Defense for 4s.", Params = { DefenseShred = 0.15 } },
			[3] = {
				Name = "Pharaoh's Binding",
				Description = "Chains to a second nearby enemy.",
				Params = { DefenseShred = 0.15, Chains = 1 },
			},
		},
	},
	{
		Id = "Sorcery",
		Name = "Sorcery Specialization",
		Slot = "C",
		Kind = "School",
		Description = "Casts the technique of your equipped sorcery school.",
		Cost = 35,
		Cooldown = 10,
		Tags = { Magic = true, Ability = true },
		Params = { SchoolGroup = "Sorcerer" },
		Stages = {
			[2] = { Description = "School effects are 10% stronger.", Params = { Potency = 1.1 } },
			[3] = {
				Name = "Grand Sorcery",
				Description = "School effects are 20% stronger.",
				Params = { Potency = 1.2 },
			},
		},
	},
	{
		Id = "DeathsAuthority",
		Name = "Death's Authority",
		Slot = "C",
		Kind = "DelayedArea",
		Description = "Mark an area; after a short delay, judgment strikes everything inside for heavy soul damage.",
		Cost = 60,
		Cooldown = 75,
		Tags = { Ability = true },
		Params = {
			Range = 50,
			Radius = 14,
			Delay = 0.9,
			Damage = 160,
			Aftershocks = 0,
			JudgedDuration = 0,
		},
		Stages = {
			[2] = {
				Description = "Radius 16; targets are Judged (-10% damage dealt) for 4s.",
				Params = { Radius = 16, JudgedDuration = 4 },
			},
			[3] = {
				Name = "Lines of Sanzu",
				Description = "Radius 16, Judged, and two aftershocks at 40% damage.",
				Params = { Radius = 16, JudgedDuration = 4, Aftershocks = 2 },
			},
		},
	},
	{
		Id = "ColossusSlam",
		Name = "Colossus Slam",
		Slot = "C",
		Kind = "TelegraphedSlam",
		Description = "Plant yourself and wind up (visible to everyone), then slam the ground in a wide area.",
		Cost = 30,
		Cooldown = 20,
		Tags = { Charged = true, Ability = true },
		Params = {
			WindUp = 1.1,
			Radius = 14,
			Damage = 130,
			Knockback = 55,
			AftershockRadius = 0,
		},
		Stages = {
			[2] = { Description = "Wind-up 1.0s, radius 15.", Params = { WindUp = 1.0, Radius = 15 } },
			[3] = {
				Name = "Titan's Wake",
				Description = "Wind-up 1.0s, radius 15, plus an aftershock ring to 22 studs.",
				Params = { WindUp = 1.0, Radius = 15, AftershockRadius = 22 },
			},
		},
	},

	-- ── Role techniques (V) ──────────────────────────────────────────────────────
	{
		Id = "WavelengthStrike",
		Name = "Wavelength Strike",
		Slot = "V",
		Kind = "Cone",
		Description = "Channel your soul wavelength through your weapon in a forward strike. Stronger when synchronized with a Demon Weapon partner.",
		Cost = 30,
		Cooldown = 14,
		Tags = { Ability = true, Weapon = true },
		Params = { Range = 12, Angle = 70, Damage = 75, SyncedBonus = 1.2 },
	},
	{
		Id = "ShadowStep",
		Name = "Shadow Step",
		Slot = "V",
		Kind = "Blink",
		Description = "Slip behind the nearest enemy (or blink forward). Your next hit within 3s deals +25% damage.",
		Cost = 20,
		Cooldown = 12,
		Tags = {},
		Params = { Range = 18, NextHitBuff = 1.25, BuffWindow = 3 },
	},
	{
		Id = "SoulPulse",
		Name = "Soul Pulse",
		Slot = "V",
		Kind = "SelfArea",
		Description = "Release a wavelength burst around you that damages and staggers.",
		Cost = 30,
		Cooldown = 15,
		Tags = { Ability = true },
		Params = { Radius = 12, Damage = 55, Stagger = 0.6 },
	},
	{
		Id = "PartialTransformation",
		Name = "Partial Transformation",
		Slot = "V",
		Kind = "SelfBuff",
		Description = "Transform your arm into a blade: +12% weapon damage and +8% attack speed for 8s.",
		Cost = 25,
		Cooldown = 25,
		Tags = {},
		Params = {
			Duration = 8,
			DamageBuff = 1.12,
			DamageBuffTags = { Weapon = true },
			Modifiers = { { Stat = "AttackSpeed", Kind = "Multiplicative", Value = 0.08 } },
		},
	},

	-- ── School spells (cast through Witchcraft / Sorcery) ────────────────────────
	{
		Id = "VectorArrows",
		Name = "Vector Arrows",
		Slot = "School",
		Kind = "HomingProjectiles",
		Description = "Fire three homing arrows.",
		Cost = 0,
		Cooldown = 0,
		Tags = { Magic = true, Ability = true },
		Params = { Count = 3, Damage = 40, Speed = 85, Range = 70, Turn = 6, Projectile = "VectorArrow" },
	},
	{
		Id = "TadpoleBombs",
		Name = "Tadpole Bombs",
		Slot = "School",
		Kind = "DelayedArea",
		Description = "Lob a cluster of explosive tadpoles at the target area, slowing survivors.",
		Cost = 0,
		Cooldown = 0,
		Tags = { Magic = true, Ability = true },
		Params = { Range = 45, Radius = 10, Delay = 0.6, Damage = 90, Slow = 0.3, SlowDuration = 2 },
	},
	{
		Id = "RestorationCircle",
		Name = "Restoration Circle",
		Slot = "School",
		Kind = "AreaHeal",
		Description = "Heal yourself and nearby allies for 20% of Max Health over 4s.",
		Cost = 0,
		Cooldown = 0,
		Tags = { Magic = true },
		Params = { Radius = 16, HealFraction = 0.20, Duration = 4 },
	},
	{
		Id = "EmberBurst",
		Name = "Ember Burst",
		Slot = "School",
		Kind = "Cone",
		Description = "A cone of sorcerous flame that leaves a burn.",
		Cost = 0,
		Cooldown = 0,
		Tags = { Magic = true, Ability = true },
		Params = { Range = 14, Angle = 60, Damage = 110, Burn = 8, BurnDuration = 4 },
	},
	{
		Id = "VoidWell",
		Name = "Void Well",
		Slot = "School",
		Kind = "PullArea",
		Description = "Open a gravity well that pulls enemies inward and damages them.",
		Cost = 0,
		Cooldown = 0,
		Tags = { Magic = true, Ability = true },
		Params = { Range = 45, Radius = 12, Duration = 2, Damage = 60, Pull = 22 },
	},
	{
		Id = "ArtificeConstruct",
		Name = "Artifice Construct",
		Slot = "School",
		Kind = "Summon",
		Description = "Assemble a small demon-tool construct that fires at nearby enemies for 8s.",
		Cost = 0,
		Cooldown = 0,
		Tags = { Magic = true, Ability = true },
		Params = { Duration = 8, Interval = 0.8, Damage = 25, Range = 40 },
	},

	-- ── Endgame (B) ──────────────────────────────────────────────────────────────
	{
		Id = "KishinAwakening",
		Name = "Kishin Awakening",
		Slot = "B",
		Kind = "Transformation",
		Description = "Requires the Kishin questline and Madness >= 80. For 15s: +20% damage and +10% speed, but you lose 1.5% Max Health per second and Madness resets afterwards.",
		Cost = 0,
		Cooldown = 120,
		Tags = {},
		Params = {
			Duration = 15,
			MadnessRequired = 80,
			DamageBuff = 1.20,
			Modifiers = { { Stat = "MoveSpeed", Kind = "Multiplicative", Value = 0.10 } },
			HealthDrainPerSecond = 0.015,
		},
		Lore = "Original gameplay interpretation of a Kishin's madness. It is a temporary corruption state, not a race.",
	},
}

AbilityConfig.List = abilities
AbilityConfig.ById = {} :: { [string]: Ability }
for _, ability in abilities do
	assert(AbilityConfig.ById[ability.Id] == nil, "duplicate ability " .. ability.Id)
	AbilityConfig.ById[ability.Id] = ability
end

-- Body gesture (AnimationLibrary action) played when an ability is cast.
AbilityConfig.Gestures = {
	AdaptiveFocus = "Pulse",
	ResonanceSurge = "Roar",
	BeastShift = "Roar",
	Witchcraft = "CastSpell",
	GraveboundRecovery = "Heal",
	BindingCurse = "CastSpell",
	Sorcery = "CastSpell",
	DeathsAuthority = "CastSpell",
	ColossusSlam = "GolemSlam",
	WavelengthStrike = "Pulse",
	ShadowStep = "Blink",
	SoulPulse = "Pulse",
	PartialTransformation = "Roar",
	KishinAwakening = "Roar",
}

-- Aura / burst color of each ability's visual.
AbilityConfig.Colors = {
	AdaptiveFocus = Color3.fromRGB(235, 240, 255),
	ResonanceSurge = Color3.fromRGB(255, 70, 80),
	BeastShift = Color3.fromRGB(170, 170, 185),
	GraveboundRecovery = Color3.fromRGB(140, 230, 140),
	PartialTransformation = Color3.fromRGB(230, 50, 60),
	KishinAwakening = Color3.fromRGB(150, 20, 30),
	SoulPulse = Color3.fromRGB(120, 180, 255),
	WavelengthStrike = Color3.fromRGB(150, 200, 255),
}

-- Witchcraft costs 25 from stage II on (handled here so the UI and server agree).
AbilityConfig.StageCostOverrides = {
	Witchcraft = { [2] = 25, [3] = 25 },
}

function AbilityConfig.Get(id: string): Ability?
	return AbilityConfig.ById[id]
end

-- Returns the ability's params with the mastery stage overrides merged in.
function AbilityConfig.Resolve(id: string, stage: number?): (Ability?, { [string]: any }, string, string)
	local ability = AbilityConfig.ById[id]
	if not ability then
		return nil, {}, "", ""
	end
	local params = table.clone(ability.Params)
	local name, description = ability.Name, ability.Description
	local s = stage or 1
	if ability.Stages then
		for level = 2, s do
			local override = ability.Stages[level]
			if override then
				if override.Name then
					name = override.Name
				end
				if override.Description then
					description = ability.Description .. " " .. override.Description
				end
				for k, v in override.Params or {} do
					params[k] = v
				end
			end
		end
	end
	return ability, params, name, description
end

function AbilityConfig.CostFor(id: string, stage: number?): number
	local ability = AbilityConfig.ById[id]
	if not ability then
		return 0
	end
	local overrides = AbilityConfig.StageCostOverrides[id]
	if overrides and stage and overrides[stage] then
		return overrides[stage]
	end
	return ability.Cost
end

return AbilityConfig
