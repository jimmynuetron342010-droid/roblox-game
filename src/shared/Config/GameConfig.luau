--[[
	GameConfig
	Global tuning values. Everything gameplay-relevant that is not race/weapon specific lives here.
	Values are initial tuning targets, not final balance.
]]

local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

local GameConfig = {
	Version = "1.0.0",

	Data = {
		StoreName = "SoulEaterRPG_Profiles_v1",
		KeyPrefix = "Player_",
		AutosaveInterval = 60, -- seconds
		SessionLockStaleAfter = 150, -- seconds without a heartbeat before a lock may be stolen
		LoadRetries = 6,
		RetryDelay = 2,
		HistoryLimit = 50, -- race history entries kept per player
		RequestMemory = 32, -- processed request ids remembered for idempotency
	},

	RaceRoll = {
		TokenCost = 1, -- "Race Rolls" consumed per roll
		SoulsCost = 250, -- alternative payment in Souls currency
		Cooldown = 1.0, -- seconds between accepted roll requests (server clock)
		StartingRolls = 3,
		TotalWeight = 10000, -- weights are basis points; must sum to this
	},

	Level = {
		Max = 50,
		-- EXP needed to go from `level` to `level + 1`
		ExpToNext = function(level: number): number
			return math.floor(80 + level * 45)
		end,
		RollRewardEvery = 5, -- grant 1 Race Roll every N levels
	},

	Combat = {
		BaseStamina = 100,
		SprintMultiplier = 1.45,
		SprintStaminaPerSecond = 14,
		DashStaminaCost = 22,
		DashCooldown = 0.75,
		DashDistance = 18, -- scaled by DodgeDistance stat
		CombatTagDuration = 5, -- seconds after taking/dealing damage before out-of-combat regen
		StaggerDuration = 0.25,
		MaxAttackRequestRate = 12, -- requests per second hard limit (rate limiter)
		PvP = {
			-- "Zones": PvP only inside parts tagged as PvP arenas. "Off" disables PvP entirely.
			Mode = "Zones",
		},
		MeleeLeniency = 3.5, -- extra studs of reach tolerated for latency
	},

	SoulPerception = {
		BaseRange = 60,
		ToggleKey = Enum.KeyCode.G,
		SoulEnergyDrainPerSecond = 1.5,
	},

	Debug = {
		-- Only ever active inside Roblox Studio. Published servers ignore these.
		Enabled = IS_STUDIO,
		UnlockAllWeapons = IS_STUDIO,
		StartingRolls = 25,
		StartingSouls = 5000,
		StartingLevel = 15,
		UseMockDataStoreWhenUnavailable = true,
	},
}

return GameConfig
