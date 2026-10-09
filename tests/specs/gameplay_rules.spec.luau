local Loader = require("../harness/Loader")
local Polyfills = require("../harness/Polyfills")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

local loader = Loader.new({
	Services = {
		Players = {
			PlayerAdded = signal(),
			PlayerRemoving = signal(),
			GetPlayers = function()
				return {}
			end,
		},
		TextService = {},
	},
	SilenceWarnings = true,
})
local roblox = Loader.roblox
local R = loader.RequirePath

local CharacterService = R("ServerScriptService.Server.Services.CharacterService")
local LoadoutService = R("ServerScriptService.Server.Services.LoadoutService")
local MasteryService = R("ServerScriptService.Server.Services.MasteryService")
local QuestService = R("ServerScriptService.Server.Services.QuestService")
local ProfileCore = R("ServerScriptService.Server.Data.ProfileCore")
local AbilitySlots = R("ReplicatedStorage.Modules.Core.AbilitySlots")
local AbilityConfig = R("ReplicatedStorage.Modules.Config.AbilityConfig")
local BuildRules = R("ReplicatedStorage.Modules.Config.BuildRules")
local CombatRoleConfig = R("ReplicatedStorage.Modules.Config.CombatRoleConfig")
local MagicConfig = R("ReplicatedStorage.Modules.Config.MagicConfig")
local MasteryConfig = R("ReplicatedStorage.Modules.Config.MasteryConfig")
local QuestConfig = R("ReplicatedStorage.Modules.Config.QuestConfig")
local RaceConfig = R("ReplicatedStorage.Modules.Config.RaceConfig")
local StudentConfig = R("ReplicatedStorage.Modules.Config.StudentConfig")
local WeaponConfig = R("ReplicatedStorage.Modules.WeaponConfig")
local ProjectileController = R("ReplicatedStorage.Modules.ProjectileController")

local rng = Polyfills.Random.new(1234)

local function validStudent()
	return {
		Name = "  Kaito   Ren ",
		SkinTone = 3,
		HairColor = 2,
		HairStyle = 4,
		Uniform = 2,
		Wavelength = "Precise",
		Role = "Technician",
		Weapon = "StarShuriken",
	}
end

-- Random junk of every Luau type (and nested tables) for fuzzing remote payloads.
local function junk(depth: number): any
	local kind = rng:NextInteger(1, 9)
	if kind == 1 then
		return nil
	elseif kind == 2 then
		return rng:NextNumber(-1e9, 1e9)
	elseif kind == 3 then
		return ({ 0 / 0, math.huge, -math.huge, -1, 0, 1.5, 2 ^ 53 })[rng:NextInteger(1, 7)]
	elseif kind == 4 then
		return rng:NextInteger(0, 1) == 1
	elseif kind == 5 then
		return string.rep(string.char(rng:NextInteger(0, 255)), rng:NextInteger(0, 80))
	elseif kind == 6 then
		return ({ "Meister", "PartnerWeapon", "Golem", "Calm", "MakaScythe", "", "Kishin", "rbxassetid://1" })[rng:NextInteger(
			1,
			8
		)]
	elseif kind == 7 and depth > 0 then
		local t = {}
		for _ = 1, rng:NextInteger(0, 20) do
			local key = junk(0)
			if key == nil or key ~= key then
				key = "k" -- nil / NaN cannot be table keys
			end
			t[key] = junk(depth - 1)
		end
		return t
	elseif kind == 8 then
		return roblox.Vector3.new(1, 2, 3)
	end
	return function() end
end

