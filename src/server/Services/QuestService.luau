--[[
	QuestService
	Linear quest chains driven by the same gameplay events as mastery. Rewards include EXP, Souls,
	Race Rolls (earned, never bought) and unlocks for the endgame systems (Black Blood, Kishin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local QuestConfig = require(Modules.Config.QuestConfig)

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)

local QuestService = {}

local DataService
local ProgressionService

local function syncAttributes(player: Player, profile)
	local quest = QuestConfig.ById[profile.Quests.Active]
	player:SetAttribute("QuestId", quest and quest.Id or "")
	player:SetAttribute("QuestProgress", profile.Quests.Progress)
end

-- Pure step for tests: returns the completed quest (if any).
function QuestService.ApplyEvent(profile, eventName: string, payload)
	local quest = QuestConfig.ById[profile.Quests.Active]
	if not quest or quest.Event ~= eventName then
		return nil
	end
	if quest.RequiresLevel and profile.Level < quest.RequiresLevel then
		return nil
	end
	if not QuestConfig.Matches(quest, payload) then
		return nil
	end
	profile.Quests.Progress += 1
	if profile.Quests.Progress < quest.Count then
		return nil
	end
	profile.Quests.Completed[quest.Id] = os.time()
	profile.Quests.Active = quest.Next or ""
	profile.Quests.Progress = 0
	return quest
end

local function grant(player: Player, profile, quest)
	local rewards = quest.Rewards
	local parts = {}
	if rewards.Exp then
		ProgressionService:AddExp(player, rewards.Exp, "Quest")
		table.insert(parts, rewards.Exp .. " EXP")
	end
	if rewards.Souls then
		ProgressionService:AddSouls(player, rewards.Souls)
		table.insert(parts, rewards.Souls .. " Souls")
	end
	if rewards.RaceRolls then
		ProgressionService:AddRolls(player, rewards.RaceRolls)
		table.insert(parts, rewards.RaceRolls .. " Race Roll" .. (rewards.RaceRolls > 1 and "s" or ""))
	end
	if rewards.Unlock and profile.Unlocks[rewards.Unlock] ~= nil then
		profile.Unlocks[rewards.Unlock] = true
		table.insert(parts, "Unlocked " .. rewards.Unlock)
	end
	Notifier.Send(player, string.format("Quest complete: %s (%s)", quest.Title, table.concat(parts, ", ")), "Reward")
end

local function onEvent(player: Player, eventName: string, payload)
	if eventName == "QuestCompleted" then
		return
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	local before = profile.Quests.Progress
	local completed = QuestService.ApplyEvent(profile, eventName, payload)
	if completed then
		grant(player, profile, completed)
		GameEvents.Fire(player, "QuestCompleted", { QuestId = completed.Id })
	end
	if completed or before ~= profile.Quests.Progress then
		syncAttributes(player, profile)
		DataService:MarkDirty(player)
	end
end

function QuestService:Init(registry)
	DataService = registry.DataService
	ProgressionService = registry.ProgressionService
end

function QuestService:Start()
	GameEvents.Fired:Connect(onEvent)
	DataService.ProfileLoaded:Connect(syncAttributes)
end

return QuestService
