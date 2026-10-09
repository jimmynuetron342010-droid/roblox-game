--[[
	LoreCodex
	Separates what Soul Eater (Atsushi Ohkubo) establishes from what this game invents.
	Shown in the Race Index ("Lore" tab) so players can tell canon from gameplay interpretation.

	Canon     — established by the manga/anime (kept deliberately conservative).
	Game      — original gameplay interpretation used by this experience.
	System    — how the game models it (race, transformation, status, quest, enemy...).
]]

export type Entry = {
	Id: string,
	Title: string,
	System: string,
	Canon: { string },
	Game: { string },
}

local LoreCodex = {}

local entries: { Entry } = {
	-- ── Rollable origins ───────────────────────────────────────────────────────
	{
		Id = "Human",
		Title = "Humans",
		System = "Rollable origin (biological race)",
		Canon = {
			"Most students at the DWMA (Shibusen) are human Meisters.",
			"Soul Perception is a trained skill, not a racial trait; Maka is singled out for her skill at it.",
		},
		Game = {
			"Humans gain bonus XP, mastery and perception to reward versatility.",
			"Adaptive Focus is an original ability earned at mastery Stage II.",
		},
	},
	{
		Id = "DemonWeapon",
		Title = "Demon Weapons",
		System = "Rollable origin (human lineage with transformation)",
		Canon = {
			"Demon Weapons are humans who can transform their bodies into weapons.",
			"A Demon Weapon becomes a Death Scythe by consuming 99 Kishin Eggs and one witch's soul.",
			"Weapons fight alongside Meisters; matching soul wavelengths (Soul Resonance) multiplies their power.",
			"Partial transformation (e.g. a blade emerging from an arm) appears in the series.",
		},
		Game = {
			"Demon Weapon is an origin; Meister is a separate combat role. A Demon Weapon cannot take the Meister role.",
			"Weapon Resonance and Resonance Surge are original mechanics representing synchronization.",
			"Death Scythe is used only as a cosmetic Stage III title, not as a power level.",
		},
	},
	{
		Id = "Werewolf",
		Title = "Werewolves",
		System = "Rollable origin (biological race)",
		Canon = {
			"Free is an immortal werewolf who serves Medusa's faction and also uses magic.",
		},
		Game = {
			"Werewolf bonuses, Predator Instinct and Beast Shift are original mechanics.",
			"Player werewolves are not immortal and gain no witch magic.",
		},
	},
	{
		Id = "Witch",
		Title = "Witches",
		System = "Rollable origin (magic-born race)",
		Canon = {
			"Witches are magic users; their magic commonly carries an animal motif (Medusa's snakes, Eruka's frogs).",
			"Witches can hide their souls from Soul Perception (Soul Protect).",
			"Witch souls are normally driven toward destruction; Kim Diehl is notable for regenerative magic.",
			"Kim Diehl is both a witch and a Meister (partnered with Jacqueline), so witches can wield weapons.",
		},
		Game = {
			"Witch schools are inspired by canon witches; players learn a school and never become those characters.",
			"Soul Protect is modeled as being hidden from non-Shinigami Soul Perception.",
		},
	},
	{
		Id = "Zombie",
		Title = "Zombies",
		System = "Rollable origin (revived undead)",
		Canon = {
			"Sid Barrett, a DWMA teacher, is a zombie revived by Franken Stein.",
		},
		Game = {
			"Zombie is treated as an origin you awaken with, not a species you are born into.",
			"Undying Persistence and Gravebound Recovery are original mechanics.",
		},
	},
	{
		Id = "Mummy",
		Title = "Mummies",
		System = "Rollable origin (preserved undead)",
		Canon = {
			"Ancient preserved undead appear as enemies, such as the Pharaoh encountered by Black☆Star and Tsubaki.",
		},
		Game = {
			"Mummy as a playable origin, Ancient Wrappings and Binding Curse are original.",
			"The Pharaoh boss in this game is an original encounter inspired by that episode.",
		},
	},
	{
		Id = "Sorcerer",
		Title = "Sorcerers",
		System = "Rollable origin (scholarly tradition, not a species)",
		Canon = {
			"Eibon, one of the Great Old Ones, is described as a sorcerer who created many Demon Tools (including BREW).",
		},
		Game = {
			"Player sorcerers are human practitioners of an original sorcery tradition, not Eibon or his kin.",
			"Ember, Void and Artifice schools are original; Artifice is inspired by Eibon's Demon Tools.",
		},
	},
	{
		Id = "Shinigami",
		Title = "Shinigami",
		System = "Rollable origin (divine lineage) with mastery-gated power",
		Canon = {
			"Lord Death (Shinigami-sama) leads the DWMA; Death the Kid is his son.",
			"Kid's Lines of Sanzu connect as his power as a Shinigami matures.",
		},
		Game = {
			"Player Shinigami are an original lineage and start modest; mastery unlocks the Lines of Sanzu cosmetic and stronger Death's Authority variants.",
			"Divine Soul Perception revealing soul-protected enemies is an original mechanic.",
		},
	},
	{
		Id = "Golem",
		Title = "Golems",
		System = "Rollable origin (soul-bound construct)",
		Canon = {
			"The Oldest Golem near Loew Village was built about 800 years ago and is occupied by a soul.",
		},
		Game = {
			"A Golem origin is a soul bound to a crafted body — not a biological race.",
			"Living Fortress and Colossus Slam are original; its slow, visible wind-ups are its counterplay.",
		},
	},

	-- ── Not rollable: separate systems ────────────────────────────────────────
	{
		Id = "Kishin",
		Title = "Kishin",
		System = "Endgame questline + temporary transformation (never a roll)",
		Canon = {
			"A Kishin is born when a being devours innocent human souls; Asura was the first.",
			"Kishin Eggs are the souls of humans corrupted by eating innocent souls.",
			"Asura's madness is tied to fear.",
		},
		Game = {
			"Kishin Awakening is an original corruption state unlocked by the endgame questline and fueled by Madness.",
			"It drains your health and resets your Madness, so it is a risky burst, not a permanent form.",
		},
	},
	{
		Id = "BlackBlood",
		Title = "Black Blood",
		System = "Special progression / status system (not a race)",
		Canon = {
			"Black Blood was created by the witch Medusa; Crona and Ragnarok carry it.",
			"It can harden to block attacks and is associated with madness; Soul is infected during the series.",
		},
		Game = {
			"Black Blood is unlocked through a quest and grants a defensive hardening reaction at low health, at the cost of Madness.",
		},
	},
	{
		Id = "Madness",
		Title = "Madness Wavelengths",
		System = "Combat & encounter mechanic",
		Canon = {
			"Madness spreads through wavelengths; the Kishin's madness can infect others.",
		},
		Game = {
			"Madness Wraith enemies emit wavelengths that raise your Madness meter. High Madness raises damage dealt and taken.",
		},
	},
	{
		Id = "SoulResonance",
		Title = "Soul Wavelength Compatibility",
		System = "Partner synchronization mechanic",
		Canon = {
			"Meisters and weapons must match soul wavelengths to resonate; some pairs are incompatible.",
		},
		Game = {
			"Each student picks a wavelength type at creation. A Demon Weapon and a Meister can synchronize; compatibility scales the bonus.",
		},
	},
	{
		Id = "Meister",
		Title = "Meisters",
		System = "Combat role",
		Canon = {
			"Meisters wield Demon Weapons and are trained at the DWMA.",
		},
		Game = {
			"Meister is a role any non-weapon origin can pick. It improves weapon mastery and enables synchronization.",
		},
	},
}

