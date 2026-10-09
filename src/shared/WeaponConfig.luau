--[[
	WeaponConfig
	Central configuration for every weapon: dimensions, palettes, mounts, movesets, attack timing,
	damage, projectile speed, trails, sounds and animation overrides.

	ASSET IDS
	  Every sound / animation / mesh id below is a clearly marked placeholder ("rbxassetid://0").
	  Nothing plays or loads until you replace it with an asset you own. Procedural animations and
	  procedural models are used whenever an id is still a placeholder.

	UNITS
	  Distances in studs, times in seconds, angles in degrees. Damage is *base* damage before the
	  attacker's StatCalculator multiplier and the target's mitigation.
]]

local WeaponConfig = {}

WeaponConfig.PLACEHOLDER = "rbxassetid://0"
local PH = WeaponConfig.PLACEHOLDER

function WeaponConfig.IsPlaceholder(id: string?): boolean
	return id == nil or id == "" or id == PH
end

-- Weapon mastery: XP thresholds for levels 0..10. Each level = +1% WeaponDamage (additive).
WeaponConfig.MasteryThresholds = { 0, 100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500 }
WeaponConfig.MasteryDamagePerLevel = 0.01

function WeaponConfig.MasteryLevel(xp: number): number
	local level = 0
	for i, threshold in WeaponConfig.MasteryThresholds do
		if xp >= threshold then
			level = i - 1
		end
	end
	return level
end

