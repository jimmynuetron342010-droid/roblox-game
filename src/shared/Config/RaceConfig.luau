--[[
	RaceConfig
	Rollable origins ("races") with their roll weights, base stat modifiers, passives and racial ability.

	IMPORTANT
	  * Weights are basis points (1/100 of a percent) and MUST sum to GameConfig.RaceRoll.TotalWeight
	    (10000 = 100%). A unit test enforces this. If you add a race, rebalance the whole table
	    explicitly — never silently change one entry.
	  * Every percentage below is an initial *tuning target*, not a balance guarantee. All values flow
	    through StatCalculator, which applies soft/hard caps.
	  * These are custom game-balance values, not official canon statistics. Canon notes live in
	    LoreCodex; `Classification` makes clear that not every origin is a biological species.

	Modifiers are Additive fractions (0.25 = +25%) unless Kind is given.
]]

local RarityConfig = require(script.Parent.RarityConfig)

export type RaceModifier = { Stat: string, Value: number, Kind: string? }

export type Race = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Weight: number,
	Classification: { Type: string, Label: string },
	Tagline: string,
	Purpose: string,
	Modifiers: { RaceModifier },
	Passive: { Id: string, Name: string, Description: string },
	AbilityId: string?,
	AbilityUnlockStage: number,
	Drawback: string?,
	Appearance: {
		AuraColor: Color3,
		EyeColor: Color3,
		SkinTint: Color3?,
		Features: { string },
	},
}

local RaceConfig = {}

