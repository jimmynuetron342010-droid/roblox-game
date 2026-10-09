--[[
	RaceService
	Remote endpoints for race rolling. The roll is decided on the server by RaceRollLogic using a
	server-owned Random object *before* the client animates anything.

	Duplicate protection (defense in depth):
	  * per-player busy lock (concurrent invocations are rejected)
	  * idempotent request ids stored in the profile (retries never charge twice)
	  * pending keep/replace decision blocks new rolls
	  * server-clock cooldown
	  * RemoteGuard rate limit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local BuildRules = require(Modules.Config.BuildRules)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local RaceConfig = require(Modules.Config.RaceConfig)
local RarityConfig = require(Modules.Config.RarityConfig)

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)
local RaceRollLogic = require(Server.Race.RaceRollLogic)
local RemoteGuard = require(Server.Core.RemoteGuard)

local RaceService = {}

local DataService
local StatService
local CharacterService

local rng = Random.new()
local busy: { [Player]: boolean } = {}
local lastRollAt: { [Player]: number } = {}

local function syncAttributes(player: Player, profile)
	local raceId = profile.Race.Active
	local race = RaceConfig.ById[raceId]
	player:SetAttribute("Race", raceId)
	player:SetAttribute("RaceRarity", race and race.Rarity or "")
	local progress = profile.Race.Progress[raceId]
	player:SetAttribute("RaceStage", progress and progress.Stage or 0)
	-- Highest unlocked prestige title of the active race.
	local title = ""
	if race and progress then
		for s = 1, progress.Stage do
			local def = MasteryConfig.StageDef(raceId, s)
			if def and def.Title then
				title = def.Title
			end
		end
	end
	player:SetAttribute("Title", title)
end

function RaceService:OnRaceChanged(player: Player, previous: string?)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	local raceId = profile.Race.Active
	local role, school, changes = BuildRules.Sanitize(
		raceId,
		profile.Loadout.Role,
		profile.Loadout.School ~= "" and profile.Loadout.School or nil,
		profile.Level
	)
	profile.Loadout.Role = role
	profile.Loadout.School = school or ""
	player:SetAttribute("Role", role)
	player:SetAttribute("School", profile.Loadout.School)
	for _, change in changes do
		Notifier.Send(player, change, "Info")
	end
	syncAttributes(player, profile)
	StatService:Recompute(player)
	CharacterService:ApplyAppearance(player)
	GameEvents.Fire(player, "RaceChanged", { RaceId = raceId, Previous = previous })
	DataService:MarkDirty(player)
end

function RaceService:SyncAttributes(player: Player)
	local profile = DataService:GetProfile(player)
	if profile then
		syncAttributes(player, profile)
	end
end

local function roll(player: Player, requestId: any, payment: any)
	if busy[player] then
		return { Ok = false, Reason = "Busy" }
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "Loading" }
	end
	busy[player] = true
	local ok, result = pcall(RaceRollLogic.Roll, profile, requestId, payment, {
		Now = os.clock(),
		UnixTime = os.time(),
		Rng = rng,
		LastRollAt = lastRollAt[player],
	})
	busy[player] = nil
	if not ok then
		warn("[RaceService] roll error: " .. tostring(result))
		return { Ok = false, Reason = "ServerError" }
	end
	if result.Ok and not result.Replayed then
		lastRollAt[player] = os.clock()
		if result.Applied then
			RaceService:OnRaceChanged(player, result.Previous)
		end
		DataService:MarkDirty(player)
		DataService:SaveNow(player) -- purchases are saved immediately
		local race = RaceConfig.ById[result.RaceId]
		local rarity = RarityConfig.Tiers[race.Rarity]
		if rarity.Order >= 5 then
			-- Legendary and Mythic pulls are announced server-wide (after the reveal delay).
			task.delay(rarity.RevealBuildUp + 0.5, function()
				Notifier.All(
					string.format("%s awakened as a %s %s!", player.DisplayName, rarity.DisplayName, race.DisplayName),
					"Rare",
					{
						Rarity = race.Rarity,
					}
				)
			end)
		end
	end
	return result
end

local function resolve(player: Player, requestId: any, accept: any)
	if busy[player] then
		return { Ok = false, Reason = "Busy" }
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "Loading" }
	end
	busy[player] = true
	local ok, result = pcall(RaceRollLogic.Resolve, profile, requestId, accept)
	busy[player] = nil
	if not ok then
		warn("[RaceService] resolve error: " .. tostring(result))
		return { Ok = false, Reason = "ServerError" }
	end
	if result.Ok and not result.Replayed then
		if result.Accepted then
			RaceService:OnRaceChanged(player, result.Previous)
			local race = RaceConfig.ById[result.Active]
			Notifier.Send(player, "Your soul now resonates as a " .. race.DisplayName .. ".", "Success")
		else
			Notifier.Send(player, "You kept your current origin.", "Info")
		end
		DataService:MarkDirty(player)
		DataService:SaveNow(player)
	end
	return result
end

function RaceService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
	CharacterService = registry.CharacterService
end

function RaceService:Start()
	RemoteGuard.OnInvoke("RollRace", 2, 3, roll)
	RemoteGuard.OnInvoke("ResolveRaceRoll", 2, 3, resolve)
	DataService.ProfileLoaded:Connect(function(player, profile)
		syncAttributes(player, profile)
	end)
	DataService.ProfileReleasing:Connect(function(player)
		busy[player] = nil
		lastRollAt[player] = nil
	end)
end

return RaceService