--[[
	ATTACKS
	Hits[n].Shape:
	  Arc        { Range, Angle, Height }            cone in front of the attacker
	  Circle     { Radius, Offset }                  area centered Offset studs in front
	  Line       { Length, Width }                   swept from dash start to current position
	  Projectile { Projectile, Speed, Range, Gravity?, Count?, Spread?, Pierce? }
	  Hitscan    { Range, Spread?, Hand? }            instant ray (bullets)
	  Ticks      { Range, Angle, Count, Interval }    repeated short-range hits (drill)
	Times are fractions-of-a-second at 1.0 attack speed; AttackSpeed shortens them.
]]
WeaponConfig.Attacks = {
	-- ── Scythes ─────────────────────────────────────────────────────────────────
	Scythe_SlashA = {
		Animation = "ScytheSlashA",
		Duration = 0.55,
		Stamina = 4,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash" },
		Hits = { { Time = 0.22, Shape = "Arc", Range = 10, Angle = 150, Height = 7, Damage = 22, Stagger = 0.2, Knockback = 6 } },
	},
	Scythe_SlashB = {
		Animation = "ScytheSlashB",
		Duration = 0.55,
		Stamina = 4,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Mirror = true } },
		Hits = { { Time = 0.2, Shape = "Arc", Range = 10, Angle = 150, Height = 7, Damage = 22, Stagger = 0.2, Knockback = 6 } },
	},
	Scythe_SlashC = {
		Animation = "ScytheSpin",
		Duration = 0.75,
		Stamina = 6,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Spin = true } },
		Hits = { { Time = 0.32, Shape = "Arc", Range = 10.5, Angle = 360, Height = 7, Damage = 30, Stagger = 0.3, Knockback = 18 } },
	},
	Scythe_Heavy = {
		Animation = "ScytheHeavy",
		Duration = 1.05,
		Cooldown = 5,
		Stamina = 16,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "HeavySlash" },
		Hits = { { Time = 0.55, Shape = "Arc", Range = 11.5, Angle = 120, Height = 9, Damage = 60, Stagger = 0.5, Knockback = 30 } },
	},
	Scythe_DashSlash = {
		Animation = "DashSlash",
		Duration = 0.7,
		Cooldown = 7,
		Stamina = 18,
		Lunge = 22,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "RapidDashSlash" },
		Hits = {
			{ Time = 0.18, Shape = "Line", Length = 24, Width = 7, Damage = 20, Stagger = 0.2 },
			{ Time = 0.32, Shape = "Line", Length = 24, Width = 7, Damage = 20, Stagger = 0.2 },
			{ Time = 0.46, Shape = "Arc", Range = 9, Angle = 160, Height = 7, Damage = 26, Stagger = 0.3, Knockback = 12 },
		},
	},
	Scythe_GroundSlam = {
		Animation = "ScytheSlam",
		Duration = 1.1,
		Cooldown = 8,
		Stamina = 18,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "GroundSlam", Params = { Radius = 12 } },
		Hits = { { Time = 0.6, Shape = "Circle", Radius = 12, Offset = 6, Damage = 55, Stagger = 0.5, Knockback = 26 } },
	},

	-- ── Swords / blades ─────────────────────────────────────────────────────────
	Sword_SlashA = {
		Animation = "SwordSlashA",
		Duration = 0.42,
		Stamina = 3,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash" },
		Hits = { { Time = 0.16, Shape = "Arc", Range = 8, Angle = 120, Height = 6, Damage = 17, Stagger = 0.15, Knockback = 4 } },
	},
	Sword_SlashB = {
		Animation = "SwordSlashB",
		Duration = 0.42,
		Stamina = 3,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Mirror = true } },
		Hits = { { Time = 0.15, Shape = "Arc", Range = 8, Angle = 120, Height = 6, Damage = 17, Stagger = 0.15, Knockback = 4 } },
	},
	Sword_SlashC = {
		Animation = "SwordThrust",
		Duration = 0.55,
		Stamina = 4,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Thrust = true } },
		Hits = { { Time = 0.22, Shape = "Arc", Range = 9.5, Angle = 50, Height = 6, Damage = 24, Stagger = 0.25, Knockback = 14 } },
	},
	Sword_MultiHit = {
		Animation = "SwordMultiHit",
		Duration = 1.0,
		Cooldown = 6,
		Stamina = 16,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "MultiHitCombo", Params = { Count = 4 } },
		Hits = {
			{ Time = 0.12, Shape = "Arc", Range = 8.5, Angle = 130, Height = 6, Damage = 12, Stagger = 0.12 },
			{ Time = 0.3, Shape = "Arc", Range = 8.5, Angle = 130, Height = 6, Damage = 12, Stagger = 0.12 },
			{ Time = 0.48, Shape = "Arc", Range = 8.5, Angle = 130, Height = 6, Damage = 12, Stagger = 0.12 },
			{ Time = 0.7, Shape = "Arc", Range = 9.5, Angle = 140, Height = 6, Damage = 20, Stagger = 0.3, Knockback = 16 },
		},
	},
	Sword_DashSlash = {
		Animation = "DashSlash",
		Duration = 0.6,
		Cooldown = 6,
		Stamina = 16,
		Lunge = 24,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "RapidDashSlash" },
		Hits = {
			{ Time = 0.16, Shape = "Line", Length = 26, Width = 6, Damage = 18, Stagger = 0.2 },
			{ Time = 0.36, Shape = "Line", Length = 26, Width = 6, Damage = 22, Stagger = 0.25, Knockback = 8 },
		},
	},
	Sword_Heavy = {
		Animation = "SwordHeavy",
		Duration = 0.95,
		Cooldown = 5,
		Stamina = 15,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "HeavySlash" },
		Hits = { { Time = 0.5, Shape = "Arc", Range = 9.5, Angle = 110, Height = 8, Damage = 52, Stagger = 0.45, Knockback = 24 } },
	},

	-- ── Shuriken ────────────────────────────────────────────────────────────────
	Star_SlashA = {
		Animation = "StarSlashA",
		Duration = 0.36,
		Stamina = 3,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Short = true } },
		Hits = { { Time = 0.13, Shape = "Arc", Range = 6.5, Angle = 110, Height = 6, Damage = 14, Stagger = 0.12 } },
	},
	Star_SlashB = {
		Animation = "StarSlashB",
		Duration = 0.36,
		Stamina = 3,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Short = true, Mirror = true } },
		Hits = { { Time = 0.13, Shape = "Arc", Range = 6.5, Angle = 110, Height = 6, Damage = 14, Stagger = 0.12 } },
	},
	Star_Throw = {
		Animation = "Throw",
		Duration = 0.5,
		Cooldown = 1.4,
		Stamina = 8,
		Tags = { Weapon = true },
		VFX = { Effect = "ShurikenThrow" },
		Hits = { { Time = 0.2, Shape = "Projectile", Projectile = "Shuriken", Speed = 120, Range = 90, Damage = 26, Stagger = 0.2 } },
		Ranged = true,
	},
	Star_MultiThrow = {
		Animation = "ThrowMulti",
		Duration = 0.75,
		Cooldown = 6,
		Stamina = 16,
		Tags = { Weapon = true },
		VFX = { Effect = "ShurikenThrow", Params = { Count = 3 } },
		Hits = {
			{ Time = 0.25, Shape = "Projectile", Projectile = "Shuriken", Speed = 120, Range = 80, Damage = 18, Count = 3, Spread = 14, Stagger = 0.15 },
		},
		Ranged = true,
	},

	-- ── Chains / flails ─────────────────────────────────────────────────────────
	Chain_SwingA = {
		Animation = "ChainSwingA",
		Duration = 0.6,
		Stamina = 5,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "ChainSwing" },
		Hits = { { Time = 0.28, Shape = "Arc", Range = 13, Angle = 140, Height = 7, Damage = 20, Stagger = 0.2, Knockback = 8 } },
	},
	Chain_SwingB = {
		Animation = "ChainSwingB",
		Duration = 0.6,
		Stamina = 5,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "ChainSwing", Params = { Mirror = true } },
		Hits = { { Time = 0.28, Shape = "Arc", Range = 13, Angle = 140, Height = 7, Damage = 20, Stagger = 0.2, Knockback = 8 } },
	},
	Chain_Multi = {
		Animation = "ChainWhirl",
		Duration = 1.1,
		Cooldown = 7,
		Stamina = 18,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "MultiHitCombo", Params = { Count = 3, Chain = true } },
		Hits = {
			{ Time = 0.25, Shape = "Arc", Range = 12, Angle = 360, Height = 7, Damage = 14, Stagger = 0.15 },
			{ Time = 0.5, Shape = "Arc", Range = 12, Angle = 360, Height = 7, Damage = 14, Stagger = 0.15 },
			{ Time = 0.75, Shape = "Arc", Range = 12, Angle = 360, Height = 7, Damage = 20, Stagger = 0.3, Knockback = 20 },
		},
	},
	Chain_Slam = {
		Animation = "ChainSlam",
		Duration = 1.0,
		Cooldown = 8,
		Stamina = 18,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "GroundSlam", Params = { Radius = 10 } },
		Hits = { { Time = 0.55, Shape = "Circle", Radius = 10, Offset = 10, Damage = 50, Stagger = 0.5, Knockback = 22 } },
	},
	Flail_Swing = {
		Animation = "FlailSwing",
		Duration = 0.85,
		Stamina = 7,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "ChainSwing", Params = { Heavy = true } },
		Hits = { { Time = 0.42, Shape = "Arc", Range = 12, Angle = 150, Height = 7, Damage = 32, Stagger = 0.35, Knockback = 18 } },
	},
	Flail_SwingB = {
		Animation = "FlailSwingB",
		Duration = 0.85,
		Stamina = 7,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "ChainSwing", Params = { Heavy = true, Mirror = true } },
		Hits = { { Time = 0.42, Shape = "Arc", Range = 12, Angle = 150, Height = 7, Damage = 32, Stagger = 0.35, Knockback = 18 } },
	},
	Flail_Slam = {
		Animation = "FlailSlam",
		Duration = 1.25,
		Cooldown = 8,
		Stamina = 20,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "GroundSlam", Params = { Radius = 13, Heavy = true } },
		Hits = { { Time = 0.72, Shape = "Circle", Radius = 13, Offset = 10, Damage = 70, Stagger = 0.6, Knockback = 34 } },
	},

	-- ── Arm weapon ──────────────────────────────────────────────────────────────
	Arm_PunchA = {
		Animation = "PunchA",
		Duration = 0.4,
		Stamina = 3,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "MultiHitCombo", Params = { Count = 1, Punch = true } },
		Hits = { { Time = 0.14, Shape = "Arc", Range = 7.5, Angle = 70, Height = 6, Damage = 16, Stagger = 0.2, Knockback = 6 } },
	},
	Arm_PunchB = {
		Animation = "PunchB",
		Duration = 0.4,
		Stamina = 3,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "MultiHitCombo", Params = { Count = 1, Punch = true, Mirror = true } },
		Hits = { { Time = 0.14, Shape = "Arc", Range = 7.5, Angle = 70, Height = 6, Damage = 16, Stagger = 0.2, Knockback = 6 } },
	},
	Arm_PunchC = {
		Animation = "PunchC",
		Duration = 0.6,
		Stamina = 5,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "MultiHitCombo", Params = { Count = 3, Punch = true } },
		Hits = {
			{ Time = 0.1, Shape = "Arc", Range = 7.5, Angle = 70, Height = 6, Damage = 9, Stagger = 0.1 },
			{ Time = 0.22, Shape = "Arc", Range = 7.5, Angle = 70, Height = 6, Damage = 9, Stagger = 0.1 },
			{ Time = 0.34, Shape = "Arc", Range = 8, Angle = 70, Height = 6, Damage = 14, Stagger = 0.25, Knockback = 16 },
		},
	},
	Arm_Slam = {
		Animation = "PunchSlam",
		Duration = 1.0,
		Cooldown = 7,
		Stamina = 18,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "GroundSlam", Params = { Radius = 11 } },
		Hits = { { Time = 0.55, Shape = "Circle", Radius = 11, Offset = 4, Damage = 58, Stagger = 0.5, Knockback = 28 } },
	},
	Arm_DashPunch = {
		Animation = "DashPunch",
		Duration = 0.6,
		Cooldown = 6,
		Stamina = 15,
		Lunge = 20,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "RapidDashSlash", Params = { Punch = true } },
		Hits = { { Time = 0.3, Shape = "Line", Length = 22, Width = 6, Damage = 38, Stagger = 0.4, Knockback = 24 } },
	},

	-- ── Guns ────────────────────────────────────────────────────────────────────
	Gun_ShotR = {
		Animation = "PistolShotR",
		Duration = 0.26,
		Stamina = 2,
		Tags = { Weapon = true },
		VFX = { Effect = "GunShot", Params = { Hand = "Right" } },
		Hits = { { Time = 0.04, Shape = "Hitscan", Range = 110, Spread = 1.2, Hand = "Right", Damage = 11, Stagger = 0.08 } },
		Ranged = true,
	},
	Gun_ShotL = {
		Animation = "PistolShotL",
		Duration = 0.26,
		Stamina = 2,
		Tags = { Weapon = true },
		VFX = { Effect = "GunShot", Params = { Hand = "Left" } },
		Hits = { { Time = 0.04, Shape = "Hitscan", Range = 110, Spread = 1.2, Hand = "Left", Damage = 11, Stagger = 0.08 } },
		Ranged = true,
	},
	Gun_Rapid = {
		Animation = "PistolRapid",
		Duration = 1.0,
		Cooldown = 6,
		Stamina = 14,
		Tags = { Weapon = true },
		VFX = { Effect = "GunShot", Params = { Rapid = true } },
		Hits = {
			{ Time = 0.05, Shape = "Hitscan", Range = 100, Spread = 2.5, Hand = "Right", Damage = 8 },
			{ Time = 0.17, Shape = "Hitscan", Range = 100, Spread = 2.5, Hand = "Left", Damage = 8 },
			{ Time = 0.29, Shape = "Hitscan", Range = 100, Spread = 2.5, Hand = "Right", Damage = 8 },
			{ Time = 0.41, Shape = "Hitscan", Range = 100, Spread = 2.5, Hand = "Left", Damage = 8 },
			{ Time = 0.53, Shape = "Hitscan", Range = 100, Spread = 2.5, Hand = "Right", Damage = 8 },
			{ Time = 0.65, Shape = "Hitscan", Range = 100, Spread = 2.5, Hand = "Left", Damage = 8 },
		},
		Ranged = true,
	},
	Gun_Charged = {
		Animation = "PistolCharged",
		Duration = 0.9,
		Cooldown = 7,
		Stamina = 14,
		Tags = { Weapon = true, Charged = true },
		VFX = { Effect = "GunShot", Params = { Charged = true } },
		Hits = {
			{ Time = 0.55, Shape = "Hitscan", Range = 140, Spread = 0.2, Hand = "Right", Damage = 30, Stagger = 0.3, Knockback = 12 },
			{ Time = 0.58, Shape = "Hitscan", Range = 140, Spread = 0.2, Hand = "Left", Damage = 30, Stagger = 0.3, Knockback = 12 },
		},
		Ranged = true,
	},

	-- ── Drill ───────────────────────────────────────────────────────────────────
	Drill_Thrust = {
		Animation = "DrillThrust",
		Duration = 0.55,
		Stamina = 5,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "DrillAttack", Params = { Duration = 0.4 } },
		Hits = { { Time = 0.2, Shape = "Ticks", Range = 8.5, Angle = 45, Count = 3, Interval = 0.08, Damage = 8, Stagger = 0.1 } },
	},
	Drill_Grind = {
		Animation = "DrillGrind",
		Duration = 1.3,
		Cooldown = 6,
		Stamina = 16,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "DrillAttack", Params = { Duration = 1.05, Heavy = true } },
		Hits = { { Time = 0.15, Shape = "Ticks", Range = 9, Angle = 50, Count = 10, Interval = 0.1, Damage = 7, Stagger = 0.1 } },
	},
	Drill_Dash = {
		Animation = "DrillDash",
		Duration = 0.7,
		Cooldown = 7,
		Stamina = 16,
		Lunge = 24,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "RapidDashSlash", Params = { Drill = true } },
		Hits = { { Time = 0.32, Shape = "Line", Length = 26, Width = 6, Damage = 40, Stagger = 0.35, Knockback = 20 } },
	},

	-- ── Spider weapon ───────────────────────────────────────────────────────────
	Spider_StrikeA = {
		Animation = "SpiderStrikeA",
		Duration = 0.5,
		Stamina = 4,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "BasicSlash", Params = { Stab = true } },
		Hits = { { Time = 0.2, Shape = "Arc", Range = 10, Angle = 70, Height = 7, Damage = 19, Stagger = 0.2 } },
	},
	Spider_StrikeB = {
		Animation = "SpiderStrikeB",
		Duration = 0.65,
		Stamina = 5,
		Tags = { Weapon = true, Melee = true },
		VFX = { Effect = "MultiHitCombo", Params = { Count = 2, Stab = true } },
		Hits = {
			{ Time = 0.18, Shape = "Arc", Range = 10, Angle = 80, Height = 7, Damage = 13, Stagger = 0.15 },
			{ Time = 0.36, Shape = "Arc", Range = 10, Angle = 80, Height = 7, Damage = 13, Stagger = 0.2 },
		},
	},
	Spider_Sweep = {
		Animation = "SpiderSweep",
		Duration = 0.95,
		Cooldown = 6,
		Stamina = 16,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "HeavySlash", Params = { Wide = true } },
		Hits = { { Time = 0.45, Shape = "Arc", Range = 12, Angle = 300, Height = 7, Damage = 42, Stagger = 0.4, Knockback = 20 } },
	},
	Spider_Slam = {
		Animation = "SpiderSlam",
		Duration = 1.1,
		Cooldown = 8,
		Stamina = 18,
		Tags = { Weapon = true, Melee = true, Charged = true },
		VFX = { Effect = "GroundSlam", Params = { Radius = 12 } },
		Hits = { { Time = 0.6, Shape = "Circle", Radius = 12, Offset = 3, Damage = 56, Stagger = 0.5, Knockback = 24 } },
	},
}

