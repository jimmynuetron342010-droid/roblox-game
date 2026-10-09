local Loader = require("../harness/Loader")
local Polyfills = require("../harness/Polyfills")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new()
local RaceRollLogic = loader.RequirePath("ServerScriptService.Server.Race.RaceRollLogic")
local ProfileCore = loader.RequirePath("ServerScriptService.Server.Data.ProfileCore")
local GameConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.GameConfig")
local RaceConfig = loader.RequirePath("ReplicatedStorage.Modules.Config.RaceConfig")

local function newProfile()
	local profile = ProfileCore.Template()
	profile.Student.Created = true
	profile.Currency.RaceRolls = 10
	profile.Currency.Souls = 1000
	return profile
end

-- RNG stub that returns a chosen race.
local function rngFor(raceId)
	local cumulative = 0
	for _, entry in RaceConfig.RollTable do
		cumulative += entry.Weight
		if entry.Id == raceId then
			local target = cumulative
			return {
				NextInteger = function()
					return target
				end,
			}
		end
	end
	error("unknown race " .. raceId)
end

local t = 0
local function ctx(rng, last)
	t += 10
	return { Now = t, UnixTime = 1700000000 + t, Rng = rng, LastRollAt = last }
end

describe("Race rolling (server-authoritative)", function()
	it("applies the first race immediately and charges exactly one token", function()
		local p = newProfile()
		local r = RaceRollLogic.Roll(p, "req-0001", "Token", ctx(rngFor("Witch")))
		expect(r.Ok).toBe(true)
		expect(r.RaceId).toBe("Witch")
		expect(r.Applied).toBe(true)
		expect(r.NeedsConfirm).toBe(false)
		expect(r.IsNew).toBe(true)
		expect(p.Race.Active).toBe("Witch")
		expect(p.Currency.RaceRolls).toBe(9)
		expect(p.Race.Progress.Witch.Stage).toBe(1)
	end)

	it("returns the cached result for a repeated request id and never double-charges", function()
		local p = newProfile()
		local first = RaceRollLogic.Roll(p, "req-dup-01", "Token", ctx(rngFor("Human")))
		for _ = 1, 25 do
			local again = RaceRollLogic.Roll(p, "req-dup-01", "Token", ctx(rngFor("Golem")))
			expect(again.Replayed).toBe(true)
			expect(again.RaceId).toBe(first.RaceId)
		end
		expect(p.Currency.RaceRolls).toBe(9)
		expect(p.Race.TotalRolls).toBe(1)
	end)

	it("requires a decision before replacing an existing race, and blocks further rolls meanwhile", function()
		local p = newProfile()
		RaceRollLogic.Roll(p, "req-a0001", "Token", ctx(rngFor("Werewolf")))
		p.Race.Progress.Werewolf.XP = 2500
		p.Race.Progress.Werewolf.Stage = 2
		local r = RaceRollLogic.Roll(p, "req-a0002", "Token", ctx(rngFor("Golem")))
		expect(r.NeedsConfirm).toBe(true)
		expect(p.Race.Active).toBe("Werewolf") -- not replaced yet
		local blocked = RaceRollLogic.Roll(p, "req-a0003", "Token", ctx(rngFor("Human")))
		expect(blocked.Ok).toBe(false)
		expect(blocked.Reason).toBe("PendingChoice")
		expect(p.Currency.RaceRolls).toBe(8) -- blocked roll not charged
	end)

	it("keeps every race's mastery when switching back and forth", function()
		local p = newProfile()
		RaceRollLogic.Roll(p, "req-b0001", "Token", ctx(rngFor("Werewolf")))
		p.Race.Progress.Werewolf = { XP = 2500, Stage = 2, Objectives = { W2a = 8 } }
		local r = RaceRollLogic.Roll(p, "req-b0002", "Token", ctx(rngFor("Golem")))
		local accepted = RaceRollLogic.Resolve(p, r.RequestId, true)
		expect(accepted.Ok).toBe(true)
		expect(p.Race.Active).toBe("Golem")
		expect(p.Race.Progress.Werewolf.Stage).toBe(2) -- preserved
		local back = RaceRollLogic.Roll(p, "req-b0003", "Token", ctx(rngFor("Werewolf")))
		RaceRollLogic.Resolve(p, back.RequestId, true)
		expect(p.Race.Active).toBe("Werewolf")
		expect(p.Race.Progress.Werewolf.XP).toBe(2500)
		expect(p.Race.Progress.Werewolf.Objectives.W2a).toBe(8)
	end)

	it("declining keeps the current race and records the decision", function()
		local p = newProfile()
		RaceRollLogic.Roll(p, "req-c0001", "Token", ctx(rngFor("Shinigami")))
		local r = RaceRollLogic.Roll(p, "req-c0002", "Token", ctx(rngFor("Human")))
		local declined = RaceRollLogic.Resolve(p, r.RequestId, false)
		expect(declined.Ok).toBe(true)
		expect(p.Race.Active).toBe("Shinigami")
		expect(p.Race.Pending.RaceId).toBe(nil)
		expect(p.Race.History[#p.Race.History].Outcome).toBe("Declined")
		expect(p.Race.Discovered.Human ~= nil).toBe(true) -- still discovered in the index
		-- Resolving twice is idempotent.
		local again = RaceRollLogic.Resolve(p, r.RequestId, true)
		expect(again.Replayed).toBe(true)
		expect(p.Race.Active).toBe("Shinigami")
	end)

	it("grants Soul Echo mastery XP when rolling the race you already have", function()
		local p = newProfile()
		RaceRollLogic.Roll(p, "req-d0001", "Token", ctx(rngFor("Mummy")))
		local r = RaceRollLogic.Roll(p, "req-d0002", "Token", ctx(rngFor("Mummy")))
		expect(r.SameRace).toBe(true)
		expect(r.NeedsConfirm).toBe(false)
		expect(p.Race.Progress.Mummy.XP).toBe(RaceRollLogic.SoulEchoXP)
	end)

	it("enforces the roll cooldown", function()
		local p = newProfile()
		local c = ctx(rngFor("Human"))
		RaceRollLogic.Roll(p, "req-e0001", "Token", c)
		local tooSoon = RaceRollLogic.Roll(
			p,
			"req-e0002",
			"Token",
			{ Now = c.Now + 0.1, UnixTime = 0, Rng = rngFor("Human"), LastRollAt = c.Now }
		)
		expect(tooSoon.Reason).toBe("Cooldown")
	end)

	it("validates currency for both payment methods", function()
		local p = newProfile()
		p.Currency.RaceRolls = 0
		p.Currency.Souls = GameConfig.RaceRoll.SoulsCost - 1
		local noTokens = RaceRollLogic.Roll(p, "req-f0001", "Token", ctx(rngFor("Human")))
		expect(noTokens.Reason).toBe("InsufficientFunds")
		local noSouls = RaceRollLogic.Roll(p, "req-f0002", "Souls", ctx(rngFor("Human")))
		expect(noSouls.Reason).toBe("InsufficientFunds")
		p.Currency.Souls = GameConfig.RaceRoll.SoulsCost
		local paid = RaceRollLogic.Roll(p, "req-f0003", "Souls", ctx(rngFor("Human")))
		expect(paid.Ok).toBe(true)
		expect(p.Currency.Souls).toBe(0)
	end)

	it("rejects malformed and malicious requests without side effects", function()
		local p = newProfile()
		local before = p.Currency.RaceRolls
		local bad = {
			{ nil, "Token" },
			{ 12345, "Token" },
			{ "short", "Token" },
			{ string.rep("a", 200), "Token" },
			{ "req-g0001'; DROP", "Token" },
			{ "req-g0002", "Free" },
			{ "req-g0003", nil },
			{ "req-g0004", { "Token" } },
			{ "req-g0005", "Golem" }, -- trying to pick the outcome
		}
		for _, args in bad do
			local r = RaceRollLogic.Roll(p, args[1], args[2], ctx(rngFor("Human")))
			expect(r.Ok).toBe(false)
		end
		expect(p.Currency.RaceRolls).toBe(before)
		expect(p.Race.Active).toBe("")
		local badResolve = RaceRollLogic.Resolve(p, "req-g0006", "yes")
		expect(badResolve.Ok).toBe(false)
	end)

	it("requires a created student", function()
		local p = ProfileCore.Template()
		p.Currency.RaceRolls = 5
		local r = RaceRollLogic.Roll(p, "req-h0001", "Token", ctx(rngFor("Human")))
		expect(r.Reason).toBe("NoStudent")
		expect(p.Currency.RaceRolls).toBe(5)
	end)

	it("handles 5,000 rapid rolls with consistent accounting", function()
		local p = newProfile()
		p.Currency.RaceRolls = 5000
		local rng = Polyfills.Random.new(99)
		local accepted = 0
		for i = 1, 5000 do
			local r = RaceRollLogic.Roll(p, string.format("bulk-%06d", i), "Token", ctx(rng))
			expect(r.Ok).toBe(true)
			if r.NeedsConfirm then
				RaceRollLogic.Resolve(p, r.RequestId, i % 2 == 0)
				accepted += 1
			end
		end
		expect(p.Currency.RaceRolls).toBe(0)
		expect(p.Race.TotalRolls).toBe(5000)
		expect(#p.Race.History).toBe(GameConfig.Data.HistoryLimit)
		expect(#p.Requests.Order).toBe(GameConfig.Data.RequestMemory)
		expect(accepted > 0).toBe(true)
	end)
end)
