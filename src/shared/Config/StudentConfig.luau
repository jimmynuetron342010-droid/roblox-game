--[[
	StudentConfig
	Options for the "Create Your Student" screen. All choices are indices into these lists so the
	server can validate them trivially (the client never sends raw colors or names of assets).
]]

local StudentConfig = {}

StudentConfig.NameMinLength = 3
StudentConfig.NameMaxLength = 16
StudentConfig.NamePattern = "^[%a][%a%d _%-]*$"

StudentConfig.SkinTones = {
	Color3.fromRGB(255, 224, 196),
	Color3.fromRGB(241, 194, 158),
	Color3.fromRGB(224, 172, 128),
	Color3.fromRGB(198, 134, 94),
	Color3.fromRGB(150, 96, 62),
	Color3.fromRGB(102, 64, 42),
}

StudentConfig.HairColors = {
	{ Name = "Ash Blonde", Color = Color3.fromRGB(226, 205, 150) },
	{ Name = "Snow White", Color = Color3.fromRGB(235, 235, 240) },
	{ Name = "Raven", Color = Color3.fromRGB(28, 26, 32) },
	{ Name = "Ocean Blue", Color = Color3.fromRGB(56, 120, 210) },
	{ Name = "Crimson", Color = Color3.fromRGB(170, 30, 45) },
	{ Name = "Violet", Color = Color3.fromRGB(120, 70, 190) },
	{ Name = "Chestnut", Color = Color3.fromRGB(110, 66, 40) },
}

-- Part-built hairstyles (see Race/StudentAppearance). "Keep" uses the player's own avatar hair.
StudentConfig.HairStyles = { "Keep", "Spiked", "Pigtails", "Swept", "Crop" }

StudentConfig.Uniforms = {
	{
		Name = "My Avatar Outfit",
		Keep = true,
		Primary = Color3.fromRGB(60, 60, 70),
		Secondary = Color3.fromRGB(196, 40, 52),
	},
	{ Name = "DWMA Classic", Primary = Color3.fromRGB(40, 40, 52), Secondary = Color3.fromRGB(196, 40, 52) },
	{ Name = "Crescent Night", Primary = Color3.fromRGB(32, 28, 60), Secondary = Color3.fromRGB(240, 196, 60) },
	{ Name = "Bone White", Primary = Color3.fromRGB(220, 216, 206), Secondary = Color3.fromRGB(40, 40, 46) },
	{ Name = "Death City Red", Primary = Color3.fromRGB(120, 24, 34), Secondary = Color3.fromRGB(28, 26, 30) },
	{ Name = "Graveyard Green", Primary = Color3.fromRGB(38, 60, 48), Secondary = Color3.fromRGB(180, 200, 170) },
}

-- Soul wavelength types and pairwise compatibility (0..1). Used for Meister/Weapon synchronization.
StudentConfig.Wavelengths = {
	{ Id = "Calm", Description = "Steady and patient." },
	{ Id = "Fierce", Description = "Aggressive and loud." },
	{ Id = "Precise", Description = "Focused and exact." },
	{ Id = "Gentle", Description = "Kind and supportive." },
	{ Id = "Wild", Description = "Unpredictable and free." },
}

local compat = {
	Calm = { Calm = 0.85, Fierce = 0.6, Precise = 0.9, Gentle = 1.0, Wild = 0.55 },
	Fierce = { Calm = 0.6, Fierce = 0.8, Precise = 0.7, Gentle = 0.75, Wild = 0.95 },
	Precise = { Calm = 0.9, Fierce = 0.7, Precise = 0.85, Gentle = 0.8, Wild = 0.5 },
	Gentle = { Calm = 1.0, Fierce = 0.75, Precise = 0.8, Gentle = 0.85, Wild = 0.7 },
	Wild = { Calm = 0.55, Fierce = 0.95, Precise = 0.5, Gentle = 0.7, Wild = 0.8 },
}

function StudentConfig.Compatibility(a: string?, b: string?): number
	local row = a and compat[a]
	return (row and b and row[b]) or 0.5
end

function StudentConfig.IsWavelength(id: any): boolean
	return type(id) == "string" and compat[id] ~= nil
end

StudentConfig.StarterWeapons = { "MakaScythe", "SoulEaterBlade", "StarShuriken", "TwinPistols" }

return StudentConfig
