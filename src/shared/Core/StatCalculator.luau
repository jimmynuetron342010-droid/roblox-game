--[[
	StatCalculator
	Pure, deterministic stat math shared by the server (authoritative values) and the client
	(previews such as the before/after comparison on the race reveal screen).

	Pipeline for every stat:
	  1. Flat           — added to the base value                     (e.g. +10 Defense from gear)
	  2. Additive       — fractions summed together                    (race, role, mastery: +0.25 +0.05)
	  3. Multiplicative — each one multiplies separately               (temporary buffs: x1.10 * x1.15)
	  4. Caps           — soft cap (diminishing returns) then hard cap (see StatDefinitions)

	Scalar stats:  final = (base + flat) * (1 + cap((1 + additive) * multiplicative - 1))
	Percent stats: final = cap(base + flat + additive + sum(multiplicative))
	(For Percent stats a "multiplicative" source is just another addend — multiplying a 0-based
	 fraction would be meaningless — so every source still respects the same caps.)

	Never modify Humanoid/character stats directly from gameplay scripts; go through StatService,
	which calls this module.
]]

local StatDefinitions = require(script.Parent.Parent.Config.StatDefinitions)

export type ModifierKind = "Flat" | "Additive" | "Multiplicative"

export type Modifier = {
	Stat: string,
	Kind: ModifierKind,
	Value: number,
	Source: string,
}

export type StatBreakdown = {
	Stat: string,
	Base: number,
	Flat: number,
	Additive: { { Source: string, Value: number } },
	Multiplicative: { { Source: string, Value: number } },
	RawBonus: number,
	CappedBonus: number,
	Final: number,
	CapState: "None" | "Soft" | "Hard" | "Floor",
}

export type ComputedStats = {
	Level: number,
	Values: { [string]: number },
	Breakdown: { [string]: StatBreakdown },
	DamageReduction: number,
}

local StatCalculator = {}

-- Applies floor, soft cap (diminishing returns) and hard cap to a value.
-- Returns the limited value and which limit (if any) was hit.
function StatCalculator.Limit(
	value: number,
	softCap: number?,
	hardCap: number?,
	floor: number?,
	diminishFactor: number?
): (number, string)
	local state = "None"
	if floor ~= nil and value < floor then
		return floor, "Floor"
	end
	if softCap ~= nil and value > softCap then
		value = softCap + (value - softCap) * (diminishFactor or 0.5)
		state = "Soft"
	end
	if hardCap ~= nil and value > hardCap then
		value = hardCap
		state = "Hard"
	end
	return value, state
end

local function validModifier(modifier: Modifier): boolean
	return type(modifier) == "table"
		and StatDefinitions.ById[modifier.Stat] ~= nil
		and (modifier.Kind == "Flat" or modifier.Kind == "Additive" or modifier.Kind == "Multiplicative")
		and type(modifier.Value) == "number"
		and modifier.Value == modifier.Value -- NaN guard
		and math.abs(modifier.Value) < 1e6
end

function StatCalculator.Compute(level: number, modifiers: { Modifier }): ComputedStats
	level = math.clamp(math.floor(level or 1), 1, 1000)

	-- Bucket modifiers by stat.
	local byStat: { [string]: { Modifier } } = {}
	for _, modifier in modifiers do
		if validModifier(modifier) then
			local bucket = byStat[modifier.Stat]
			if not bucket then
				bucket = {}
				byStat[modifier.Stat] = bucket
			end
			table.insert(bucket, modifier)
		else
			warn("[StatCalculator] ignoring invalid modifier from " .. tostring(modifier and modifier.Source))
		end
	end

	local values = {}
	local breakdown = {}

	for _, def in StatDefinitions.List do
		local base = StatDefinitions.BaseValue(def.Id, level)
		local flat, additive, multiplicative = 0, 0, 1
		local multiplicativeSum = 0
		local addList, multList = {}, {}

		for _, modifier in (byStat[def.Id] or {}) :: { Modifier } do
			if modifier.Kind == "Flat" then
				flat += modifier.Value
			elseif modifier.Kind == "Additive" then
				additive += modifier.Value
				table.insert(addList, { Source = modifier.Source, Value = modifier.Value })
			else
				multiplicative *= (1 + modifier.Value)
				multiplicativeSum += modifier.Value
				table.insert(multList, { Source = modifier.Source, Value = modifier.Value })
			end
		end

		local final, rawBonus, cappedBonus, capState
		if def.Kind == "Scalar" then
			rawBonus = (1 + additive) * multiplicative - 1
			cappedBonus, capState =
				StatCalculator.Limit(rawBonus, def.SoftCap, def.HardCap, def.Floor, def.DiminishFactor)
			final = (base + flat) * (1 + cappedBonus)
		else
			rawBonus = base + flat + additive + multiplicativeSum
			cappedBonus, capState =
				StatCalculator.Limit(rawBonus, def.SoftCap, def.HardCap, def.Floor, def.DiminishFactor)
			final = cappedBonus
		end

		if def.AbsoluteMin ~= nil and final < def.AbsoluteMin then
			final = def.AbsoluteMin
			capState = "Floor"
		end
		if def.AbsoluteMax ~= nil and final > def.AbsoluteMax then
			final = def.AbsoluteMax
			capState = "Hard"
		end

		values[def.Id] = final
		breakdown[def.Id] = {
			Stat = def.Id,
			Base = base,
			Flat = flat,
			Additive = addList,
			Multiplicative = multList,
			RawBonus = rawBonus,
			CappedBonus = cappedBonus,
			Final = final,
			CapState = capState,
		}
	end

	local reduction = StatCalculator.DamageReductionFromDefense(values.Defense, level)

	return {
		Level = level,
		Values = values,
		Breakdown = breakdown,
		DamageReduction = reduction,
	}