LoreCodex.List = entries
LoreCodex.ById = {} :: { [string]: Entry }
for _, entry in entries do
	LoreCodex.ById[entry.Id] = entry
end

-- Lore notes for weapons whose names in the art references do not match canon wielders.
LoreCodex.WeaponNotes = {
	MakaScythe = "Canon: Maka Albarn wields Soul Eater Evans in scythe form.",
	SoulScythe = "Original variant inspired by Soul's scythe form; the bone-white shaft is a game design.",
	StarShuriken = "Canon: Tsubaki can take a shuriken form for Black☆Star.",
	SoulEaterBlade = "Original sword interpretation; Soul's canon weapon form is a scythe.",
	TsubakiForms = "Canon: Tsubaki's forms include a chain scythe (kusarigama), ninja sword and shuriken.",
	Ragnarok = "Canon: Ragnarok is Crona's Black Blood sword. This compact scythe form is a game interpretation.",
	TsunamiChain = "Original weapon. Crona's canon weapon is Ragnarok, not a chain.",
	GevurahChain = "Original weapon. Eruka Frog's canon magic uses frogs and tadpoles, not chains.",
	AsuraArm = "Original segmented arm weapon. Asura's canon weapon is Vajra; this is not Vajra.",
	TwinPistols = "Canon: Liz and Patty Thompson are twin pistols wielded by Death the Kid.",
	PattyDrill = "Original drill form; not a canon form of Patty.",
	ArachneSpider = "Original mechanical weapon inspired by Arachne's spider motif; Arachne is a witch, not a weapon.",
}

return LoreCodex
