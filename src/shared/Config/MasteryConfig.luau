--[[
	MasteryConfig
	Race mastery trees: Stage I Awakening -> Stage II Synchronization -> Stage III Transcendence.

	* Mastery is earned by *playing* the race (kills, ability use, quests, bosses) — never by buying
	  more rolls. Progress is stored per race, so switching race and later rolling it again restores
	  everything.
	* Stage bonuses are deliberately modest (2–5%). Transcendence is about new ability variants,
	  auras and prestige cosmetics rather than raw power.
	* Every objective is achievable solo.

	Objective fields:
	  Event  — gameplay event name fired by the server (see MasteryService.Events)
	  Count  — number of matching events required (or total Amount when `Amount` is set)
	  Match  — optional key/value pairs that the event payload must contain
	  Amount — optional payload field to sum instead of counting events
]]

export type Objective = {
	Id: string,
	Text: string,
	Event: string,
	Count: number,
	Match: { [string]: any }?,
	Amount: string?,
}

export type StageDef = {
	Stage: number,
	Name: string,
	XP: number,
	Objectives: { Objective },
	Modifiers: { { Stat: string, Value: number } },
	Unlocks: { string },
	Title: string?,
}

local MasteryConfig = {}

MasteryConfig.StageNames = { "Awakening", "Synchronization", "Transcendence" }
MasteryConfig.StageNumerals = { "I", "II", "III" }

-- Mastery XP awarded per event (multiplied by nothing — mastery cannot be bought or boosted).
MasteryConfig.XPRewards = {
	EnemyKilled = 25,
	BossKilled = 300,
	QuestCompleted = 150,
	AbilityHit = 4,
	WeaponHit = 1,
}

local STAGE2_XP = 1200
local STAGE3_XP = 5000

local function pharaoh(id: string): Objective
	return { Id = id, Text = "Defeat the Pharaoh in the Tomb", Event = "BossKilled", Count = 1 }
end

