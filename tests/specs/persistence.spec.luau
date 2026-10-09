local Loader = require("../harness/Loader")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new()
local MockDataStore = loader.RequirePath("ServerScriptService.Server.Data.MockDataStore")
local SessionStore = loader.RequirePath("ServerScriptService.Server.Data.SessionStore")
local ProfileCore = loader.RequirePath("ServerScriptService.Server.Data.ProfileCore")

local now = 1000
local function clock()
	return now
end

describe("Session-locked persistence", function()
	it("creates a default profile for new players and saves/loads it across sessions", function()
		local store = MockDataStore.new()
		local serverA = SessionStore.new(store, "job-A", 150, clock)
		local status, data = serverA:Load("Player_1", ProfileCore.Template)
		expect(status).toBe("Ok")
		expect(data.Level).toBe(1)
		data.Level = 12
		data.Currency.Souls = 777
		data.Race.Active = "Werewolf"
		data.Race.Progress.Werewolf = { XP = 900, Stage = 1, Objectives = { W2a = 3 } }
		expect((serverA:Save("Player_1", data, true))).toBe("Ok")

		-- New session on another server.
		local serverB = SessionStore.new(store, "job-B", 150, clock)
		local status2, loaded = serverB:Load("Player_1", ProfileCore.Template)
		expect(status2).toBe("Ok")
		loaded = ProfileCore.Migrate(loaded)
		expect(loaded.Level).toBe(12)
		expect(loaded.Currency.Souls).toBe(777)
		expect(loaded.Race.Active).toBe("Werewolf")
		expect(loaded.Race.Progress.Werewolf.Objectives.W2a).toBe(3)
	end)

	it("refuses to load a profile that another live server holds (prevents duplication)", function()
		local store = MockDataStore.new()
		local serverA = SessionStore.new(store, "job-A", 150, clock)
		local serverB = SessionStore.new(store, "job-B", 150, clock)
		expect((serverA:Load("Player_2", ProfileCore.Template))).toBe("Ok")
		now += 30
		expect((serverB:Load("Player_2", ProfileCore.Template))).toBe("Locked")
	end)

	it("takes over an abandoned lock after it goes stale (crashed server)", function()
		local store = MockDataStore.new()
		local serverA = SessionStore.new(store, "job-A", 150, clock)
		local serverB = SessionStore.new(store, "job-B", 150, clock)
		local _, data = serverA:Load("Player_3", ProfileCore.Template)
		data.Currency.Souls = 50
		serverA:Save("Player_3", data, false)
		now += 151
		local status, loaded = serverB:Load("Player_3", ProfileCore.Template)
		expect(status).toBe("Ok")
		expect(loaded.Currency.Souls).toBe(50)
		-- The old server must not overwrite the new session's data.
		data.Currency.Souls = 999999
		expect((serverA:Save("Player_3", data, true))).toBe("LockLost")
		expect(store:Peek("Player_3").Data.Currency.Souls).toBe(50)
	end)

	it("keeps the lock fresh with autosave heartbeats", function()
		local store = MockDataStore.new()
		local serverA = SessionStore.new(store, "job-A", 150, clock)
		local serverB = SessionStore.new(store, "job-B", 150, clock)
		local _, data = serverA:Load("Player_4", ProfileCore.Template)
		for _ = 1, 5 do
			now += 60
			expect((serverA:Save("Player_4", data, false))).toBe("Ok")
		end
		expect((serverB:Load("Player_4", ProfileCore.Template))).toBe("Locked")
	end)

	it("reports errors instead of throwing when the store fails", function()
		local store = MockDataStore.new()
		store.FailNext = 1
		local serverA = SessionStore.new(store, "job-A", 150, clock)
		expect((serverA:Load("Player_5", ProfileCore.Template))).toBe("Error")
		expect((serverA:Load("Player_5", ProfileCore.Template))).toBe("Ok")
	end)
end)

describe("Profile migrations", function()
	it("upgrades v1 saves and fills new fields without touching existing data", function()
		local v1 = {
			Version = 1,
			Level = 9,
			Weapon = "Ragnarok",
			Currency = { Souls = 10, RaceRolls = 0 },
			Race = { Active = "Witch", Discovered = { Witch = 1 }, Progress = { Witch = { XP = 5, Stage = 2, Objectives = {} } } },
		}
		local migrated = ProfileCore.Migrate(v1)
		expect(migrated.Version).toBe(ProfileCore.CurrentVersion)
		expect(migrated.Loadout.Weapon).toBe("Ragnarok")
		expect(migrated.Weapon).toBe(nil)
		expect(migrated.Level).toBe(9)
		expect(migrated.Currency.RaceRolls).toBe(0)
		expect(migrated.Race.Progress.Witch.Stage).toBe(2)
		expect(migrated.Settings.SeenRollAnimation).toBe(false)
		expect(type(migrated.Race.Pending)).toBe("table")
	end)

	it("replaces corrupt data with a fresh template", function()
		local migrated = ProfileCore.Migrate("garbage")
		expect(migrated.Level).toBe(1)
	end)

	it("never replicates internal request memory to the client", function()
		local profile = ProfileCore.Template()
		ProfileCore.RememberRequest(profile, "abc12345", { Ok = true })
		expect(ProfileCore.ClientView(profile).Requests).toBe(nil)
		expect(profile.Requests.Results.abc12345 ~= nil).toBe(true)
	end)
end)
