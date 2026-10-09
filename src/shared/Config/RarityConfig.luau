--[[
	RarityConfig
	Visual identity and reveal pacing for each rarity tier.
	Colors were chosen for readable contrast on the game's dark UI (all >= 4.5:1 against #141019).
]]

export type Rarity = {
	Id: string,
	DisplayName: string,
	Order: number,
	Color: Color3,
	AccentColor: Color3,
	-- Seconds of build-up before the result is shown (full animation). Fast reveal skips most of it.
	RevealBuildUp: number,
	ParticleBurst: number,
	ScreenFlash: boolean,
	SoundKey: string,
}

local RarityConfig = {}

RarityConfig.Tiers = {
	Common = {
		Id = "Common",
		DisplayName = "Common",
		Order = 1,
		Color = Color3.fromRGB(190, 198, 210),
		AccentColor = Color3.fromRGB(120, 128, 142),
		RevealBuildUp = 1.6,
		ParticleBurst = 18,
		ScreenFlash = false,
		SoundKey = "RevealCommon",
	},
	Uncommon = {
		Id = "Uncommon",
		DisplayName = "Uncommon",
		Order = 2,
		Color = Color3.fromRGB(94, 226, 138),
		AccentColor = Color3.fromRGB(34, 140, 78),
		RevealBuildUp = 1.9,
		ParticleBurst = 26,
		ScreenFlash = false,
		SoundKey = "RevealUncommon",
	},
	Rare = {
		Id = "Rare",
		DisplayName = "Rare",
		Order = 3,
		Color = Color3.fromRGB(86, 156, 255),
		AccentColor = Color3.fromRGB(30, 82, 190),
		RevealBuildUp = 2.3,
		ParticleBurst = 36,
		ScreenFlash = false,
		SoundKey = "RevealRare",
	},
	Epic = {
		Id = "Epic",
		DisplayName = "Epic",
		Order = 4,
		Color = Color3.fromRGB(190, 120, 255),
		AccentColor = Color3.fromRGB(112, 46, 196),
		RevealBuildUp = 2.8,
		ParticleBurst = 48,
		ScreenFlash = true,
		SoundKey = "RevealEpic",
	},
	Legendary = {
		Id = "Legendary",
		DisplayName = "Legendary",
		Order = 5,
		Color = Color3.fromRGB(255, 194, 64),
		AccentColor = Color3.fromRGB(196, 120, 10),
		RevealBuildUp = 3.3,
		ParticleBurst = 64,
		ScreenFlash = true,
		SoundKey = "RevealLegendary",
	},
	Mythic = {
		Id = "Mythic",
		DisplayName = "Mythic",
		Order = 6,
		Color = Color3.fromRGB(255, 82, 96),
		AccentColor = Color3.fromRGB(150, 16, 40),
		RevealBuildUp = 3.8,
		ParticleBurst = 84,
		ScreenFlash = true,
		SoundKey = "RevealMythic",
	},
} :: { [string]: Rarity }

-- Ordered list (lowest to highest) for UI iteration.
RarityConfig.Ordered = {} :: { Rarity }
for _, tier in RarityConfig.Tiers do
	table.insert(RarityConfig.Ordered, tier)
end
table.sort(RarityConfig.Ordered, function(a, b)
	return a.Order < b.Order
end)

function RarityConfig.Get(id: string): Rarity
	local tier = RarityConfig.Tiers[id]
	assert(tier, "Unknown rarity " .. tostring(id))
	return tier
end

return RarityConfig
