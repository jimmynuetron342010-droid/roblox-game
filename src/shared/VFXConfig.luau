--[[
	VFXConfig
	Central tuning for the 10 reusable attack effects, impacts, camera shake and quality tiers.
	Effects are physical (sparks, dust, smoke, debris, muzzle flashes, air trails, shockwave rings);
	there are no runes, glyphs or energy beams on ordinary weapon attacks.

	TEXTURES: built-in Roblox particle textures are used by default. To use your own, put a
	ParticleEmitter named like the template ("Spark", "Dust", "Smoke", ...) into
	ReplicatedStorage.VFXAssets — the controller clones it instead (keeps your texture/colors).
	SOUNDS: placeholders ("rbxassetid://0") never play. Replace with assets you own.
]]

local VFXConfig = {}

local PH = "rbxassetid://0"

VFXConfig.Textures = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

-- Quality tiers. "Auto" picks one from device + Roblox graphics level.
VFXConfig.Quality = {
	Low = { Particles = 0.4, Debris = 0, Afterimages = 0, Lights = false, RingSegments = 10, ShakeScale = 0.6 },
	Medium = { Particles = 0.7, Debris = 4, Afterimages = 2, Lights = true, RingSegments = 14, ShakeScale = 0.85 },
	High = { Particles = 1.0, Debris = 8, Afterimages = 3, Lights = true, RingSegments = 18, ShakeScale = 1 },
}

-- Per-effect defaults. Any field can be overridden per attack via WeaponConfig Attack.VFX.Params.
VFXConfig.Effects = {
	BasicSlash = {
		Enabled = true,
		GlintSize = 1.1,
		GlintLifetime = 0.12,
		AirStreaks = 3,
		Sound = PH,
	},
	HeavySlash = {
		Enabled = true,
		TrailWidthScale = 1.6,
		TrailLifetime = 0.24,
		GlintSize = 1.6,
		DustCount = 14,
		DebrisCount = 5,
		FlashBrightness = 3,
		FlashRange = 10,
		Shake = 0.35,
		Sound = PH,
	},
	MultiHitCombo = {
		Enabled = true,
		TrailLifetime = 0.09, -- short so successive slashes never pile up on screen
		PuffCount = 6,
		Sound = PH,
	},
	ChainSwing = {
		Enabled = true,
		WhipImpulse = 140,
		AirStreaks = 4,
		TrailLifetime = 0.18,
		Sound = PH,
	},
	GroundSlam = {
		Enabled = true,
		Radius = 12,
		RingLifetime = 0.42,
		RingThickness = 0.35,
		DustCount = 26,
		DebrisCount = 8,
		DebrisSpeed = 34,
		Shake = 0.7,
		ShakeRange = 70,
		Sound = PH,
	},
	ShurikenThrow = {
		Enabled = true,
		TrailLifetime = 0.16,
		TrailWidth = 0.35,
		Streaks = 4,
		Sound = PH,
	},
	GunShot = {
		Enabled = true,
		FlashLifetime = 0.05,
		LightBrightness = 4,
		LightRange = 9,
		SmokeLifetime = 0.9,
		TracerLifetime = 0.08,
		ShellCasings = true,
		Sound = PH,
	},
	DrillAttack = {
		Enabled = true,
		SparkRate = 90,
		DustRate = 30,
		ContactDistance = 1.8,
		Sound = PH,
	},
	RapidDashSlash = {
		Enabled = true,
		DustCount = 12,
		AfterimageInterval = 0.06,
		AfterimageLifetime = 0.26,
		AfterimageTransparency = 0.55,
		Sound = PH,
	},
	WeaponImpact = {
		Enabled = true,
		Blade = { Sparks = 14, Streak = true, Flash = 1.6 },
		Heavy = { Dust = 16, Debris = 4, Flash = 2.2, Shake = 0.25 },
		Gun = { Sparks = 6, Dust = 6, Flash = 1.0 },
		Chain = { Sparks = 10, Flash = 1.4 },
		Sound = PH,
	},
}

-- Ability / soul effects (racial abilities are allowed a soul look; weapon attacks are not).
VFXConfig.Abilities = {
	TelegraphColor = Color3.fromRGB(255, 120, 60),
	TelegraphTransparency = 0.55,
	SoulColor = Color3.fromRGB(235, 240, 255),
}

VFXConfig.CameraShake = {
	MaxIntensity = 1.2,
	Decay = 4.5,
	Frequency = 22,
	MaxAngleDegrees = 1.6,
}

VFXConfig.DamageNumbers = {
	Lifetime = 0.9,
	Rise = 3,
	MaxVisible = 30,
}

-- Surface material -> impact particle color for bullets / slams.
VFXConfig.SurfaceColors = {
	Grass = Color3.fromRGB(96, 140, 70),
	LeafyGrass = Color3.fromRGB(96, 140, 70),
	Sand = Color3.fromRGB(210, 190, 140),
	Wood = Color3.fromRGB(140, 100, 60),
	WoodPlanks = Color3.fromRGB(140, 100, 60),
	Brick = Color3.fromRGB(150, 90, 70),
	Slate = Color3.fromRGB(110, 110, 120),
	Concrete = Color3.fromRGB(150, 150, 150),
	Cobblestone = Color3.fromRGB(130, 128, 125),
	Basalt = Color3.fromRGB(70, 70, 78),
	Metal = Color3.fromRGB(200, 200, 210),
	DiamondPlate = Color3.fromRGB(200, 200, 210),
	Default = Color3.fromRGB(160, 155, 150),
}

return VFXConfig