local trees: { [string]: { StageDef } } = {
	Human = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Adaptive Potential passive", "Student soul aura" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{ Id = "H2a", Text = "Defeat 40 enemies", Event = "EnemyKilled", Count = 40 },
				{ Id = "H2b", Text = "Land 150 weapon hits", Event = "WeaponHit", Count = 150 },
			},
			Modifiers = { { Stat = "WeaponMasteryGain", Value = 0.05 }, { Stat = "StaminaRegen", Value = 0.05 } },
			Unlocks = { "Ability: Adaptive Focus (C)", "Brighter soul aura" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{ Id = "H3a", Text = "Defeat 150 enemies", Event = "EnemyKilled", Count = 150 },
				pharaoh("H3b"),
			},
			-- Versatility: small bonuses across many stats instead of one big one.
			Modifiers = {
				{ Stat = "XPGain", Value = 0.05 },
				{ Stat = "WeaponDamage", Value = 0.04 },
				{ Stat = "MagicDamage", Value = 0.04 },
				{ Stat = "MaxHealth", Value = 0.04 },
				{ Stat = "Defense", Value = 0.04 },
			},
			Unlocks = { "Ability variant: Indomitable Focus", "Unique aura: Unbound Soul", "Prestige title" },
			Title = "Unbound Soul",
		},
	},
	DemonWeapon = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Weapon Resonance passive", "Resonance Surge (C)", "Crimson edge aura" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "D2a",
					Text = "Activate Resonance Surge 8 times",
					Event = "AbilityUsed",
					Count = 8,
					Match = { AbilityId = "ResonanceSurge" },
				},
				{
					Id = "D2b",
					Text = "Land 100 weapon hits during Resonance Surge",
					Event = "WeaponHit",
					Count = 100,
					Match = { Surge = true },
				},
			},
			Modifiers = { { Stat = "WeaponDamage", Value = 0.03 } },
			Unlocks = { "Resonance Surge lasts longer, meter fills faster", "Sharper blade VFX" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "D3a",
					Text = "Defeat 25 enemies while synchronized or surging",
					Event = "EnemyKilled",
					Count = 25,
					Match = { Empowered = true },
				},
				pharaoh("D3b"),
			},
			Modifiers = { { Stat = "WeaponDamage", Value = 0.03 }, { Stat = "AttackSpeed", Value = 0.03 } },
			Unlocks = { "Ability variant: Death Scythe Surge", "Unique aura: Scythe Wavelength", "Prestige title" },
			Title = "Death Scythe Candidate",
		},
	},
	Werewolf = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Predator Instinct passive", "Beast Shift (C)", "Wolf ears and claws" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "W2a",
					Text = "Activate Beast Shift 8 times",
					Event = "AbilityUsed",
					Count = 8,
					Match = { AbilityId = "BeastShift" },
				},
				{
					Id = "W2b",
					Text = "Land 120 melee hits",
					Event = "WeaponHit",
					Count = 120,
					Match = { Melee = true },
				},
			},
			Modifiers = { { Stat = "MeleeDamage", Value = 0.03 } },
			Unlocks = { "Beast Shift lifesteal", "Moonlit eye glow" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "W3a",
					Text = "Defeat 30 enemies during Beast Shift",
					Event = "EnemyKilled",
					Count = 30,
					Match = { Buff = "BeastShift" },
				},
				pharaoh("W3b"),
			},
			Modifiers = { { Stat = "MoveSpeed", Value = 0.02 }, { Stat = "MeleeDamage", Value = 0.03 } },
			Unlocks = { "Ability variant: Moonlit Frenzy", "Unique aura: Silver Hunt", "Prestige title" },
			Title = "Alpha of the Night",
		},
	},
	Witch = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Arcane Affinity passive", "Witchcraft (C)", "Witch hat" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "X2a",
					Text = "Cast Witchcraft 25 times",
					Event = "AbilityUsed",
					Count = 25,
					Match = { AbilityId = "Witchcraft" },
				},
				{ Id = "X2b", Text = "Apply 20 status effects", Event = "StatusApplied", Count = 20 },
			},
			Modifiers = { { Stat = "MagicDamage", Value = 0.03 } },
			Unlocks = { "Witchcraft costs less", "Familiar sparks VFX" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "X3a",
					Text = "Defeat 40 enemies with magic",
					Event = "EnemyKilled",
					Count = 40,
					Match = { Magic = true },
				},
				pharaoh("X3b"),
			},
			Modifiers = { { Stat = "MagicDamage", Value = 0.03 }, { Stat = "SoulEnergyRegen", Value = 0.05 } },
			Unlocks = { "Ability variant: High Witchcraft", "Unique aura: Coven Glow", "Prestige title" },
			Title = "Coven Luminary",
		},
	},
	Zombie = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Undying Persistence passive", "Gravebound Recovery (C)", "Stitches" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{ Id = "Z2a", Text = "Recover 3,000 health", Event = "Healed", Count = 3000, Amount = "Amount" },
				{ Id = "Z2b", Text = "Trigger Undying Persistence 2 times", Event = "UndyingTriggered", Count = 2 },
			},
			Modifiers = { { Stat = "HealthRegen", Value = 0.05 } },
			Unlocks = { "Gravebound Recovery cleanses poison", "Grave mist VFX" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{ Id = "Z3a", Text = "Take 15,000 damage", Event = "DamageTaken", Count = 15000, Amount = "Amount" },
				pharaoh("Z3b"),
			},
			Modifiers = { { Stat = "MaxHealth", Value = 0.04 }, { Stat = "PoisonResistance", Value = 0.05 } },
			Unlocks = { "Ability variant: Grave Rise", "Unique aura: Restless Grave", "Prestige title" },
			Title = "The Unburied",
		},
	},
	Mummy = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Ancient Wrappings passive", "Binding Curse (C)", "Wrappings" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "M2a",
					Text = "Bind 20 enemies with Binding Curse",
					Event = "StatusApplied",
					Count = 20,
					Match = { Source = "BindingCurse" },
				},
				{
					Id = "M2b",
					Text = "Take 2,000 ranged damage",
					Event = "DamageTaken",
					Count = 2000,
					Amount = "Amount",
					Match = { Ranged = true },
				},
			},
			Modifiers = { { Stat = "StatusResistance", Value = 0.03 } },
			Unlocks = { "Binding Curse shreds Defense", "Drifting sand VFX" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "M3a",
					Text = "Bind 60 enemies with Binding Curse",
					Event = "StatusApplied",
					Count = 60,
					Match = { Source = "BindingCurse" },
				},
				pharaoh("M3b"),
			},
			Modifiers = { { Stat = "Defense", Value = 0.04 }, { Stat = "MoveSpeed", Value = 0.03 } },
			Unlocks = { "Ability variant: Pharaoh's Binding", "Unique aura: Tomb Dust", "Prestige title" },
			Title = "Keeper of the Tomb",
		},
	},
	Sorcerer = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Arcane Mastery passive", "Sorcery Specialization (C)", "Hood" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "S2a",
					Text = "Cast Sorcery 30 times",
					Event = "AbilityUsed",
					Count = 30,
					Match = { AbilityId = "Sorcery" },
				},
				{
					Id = "S2b",
					Text = "Deal 8,000 magic damage",
					Event = "DamageDealt",
					Count = 8000,
					Amount = "Amount",
					Match = { Magic = true },
				},
			},
			Modifiers = { { Stat = "SoulEnergyMax", Value = 0.05 } },
			Unlocks = { "Sorcery 10% stronger", "Orbiting glyph-free sparks VFX" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "S3a",
					Text = "Deal 30,000 magic damage",
					Event = "DamageDealt",
					Count = 30000,
					Amount = "Amount",
					Match = { Magic = true },
				},
				pharaoh("S3b"),
			},
			Modifiers = { { Stat = "MagicDamage", Value = 0.03 }, { Stat = "CooldownReduction", Value = 0.02 } },
			Unlocks = { "Ability variant: Grand Sorcery", "Unique aura: Archive Light", "Prestige title" },
			Title = "Archsorcerer",
		},
	},
	Shinigami = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Divine Soul Perception passive", "Death's Authority (C)", "Faint white aura" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "G2a",
					Text = "Reveal 10 hidden souls with Soul Perception",
					Event = "HiddenRevealed",
					Count = 10,
				},
				{
					Id = "G2b",
					Text = "Hit 25 enemies with Death's Authority",
					Event = "AbilityHit",
					Count = 25,
					Match = { AbilityId = "DeathsAuthority" },
				},
			},
			Modifiers = { { Stat = "AbilityDamage", Value = 0.03 } },
			Unlocks = { "Death's Authority judges targets", "First Line of Sanzu (cosmetic)" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "G3a",
					Text = "Defeat 10 Shrouded Kishin Eggs",
					Event = "EnemyKilled",
					Count = 10,
					Match = { EnemyType = "ShroudedKishinEgg" },
				},
				pharaoh("G3b"),
			},
			Modifiers = { { Stat = "AbilityDamage", Value = 0.03 }, { Stat = "SoulEnergyMax", Value = 0.05 } },
			Unlocks = { "Ability variant: Lines of Sanzu", "Unique aura: Absolute Order", "Prestige title" },
			Title = "Reaper of Order",
		},
	},
	Golem = {
		{
			Stage = 1,
			Name = "Awakening",
			XP = 0,
			Objectives = {},
			Modifiers = {},
			Unlocks = { "Living Fortress passive", "Colossus Slam (C)", "Stone plating" },
		},
		{
			Stage = 2,
			Name = "Synchronization",
			XP = STAGE2_XP,
			Objectives = {
				{
					Id = "O2a",
					Text = "Hit 30 enemies with Colossus Slam",
					Event = "AbilityHit",
					Count = 30,
					Match = { AbilityId = "ColossusSlam" },
				},
				{ Id = "O2b", Text = "Absorb 5,000 damage", Event = "DamageTaken", Count = 5000, Amount = "Amount" },
			},
			Modifiers = { { Stat = "ChargedDamage", Value = 0.03 } },
			Unlocks = { "Faster Colossus Slam wind-up", "Glowing core VFX" },
		},
		{
			Stage = 3,
			Name = "Transcendence",
			XP = STAGE3_XP,
			Objectives = {
				{
					Id = "O3a",
					Text = "Hit 100 enemies with Colossus Slam",
					Event = "AbilityHit",
					Count = 100,
					Match = { AbilityId = "ColossusSlam" },
				},
				pharaoh("O3b"),
			},
			Modifiers = {
				{ Stat = "KnockbackResistance", Value = 0.05 },
				{ Stat = "ChargedDamage", Value = 0.03 },
				{ Stat = "MoveSpeed", Value = 0.03 },
			},
			Unlocks = { "Ability variant: Titan's Wake", "Unique aura: Furnace Heart", "Prestige title" },
			Title = "Living Citadel",
		},
	},
}