local races: { Race } = {
	{
		Id = "Human",
		DisplayName = "Human",
		Rarity = "Common",
		Weight = 4000, -- 40%
		Classification = { Type = "Biological", Label = "Biological race" },
		Tagline = "Unbound potential.",
		Purpose = "Versatile progression race with no major weaknesses.",
		Modifiers = {
			{ Stat = "XPGain", Value = 0.10 },
			{ Stat = "SoulPerception", Value = 0.10 },
			{ Stat = "StaminaRegen", Value = 0.05 },
			{ Stat = "WeaponMasteryGain", Value = 0.05 }, -- Adaptive Potential
		},
		Passive = {
			Id = "AdaptivePotential",
			Name = "Adaptive Potential",
			Description = "Gain an additional 5% weapon mastery experience. Mastery stages add small bonuses across many stats instead of one.",
		},
		AbilityId = "AdaptiveFocus",
		AbilityUnlockStage = 2, -- Humans earn their ability through mastery
		Appearance = {
			AuraColor = Color3.fromRGB(200, 210, 230),
			EyeColor = Color3.fromRGB(70, 90, 120),
			Features = {},
		},
	},
	{
		Id = "DemonWeapon",
		DisplayName = "Demon Weapon",
		Rarity = "Uncommon",
		Weight = 2500, -- 25%
		Classification = { Type = "Hybrid", Label = "Human lineage with weapon transformation" },
		Tagline = "Your soul is a blade.",
		Purpose = "Weapon specialist that excels when synchronized with a Meister partner.",
		Modifiers = {
			{ Stat = "WeaponDamage", Value = 0.20 },
			{ Stat = "WeaponMasteryGain", Value = 0.15 },
			{ Stat = "AttackSpeed", Value = 0.10 },
		},
		Passive = {
			Id = "WeaponResonance",
			Name = "Weapon Resonance",
			Description = "While synchronized with a compatible Meister partner nearby, deal more damage and spend less Soul Energy. Compatibility depends on both souls' wavelengths.",
		},
		AbilityId = "ResonanceSurge",
		AbilityUnlockStage = 1,
		Appearance = {
			AuraColor = Color3.fromRGB(230, 60, 70),
			EyeColor = Color3.fromRGB(220, 40, 50),
			Features = { "BladeFin" },
		},
	},
	{
		Id = "Werewolf",
		DisplayName = "Werewolf",
		Rarity = "Rare",
		Weight = 1200, -- 12%
		Classification = { Type = "Biological", Label = "Biological race" },
		Tagline = "The hunt never ends.",
		Purpose = "Fast melee pressure with excellent chase potential.",
		Modifiers = {
			{ Stat = "MoveSpeed", Value = 0.25 },
			{ Stat = "MeleeDamage", Value = 0.20 },
			{ Stat = "AttackSpeed", Value = 0.15 },
			{ Stat = "DodgeDistance", Value = 0.10 },
		},
		Passive = {
			Id = "PredatorInstinct",
			Name = "Predator Instinct",
			Description = "Nearby enemies are tracked: wounded enemies inside your Soul Perception range are outlined.",
		},
		AbilityId = "BeastShift",
		AbilityUnlockStage = 1,
		Appearance = {
			AuraColor = Color3.fromRGB(150, 160, 175),
			EyeColor = Color3.fromRGB(255, 200, 60),
			Features = { "WolfEars", "Claws" },
		},
	},
	{
		Id = "Witch",
		DisplayName = "Witch",
		Rarity = "Rare",
		Weight = 1000, -- 10%
		Classification = { Type = "Biological", Label = "Biological race (magic-born)" },
		Tagline = "Magic is instinct.",
		Purpose = "Magic damage and control, gated by Soul Energy.",
		Modifiers = {
			{ Stat = "MagicDamage", Value = 0.30 },
			{ Stat = "SoulEnergyRegen", Value = 0.20 },
			{ Stat = "CooldownReduction", Value = 0.15 },
			{ Stat = "StatusEffectiveness", Value = 0.15 },
		},
		Passive = {
			Id = "ArcaneAffinity",
			Name = "Arcane Affinity",
			Description = "Enhanced control over witchcraft schools: your equipped school shapes Witchcraft. Your soul is hidden from normal Soul Perception (Soul Protect).",
		},
		AbilityId = "Witchcraft",
		AbilityUnlockStage = 1,
		Appearance = {
			AuraColor = Color3.fromRGB(170, 90, 255),
			EyeColor = Color3.fromRGB(190, 120, 255),
			Features = { "WitchHat" },
		},
	},
	{
		Id = "Zombie",
		DisplayName = "Zombie",
		Rarity = "Epic",
		Weight = 500, -- 5%
		Classification = { Type = "Undead", Label = "Revived undead (not born)" },
		Tagline = "Death was only a delay.",
		Purpose = "Sustain fighter that outlasts opponents.",
		Modifiers = {
			{ Stat = "MaxHealth", Value = 0.25 },
			{ Stat = "Defense", Value = 0.20 },
			{ Stat = "HealthRegen", Value = 0.15 },
			{ Stat = "PoisonResistance", Value = 0.20 },
		},
		Passive = {
			Id = "UndyingPersistence",
			Name = "Undying Persistence",
			Description = "Once every 180s, a lethal hit leaves you at 1 HP with 1.5s of protection — only if you were above 25% health before the hit.",
		},
		AbilityId = "GraveboundRecovery",
		AbilityUnlockStage = 1,
		Appearance = {
			AuraColor = Color3.fromRGB(120, 200, 120),
			EyeColor = Color3.fromRGB(180, 255, 140),
			SkinTint = Color3.fromRGB(150, 170, 150),
			Features = { "Stitches", "Bolt" },
		},
	},
	{
		Id = "Mummy",
		DisplayName = "Mummy",
		Rarity = "Epic",
		Weight = 300, -- 3%
		Classification = { Type = "Undead", Label = "Preserved undead (not born)" },
		Tagline = "Wrapped in ages.",
		Purpose = "Heavy defense and crowd control, traded for mobility.",
		Modifiers = {
			{ Stat = "Defense", Value = 0.30 },
			{ Stat = "MaxHealth", Value = 0.20 },
			{ Stat = "StatusResistance", Value = 0.25 },
			{ Stat = "SoulEnergyMax", Value = 0.15 },
			{ Stat = "RangedDamageReduction", Value = 0.15 }, -- Ancient Wrappings
			{ Stat = "MoveSpeed", Value = -0.10 }, -- counterbalance for the high defense
		},
		Passive = {
			Id = "AncientWrappings",
			Name = "Ancient Wrappings",
			Description = "Take 15% less damage from projectiles and gunfire.",
		},
		AbilityId = "BindingCurse",
		AbilityUnlockStage = 1,
		Drawback = "-10% movement speed",
		Appearance = {
			AuraColor = Color3.fromRGB(230, 200, 140),
			EyeColor = Color3.fromRGB(255, 220, 120),
			Features = { "Wrappings" },
		},
	},
	{
		Id = "Sorcerer",
		DisplayName = "Sorcerer",
		Rarity = "Legendary",
		Weight = 200, -- 2%
		Classification = { Type = "Tradition", Label = "Human practitioner of sorcery (a lineage, not a species)" },
		Tagline = "Knowledge made manifest.",
		Purpose = "Highest magic output with strict resource costs.",
		Modifiers = {
			{ Stat = "MagicDamage", Value = 0.35 },
			{ Stat = "SoulEnergyMax", Value = 0.25 },
			{ Stat = "CooldownReduction", Value = 0.20 },
			{ Stat = "SoulEnergyRegen", Value = 0.20 },
		},
		Passive = {
			Id = "ArcaneMastery",
			Name = "Arcane Mastery",
			Description = "Abilities cast within 3s of another ability cost 15% less Soul Energy (magical combos).",
		},
		AbilityId = "Sorcery",
		AbilityUnlockStage = 1,
		Appearance = {
			AuraColor = Color3.fromRGB(80, 200, 255),
			EyeColor = Color3.fromRGB(120, 220, 255),
			Features = { "Hood", "Runebook" },
		},
	},
	{
		Id = "Shinigami",
		DisplayName = "Shinigami",
		Rarity = "Mythic",
		Weight = 200, -- 2%
		Classification = { Type = "Divine", Label = "Death god lineage" },
		Tagline = "Order incarnate.",
		Purpose = "Durable soul specialist whose power grows through mastery, not at the start.",
		Modifiers = {
			{ Stat = "MaxHealth", Value = 0.25 },
			{ Stat = "Defense", Value = 0.25 },
			{ Stat = "SoulEnergyMax", Value = 0.25 },
			{ Stat = "SoulPerception", Value = 0.20 },
			{ Stat = "AbilityDamage", Value = 0.15 },
		},
		Passive = {
			Id = "DivineSoulPerception",
			Name = "Divine Soul Perception",
			Description = "Soul Perception reveals soul-protected enemies and hidden world secrets.",
		},
		AbilityId = "DeathsAuthority",
		AbilityUnlockStage = 1,
		Appearance = {
			AuraColor = Color3.fromRGB(245, 245, 255),
			EyeColor = Color3.fromRGB(255, 215, 90),
			Features = { "SanzuLines", "SkullRing" },
		},
	},
	{
		Id = "Golem",
		DisplayName = "Golem",
		Rarity = "Mythic",
		Weight = 100, -- 1%
		Classification = { Type = "Construct", Label = "Soul bound to a crafted body (not a biological race)" },
		Tagline = "An unbreakable vessel.",
		Purpose = "Immovable frontliner with slow, telegraphed power.",
		Modifiers = {
			{ Stat = "MaxHealth", Value = 0.50 },
			{ Stat = "Defense", Value = 0.35 },
			{ Stat = "KnockbackResistance", Value = 0.25 },
			{ Stat = "ChargedDamage", Value = 0.20 },
			{ Stat = "MoveSpeed", Value = -0.15 },
			{ Stat = "InterruptResistance", Value = 0.50 }, -- Living Fortress
		},
		Passive = {
			Id = "LivingFortress",
			Name = "Living Fortress",
			Description = "Incoming hits interrupt you for half as long.",
		},
		AbilityId = "ColossusSlam",
		AbilityUnlockStage = 1,
		Drawback = "-15% movement speed; slow, visible wind-ups",
		Appearance = {
			AuraColor = Color3.fromRGB(255, 150, 60),
			EyeColor = Color3.fromRGB(255, 170, 70),
			SkinTint = Color3.fromRGB(128, 120, 112),
			Features = { "StonePlates" },
		},
	},
}

RaceConfig.List = races
RaceConfig.ById = {} :: { [string]: Race }
for _, race in races do
	assert(RaceConfig.ById[race.Id] == nil, "duplicate race " .. race.Id)
	assert(RarityConfig.Tiers[race.Rarity], "bad rarity on " .. race.Id)
	RaceConfig.ById[race.Id] = race
end

-- Entries in the shape WeightedRoll expects.
RaceConfig.RollTable = {}
for _, race in races do
	table.insert(RaceConfig.RollTable, { Id = race.Id, Weight = race.Weight })
end

function RaceConfig.Get(id: string): Race?
	return RaceConfig.ById[id]
end

function RaceConfig.IsValid(id: any): boolean
	return type(id) == "string" and RaceConfig.ById[id] ~= nil
end

-- Converts race modifiers into StatCalculator modifiers.
function RaceConfig.StatModifiers(id: string): { any }
	local race = RaceConfig.ById[id]
	if not race then
		return {}
	end
	local out = {}
	for _, modifier in race.Modifiers do
		table.insert(out, {
			Stat = modifier.Stat,
			Kind = modifier.Kind or "Additive",
			Value = modifier.Value,
			Source = "Race:" .. id,
		})
	end
	return out
end

return RaceConfig
