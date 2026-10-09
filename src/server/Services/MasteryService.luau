--[[
	MasteryService
	Advances race mastery from gameplay events (GameEvents). Only the *active* race earns mastery,
	and only objectives of the *next* stage are tracked, so progress is always legible.

	Stage-ups require BOTH the stage's mastery XP and all of its objectives. Rewards are modest stat
	bonuses (MasteryConfig), ability variants (AbilityConfig.Stages), auras and prestige titles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local MasteryConfig = require(Modules.Config.MasteryConfig)
local RaceConfig = require(Modules.Config.RaceConfig)

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)
local FXBroadcast = require(Server.Core.FXBroadcast)
local ProfileCore = require(Server.Data.ProfileCore)

local MasteryService = {}

local DataService
local StatService
local RaceService
local CharacterService

-- Pure step used by the service and the tests. Returns true if the stage advanced.
function MasteryService.ApplyEvent(progress, raceId: string, eventName: string, payload): (boolean, boolean)
	local changed = false
	local reward = MasteryConfig.XPRewards[eventName]
	if reward then
		progress.XP += reward
		changed = true
	end
	local nextStage = MasteryConfig.StageDef(raceId, progress.Stage + 1)
	if not nextStage then
		return changed, false
	end
	for _, objective in nextStage.Objectives do
		if objective.Event == eventName and MasteryConfig.Matches(objective, payload) then
			local current = progress.Objectives[objective.Id] or 0
			if current < objective.Count then
				local add = 1
				if objective.Amount then
					add = tonumber(payload[objective.Amount]) or 0
				end
				progress.Objectives[objective.Id] = math.min(objective.Count, current + add)
				changed = true
			end
		end
	end
	return changed, MasteryService.TryAdvance(progress, raceId)
end

function MasteryService.TryAdvance(progress, raceId: string): boolean
	local nextStage = MasteryConfig.StageDef(raceId, progress.Stage + 1)
	if not nextStage or progress.XP < nextStage.XP then
		return false
	end
	for _, objective in nextStage.Objectives do
		if (progress.Objectives[objective.Id] or 0) < objective.Count then
			return false
		end
	end
	progress.Stage += 1
	return true
end

local function onEvent(player: Player, eventName: string, payload)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	local raceId = profile.Race.Active
	if raceId == "" or not RaceConfig.ById[raceId] then
		return
	end
	local progress = ProfileCore.EnsureRaceProgress(profile, raceId)
	local changed, advanced = MasteryService.ApplyEvent(progress, raceId, eventName, payload)
	if advanced then
		local stage = MasteryConfig.StageDef(raceId, progress.Stage)
		Notifier.Send(
			player,
			string.format("%s Mastery %s — %s!", RaceConfig.ById[raceId].DisplayName, MasteryConfig.StageNumerals[progress.Stage], stage.Name),
			"Rare",
			{ Rarity = RaceConfig.ById[raceId].Rarity }
		)
		RaceService:SyncAttributes(player)
		StatService:Recompute(player)
		CharacterService:ApplyAppearance(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			FXBroadcast.Broadcast({ Type = "MasteryUp", Character = character, Race = raceId, Stage = progress.Stage }, root.Position)
		end
	end
	if changed then
		DataService:MarkDirty(player)
	end
end

function MasteryService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
	RaceService = registry.RaceService
	CharacterService = registry.CharacterService
end

function MasteryService:Start()
	GameEvents.Fired:Connect(onEvent)
end

return MasteryService
