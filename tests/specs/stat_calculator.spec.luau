local Loader = require("../harness/Loader")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new()
local StatCalculator = loader.RequirePath("ReplicatedStorage.Modules.Core.StatCalculator")
local StatDefinitions = loader.RequirePath("ReplicatedStorage.Modules.Config.StatDefinitions")
local RaceConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.RaceConfig")
local MasteryConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.MasteryConfig")
local CombatRoleConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.CombatRoleConfig")

local function mod(stat, kind, value, source)
	return { Stat = stat, Kind = kind, Value = value, Source = source or "Test" }
end

describe("StatCalculator basics", function()
	it("returns base values with no modifiers", function()
		local stats = StatCalculator.Compute(1, {})
		expect(stats.Values.MaxHealth).toBe(100)
		expect(stats.Values.MoveSpeed).toBe(16)
		expect(stats.Values.CooldownReduction).toBe(0)
	end)

	it("sums additive bonuses and multiplies multiplicative ones separately", function()
		local stats = StatCalculator.Compute(1, {
			mod("MaxHealth", "Additive", 0.2),
			mod("MaxHealth", "Additive", 0.1),
			mod("MaxHealth", "Multiplicative", 0.1),
		})
		-- (1 + 0.3) * 1.1 - 1 = 0.43 bonus (under the 0.6 soft cap)
		expect(stats.Values.MaxHealth).toBeNear(143, 1e-9)
		local b = stats.Breakdown.MaxHealth
		expect(#b.Additive).toBe(2)
		expect(#b.Multiplicative).toBe(1)
		expect(b.CapState).toBe("None")
	end)

	it("applies flat bonuses before percentage bonuses", function()
		local stats = StatCalculator.Compute(1, { mod("Defense", "Flat", 10), mod("Defense", "Additive", 0.5) })
		expect(stats.Values.Defense).toBeNear((20 + 10) * 1.5, 1e-9)
	end)

	it("applies diminishing returns past the soft cap and never exceeds the hard cap", function()
		-- Cooldown reduction: soft 0.25, hard 0.40
		local a = StatCalculator.Compute(1, { mod("CooldownReduction", "Additive", 0.35) })
		expect(a.Values.CooldownReduction).toBeNear(0.25 + 0.10 * 0.5, 1e-9)
		expect(a.Breakdown.CooldownReduction.CapState).toBe("Soft")
		local b = StatCalculator.Compute(1, { mod("CooldownReduction", "Additive", 5) })
		expect(b.Values.CooldownReduction).toBe(0.4)
		expect(b.Breakdown.CooldownReduction.CapState).toBe("Hard")
	end)

	it("clamps movement speed to safe absolute limits", function()
		local fast = StatCalculator.Compute(1, { mod("MoveSpeed", "Additive", 3), mod("MoveSpeed", "Multiplicative", 2) })
		expect(fast.Values.MoveSpeed).toBeAtMost(22)
		local slow = StatCalculator.Compute(1, { mod("MoveSpeed", "Additive", -5) })
		expect(slow.Values.MoveSpeed).toBeAtLeast(10)
	end)

	it("ignores malformed modifiers (unknown stat, NaN, huge values)", function()
		local stats = StatCalculator.Compute(1, {
			mod("NotAStat", "Additive", 1),
			mod("MaxHealth", "Additive", 0 / 0),
			mod("MaxHealth", "Additive", 1e9),
			mod("MaxHealth", "Exploit", 1),
		})
		expect(stats.Values.MaxHealth).toBe(100)
	end)

	it("caps damage reduction from Defense at 60%", function()
		local stats = StatCalculator.Compute(1, { mod("Defense", "Flat", 1e5) })
		expect(stats.DamageReduction).toBe(0.6)
	end)

	it("respects every stat's hard cap under absurd stacking", function()
		local mods = {}
		for _, def in StatDefinitions.List do
			for i = 1, 20 do
				table.insert(mods, mod(def.Id, "Additive", 0.5, "Stack" .. i))
				table.insert(mods, mod(def.Id, "Multiplicative", 0.5, "Buff" .. i))
			end
		end
		local stats = StatCalculator.Compute(50, mods)
		for _, def in StatDefinitions.List do
			local value = stats.Values[def.Id]
			expect(value == value).toBe(true) -- not NaN
			if def.Kind == "Percent" then
				expect(value).toBeAtMost(def.HardCap)
			else
				local base = StatDefinitions.BaseValue(def.Id, 50)
				expect(value).toBeAtMost(base * (1 + def.HardCap) + 1e-9)
			end
			if def.AbsoluteMax then
				expect(value).toBeAtMost(def.AbsoluteMax)
			end
		end
	end)
end)

describe("Damage pooling", function()
	it("pools additive damage categories and soft caps the pool", function()
		local values = { WeaponDamage = 0.75, MeleeDamage = 0.75 }
		local multiplier, detail = StatCalculator.DamageMultiplier(values, { Weapon = true, Melee = true }, {})
		-- 1.5 raw -> 0.6 + 0.9 * 0.5 = 1.05 -> hard cap 1.0
		expect(detail.Additive).toBe(1.0)
		expect(multiplier).toBe(2.0)
	end)

	it("caps stacked multiplicative buffs at x1.4", function()
		local multiplier, detail = StatCalculator.DamageMultiplier({}, { Weapon = true }, { 1.2, 1.2, 1.2 })
		expect(detail.Buffs).toBe(1.4)
		expect(multiplier).toBe(1.4)
	end)

	it("never exceeds the total multiplier ceiling", function()
		local values = { WeaponDamage = 9, MeleeDamage = 9, ChargedDamage = 9, AbilityDamage = 9, MagicDamage = 9 }
		local multiplier = StatCalculator.DamageMultiplier(
			values,
			{ Weapon = true, Melee = true, Charged = true, Ability = true, Magic = true },
			{ 5, 5, 5 }
		)
		expect(multiplier).toBeAtMost(StatDefinitions.DamagePools.TotalMultiplierCap)
	end)

	it("only applies categories that match the hit's tags", function()
		local values = { WeaponDamage = 0.2, MagicDamage = 0.3 }
		local melee = StatCalculator.DamageMultiplier(values, { Weapon = true, Melee = true })
		local magic = StatCalculator.DamageMultiplier(values, { Magic = true })
		expect(melee).toBeNear(1.2, 1e-9)
		expect(magic).toBeNear(1.3, 1e-9)
	end)

	it("mitigates ranged hits with Ancient Wrappings before Defense", function()
		local mummy = StatCalculator.Compute(10, RaceConfig.StatModifiers("Mummy"))
		local human = StatCalculator.Compute(10, RaceConfig.StatModifiers("Human"))
		local toMummy = StatCalculator.Mitigate(100, mummy, { Ranged = true })
		local toHuman = StatCalculator.Mitigate(100, human, { Ranged = true })
		expect(toMummy < toHuman).toBe(true)
		expect(StatCalculator.Mitigate(0 / 0, human)).toBe(0)
		expect(StatCalculator.Mitigate(-50, human)).toBe(0)
	end)
end)

describe("Race balance at equal level (initial tuning sanity)", function()
	local LEVELS = { 1, 15, 30, 50 }

	it("applies every race's published bonuses exactly when under caps", function()
		local human = StatCalculator.Compute(10, RaceConfig.StatModifiers("Human"))
		expect(human.Values.XPGain).toBeNear(0.10, 1e-9)
		expect(human.Values.WeaponMasteryGain).toBeNear(0.05, 1e-9)
		local golem = StatCalculator.Compute(10, RaceConfig.StatModifiers("Golem"))
		expect(golem.Values.MoveSpeed).toBeNear(16 * 0.85, 1e-9)
		local werewolf = StatCalculator.Compute(10, RaceConfig.StatModifiers("Werewolf"))
		-- +25% speed is above the 20% soft cap: 0.2 + 0.05 * 0.5 = 0.225
		expect(werewolf.Values.MoveSpeed).toBeNear(16 * 1.225, 1e-9)
	end)

	it("keeps every race + role + full mastery build inside safe limits at all levels", function()
		for _, level in LEVELS do
			print(string.format("      level %d", level))
			for _, race in RaceConfig.List do
				for _, role in CombatRoleConfig.List do
					local mods = {}
					for _, m in RaceConfig.StatModifiers(race.Id) do
						table.insert(mods, m)
					end
					for _, m in MasteryConfig.StatModifiers(race.Id, 3) do
						table.insert(mods, m)
					end
					for _, m in CombatRoleConfig.StatModifiers(role.Id) do
						table.insert(mods, m)
					end
					local stats = StatCalculator.Compute(level, mods)
					local v = stats.Values
					expect(v.MoveSpeed).toBeAtMost(22)
					expect(v.CooldownReduction).toBeAtMost(0.4)
					expect(stats.DamageReduction).toBeAtMost(0.6)
					expect(v.AttackSpeed).toBeAtMost(1.4)
					local dmg = StatCalculator.DamageMultiplier(v, { Weapon = true, Melee = true }, {})
					expect(dmg).toBeAtMost(2.0)
				end
			end
		end
	end)

	it("reports an effective-power table so tuning can be reviewed", function()
		-- Effective HP (HP / (1 - DR)) and weapon DPS multiplier (damage mult * attack speed) at level 30.
		local rows = {}
		for _, race in RaceConfig.List do
			local mods = RaceConfig.StatModifiers(race.Id)
			local s = StatCalculator.Compute(30, mods)
			local ehp = s.Values.MaxHealth / (1 - s.DamageReduction)
			local dps = StatCalculator.DamageMultiplier(s.Values, { Weapon = true, Melee = true }) * s.Values.AttackSpeed
			local magic = StatCalculator.DamageMultiplier(s.Values, { Magic = true, Ability = true })
			table.insert(rows, { race.Id, ehp, dps, magic, s.Values.MoveSpeed })
		end
		local minEhp, maxEhp = math.huge, 0
		for _, r in rows do
			print(string.format("      %-12s EHP %6.0f  weaponDPSx %.2f  magicx %.2f  speed %.1f", r[1], r[2], r[3], r[4], r[5]))
			minEhp = math.min(minEhp, r[2])
			maxEhp = math.max(maxEhp, r[2])
		end
		-- The tankiest origin should not have more than ~2.3x the effective HP of the squishiest.
		expect(maxEhp / minEhp).toBeAtMost(2.3)
	end)
end)