end

function StatCalculator.DamageReductionFromDefense(defense: number, level: number): number
	local config = StatDefinitions.DamageReduction
	local k = config.K(level)
	local reduction = math.max(defense, 0) / (math.max(defense, 0) + k)
	return math.min(reduction, config.Cap)
end

export type DamageTags = {
	Weapon: boolean?,
	Melee: boolean?,
	Magic: boolean?,
	Charged: boolean?,
	Ability: boolean?,
	Ranged: boolean?,
}

-- Outgoing damage multiplier for a hit with the given tags.
-- `buffMultipliers` are the active multiplicative buffs (e.g. {1.10, 1.15}).
function StatCalculator.DamageMultiplier(
	values: { [string]: number },
	tags: DamageTags,
	buffMultipliers: { number }?
): (number, { Additive: number, Buffs: number })
	local pools = StatDefinitions.DamagePools
	local additive = 0
	if tags.Weapon then
		additive += values.WeaponDamage or 0
	end
	if tags.Melee then
		additive += values.MeleeDamage or 0
	end
	if tags.Magic then
		additive += values.MagicDamage or 0
	end
	if tags.Charged then
		additive += values.ChargedDamage or 0
	end
	if tags.Ability then
		additive += values.AbilityDamage or 0
	end
	additive = StatCalculator.Limit(
		additive,
		pools.Additive.SoftCap,
		pools.Additive.HardCap,
		-0.75,
		pools.Additive.DiminishFactor
	)

	local buffs = 1
	for _, multiplier in (buffMultipliers or {}) :: { number } do
		if type(multiplier) == "number" and multiplier == multiplier then
			buffs *= math.max(multiplier, 0)
		end
	end
	buffs = math.min(buffs, pools.Multiplicative.HardCap)

	local total = math.min((1 + additive) * buffs, pools.TotalMultiplierCap)
	return math.max(total, 0), { Additive = additive, Buffs = buffs }
end

export type MitigationOptions = {
	Ranged: boolean?,
	Poison: boolean?,
	TrueDamage: boolean?,
}

-- Incoming damage after the target's defenses.
function StatCalculator.Mitigate(rawDamage: number, target: ComputedStats, options: MitigationOptions?): number
	if type(rawDamage) ~= "number" or rawDamage ~= rawDamage or rawDamage <= 0 then
		return 0
	end
	local opts = options or {}
	local damage = rawDamage
	if opts.TrueDamage then
		return damage
	end
	if opts.Ranged then
		damage *= 1 - (target.Values.RangedDamageReduction or 0)
	end
	if opts.Poison then
		damage *= 1 - (target.Values.PoisonResistance or 0)
	end
	damage *= 1 - target.DamageReduction
	return damage
end

-- Ability cooldown after Cooldown Reduction (already capped at 40%).
function StatCalculator.Cooldown(baseSeconds: number, values: { [string]: number }): number
	return baseSeconds * (1 - (values.CooldownReduction or 0))
end

-- Status duration after the applier's effectiveness and the target's resistance.
function StatCalculator.StatusDuration(
	baseSeconds: number,
	applier: { [string]: number }?,
	target: { [string]: number }?
): number
	local effectiveness = applier and applier.StatusEffectiveness or 0
	local resistance = target and target.StatusResistance or 0
	return baseSeconds * (1 + effectiveness) * (1 - resistance)
end

-- Human readable diff used by the before/after comparison UI.
function StatCalculator.Diff(
	before: ComputedStats,
	after: ComputedStats
): { { Stat: string, Before: number, After: number, Delta: number } }
	local changes = {}
	for _, def in StatDefinitions.List do
		local a, b = before.Values[def.Id], after.Values[def.Id]
		if math.abs(a - b) > 1e-6 then
			table.insert(changes, { Stat = def.Id, Before = a, After = b, Delta = b - a })
		end
	end
	if math.abs(before.DamageReduction - after.DamageReduction) > 1e-6 then
		table.insert(changes, {
			Stat = "DamageReduction",
			Before = before.DamageReduction,
			After = after.DamageReduction,
			Delta = after.DamageReduction - before.DamageReduction,
		})
	end
	return changes
end

return StatCalculator
