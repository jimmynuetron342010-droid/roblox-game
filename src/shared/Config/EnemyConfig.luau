--[[
	EnemyConfig
	PvE enemies. Kishin Eggs are corrupted human souls (canon concept); their bodies, the Shrouded
	variant, Madness Wraiths and the Pharaoh fight are original encounter designs.
	Stats scale with the zone level so the same encounters remain relevant at multiple levels.
]]

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	MaxHealth: number,
	Defense: number,
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,
	WindUp: number,
	MoveSpeed: number,
	AggroRange: number,
	Exp: number,
	Souls: number,
	IsBoss: boolean,
	Hidden: boolean?,
	MadnessAura: { Radius: number, PerSecond: number, Type: string }?,
	Ranged: boolean?,
	Tags: { [string]: boolean },
	Colors: { Body: Color3, Accent: Color3, Eyes: Color3 },
	Scale: number,
}

local EnemyConfig = {}

local enemies: { EnemyDef } = {
	{
		Id = "KishinEgg",
		DisplayName = "Kishin Egg",
		MaxHealth = 140,
		Defense = 10,
		Damage = 12,
		AttackRange = 6,
		AttackCooldown = 1.8,
		WindUp = 0.45,
		MoveSpeed = 13,
		AggroRange = 55,
		Exp = 40,
		Souls = 12,
		IsBoss = false,
		Tags = { KishinEgg = true },
		Colors = { Body = Color3.fromRGB(30, 26, 36), Accent = Color3.fromRGB(80, 20, 30), Eyes = Color3.fromRGB(255, 40, 50) },
		Scale = 1,
	},
	{
		Id = "ShroudedKishinEgg",
		DisplayName = "Shrouded Kishin Egg",
		MaxHealth = 120,
		Defense = 8,
		Damage = 14,
		AttackRange = 6,
		AttackCooldown = 1.6,
		WindUp = 0.4,
		MoveSpeed = 14,
		AggroRange = 45,
		Exp = 60,
		Souls = 18,
		IsBoss = false,
		Hidden = true,
		Tags = { KishinEgg = true },
		Colors = { Body = Color3.fromRGB(40, 40, 60), Accent = Color3.fromRGB(70, 70, 110), Eyes = Color3.fromRGB(160, 160, 255) },
		Scale = 1,
	},
	{
		Id = "MadnessWraith",
		DisplayName = "Madness Wraith",
		MaxHealth = 220,
		Defense = 14,
		Damage = 16,
		AttackRange = 40,
		AttackCooldown = 2.4,
		WindUp = 0.6,
		MoveSpeed = 10,
		AggroRange = 60,
		Exp = 80,
		Souls = 25,
		IsBoss = false,
		Ranged = true,
		MadnessAura = { Radius = 22, PerSecond = 6, Type = "Fear" },
		Tags = { Madness = true },
		Colors = { Body = Color3.fromRGB(20, 10, 24), Accent = Color3.fromRGB(120, 30, 140), Eyes = Color3.fromRGB(255, 120, 255) },
		Scale = 1.15,
	},
	{
		Id = "Pharaoh",
		DisplayName = "The Pharaoh",
		MaxHealth = 4200,
		Defense = 45,
		Damage = 38,
		AttackRange = 9,
		AttackCooldown = 2.2,
		WindUp = 1.0,
		MoveSpeed = 12,
		AggroRange = 70,
		Exp = 900,
		Souls = 400,
		IsBoss = true,
		Tags = { Boss = true },
		Colors = { Body = Color3.fromRGB(214, 196, 150), Accent = Color3.fromRGB(40, 90, 160), Eyes = Color3.fromRGB(255, 210, 80) },
		Scale = 1.8,
	},
	{
		Id = "TrainingDummy",
		DisplayName = "Training Dummy",
		MaxHealth = 5000,
		Defense = 20,
		Damage = 0,
		AttackRange = 0,
		AttackCooldown = 999,
		WindUp = 0,
		MoveSpeed = 0,
		AggroRange = 0,
		Exp = 0,
		Souls = 0,
		IsBoss = false,
		Tags = { Dummy = true },
		Colors = { Body = Color3.fromRGB(160, 120, 80), Accent = Color3.fromRGB(200, 40, 50), Eyes = Color3.fromRGB(30, 30, 30) },
		Scale = 1,
	},
}

EnemyConfig.List = enemies
EnemyConfig.ById = {} :: { [string]: EnemyDef }
for _, enemy in enemies do
	EnemyConfig.ById[enemy.Id] = enemy
end

-- Zone level scaling for "PvE balance at multiple progression levels".
function EnemyConfig.Scale(def: EnemyDef, zoneLevel: number): { MaxHealth: number, Defense: number, Damage: number }
	local l = math.max(zoneLevel, 1)
	return {
		MaxHealth = math.floor(def.MaxHealth * (1 + (l - 1) * 0.09)),
		Defense = def.Defense + (l - 1) * 2,
		Damage = def.Damage * (1 + (l - 1) * 0.07),
	}
end

EnemyConfig.Respawn = 12
EnemyConfig.LeashRange = 90

return EnemyConfig