--[[
	WEAPONS
	Mount:        RightHand | DualHands | RightForearm | Back
	HoldStyle:    procedural animation stance (see Animation/AnimationLibrary)
	ImpactType:   Blade | Heavy | Gun | Chain (drives Effect 10, Weapon Impact)
	Dimensions:   read by the weapon's builder module (Modules/WeaponBuilder/Models/*)
	Palette:      read by the builder; every color is editable here
]]
WeaponConfig.Weapons = {
	MakaScythe = {
		Id = "MakaScythe",
		DisplayName = "Death Scythe (Maka)",
		Category = "Scythe",
		Builder = "MakaScythe",
		Mount = "RightHand",
		HoldStyle = "ScytheTwoHand",
		ImpactType = "Blade",
		UnlockLevel = 1,
		Starter = true,
		Scale = 1,
		Dimensions = { ShaftLength = 7.4, GripFromBottom = 2.1, BladeLength = 5.6, BladeWidth = 1.85, Thickness = 0.14, ShaftDiameter = 0.32 },
		Palette = {
			Shaft = Color3.fromRGB(56, 52, 66),
			Metal = Color3.fromRGB(124, 126, 138),
			Grip = Color3.fromRGB(22, 20, 26),
			Blade = Color3.fromRGB(26, 22, 30),
			Edge = Color3.fromRGB(196, 22, 36),
			Eye = Color3.fromRGB(240, 238, 232),
			Pupil = Color3.fromRGB(190, 20, 30),
		},
		Trail = { Color = Color3.fromRGB(255, 120, 120), Width = 1.0, Lifetime = 0.16, Transparency = 0.35 },
		Moveset = { M1 = { "Scythe_SlashA", "Scythe_SlashB", "Scythe_SlashC" }, Z = "Scythe_Heavy", X = "Scythe_DashSlash" },
		ComboWindow = 0.9,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	SoulScythe = {
		Id = "SoulScythe",
		DisplayName = "Death Scythe (Soul)",
		Category = "Scythe",
		Builder = "SoulScythe",
		Mount = "RightHand",
		HoldStyle = "ScytheTwoHand",
		ImpactType = "Blade",
		UnlockLevel = 6,
		Scale = 1,
		Dimensions = { ShaftLength = 7.6, GripFromBottom = 2.2, BladeLength = 5.8, BladeWidth = 1.6, Thickness = 0.15, ShaftDiameter = 0.34, Segments = 7 },
		Palette = {
			Shaft = Color3.fromRGB(226, 220, 204),
			Joint = Color3.fromRGB(196, 188, 170),
			Grip = Color3.fromRGB(60, 50, 46),
			Blade = Color3.fromRGB(176, 182, 192),
			Edge = Color3.fromRGB(186, 28, 40),
			Accent = Color3.fromRGB(30, 28, 34),
			Eye = Color3.fromRGB(190, 20, 30),
		},
		Trail = { Color = Color3.fromRGB(255, 160, 160), Width = 1.1, Lifetime = 0.16, Transparency = 0.35 },
		Moveset = { M1 = { "Scythe_SlashA", "Scythe_SlashB", "Scythe_SlashC" }, Z = "Scythe_Heavy", X = "Scythe_GroundSlam" },
		ComboWindow = 0.9,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	StarShuriken = {
		Id = "StarShuriken",
		DisplayName = "Star Weapon (Black☆Star)",
		Category = "Shuriken",
		Builder = "StarShuriken",
		Mount = "RightHand",
		HoldStyle = "ShurikenHold",
		ImpactType = "Blade",
		UnlockLevel = 1,
		Starter = true,
		Scale = 1,
		Dimensions = { Radius = 1.35, Points = 4, Thickness = 0.12, HubRadius = 0.36 },
		Palette = {
			Blade = Color3.fromRGB(42, 44, 54),
			Edge = Color3.fromRGB(158, 164, 176),
			Hub = Color3.fromRGB(24, 24, 30),
			Ring = Color3.fromRGB(230, 230, 236),
		},
		Trail = { Color = Color3.fromRGB(200, 210, 255), Width = 0.5, Lifetime = 0.12, Transparency = 0.4 },
		Moveset = { M1 = { "Star_SlashA", "Star_SlashB" }, Z = "Star_Throw", X = "Star_MultiThrow" },
		ComboWindow = 0.7,
		Sounds = { Swing = PH, Hit = PH, Throw = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	SoulEaterBlade = {
		Id = "SoulEaterBlade",
		DisplayName = "Soul Eater Blade",
		Category = "Sword",
		Builder = "SoulEaterBlade",
		Mount = "RightHand",
		HoldStyle = "SwordOneHand",
		ImpactType = "Blade",
		UnlockLevel = 1,
		Starter = true,
		Scale = 1,
		Dimensions = { BladeLength = 4.3, BladeWidth = 0.95, Thickness = 0.14, GripLength = 1.15 },
		Palette = {
			Blade = Color3.fromRGB(34, 32, 38),
			Edge = Color3.fromRGB(232, 232, 238),
			Skull = Color3.fromRGB(240, 238, 232),
			Eye = Color3.fromRGB(196, 22, 36),
			Guard = Color3.fromRGB(64, 64, 72),
			Grip = Color3.fromRGB(20, 20, 24),
		},
		Trail = { Color = Color3.fromRGB(235, 235, 255), Width = 0.8, Lifetime = 0.14, Transparency = 0.35 },
		Moveset = { M1 = { "Sword_SlashA", "Sword_SlashB", "Sword_SlashC" }, Z = "Sword_MultiHit", X = "Sword_DashSlash" },
		ComboWindow = 0.8,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	TsubakiForms = {
		Id = "TsubakiForms",
		DisplayName = "Tsubaki's Forms",
		Category = "Modular",
		Builder = "TsubakiForms",
		Mount = "RightHand",
		HoldStyle = "SwordOneHand",
		ImpactType = "Blade",
		UnlockLevel = 4,
		Scale = 1,
		-- Forms switch with the T key (server rebuilds the model). Each form overrides fields below.
		Forms = {
			Blade = {
				DisplayName = "Ninja Blade",
				HoldStyle = "SwordOneHand",
				ImpactType = "Blade",
				Moveset = { M1 = { "Sword_SlashA", "Sword_SlashB", "Sword_SlashC" }, Z = "Sword_Heavy", X = "Sword_DashSlash" },
			},
			Kusarigama = {
				DisplayName = "Kusarigama",
				HoldStyle = "Kusarigama",
				ImpactType = "Chain",
				Moveset = { M1 = { "Chain_SwingA", "Chain_SwingB" }, Z = "Chain_Multi", X = "Chain_Slam" },
			},
			ChainSickle = {
				DisplayName = "Chain Sickle",
				HoldStyle = "Kusarigama",
				ImpactType = "Chain",
				Moveset = { M1 = { "Chain_SwingA", "Chain_SwingB" }, Z = "Chain_Multi", X = "Sword_DashSlash" },
			},
		},
		FormOrder = { "Blade", "Kusarigama", "ChainSickle" },
		DefaultForm = "Blade",
		Dimensions = { BladeLength = 3.8, BladeWidth = 0.42, Thickness = 0.12, GripLength = 1.2, ChainLinks = 10, LinkLength = 0.42, SickleRadius = 1.1 },
		Palette = {
			Blade = Color3.fromRGB(30, 28, 34),
			Edge = Color3.fromRGB(206, 210, 220),
			Accent = Color3.fromRGB(190, 28, 40),
			Handle = Color3.fromRGB(70, 18, 24),
			Wrap = Color3.fromRGB(20, 18, 22),
			Metal = Color3.fromRGB(126, 128, 138),
		},
		Trail = { Color = Color3.fromRGB(255, 150, 150), Width = 0.7, Lifetime = 0.14, Transparency = 0.35 },
		Moveset = { M1 = { "Sword_SlashA", "Sword_SlashB", "Sword_SlashC" }, Z = "Sword_Heavy", X = "Sword_DashSlash" },
		ComboWindow = 0.8,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	Ragnarok = {
		Id = "Ragnarok",
		DisplayName = "Ragnarok (Scythe Form)",
		Category = "Scythe",
		Builder = "Ragnarok",
		Mount = "RightHand",
		HoldStyle = "CompactScythe",
		ImpactType = "Blade",
		UnlockLevel = 10,
		Scale = 1,
		Dimensions = { ShaftLength = 4.6, GripFromBottom = 1.2, BladeLength = 3.4, BladeWidth = 0.95, Thickness = 0.14, ShaftDiameter = 0.28 },
		Palette = {
			Shaft = Color3.fromRGB(222, 216, 202),
			Joint = Color3.fromRGB(150, 144, 132),
			Blade = Color3.fromRGB(18, 16, 22),
			Edge = Color3.fromRGB(236, 236, 240),
			Skull = Color3.fromRGB(238, 236, 230),
			Eye = Color3.fromRGB(180, 18, 28),
		},
		Trail = { Color = Color3.fromRGB(230, 230, 240), Width = 0.8, Lifetime = 0.14, Transparency = 0.35 },
		Moveset = { M1 = { "Scythe_SlashA", "Scythe_SlashB" }, Z = "Scythe_Heavy", X = "Sword_MultiHit" },
		ComboWindow = 0.8,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	TsunamiChain = {
		Id = "TsunamiChain",
		DisplayName = "Tsunami Chain",
		Category = "Chain",
		Builder = "TsunamiChain",
		Mount = "RightHand",
		HoldStyle = "ChainWeapon",
		ImpactType = "Chain",
		UnlockLevel = 8,
		Scale = 1,
		Dimensions = { Links = 11, LinkLength = 0.46, LinkWidth = 0.26, BladeLength = 1.6, GripLength = 1.0 },
		Palette = {
			Link = Color3.fromRGB(78, 52, 120),
			LinkDark = Color3.fromRGB(46, 30, 74),
			Blade = Color3.fromRGB(56, 46, 78),
			Edge = Color3.fromRGB(196, 184, 230),
			Grip = Color3.fromRGB(24, 20, 30),
		},
		Trail = { Color = Color3.fromRGB(200, 170, 255), Width = 0.6, Lifetime = 0.18, Transparency = 0.45 },
		Moveset = { M1 = { "Chain_SwingA", "Chain_SwingB" }, Z = "Chain_Multi", X = "Chain_Slam" },
		ComboWindow = 0.9,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	GevurahChain = {
		Id = "GevurahChain",
		DisplayName = "Gevurah Spiked Chain",
		Category = "Flail",
		Builder = "GevurahChain",
		Mount = "RightHand",
		HoldStyle = "HeavyFlail",
		ImpactType = "Heavy",
		UnlockLevel = 14,
		Scale = 1,
		Dimensions = { Links = 6, LinkLength = 0.55, LinkWidth = 0.32, BallRadius = 0.75, GripLength = 1.3, Spikes = 10 },
		Palette = {
			Link = Color3.fromRGB(116, 118, 128),
			Ball = Color3.fromRGB(64, 66, 74),
			Spike = Color3.fromRGB(196, 198, 206),
			Band = Color3.fromRGB(36, 36, 42),
			Grip = Color3.fromRGB(46, 30, 26),
		},
		Trail = { Color = Color3.fromRGB(220, 220, 230), Width = 0.9, Lifetime = 0.2, Transparency = 0.45 },
		Moveset = { M1 = { "Flail_Swing", "Flail_SwingB" }, Z = "Flail_Slam", X = "Chain_Multi" },
		ComboWindow = 1.0,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	AsuraArm = {
		Id = "AsuraArm",
		DisplayName = "Segmented Arm",
		Category = "Gauntlet",
		Builder = "AsuraArm",
		Mount = "RightForearm",
		HoldStyle = "ArmWeapon",
		ImpactType = "Heavy",
		UnlockLevel = 12,
		Scale = 1,
		Dimensions = { Segments = 5, SegmentSize = 0.62, FistSize = 1.05 },
		Palette = {
			Block = Color3.fromRGB(206, 206, 212),
			Dark = Color3.fromRGB(104, 104, 114),
			Eye = Color3.fromRGB(196, 20, 32),
			Joint = Color3.fromRGB(46, 46, 52),
		},
		Trail = { Color = Color3.fromRGB(230, 230, 240), Width = 0.7, Lifetime = 0.12, Transparency = 0.4 },
		Moveset = { M1 = { "Arm_PunchA", "Arm_PunchB", "Arm_PunchC" }, Z = "Arm_Slam", X = "Arm_DashPunch" },
		ComboWindow = 0.8,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	TwinPistols = {
		Id = "TwinPistols",
		DisplayName = "Twin Pistols (Liz & Patty)",
		Category = "Guns",
		Builder = "TwinPistols",
		Mount = "DualHands",
		HoldStyle = "DualPistols",
		ImpactType = "Gun",
		UnlockLevel = 1,
		Starter = true,
		Scale = 1,
		Dimensions = { BarrelLength = 1.25, BodyLength = 1.6, BodyHeight = 0.46, GripLength = 0.85 },
		-- Two distinct guns: Liz (right hand) and Patty (left hand).
		Palette = {
			Body = Color3.fromRGB(236, 232, 226),
			Barrel = Color3.fromRGB(58, 58, 66),
			Grip = Color3.fromRGB(38, 38, 46),
			Metal = Color3.fromRGB(150, 152, 160),
			LizTrim = Color3.fromRGB(196, 28, 40),
			PattyTrim = Color3.fromRGB(56, 96, 196),
			Skull = Color3.fromRGB(30, 30, 36),
		},
		Muzzle = {
			Liz = { FlashSize = 0.9, FlashColor = Color3.fromRGB(255, 206, 120), Smoke = 4 },
			Patty = { FlashSize = 1.25, FlashColor = Color3.fromRGB(255, 180, 90), Smoke = 7 },
		},
		Projectile = { TracerSpeed = 600, TracerLength = 3.5, TracerWidth = 0.08 },
		Trail = { Color = Color3.fromRGB(255, 255, 255), Width = 0.3, Lifetime = 0.1, Transparency = 0.6 },
		Moveset = { M1 = { "Gun_ShotR", "Gun_ShotL" }, Z = "Gun_Rapid", X = "Gun_Charged" },
		ComboWindow = 0.6,
		Sounds = { Shot = PH, ShotPatty = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	PattyDrill = {
		Id = "PattyDrill",
		DisplayName = "Drill Form",
		Category = "Drill",
		Builder = "PattyDrill",
		Mount = "RightHand",
		HoldStyle = "DrillArm",
		ImpactType = "Heavy",
		UnlockLevel = 16,
		Scale = 1,
		Dimensions = { HousingLength = 1.6, HousingRadius = 0.62, BitLength = 2.8, BitRadius = 0.6, Bands = 4 },
		Palette = {
			Housing = Color3.fromRGB(40, 50, 86),
			Bit = Color3.fromRGB(152, 158, 172),
			BitDark = Color3.fromRGB(92, 96, 108),
			Band = Color3.fromRGB(232, 232, 236),
			Accent = Color3.fromRGB(22, 22, 28),
			Skull = Color3.fromRGB(236, 236, 240),
		},
		SpinSpeed = 28, -- radians per second while drilling
		Trail = { Color = Color3.fromRGB(200, 210, 255), Width = 0.6, Lifetime = 0.12, Transparency = 0.5 },
		Moveset = { M1 = { "Drill_Thrust" }, Z = "Drill_Grind", X = "Drill_Dash" },
		ComboWindow = 0.6,
		Sounds = { Spin = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
	ArachneSpider = {
		Id = "ArachneSpider",
		DisplayName = "Arachnid Rig",
		Category = "Rig",
		Builder = "ArachneSpider",
		Mount = "Back",
		HoldStyle = "SpiderBack",
		ImpactType = "Blade",
		UnlockLevel = 18,
		Scale = 1,
		Dimensions = { Legs = 8, UpperLength = 2.4, LowerLength = 2.8, BodyRadius = 0.75 },
		Palette = {
			Body = Color3.fromRGB(30, 30, 36),
			Joint = Color3.fromRGB(96, 96, 106),
			Leg = Color3.fromRGB(44, 44, 52),
			Tip = Color3.fromRGB(186, 188, 198),
			Eye = Color3.fromRGB(190, 20, 30),
			Ring = Color3.fromRGB(226, 226, 230),
		},
		Trail = { Color = Color3.fromRGB(220, 200, 255), Width = 0.5, Lifetime = 0.14, Transparency = 0.45 },
		Moveset = { M1 = { "Spider_StrikeA", "Spider_StrikeB" }, Z = "Spider_Sweep", X = "Spider_Slam" },
		ComboWindow = 0.9,
		Sounds = { Swing = PH, Hit = PH, Equip = PH },
		AnimationIds = { Idle = PH, Walk = PH, Run = PH },
	},
}

WeaponConfig.Order = {
	"MakaScythe",
	"SoulScythe",
	"StarShuriken",
	"SoulEaterBlade",
	"TsubakiForms",
	"Ragnarok",
	"TsunamiChain",
	"GevurahChain",
	"AsuraArm",
	"TwinPistols",
	"PattyDrill",
	"ArachneSpider",
}

-- Projectile visuals/physics shared by server simulation and client rendering.
WeaponConfig.Projectiles = {
	Shuriken = { Radius = 0.9, Gravity = 0, SpinSpeed = 30, Model = "StarShuriken", Lifetime = 2 },
	Wrapping = { Radius = 1.2, Gravity = 0, SpinSpeed = 6, Lifetime = 1.5 },
	VectorArrow = { Radius = 1, Gravity = 0, SpinSpeed = 0, Lifetime = 2 },
	Bolt = { Radius = 0.6, Gravity = 0, SpinSpeed = 0, Lifetime = 1.5 },
}

function WeaponConfig.Get(id: string)
	return WeaponConfig.Weapons[id]
end

function WeaponConfig.IsValid(id: any): boolean
	return type(id) == "string" and WeaponConfig.Weapons[id] ~= nil
end

-- Resolves form overrides (Tsubaki) into a flat view of the weapon.
function WeaponConfig.Resolve(id: string, form: string?)
	local weapon = WeaponConfig.Weapons[id]
	if not weapon then
		return nil
	end
	if not weapon.Forms then
		return weapon
	end
	local formId = (form and weapon.Forms[form]) and form or weapon.DefaultForm
	local resolved = table.clone(weapon)
	for key, value in weapon.Forms[formId] do
		resolved[key] = value
	end
	resolved.Form = formId
	return resolved
end

function WeaponConfig.Attack(attackId: string)
	return WeaponConfig.Attacks[attackId]
end

-- Validates internal consistency (used by tests and at server start).
function WeaponConfig.Validate(): (boolean, string?)
	for id, weapon in WeaponConfig.Weapons do
		if weapon.Id ~= id then
			return false, "id mismatch " .. id
		end
		local movesets = { weapon.Moveset }
		for _, form in weapon.Forms or {} do
			table.insert(movesets, form.Moveset)
		end
		for _, moveset in movesets do
			for _, attackId in moveset.M1 do
				if not WeaponConfig.Attacks[attackId] then
					return false, id .. " unknown M1 attack " .. attackId
				end
			end
			for _, slot in { "Z", "X" } do
				if not WeaponConfig.Attacks[moveset[slot]] then
					return false, id .. " unknown " .. slot .. " attack " .. tostring(moveset[slot])
				end
			end
		end
	end
	for _, id in WeaponConfig.Order do
		if not WeaponConfig.Weapons[id] then
			return false, "order lists unknown weapon " .. id
		end
	end
	return true, nil
end

return WeaponConfig
