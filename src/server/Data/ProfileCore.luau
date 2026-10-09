--[[
	ProfileCore
	Profile schema, migrations and the trimmed view replicated to the owning client.
	Pure functions — no engine access — so the Lune test-suite can exercise save/load/migration.

	"None" values are stored as "" (empty string) because DataStores serialize to JSON and nil keys
	would disappear from the template during reconciliation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local Util = require(Modules.Core.Util)
local GameConfig = require(Modules.Config.GameConfig)
local QuestConfig = require(Modules.Config.QuestConfig)

local ProfileCore = {}

ProfileCore.CurrentVersion = 2

function ProfileCore.Template()
	return {
		Version = ProfileCore.CurrentVersion,
		CreatedAt = 0,
		Student = {
			Created = false,
			Name = "",
			SkinTone = 2,
			HairColor = 1,
			HairStyle = 1,
			Uniform = 1,
			Wavelength = "Calm",
		},
		Level = 1,
		Exp = 0,
		Currency = {
			Souls = 0,
			RaceRolls = GameConfig.RaceRoll.StartingRolls,
		},
		Race = {
			Active = "",
			Pending = {}, -- { RaceId, RequestId, At } while the player is choosing keep/replace
			History = {}, -- { RaceId, At, Outcome } newest last, capped
			Discovered = {}, -- [raceId] = first discovery unix time
			TotalRolls = 0,
			Progress = {}, -- [raceId] = { XP, Stage, Objectives = { [id] = n } }
		},
		Loadout = {
			Role = "Meister",
			School = "",
			Weapon = "MakaScythe",
			TsubakiForm = "Blade",
		},
		Weapons = {
			Owned = {}, -- [weaponId] = true
			Mastery = {}, -- [weaponId] = xp
		},
		Quests = {
			Active = QuestConfig.FirstQuest,
			Progress = 0,
			Completed = {}, -- [questId] = unix time
		},
		Unlocks = {
			BlackBlood = false,
			KishinAwakening = false,
		},
		Settings = {
			ReducedMotion = false,
			FastReveal = false,
			SeenRollAnimation = false,
			VFXQuality = "Auto",
			CameraShake = true,
			DamageNumbers = true,
			UIScale = 1,
		},
		Requests = {
			Order = {}, -- request ids, oldest first
			Results = {}, -- [requestId] = cached result
		},
		Stats = {
			Kills = 0,
			BossKills = 0,
			Deaths = 0,
		},
	}
end

-- Upgrades older saves. Each step must be idempotent.
local migrations = {
	-- v1 -> v2: "Weapon" moved under Loadout, and Settings gained SeenRollAnimation.
	[1] = function(data)
		if type(data.Weapon) == "string" then
			data.Loadout = data.Loadout or {}
			data.Loadout.Weapon = data.Weapon
			data.Weapon = nil
		end
	end,
}

function ProfileCore.Migrate(data: any)
	if type(data) ~= "table" then
		return ProfileCore.Template()
	end
	local version = tonumber(data.Version) or 1
	while version < ProfileCore.CurrentVersion do
		local step = migrations[version]
		if step then
			step(data)
		end
		version += 1
	end
	data.Version = ProfileCore.CurrentVersion
	Util.Reconcile(data, ProfileCore.Template())
	return data
end

function ProfileCore.EnsureRaceProgress(profile, raceId: string)
	local progress = profile.Race.Progress[raceId]
	if not progress then
		progress = { XP = 0, Stage = 1, Objectives = {} }
		profile.Race.Progress[raceId] = progress
	end
	return progress
end

-- Idempotency memory -----------------------------------------------------------
function ProfileCore.GetRequestResult(profile, requestId: string)
	return profile.Requests.Results[requestId]
end

function ProfileCore.RememberRequest(profile, requestId: string, result)
	local requests = profile.Requests
	if requests.Results[requestId] == nil then
		table.insert(requests.Order, requestId)
	end
	requests.Results[requestId] = result
	while #requests.Order > GameConfig.Data.RequestMemory do
		local oldest = table.remove(requests.Order, 1)
		requests.Results[oldest] = nil
	end
end

function ProfileCore.PushHistory(profile, entry)
	local history = profile.Race.History
	table.insert(history, entry)
	while #history > GameConfig.Data.HistoryLimit do
		table.remove(history, 1)
	end
end

-- What the owning client receives. Internal bookkeeping (request memory) is stripped.
function ProfileCore.ClientView(profile)
	local view = Util.DeepCopy(profile)
	view.Requests = nil
	return view
end

return ProfileCore
