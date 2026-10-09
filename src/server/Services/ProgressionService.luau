--[[
	ProgressionService
	Character level, EXP and currency grants. EXP gain respects the XP Gain stat (capped by
	StatCalculator). Level-ups recompute stats and periodically grant a Race Roll so players earn
	rolls by playing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local GameConfig = require(Modules.Config.GameConfig)

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)

local ProgressionService = {}

local DataService
local StatService

local function syncAttributes(player: Player, profile)
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("Exp", profile.Exp)
	player:SetAttribute("ExpToNext", GameConfig.Level.ExpToNext(profile.Level))
end

function ProgressionService:AddExp(player: Player, amount: number, reason: string?)
	local profile = DataService:GetProfile(player)
	if not profile or amount <= 0 then
		return
	end
	local bonus = StatService:GetValues(player).XPGain or 0
	local gained = math.floor(amount * (1 + bonus) + 0.5)
	profile.Exp += gained
	local leveled = false
	while profile.Level < GameConfig.Level.Max and profile.Exp >= GameConfig.Level.ExpToNext(profile.Level) do
		profile.Exp -= GameConfig.Level.ExpToNext(profile.Level)
		profile.Level += 1
		leveled = true
		local text = string.format("Level up! You are now level %d.", profile.Level)
		if profile.Level % GameConfig.Level.RollRewardEvery == 0 then
			profile.Currency.RaceRolls += 1
			text ..= " +1 Race Roll"
		end
		Notifier.Send(player, text, "Reward")
		GameEvents.Fire(player, "LevelUp", { Level = profile.Level })
	end
	if profile.Level >= GameConfig.Level.Max then
		profile.Exp = math.min(profile.Exp, GameConfig.Level.ExpToNext(profile.Level))
	end
	syncAttributes(player, profile)
	if leveled then
		StatService:Recompute(player)
	end
	DataService:MarkDirty(player)
	return gained, reason
end

function ProgressionService:AddSouls(player: Player, amount: number)
	local profile = DataService:GetProfile(player)
	if not profile or amount <= 0 then
		return
	end
	profile.Currency.Souls += math.floor(amount)
	DataService:MarkDirty(player)
end

function ProgressionService:AddRolls(player: Player, amount: number)
	local profile = DataService:GetProfile(player)
	if not profile or amount <= 0 then
		return
	end
	profile.Currency.RaceRolls += math.floor(amount)
	DataService:MarkDirty(player)
end

function ProgressionService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
end

function ProgressionService:Start()
	DataService.ProfileLoaded:Connect(function(player, profile)
		syncAttributes(player, profile)
	end)
end

return ProgressionService
