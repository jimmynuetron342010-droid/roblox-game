--[[
	StatDefinitions
	The single source of truth for every character stat, its base value and its safety limits.

	Two stat kinds:
	  * Scalar  — has a base value (e.g. 100 HP). Bonuses are fractions applied as base * (1 + bonus).
	              SoftCap / HardCap / Floor limit the *bonus fraction*.
	  * Percent — the stat *is* a fraction (e.g. 0.15 = 15% cooldown reduction), base usually 0.
	              SoftCap / HardCap / Floor limit the *value*.

	Past SoftCap, only DiminishFactor (default 50%) of any further bonus is kept, and nothing ever
	exceeds HardCap. AbsoluteMin/AbsoluteMax clamp the final number as a last line of defence.
]]

export type StatDef = {
	Id: string,
	DisplayName: string,
	Category: string,
	Kind: "Scalar" | "Percent",
	Base: number | (level: number) -> number,
	SoftCap: number?,
	HardCap: number?,
	Floor: number?,
	DiminishFactor: number?,
	AbsoluteMin: number?,
	AbsoluteMax: number?,
	Format: string,
	Description: string,
}

local StatDefinitions = {}

local defs: { StatDef } = {
	-- ── Survival ────────────────────────────────────────────────────────────────
	{
		Id = "MaxHealth",
		DisplayName = "Max Health",
		Category = "Survival",
		Kind = "Scalar",
		Base = function(level)
			return 100 + (level - 1) * 6
		end,
		SoftCap = 0.6,
		HardCap = 0.9,
		Floor = -0.5,
		AbsoluteMin = 1,
		Format = "Integer",
		Description = "Total health.",
	},
	{
		Id = "Defense",
		DisplayName = "Defense",
		Category = "Survival",
		Kind = "Scalar",
		Base = function(level)
			return 20 + (level - 1) * 2
		end,
		SoftCap = 0.5,
		HardCap = 0.85,
		Floor = -0.5,
		AbsoluteMin = 0,
		Format = "Integer",
		Description = "Converted into damage reduction with diminishing returns (see Damage Reduction).",
	},
	{
		Id = "HealthRegen",
		DisplayName = "Health Regen",
		Category = "Survival",
		Kind = "Scalar",
		Base = 0.01, -- fraction of Max Health per second, only while out of combat
		SoftCap = 0.25,
		HardCap = 0.5,
		Floor = -0.5,
		Format = "PercentPerSecond",
		Description = "Max Health regenerated per second outside active damage windows.",
	},
	{
		Id = "StatusResistance",
		DisplayName = "Status Resistance",
		Category = "Survival",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.35,
		HardCap = 0.6,
		Floor = 0,
		Format = "Percent",
		Description = "Reduces the duration of incoming status effects.",
	},
	{
		Id = "PoisonResistance",
		DisplayName = "Poison Resistance",
		Category = "Survival",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.75,
		Floor = 0,
		Format = "Percent",
		Description = "Reduces poison, corrosion and decay damage. Stacks with Status Resistance for duration.",
	},
	{
		Id = "KnockbackResistance",
		DisplayName = "Knockback Resistance",
		Category = "Survival",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.8,
		Floor = 0,
		Format = "Percent",
		Description = "Reduces knockback distance.",
	},
	{
		Id = "InterruptResistance",
		DisplayName = "Interrupt Resistance",
		Category = "Survival",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.7,
		Floor = 0,
		Format = "Percent",
		Description = "Reduces stagger duration from incoming hits.",
	},
	{
		Id = "RangedDamageReduction",
		DisplayName = "Ranged Damage Reduction",
		Category = "Survival",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.15,
		HardCap = 0.3,
		Floor = 0,
		Format = "Percent",
		Description = "Reduces damage from projectiles and gunfire (applied before Defense).",
	},

	-- ── Offense ─────────────────────────────────────────────────────────────────
	{
		Id = "WeaponDamage",
		DisplayName = "Weapon Damage",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.75,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus damage for all weapon attacks.",
	},
	{
		Id = "MeleeDamage",
		DisplayName = "Melee Damage",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.75,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus damage for close-range attacks.",
	},
	{
		Id = "MagicDamage",
		DisplayName = "Magic Damage",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.45,
		HardCap = 0.8,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus damage for witchcraft and sorcery.",
	},
	{
		Id = "ChargedDamage",
		DisplayName = "Charged Damage",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.7,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus damage for heavy/charged attacks and slams.",
	},
	{
		Id = "AbilityDamage",
		DisplayName = "Ability Damage",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.35,
		HardCap = 0.6,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus damage for compatible soul abilities (racial and technique abilities).",
	},
	{
		Id = "AttackSpeed",
		DisplayName = "Attack Speed",
		Category = "Offense",
		Kind = "Scalar",
		Base = 1,
		SoftCap = 0.25,
		HardCap = 0.4,
		Floor = -0.4,
		Format = "Multiplier",
		Description = "Speeds up attack wind-up, recovery and cooldowns of basic attacks.",
	},
	{
		Id = "StatusEffectiveness",
		DisplayName = "Status Effectiveness",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.3,
		HardCap = 0.5,
		Floor = 0,
		Format = "Percent",
		Description = "Increases duration and potency of status effects you apply.",
	},
	{
		Id = "CooldownReduction",
		DisplayName = "Cooldown Reduction",
		Category = "Offense",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.25,
		HardCap = 0.4,
		Floor = 0,
		Format = "Percent",
		Description = "Shortens ability cooldowns. Hard capped at 40%.",
	},

	-- ── Mobility ────────────────────────────────────────────────────────────────
	{
		Id = "MoveSpeed",
		DisplayName = "Move Speed",
		Category = "Mobility",
		Kind = "Scalar",
		Base = 16,
		SoftCap = 0.2,
		HardCap = 0.3,
		Floor = -0.3,
		AbsoluteMin = 10,
		AbsoluteMax = 22,
		Format = "Decimal",
		Description = "Walking speed in studs/second (sprint multiplies this).",
	},
	{
		Id = "DodgeDistance",
		DisplayName = "Dodge Distance",
		Category = "Mobility",
		Kind = "Scalar",
		Base = 1,
		SoftCap = 0.2,
		HardCap = 0.35,
		Floor = -0.3,
		Format = "Multiplier",
		Description = "Multiplier on dash distance.",
	},
	{
		Id = "StaminaMax",
		DisplayName = "Max Stamina",
		Category = "Mobility",
		Kind = "Scalar",
		Base = 100,
		SoftCap = 0.3,
		HardCap = 0.5,
		Floor = -0.3,
		Format = "Integer",
		Description = "Stamina pool used by sprinting, dashing and basic attacks.",
	},
	{
		Id = "StaminaRegen",
		DisplayName = "Stamina Regen",
		Category = "Mobility",
		Kind = "Scalar",
		Base = 22,
		SoftCap = 0.2,
		HardCap = 0.35,
		Floor = -0.5,
		Format = "PerSecond",
		Description = "Stamina regenerated per second.",
	},

	-- ── Soul ────────────────────────────────────────────────────────────────────
	{
		Id = "SoulEnergyMax",
		DisplayName = "Soul Energy",
		Category = "Soul",
		Kind = "Scalar",
		Base = 100,
		SoftCap = 0.3,
		HardCap = 0.5,
		Floor = -0.3,
		Format = "Integer",
		Description = "Resource for racial abilities, techniques and magic.",
	},
	{
		Id = "SoulEnergyRegen",
		DisplayName = "Soul Energy Regen",
		Category = "Soul",
		Kind = "Scalar",
		Base = 4,
		SoftCap = 0.25,
		HardCap = 0.4,
		Floor = -0.5,
		Format = "PerSecond",
		Description = "Soul Energy regenerated per second.",
	},
	{
		Id = "SoulPerception",
		DisplayName = "Soul Perception",
		Category = "Soul",
		Kind = "Scalar",
		Base = 60,
		SoftCap = 0.3,
		HardCap = 0.5,
		Floor = -0.5,
		Format = "Studs",
		Description = "Range at which you can perceive souls through walls (toggle with G).",
	},

	-- ── Progression ─────────────────────────────────────────────────────────────
	{
		Id = "XPGain",
		DisplayName = "XP Gain",
		Category = "Progression",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.5,
		HardCap = 1.0,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus character experience.",
	},
	{
		Id = "WeaponMasteryGain",
		DisplayName = "Weapon Mastery Gain",
		Category = "Progression",
		Kind = "Percent",
		Base = 0,
		SoftCap = 0.4,
		HardCap = 0.8,
		Floor = -0.5,
		Format = "Percent",
		Description = "Bonus weapon mastery experience.",
	},
}