describe("Create Your Student validation (server)", function()
	it("accepts a valid student and normalizes the name", function()
		local ok, clean = CharacterService.ValidateStudent(validStudent(), true)
		expect(ok).toBe(true)
		expect(clean.Name).toBe("Kaito Ren")
		expect(clean.Role).toBe("Technician")
		expect(clean.Weapon).toBe("StarShuriken")
	end)

	it("rejects bad names with a specific reason", function()
		local cases = {
			{ "ab", "NameLength" },
			{ string.rep("a", 17), "NameLength" },
			{ "9lives", "NameCharacters" },
			{ "Maka<script>", "NameCharacters" },
			{ "Kid☆", "NameCharacters" },
			{ "   ", "NameLength" },
		}
		for _, case in cases do
			local payload = validStudent()
			payload.Name = case[1]
			local ok, reason = CharacterService.ValidateStudent(payload, true)
			expect(ok).toBe(false)
			expect(reason).toBe(case[2])
		end
	end)

	it("never lets the client pick a Demon Weapon-only role or a non-starter weapon", function()
		local payload = validStudent()
		payload.Role = "PartnerWeapon"
		expect((CharacterService.ValidateStudent(payload, true))).toBe(false)
		payload = validStudent()
		payload.Weapon = "ArachneSpider"
		expect((CharacterService.ValidateStudent(payload, true))).toBe(false)
	end)

	it("edit mode only changes appearance (name/role/weapon ignored)", function()
		local payload = validStudent()
		payload.Name = nil
		payload.Role = "PartnerWeapon"
		payload.Weapon = "Nope"
		local ok, clean = CharacterService.ValidateStudent(payload, false)
		expect(ok).toBe(true)
		expect(clean.Name).toBe(nil)
		expect(clean.Role).toBe(nil)
	end)

	it("survives 3000 fuzzed payloads without erroring or accepting invalid data", function()
		for i = 1, 3000 do
			local payload = junk(2)
			if i % 3 == 0 then
				-- Mostly-valid payloads with one corrupted field are the interesting case.
				payload = validStudent()
				local keys = { "Name", "SkinTone", "HairColor", "HairStyle", "Uniform", "Wavelength", "Role", "Weapon" }
				payload[keys[rng:NextInteger(1, #keys)]] = junk(1)
			end
			local okCall, ok, clean = pcall(CharacterService.ValidateStudent, payload, i % 2 == 0)
			if not okCall then
				error("ValidateStudent threw: " .. tostring(ok))
			end
			if ok then
				expect(clean.SkinTone >= 1 and clean.SkinTone <= #StudentConfig.SkinTones).toBe(true)
				expect(clean.Uniform >= 1 and clean.Uniform <= #StudentConfig.Uniforms).toBe(true)
				expect(StudentConfig.IsWavelength(clean.Wavelength)).toBe(true)
				if i % 2 == 0 then
					expect(#clean.Name >= StudentConfig.NameMinLength and #clean.Name <= StudentConfig.NameMaxLength).toBe(
						true
					)
					expect(table.find(StudentConfig.StarterWeapons, clean.Weapon) ~= nil).toBe(true)
				end
			end
		end
	end)
end)

describe("Settings (server-side cleaning)", function()
	it("keeps valid values and drops everything else", function()
		local clean = LoadoutService.CleanSettings({
			ReducedMotion = true,
			CameraShake = "yes",
			VFXQuality = "Ultra",
			UIScale = 1.234,
			FastReveal = false,
			Unknown = 5,
		})
		expect(clean.ReducedMotion).toBe(true)
		expect(clean.CameraShake).toBe(nil)
		expect(clean.VFXQuality).toBe(nil)
		expect(clean.UIScale).toBe(1.23)
		expect(clean.FastReveal).toBe(false)
		expect(clean.Unknown).toBe(nil)
	end)

	it("rejects out-of-range, NaN and oversized inputs", function()
		expect(LoadoutService.CleanSettings({ UIScale = 5 }).UIScale).toBe(nil)
		expect(LoadoutService.CleanSettings({ UIScale = 0 / 0 }).UIScale).toBe(nil)
		local bomb = {}
		for i = 1, 100 do
			bomb["k" .. i] = true
		end
		bomb.ReducedMotion = true
		expect(next(LoadoutService.CleanSettings(bomb))).toBe(nil)
		for _ = 1, 1000 do
			local ok = pcall(LoadoutService.CleanSettings, junk(2))
			expect(ok).toBe(true)
		end
	end)
end)

describe("Build rules (race · role · weapon · magic stay independent but consistent)", function()
	it("sanitizes every race × role × school × level combination into a legal build", function()
		local roles = { "Meister", "Assassin", "Technician", "PartnerWeapon" }
		local schools = { false, "Vector", "Frog", "Restoration", "Ember", "Void", "Artifice" }
		for _, race in RaceConfig.List do
			for _, role in roles do
				for _, school in schools do
					for _, level in { 1, 8, 15, 30 } do
						local finalRole, finalSchool = BuildRules.Sanitize(race.Id, role, school or nil, level)
						expect(BuildRules.IsRoleAllowed(race.Id, finalRole)).toBe(true)
						if finalSchool then
							expect(BuildRules.IsSchoolAllowed(race.Id, finalSchool, level)).toBe(true)
						else
							expect(BuildRules.CanUseMagic(race.Id) and MagicConfig.DefaultSchool(race.Id) ~= nil).toBe(
								false
							)
						end
					end
				end
			end
		end
	end)

	it("keeps Meister a role (not a race) and Partner Weapon exclusive to Demon Weapons", function()
		expect(RaceConfig.ById.Meister).toBe(nil)
		expect(CombatRoleConfig.ById.Meister ~= nil).toBe(true)
		expect(BuildRules.IsRoleAllowed("DemonWeapon", "Meister")).toBe(false)
		expect(BuildRules.IsRoleAllowed("Human", "PartnerWeapon")).toBe(false)
		expect(BuildRules.IsRoleAllowed("DemonWeapon", "PartnerWeapon")).toBe(true)
		expect(BuildRules.CanSynchronize("DemonWeapon", "PartnerWeapon", "Human", "Meister")).toBe(true)
		expect(BuildRules.CanSynchronize("Human", "Meister", "Human", "Meister")).toBe(false)
	end)

	it("treats Kishin as an endgame unlock, never a rollable race", function()
		expect(RaceConfig.ById.Kishin).toBe(nil)
		local profile = ProfileCore.Template()
		profile.Race.Active = "Human"
		expect((AbilitySlots.Resolve(profile, "B"))).toBe(nil)
		profile.Unlocks.KishinAwakening = true
		expect((AbilitySlots.Resolve(profile, "B"))).toBe("KishinAwakening")
	end)
end)

describe("Ability slots", function()
	it("resolves C/V for every race and role, honouring mastery unlock stages", function()
		for _, race in RaceConfig.List do
			for _, role in BuildRules.AllowedRoles(race.Id) do
				local profile = ProfileCore.Template()
				profile.Race.Active = race.Id
				profile.Loadout.Role = role
				ProfileCore.EnsureRaceProgress(profile, race.Id)
				local c, _, reason = AbilitySlots.Resolve(profile, "C")
				if race.AbilityUnlockStage > 1 then
					expect(c).toBe(nil)
					expect(reason).toBe("Locked")
					profile.Race.Progress[race.Id].Stage = race.AbilityUnlockStage
					c = AbilitySlots.Resolve(profile, "C")
				end
				expect(c).toBe(race.AbilityId)
				expect(AbilityConfig.Get(c) ~= nil).toBe(true)
				local v = AbilitySlots.Resolve(profile, "V")
				expect(v).toBe(CombatRoleConfig.ById[role].TechniqueId)
				expect(AbilityConfig.Get(v) ~= nil).toBe(true)
			end
		end
	end)

	it("every castable ability has a cooldown; school spells are gated by their racial ability", function()
		local spells = {}
		for _, school in MagicConfig.List do
			spells[school.SpellId] = school
		end
		for _, ability in AbilityConfig.List do
			local school = spells[ability.Id]
			if school then
				-- Cast only through Witchcraft / Sorcery, which carry the cost and cooldown.
				local gate = AbilityConfig.Get(RaceConfig.ById[school.Group].AbilityId)
				expect(gate.Kind).toBe("School")
				expect(gate.Cooldown).toBeAtLeast(5)
				expect(gate.Cost).toBeAtLeast(10)
			else
				expect(ability.Cooldown).toBeAtLeast(1)
				expect(ability.Cost).toBeAtLeast(0)
			end
		end
		-- No slot can ever resolve directly to a school spell.
		for _, race in RaceConfig.List do
			expect(spells[race.AbilityId or ""]).toBe(nil)
		end
	end)
end)

describe("Mastery progression", function()
	it("needs both XP and every objective; playing the race is the only way up", function()
		for _, race in RaceConfig.List do
			local progress = { XP = 0, Stage = 1, Objectives = {} }
			local stage2 = MasteryConfig.StageDef(race.Id, 2)
			-- XP alone is not enough.
			progress.XP = stage2.XP + 10
			expect(MasteryService.TryAdvance(progress, race.Id)).toBe(false)
			-- Objectives alone are not enough either.
			progress.XP = 0
			for _, objective in stage2.Objectives do
				progress.Objectives[objective.Id] = objective.Count
			end
			expect(MasteryService.TryAdvance(progress, race.Id)).toBe(false)
			progress.XP = stage2.XP
			expect(MasteryService.TryAdvance(progress, race.Id)).toBe(true)
			expect(progress.Stage).toBe(2)
			-- Stage III objectives start from zero.
			progress.XP = 1e9
			expect(MasteryService.TryAdvance(progress, race.Id)).toBe(false)
		end
	end)

	it("counts matching gameplay events toward objectives and caps them", function()
		local progress = { XP = 0, Stage = 1, Objectives = {} }
		for _ = 1, 60 do
			MasteryService.ApplyEvent(progress, "Human", "EnemyKilled", {})
		end
		expect(progress.Objectives.H2a).toBe(40)
		expect(progress.XP).toBe(60 * MasteryConfig.XPRewards.EnemyKilled)
		-- Events that do not match an objective's filter do not count.
		local demon = { XP = 0, Stage = 1, Objectives = {} }
		MasteryService.ApplyEvent(demon, "DemonWeapon", "AbilityUsed", { AbilityId = "SomethingElse" })
		expect(demon.Objectives.D2a).toBe(nil)
		MasteryService.ApplyEvent(demon, "DemonWeapon", "AbilityUsed", { AbilityId = "ResonanceSurge" })
		expect(demon.Objectives.D2a).toBe(1)
	end)
end)

describe("Quests", function()
	it("advances the main chain and gates the Kishin chain by level", function()
		local profile = ProfileCore.Template()
		expect(profile.Quests.Active).toBe(QuestConfig.FirstQuest)
		local first = QuestConfig.ById[QuestConfig.FirstQuest]
		local completed
		for _ = 1, first.Count do
			completed = QuestService.ApplyEvent(profile, first.Event, { KishinEgg = true, EnemyType = "KishinEgg" })
		end
		expect(completed).toBe(first)
		expect(profile.Quests.Active).toBe(first.Next)
		-- Jump to the first Kishin quest: progress is blocked under its level requirement.
		profile.Quests.Active = "K1_Whispers"
		profile.Quests.Progress = 0
		profile.Level = 5
		QuestService.ApplyEvent(profile, "EnemyKilled", { EnemyType = "MadnessWraith" })
		expect(profile.Quests.Progress).toBe(0)
		profile.Level = 20
		QuestService.ApplyEvent(profile, "EnemyKilled", { EnemyType = "MadnessWraith" })
		expect(profile.Quests.Progress).toBe(1)
	end)

	it("every quest chain link exists and Kishin Awakening is only a quest reward", function()
		local rewardsKishin = 0
		for _, quest in QuestConfig.List do
			if quest.Next then
				expect(QuestConfig.ById[quest.Next] ~= nil).toBe(true)
			end
			if quest.Rewards and quest.Rewards.Unlock == "KishinAwakening" then
				rewardsKishin += 1
				expect(quest.Chain).toBe("Kishin")
			end
		end
		expect(rewardsKishin).toBe(1)
	end)
end)

describe("Projectiles", function()
	it("every projectile attack can reach its range before despawning", function()
		for attackId, attack in WeaponConfig.Attacks do
			for _, hit in attack.Hits or {} do
				if hit.Shape == "Projectile" then
					local spec = WeaponConfig.Projectiles[hit.Projectile]
					if not spec then
						error(attackId .. " uses unknown projectile " .. tostring(hit.Projectile))
					end
					expect(hit.Speed * spec.Lifetime).toBeAtLeast(hit.Range)
				end
			end
		end
	end)

	it("closed-form flight matches a fine numeric integration (gravity arcs)", function()
		local origin = roblox.Vector3.new(0, 5, 0)
		local direction = roblox.Vector3.new(1, 0.5, -0.2)
		local speed, gravity = 80, 35
		local position, velocity = origin, direction.Unit * speed
		local dt = 1 / 2000
		for _ = 1, 1000 do
			velocity += roblox.Vector3.new(0, -gravity, 0) * dt
			position += velocity * dt
		end
		local closed = ProjectileController.PositionAt(origin, direction, speed, gravity, 0.5)
		expect((closed - position).Magnitude).toBeAtMost(0.05)
	end)
end)
