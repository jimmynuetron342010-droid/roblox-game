local Loader = require("../harness/Loader")
local Polyfills = require("../harness/Polyfills")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new()
local RaceConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.RaceConfig")
local GameConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.GameConfig")
local WeightedRoll = loader.RequirePath("ReplicatedStorage.Modules.Core.WeightedRoll")
local StatDefinitions = loader.RequirePath("ReplicatedStorage.Modules.Config.StatDefinitions")
local AbilityConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.AbilityConfig")
local MasteryConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.MasteryConfig")

local EXPECTED = {
	Human = 0.40,
	DemonWeapon = 0.25,
	Werewolf = 0.12,
	Witch = 0.10,
	Zombie = 0.05,
	Mummy = 0.03,
	Sorcerer = 0.02,
	Shinigami = 0.02,
	Golem = 0.01,
}

describe("Race probability table", function()
	it("weights are positive integers that sum to exactly 100%", function()
		local ok, err = WeightedRoll.Validate(RaceConfig.RollTable, GameConfig.RaceRoll.TotalWeight)
		expect(ok).toBe(true)
		expect(err).toBe(nil)
	end)

	it("matches the published per-race chances exactly", function()
		local probabilities = WeightedRoll.Probabilities(RaceConfig.RollTable)
		local count = 0
		for id, expected in EXPECTED do
			expect(probabilities[id]).toBeNear(expected, 1e-12)
			count += 1
		end
		expect(count).toBe(#RaceConfig.List)
	end)

	it("produces the published distribution over 1,000,000 server rolls (chi-square)", function()
		local rng = Polyfills.Random.new(1337)
		local counts = {}
		local n = 1000000
		for _ = 1, n do
			local entry = WeightedRoll.Pick(RaceConfig.RollTable, rng)
			counts[entry.Id] = (counts[entry.Id] or 0) + 1
		end
		local chi = 0
		for id, p in EXPECTED do
			local expectedCount = n * p
			chi += ((counts[id] or 0) - expectedCount) ^ 2 / expectedCount
			print(string.format("      %-12s expected %5.2f%%  observed %6.3f%%", id, p * 100, (counts[id] or 0) / n * 100))
		end
		-- 8 degrees of freedom: critical value at p = 0.001 is 26.12
		expect(chi).toBeAtMost(26.12)
	end)

	it("rejects tables that do not sum to 100%", function()
		local broken = table.clone(RaceConfig.RollTable)
		broken[1] = { Id = broken[1].Id, Weight = broken[1].Weight + 1 }
		local ok = WeightedRoll.Validate(broken, GameConfig.RaceRoll.TotalWeight)
		expect(ok).toBe(false)
	end)

	it("picks deterministically at the boundaries of the cumulative table", function()
		local fixed = { NextInteger = function(_, _, _) return 1 end }
		expect(WeightedRoll.Pick(RaceConfig.RollTable, fixed).Id).toBe("Human")
		local last = { NextInteger = function(_, _, max) return max end }
		expect(WeightedRoll.Pick(RaceConfig.RollTable, last).Id).toBe("Golem")
		local edge = { NextInteger = function() return 4000 end }
		expect(WeightedRoll.Pick(RaceConfig.RollTable, edge).Id).toBe("Human")
		local edge2 = { NextInteger = function() return 4001 end }
		expect(WeightedRoll.Pick(RaceConfig.RollTable, edge2).Id).toBe("DemonWeapon")
	end)
end)

describe("Race definitions", function()
	it("only reference known stats, abilities and mastery trees", function()
		for _, race in RaceConfig.List do
			for _, modifier in race.Modifiers do
				expect(StatDefinitions.ById[modifier.Stat] ~= nil).toBe(true)
			end
			if race.AbilityId then
				expect(AbilityConfig.ById[race.AbilityId] ~= nil).toBe(true)
			end
			local tree = MasteryConfig.Tree(race.Id)
			expect(tree ~= nil).toBe(true)
			expect(#tree).toBe(3)
		end
	end)

	it("keeps mastery stage bonuses modest (<= 5% per stat per stage)", function()
		for raceId, tree in MasteryConfig.Trees do
			for _, stage in tree do
				for _, modifier in stage.Modifiers do
					expect(math.abs(modifier.Value)).toBeAtMost(0.05)
				end
				for _, objective in stage.Objectives do
					expect(objective.Count).toBeAtLeast(1)
				end
			end
			expect(raceId ~= nil).toBe(true)
		end
	end)

	it("gives Mummy and Golem a movement penalty as their counterbalance", function()
		local function speed(id)
			for _, m in RaceConfig.ById[id].Modifiers do
				if m.Stat == "MoveSpeed" then
					return m.Value
				end
			end
			return 0
		end
		expect(speed("Mummy")).toBeAtMost(-0.05)
		expect(speed("Golem")).toBe(-0.15)
	end)
end)