MasteryConfig.Trees = trees
MasteryConfig.MaxStage = 3

function MasteryConfig.Tree(raceId: string): { StageDef }?
	return trees[raceId]
end

function MasteryConfig.StageDef(raceId: string, stage: number): StageDef?
	local tree = trees[raceId]
	return tree and tree[stage] or nil
end

-- Additive stat modifiers granted by all stages up to `stage`.
function MasteryConfig.StatModifiers(raceId: string, stage: number): { any }
	local out = {}
	local tree = trees[raceId]
	if not tree then
		return out
	end
	for s = 1, math.min(stage, MasteryConfig.MaxStage) do
		for _, modifier in tree[s].Modifiers do
			table.insert(out, {
				Stat = modifier.Stat,
				Kind = "Additive",
				Value = modifier.Value,
				Source = "Mastery:" .. raceId .. ":" .. MasteryConfig.StageNumerals[s],
			})
		end
	end
	return out
end

-- Does an event payload satisfy an objective's Match table?
function MasteryConfig.Matches(objective: Objective, payload: { [string]: any }?): boolean
	if not objective.Match then
		return true
	end
	if not payload then
		return false
	end
	for key, expected in objective.Match do
		if payload[key] ~= expected then
			return false
		end
	end
	return true
end

return MasteryConfig
