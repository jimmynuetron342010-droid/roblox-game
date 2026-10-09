--[[
	QuestConfig
	Main questline plus the endgame Kishin / Black Blood questline.
	Quests advance automatically from server gameplay events (same events as mastery objectives).
]]

export type Quest = {
	Id: string,
	Title: string,
	Description: string,
	Event: string,
	Count: number,
	Match: { [string]: any }?,
	RequiresLevel: number?,
	Next: string?,
	Rewards: { Exp: number?, Souls: number?, RaceRolls: number?, Unlock: string? },
	Chain: string,
}

local QuestConfig = {}

local quests: { Quest } = {
	{
		Id = "Q1_FirstSouls",
		Chain = "Main",
		Title = "Defeat 5 Souls",
		Description = "Kishin Eggs prowl the graveyard district. Defeat 5 of them and collect their souls.",
		Event = "EnemyKilled",
		Count = 5,
		Match = { KishinEgg = true },
		Next = "Q2_Training",
		Rewards = { Exp = 250, Souls = 150, RaceRolls = 1 },
	},
	{
		Id = "Q2_Training",
		Chain = "Main",
		Title = "Weapon Drills",
		Description = "Land 40 weapon hits (training dummies count).",
		Event = "WeaponHit",
		Count = 40,
		Next = "Q3_Shrouded",
		Rewards = { Exp = 350, Souls = 200 },
	},
	{
		Id = "Q3_Shrouded",
		Chain = "Main",
		Title = "Hidden Souls",
		Description = "Some Kishin Eggs hide their souls. Use Soul Perception (G) and defeat 3 Shrouded Kishin Eggs.",
		Event = "EnemyKilled",
		Count = 3,
		Match = { EnemyType = "ShroudedKishinEgg" },
		Next = "Q4_Pharaoh",
		Rewards = { Exp = 500, Souls = 300, RaceRolls = 1 },
	},
	{
		Id = "Q4_Pharaoh",
		Chain = "Main",
		Title = "The Pharaoh's Tomb",
		Description = "Enter the tomb and defeat the Pharaoh. Watch his telegraphed slams.",
		Event = "BossKilled",
		Count = 1,
		Next = "K1_Whispers",
		Rewards = { Exp = 1200, Souls = 1000, RaceRolls = 2 },
	},
	{
		Id = "K1_Whispers",
		Chain = "Kishin",
		Title = "Whispers of Madness",
		Description = "Stand in the wavelengths of Madness Wraiths until your Madness peaks, then defeat 5 of them.",
		Event = "EnemyKilled",
		Count = 5,
		Match = { EnemyType = "MadnessWraith" },
		RequiresLevel = 20,
		Next = "K2_BlackBlood",
		Rewards = { Exp = 1500, Souls = 600, Unlock = "BlackBlood" },
	},
	{
		Id = "K2_BlackBlood",
		Chain = "Kishin",
		Title = "Black Blood",
		Description = "Let the Black Blood harden in battle 5 times.",
		Event = "BlackBloodHardened",
		Count = 5,
		RequiresLevel = 25,
		Next = "K3_KishinPath",
		Rewards = { Exp = 2000, Souls = 800 },
	},
	{
		Id = "K3_KishinPath",
		Chain = "Kishin",
		Title = "The Kishin's Path",
		Description = "Defeat the Pharaoh while your Madness is above 50.",
		Event = "BossKilled",
		Count = 1,
		Match = { MadnessHigh = true },
		RequiresLevel = 30,
		Rewards = { Exp = 4000, Souls = 1500, RaceRolls = 1, Unlock = "KishinAwakening" },
	},
}

QuestConfig.List = quests
QuestConfig.ById = {} :: { [string]: Quest }
for _, quest in quests do
	QuestConfig.ById[quest.Id] = quest
end
QuestConfig.FirstQuest = "Q1_FirstSouls"

function QuestConfig.Matches(quest: Quest, payload: { [string]: any }?): boolean
	if not quest.Match then
		return true
	end
	if not payload then
		return false
	end
	for key, expected in quest.Match do
		if payload[key] ~= expected then
			return false
		end
	end
	return true
end

return QuestConfig