StatDefinitions.List = defs
StatDefinitions.ById = {} :: { [string]: StatDef }
for _, def in defs do
	assert(StatDefinitions.ById[def.Id] == nil, "duplicate stat " .. def.Id)
	StatDefinitions.ById[def.Id] = def
end

StatDefinitions.Categories = { "Survival", "Offense", "Mobility", "Soul", "Progression" }

-- Derived stat: Defense -> damage reduction. Level-scaled constant keeps Defense meaningful at all levels.
StatDefinitions.DamageReduction = {
	Cap = 0.6,
	K = function(level: number): number
		return 100 + level * 5
	end,
}

-- Outgoing damage pooling. All applicable *additive* damage bonuses for a hit (e.g. Weapon + Melee)
-- are summed into one pool, which is soft/hard capped again so stacking categories cannot explode.
-- Multiplicative buffs (Beast Shift, Resonance Surge, Kishin...) form a second, separately capped pool.
StatDefinitions.DamagePools = {
	Additive = { SoftCap = 0.6, HardCap = 1.0, DiminishFactor = 0.5 },
	Multiplicative = { HardCap = 1.4 }, -- product of buffs never exceeds x1.4
	TotalMultiplierCap = 2.6, -- absolute ceiling for any single hit: (1 + additive) * buffs
}

-- Sprint speed absolute ceiling (MoveSpeed * SprintMultiplier is clamped to this).
StatDefinitions.MaxSprintSpeed = 31

function StatDefinitions.Get(id: string): StatDef
	local def = StatDefinitions.ById[id]
	assert(def, "Unknown stat " .. tostring(id))
	return def
end

function StatDefinitions.BaseValue(id: string, level: number): number
	local def = StatDefinitions.Get(id)
	local base = def.Base
	if type(base) == "function" then
		return base(level)
	end
	return base :: number
end

return StatDefinitions
