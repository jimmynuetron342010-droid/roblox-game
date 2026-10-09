--[[
	MagicConfig
	Magic / technique specializations ("schools"). Only magic-capable origins can equip them:
	  * Witch    -> witchcraft schools (motifs inspired by canon witches; the player is never one of them)
	  * Sorcerer -> sorcery schools (original; framed as a scholarly tradition)
	A school decides what the racial Witchcraft / Sorcery ability actually casts.
]]

export type School = {
	Id: string,
	DisplayName: string,
	Group: "Witch" | "Sorcerer",
	SpellId: string,
	UnlockLevel: number,
	Description: string,
	Lore: string,
	Color: Color3,
}

local MagicConfig = {}

local schools: { School } = {
	{
		Id = "Vector",
		DisplayName = "Vector Magic",
		Group = "Witch",
		SpellId = "VectorArrows",
		UnlockLevel = 1,
		Description = "Arrow-shaped force projectiles that seek their target.",
		Lore = "Inspired by the canon witch Medusa's vector magic. Player witches learn a school; they are not Medusa.",
		Color = Color3.fromRGB(150, 90, 255),
	},
	{
		Id = "Frog",
		DisplayName = "Frog Magic",
		Group = "Witch",
		SpellId = "TadpoleBombs",
		UnlockLevel = 8,
		Description = "Explosive tadpole familiars that burst on impact.",
		Lore = "Inspired by the canon witch Eruka Frog's tadpole explosives.",
		Color = Color3.fromRGB(90, 200, 120),
	},
	{
		Id = "Restoration",
		DisplayName = "Restoration Magic",
		Group = "Witch",
		SpellId = "RestorationCircle",
		UnlockLevel = 15,
		Description = "Rare regenerative witchcraft that heals allies.",
		Lore = "Inspired by the canon witch Kim Diehl, whose magic is regenerative — unusual among witches.",
		Color = Color3.fromRGB(255, 170, 90),
	},
	{
		Id = "Ember",
		DisplayName = "Ember Sorcery",
		Group = "Sorcerer",
		SpellId = "EmberBurst",
		UnlockLevel = 1,
		Description = "Controlled flame that leaves lingering burns.",
		Lore = "Original school.",
		Color = Color3.fromRGB(255, 120, 50),
	},
	{
		Id = "Void",
		DisplayName = "Void Sorcery",
		Group = "Sorcerer",
		SpellId = "VoidWell",
		UnlockLevel = 8,
		Description = "Collapses space into a short-lived gravity well.",
		Lore = "Original school.",
		Color = Color3.fromRGB(120, 90, 220),
	},
	{
		Id = "Artifice",
		DisplayName = "Demon Tool Artifice",
		Group = "Sorcerer",
		SpellId = "ArtificeConstruct",
		UnlockLevel = 15,
		Description = "Assembles a temporary construct that fights beside you.",
		Lore = "Inspired by the canon sorcerer Eibon, maker of Demon Tools. The construct is an original mechanic.",
		Color = Color3.fromRGB(80, 200, 255),
	},
}

MagicConfig.List = schools
MagicConfig.ById = {} :: { [string]: School }
for _, school in schools do
	MagicConfig.ById[school.Id] = school
end

-- Which race unlocks which school group.
MagicConfig.RaceGroups = {
	Witch = "Witch",
	Sorcerer = "Sorcerer",
}

function MagicConfig.SchoolsForRace(raceId: string?): { School }
	local group = raceId and MagicConfig.RaceGroups[raceId]
	local out = {}
	if group then
		for _, school in schools do
			if school.Group == group then
				table.insert(out, school)
			end
		end
	end
	return out
end

function MagicConfig.DefaultSchool(raceId: string?): string?
	local list = MagicConfig.SchoolsForRace(raceId)
	return list[1] and list[1].Id or nil
end

return MagicConfig
