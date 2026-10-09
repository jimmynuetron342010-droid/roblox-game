--[[
	GameEvents
	Server-internal gameplay event bus. Combat, abilities and quests fire events here; mastery,
	quests and progression listen. Keeps systems decoupled (e.g. CombatService never needs to know
	about mastery objectives).

	Events: EnemyKilled, BossKilled, WeaponHit, AbilityUsed, AbilityHit, StatusApplied, Healed,
	        DamageTaken, DamageDealt, UndyingTriggered, HiddenRevealed, QuestCompleted,
	        BlackBloodHardened, LevelUp, RaceChanged
]]

local Signal = require(game:GetService("ReplicatedStorage").Modules.Core.Signal)

local GameEvents = {}

GameEvents.Fired = Signal.new() -- (player, eventName, payload)

function GameEvents.Fire(player: Player, eventName: string, payload: { [string]: any }?)
	GameEvents.Fired:Fire(player, eventName, payload or {})
end

return GameEvents
