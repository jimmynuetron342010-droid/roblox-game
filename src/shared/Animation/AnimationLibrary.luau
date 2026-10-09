--[[
	AnimationLibrary
	All weapon animations as DATA, played procedurally by the client (no uploaded assets needed).

	Two authoring modes:
	  * Weapon trajectories (IK) — keys give the weapon's CFrame in UpperTorso space; both hands
	    follow with two-bone IK (right hand on "Grip", left hand on "SupportGrip"). Swing arcs are
	    therefore exactly the blade paths you see, and trails follow the real blade.
	  * Joint poses — keys give Motor6D rotations (degrees) for arm-mounted / back-mounted weapons
	    and for free hands.

	Holds   = idle stance per weapon HoldStyle (+ loose walk/run parameters)
	Actions = attacks and ability gestures; normalized time 0..1, stretched to the attack duration

	UpperTorso space: +X right, +Y up, -Z forward (the way the character faces).
	Every procedural clip can be replaced by an uploaded animation: set the ids in WeaponConfig
	(AnimationIds) or AnimationLibrary.UploadedIds; see docs/ANIMATION.md.
]]

local RigMath = require(script.Parent.RigMath)

local AnimationLibrary = {}

local W = RigMath.WeaponFrame
local V = Vector3.new
local E = function(x, y, z)
	return RigMath.Euler({ x, y, z })
end

local rad = math.rad

-- Optional uploaded animation ids that replace a procedural clip (placeholders by default).
AnimationLibrary.UploadedIds = {}

-- ── Holds ─────────────────────────────────────────────────────────────────────
export type Hold = {
	Mode: "IK" | "Joints",
	Weapon: { [string]: CFrame }?,
	Support: { Unit: string, Twist: number }?,
	Joints: { [string]: CFrame }?,
	Run: { Weapon: { [string]: CFrame }?, Joints: { [string]: CFrame }? }?,
	Locomotion: { ArmSwing: number, Bounce: number, HipSway: number, Twist: number, Lean: number },
	Stance: number, -- 0 = feet together, 1 = wide fighting stance
}

local LOOSE = { ArmSwing = 1, Bounce = 0.14, HipSway = 7, Twist = 9, Lean = 5 }
local HEAVY = { ArmSwing = 0.6, Bounce = 0.1, HipSway = 5, Twist = 6, Lean = 7 }

AnimationLibrary.Holds = {
	ScytheTwoHand = {
		Mode = "IK",
		Weapon = { Main = W(V(0.6, -1.0, -0.85), V(-0.42, 0.86, -0.3), V(0, 0.25, -1)) },
		Support = { Unit = "Main", Twist = 0 },
		Joints = { Waist = E(0, -12, 0), Neck = E(0, 10, 0) },
		Run = { Weapon = { Main = W(V(0.75, -0.75, -0.35), V(-0.25, 0.55, 0.8), V(0, 0.85, -0.5)) } },
		Locomotion = { ArmSwing = 0, Bounce = 0.12, HipSway = 6, Twist = 5, Lean = 7 },
		Stance = 1,
	},
	CompactScythe = {
		Mode = "IK",
		Weapon = { Main = W(V(0.8, -0.95, -0.85), V(-0.3, 0.85, -0.45), V(0, 0.3, -1)) },
		Support = { Unit = "Main", Twist = 0 },
		Joints = { Waist = E(0, -10, 0) },
		Locomotion = { ArmSwing = 0, Bounce = 0.13, HipSway = 6, Twist = 6, Lean = 6 },
		Stance = 0.8,
	},
	SwordOneHand = {
		Mode = "IK",
		Weapon = { Main = W(V(0.95, -0.9, -0.8), V(0.08, 0.5, -0.86), V(0.1, -0.86, -0.5)) },
		Joints = {
			LeftShoulder = E(22, 0, -14),
			LeftElbow = E(38, 0, 0),
			Waist = E(0, -8, 0),
		},
		Run = { Weapon = { Main = W(V(1.0, -0.9, 0.2), V(0.15, -0.35, 0.92), V(0, -0.92, -0.35)) } },
		Locomotion = LOOSE,
		Stance = 0.7,
	},
	ShurikenHold = {
		Mode = "IK",
		-- Star face turned toward the front so the silhouette reads.
		Weapon = { Main = W(V(1.1, -0.95, -0.65), V(0.1, 1, -0.15), V(1, -0.1, 0.2)) },
		Joints = { LeftShoulder = E(8, 0, -8), LeftElbow = E(18, 0, 0) },
		Locomotion = LOOSE,
		Stance = 0.5,
	},
	DualPistols = {
		Mode = "IK",
		Weapon = {
			Liz = W(V(0.8, -1.0, -0.95), V(0, 0.94, -0.33), V(0.05, -0.33, -0.94)),
			Patty = W(V(-0.8, -1.0, -0.95), V(0, 0.94, -0.33), V(-0.05, -0.33, -0.94)),
		},
		Locomotion = { ArmSwing = 0, Bounce = 0.12, HipSway = 7, Twist = 8, Lean = 4 },
		Stance = 0.6,
	},
	ChainWeapon = {
		Mode = "IK",
		Weapon = { Main = W(V(1.0, -0.95, -0.7), V(0.15, 0.65, -0.74), V(0.1, 0.74, 0.65)) },
		Joints = { LeftShoulder = E(18, 0, -16), LeftElbow = E(30, 0, 0) },
		Locomotion = LOOSE,
		Stance = 0.7,
	},
	HeavyFlail = {
		Mode = "IK",
		Weapon = { Main = W(V(0.95, -0.25, -0.8), V(0.15, 0.85, -0.5), V(0, 0.5, 0.85)) },
		Joints = { LeftShoulder = E(12, 0, -10), LeftElbow = E(22, 0, 0), Waist = E(0, -6, 0) },
		Locomotion = HEAVY,
		Stance = 0.9,
	},
	Kusarigama = {
		Mode = "IK",
		Weapon = { Main = W(V(0.95, -0.85, -0.85), V(0, 0.9, -0.4), V(0, 0.4, -0.9)) },
		Joints = { LeftShoulder = E(20, 0, -12), LeftElbow = E(35, 0, 0) },
		Locomotion = LOOSE,
		Stance = 0.7,
	},
	DrillArm = {
		Mode = "IK",
		Weapon = { Main = W(V(0.85, -0.75, -1.05), V(0, 1, -0.12), V(0, -0.12, -1)) },
		Joints = { LeftShoulder = E(14, 0, -10), LeftElbow = E(25, 0, 0) },
		Locomotion = HEAVY,
		Stance = 0.8,
	},
	ArmWeapon = {
		Mode = "Joints",
		Joints = {
			RightShoulder = E(62, 0, 10),
			RightElbow = E(22, 0, 0),
			RightWrist = E(-5, 0, 0),
			LeftShoulder = E(42, 0, -10),
			LeftElbow = E(92, 0, 0),
			Waist = E(0, -14, 0),
		},
		Locomotion = { ArmSwing = 0.2, Bounce = 0.16, HipSway = 6, Twist = 4, Lean = 6 },
		Stance = 1,
	},
	SpiderBack = {
		Mode = "Joints",
		Joints = {
			RightShoulder = E(14, 0, 14),
			RightElbow = E(28, 0, 0),
			LeftShoulder = E(14, 0, -14),
			LeftElbow = E(28, 0, 0),
		},
		Locomotion = LOOSE,
		Stance = 0.8,
	},
} :: { [string]: Hold }

-- ── Action key helpers ────────────────────────────────────────────────────────
export type Key = {
	T: number,
	Ease: string?,
	Weapon: { [string]: CFrame }?,
	Joints: { [string]: CFrame }?,
	Release: { [string]: boolean }?,
	Extend: number?,
	Spider: string?,
	Drill: boolean?,
	Recoil: string?,
}

export type Action = {
	Keys: { Key },
	Trail: { number }?,
	BlendIn: number?,
	BlendOut: number?,
	RootMotion: boolean?,
}

-- Horizontal swing around the body. theta in degrees: + = right side, 0 = front, - = left.
local function swingFrame(
	theta: number,
	radius: number,
	height: number,
	elevation: number,
	direction: number,
	tilt: number?
)
	local t = rad(theta)
	local e = rad(elevation)
	local shaft = V(math.sin(t) * math.cos(e), math.sin(e), -math.cos(t) * math.cos(e))
	-- Travel direction for decreasing theta when direction = -1 (right-to-left).
	local travel = V(-math.cos(t), 0, -math.sin(t)) * direction
	local grip = V(0.15 + math.sin(t) * radius, height, -0.85 - math.cos(t) * radius * 0.35)
	local frame = W(grip, shaft, travel)
	if tilt then
		frame = CFrame.Angles(0, 0, rad(tilt)) * frame
	end
	return frame
end

-- Vertical swing in front of the body. phi: 90 = straight up, 0 = forward, negative = down.
local function overheadFrame(phi: number, gripHigh: number, gripLow: number)
	local p = rad(phi)
	local shaft = V(0.05, math.sin(p), -math.cos(p))
	local travel = V(0, -math.cos(p), -math.sin(p))
	local blend = math.clamp((phi + 40) / 200, 0, 1)
	local grip = V(0.3, gripLow + (gripHigh - gripLow) * blend, -0.6 - (1 - blend) * 0.6)
	return W(grip, shaft, travel)
end

local function swingKeys(unit: string, from: number, to: number, opts)
	local keys = {}
	local steps = opts.Steps or 5
	for i = 0, steps do
		local alpha = i / steps
		local theta = from + (to - from) * alpha
		local t = opts.T0 + (opts.T1 - opts.T0) * alpha
		local frame = swingFrame(
			theta,
			opts.Radius or 0.5,
			opts.Height or -0.55,
			opts.Elevation or 8,
			to < from and -1 or 1,
			opts.Tilt
		)
		table.insert(keys, {
			T = t,
			Ease = i == 0 and "Out" or "Linear",
			Weapon = { [unit] = frame },
			Joints = {
				Waist = E(opts.Lean or -6, theta * (opts.TwistAmount or 0.32), 0),
				Root = E(0, theta * 0.12, 0),
				Neck = E(0, -theta * 0.18, 0),
			},
			Release = opts.Release,
		})
	end
	return keys
end

local function overheadKeys(unit: string, from: number, to: number, opts)
	local keys = {}
	local steps = opts.Steps or 5
	for i = 0, steps do
		local alpha = i / steps
		local phi = from + (to - from) * alpha
		local t = opts.T0 + (opts.T1 - opts.T0) * alpha
		local crouch = math.clamp((90 - phi) / 130, 0, 1)
		table.insert(keys, {
			T = t,
			Ease = i == 0 and "Out" or "Linear",
			Weapon = { [unit] = overheadFrame(phi, opts.High or 1.1, opts.Low or -0.95) },
			Joints = {
				Waist = E(-8 - crouch * 18, 0, 0),
				Root = CFrame.new(0, -crouch * (opts.Crouch or 0.35), 0),
				RightHip = E(crouch * 25, 0, 0),
				LeftHip = E(crouch * 40, 0, 0),
				RightKnee = E(-crouch * 35, 0, 0),
				LeftKnee = E(-crouch * 50, 0, 0),
			},
			Release = opts.Release,
		})
	end
	return keys
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, key in list do
			table.insert(out, key)
		end
	end
	table.sort(out, function(a, b)
		return a.T < b.T
	end)
	return out
end

-- Free-arm and body gesture helper.
local function pose(t: number, joints: { [string]: CFrame }, extra: { [string]: any }?): Key
	local key: Key = { T = t, Joints = joints }
	for k, v in (extra or {}) :: { [string]: any } do
		(key :: any)[k] = v
	end
	return key
end

-- ── Actions ───────────────────────────────────────────────────────────────────
local A = {}

-- Scythes ---------------------------------------------------------------------
A.ScytheSlashA = {
	Keys = concat(
		swingKeys("Main", 95, 115, { T0 = 0.0, T1 = 0.28, Steps = 1, Radius = 0.45 }),
		swingKeys("Main", 115, -105, { T0 = 0.3, T1 = 0.62, Steps = 6, Radius = 0.5 })
	),
	Trail = { 0.3, 0.66 },
}
A.ScytheSlashB = {
	Keys = concat(
		swingKeys("Main", -80, -105, { T0 = 0.0, T1 = 0.26, Steps = 1, Radius = 0.45, Tilt = -28, Height = -0.85 }),
		swingKeys(
			"Main",
			-105,
			110,
			{ T0 = 0.28, T1 = 0.6, Steps = 6, Radius = 0.5, Tilt = -28, Height = -0.4, Elevation = 25 }
		)
	),
	Trail = { 0.28, 0.64 },
}
do
	-- Full spin: the whole body turns once while the scythe is held out to the right.
	local keys = {}
	for i = 0, 8 do
		local alpha = i / 8
		table.insert(keys, {
			T = 0.12 + alpha * 0.62,
			Ease = i == 0 and "Out" or "Linear",
			Weapon = { Main = swingFrame(70, 0.55, -0.45, 5, -1) },
			Joints = { Root = E(0, -alpha * 360, 0), Waist = E(-8, 15, 0) },
		})
	end
	table.insert(
		keys,
		1,
		{ T = 0, Weapon = { Main = swingFrame(95, 0.45, -0.6, 10, -1) }, Joints = { Waist = E(-6, 30, 0) } }
	)
	A.ScytheSpin = { Keys = keys, Trail = { 0.12, 0.78 } }
end
A.ScytheHeavy = {
	Keys = concat(
		overheadKeys("Main", 95, 165, { T0 = 0.0, T1 = 0.4, Steps = 2 }),
		overheadKeys("Main", 165, -35, { T0 = 0.42, T1 = 0.62, Steps = 5, Crouch = 0.45 })
	),
	Trail = { 0.42, 0.66 },
}
A.ScytheSlam = {
	Keys = concat(
		overheadKeys("Main", 95, 170, { T0 = 0.0, T1 = 0.45, Steps = 2 }),
		overheadKeys("Main", 170, -55, { T0 = 0.47, T1 = 0.62, Steps = 5, Crouch = 0.6 })
	),
	Trail = { 0.47, 0.64 },
}
A.DashSlash = {
	Keys = concat(
		{
			pose(0, {
				Waist = E(-24, 20, 0),
				Root = E(-10, 0, 0),
				RightHip = E(30, 0, 0),
				LeftHip = E(-25, 0, 0),
				RightKnee = E(-30, 0, 0),
			}),
		},
		swingKeys("Main", 100, -80, { T0 = 0.08, T1 = 0.3, Steps = 4, Lean = -22, Radius = 0.5 }),
		swingKeys("Main", -80, 95, { T0 = 0.32, T1 = 0.46, Steps = 4, Lean = -22, Tilt = 20, Radius = 0.5 }),
		swingKeys("Main", 95, -70, { T0 = 0.48, T1 = 0.66, Steps = 4, Lean = -14, Radius = 0.5 })
	),
	Trail = { 0.08, 0.7 },
}

-- Swords ----------------------------------------------------------------------
local SWORD = { Radius = 0.55, Height = -0.35, Elevation = 12, Release = nil }
A.SwordSlashA = {
	Keys = concat(
		swingKeys("Main", 85, 110, { T0 = 0, T1 = 0.25, Steps = 1, Radius = 0.5, Height = -0.3 }),
		swingKeys("Main", 110, -95, {
			T0 = 0.27,
			T1 = 0.58,
			Steps = 5,
			Radius = SWORD.Radius,
			Height = SWORD.Height,
			Elevation = SWORD.Elevation,
		})
	),
	Trail = { 0.27, 0.62 },
}
A.SwordSlashB = {
	Keys = concat(
		swingKeys("Main", -60, -95, { T0 = 0, T1 = 0.25, Steps = 1, Radius = 0.5, Height = -0.7, Tilt = -30 }),
		swingKeys(
			"Main",
			-95,
			100,
			{ T0 = 0.27, T1 = 0.58, Steps = 5, Radius = 0.55, Height = -0.2, Tilt = -30, Elevation = 30 }
		)
	),
	Trail = { 0.27, 0.62 },
}
A.SwordThrust = {
	Keys = {
		{
			T = 0,
			Weapon = { Main = W(V(1.1, -0.5, 0.35), V(0, 0.15, -1), V(0, -1, -0.15)) },
			Joints = { Waist = E(0, 25, 0), RightHip = E(-10, 0, 0) },
		},
		{
			T = 0.32,
			Ease = "Out",
			Weapon = { Main = W(V(1.15, -0.45, 0.5), V(0, 0.1, -1), V(0, -1, -0.1)) },
			Joints = { Waist = E(-5, 30, 0) },
		},
		{
			T = 0.45,
			Ease = "In",
			Weapon = { Main = W(V(0.45, -0.25, -2.0), V(-0.05, 0.05, -1), V(0, -1, 0)) },
			Joints = {
				Waist = E(-14, -20, 0),
				Root = E(-6, 0, 0),
				RightHip = E(35, 0, 0),
				RightKnee = E(-30, 0, 0),
				LeftHip = E(-20, 0, 0),
			},
		},
		{
			T = 0.7,
			Weapon = { Main = W(V(0.5, -0.3, -1.9), V(-0.05, 0.1, -1), V(0, -1, 0)) },
			Joints = { Waist = E(-12, -18, 0) },
		},
	},
	Trail = { 0.4, 0.62 },
}
A.SwordMultiHit = {
	Keys = concat(
		swingKeys("Main", 100, -80, { T0 = 0.0, T1 = 0.16, Steps = 3, Radius = 0.5, Height = -0.3 }),
		swingKeys("Main", -80, 95, { T0 = 0.18, T1 = 0.34, Steps = 3, Radius = 0.5, Height = -0.45, Tilt = -25 }),
		swingKeys("Main", 95, -80, { T0 = 0.36, T1 = 0.52, Steps = 3, Radius = 0.5, Height = -0.25, Tilt = 20 }),
		overheadKeys("Main", 150, -30, { T0 = 0.56, T1 = 0.76, Steps = 4 })
	),
	Trail = { 0.0, 0.8 },
}
A.SwordHeavy = {
	Keys = concat(
		overheadKeys("Main", 90, 165, { T0 = 0, T1 = 0.42, Steps = 2 }),
		overheadKeys("Main", 165, -40, { T0 = 0.45, T1 = 0.62, Steps = 5, Crouch = 0.45 })
	),
	Trail = { 0.45, 0.66 },
}

-- Shuriken --------------------------------------------------------------------
A.StarSlashA = {
	Keys = concat(
		swingKeys("Main", 80, 100, { T0 = 0, T1 = 0.2, Steps = 1, Radius = 0.6, Height = -0.3 }),
		swingKeys("Main", 100, -70, { T0 = 0.22, T1 = 0.55, Steps = 4, Radius = 0.65, Height = -0.25 })
	),
	Trail = { 0.22, 0.6 },
}
A.StarSlashB = {
	Keys = concat(
		swingKeys("Main", -50, -70, { T0 = 0, T1 = 0.2, Steps = 1, Radius = 0.6, Height = -0.5, Tilt = -30 }),
		swingKeys("Main", -70, 95, { T0 = 0.22, T1 = 0.55, Steps = 4, Radius = 0.65, Height = -0.2, Tilt = -30 })
	),
	Trail = { 0.22, 0.6 },
}
A.Throw = {
	Keys = {
		{
			T = 0,
			Weapon = { Main = W(V(1.3, 0.55, 0.65), V(0.3, 0.3, 0.9), V(0, 1, -0.3)) },
			Joints = { Waist = E(6, 35, 0), LeftShoulder = E(70, 0, -10), LeftElbow = E(20, 0, 0) },
		},
		{
			T = 0.3,
			Ease = "Out",
			Weapon = { Main = W(V(1.35, 0.7, 0.8), V(0.3, 0.35, 0.88), V(0, 1, -0.35)) },
			Joints = { Waist = E(8, 40, 0), LeftShoulder = E(80, 0, -8) },
		},
		{
			T = 0.42,
			Ease = "In",
			Weapon = { Main = W(V(0.55, 0.15, -1.9), V(-0.1, 0.1, -1), V(0, 1, 0.1)) },
			Joints = {
				Waist = E(-14, -25, 0),
				LeftShoulder = E(10, 0, -20),
				RightHip = E(25, 0, 0),
				LeftHip = E(-15, 0, 0),
			},
		},
		{
			T = 0.7,
			Weapon = { Main = W(V(0.6, -0.4, -1.5), V(0, -0.3, -1), V(0, 1, -0.3)) },
			Joints = { Waist = E(-10, -20, 0) },
		},
	},
	Trail = { 0.3, 0.5 },
}
A.ThrowMulti = {
	Keys = {
		{
			T = 0,
			Weapon = { Main = W(V(1.3, 0.5, 0.6), V(0.3, 0.3, 0.9), V(0, 1, -0.3)) },
			Joints = { Waist = E(6, 35, 0) },
		},
		{
			T = 0.22,
			Ease = "In",
			Weapon = { Main = W(V(0.6, 0.2, -1.8), V(-0.1, 0.1, -1), V(0, 1, 0.1)) },
			Joints = { Waist = E(-10, -15, 0) },
		},
		{
			T = 0.36,
			Weapon = { Main = W(V(1.25, 0.4, 0.5), V(0.3, 0.3, 0.9), V(0, 1, -0.3)) },
			Joints = { Waist = E(5, 30, 0) },
		},
		{
			T = 0.48,
			Ease = "In",
			Weapon = { Main = W(V(0.4, 0.1, -1.9), V(-0.2, 0.1, -1), V(0, 1, 0.1)) },
			Joints = { Waist = E(-10, -25, 0) },
		},
		{
			T = 0.6,
			Weapon = { Main = W(V(1.2, 0.45, 0.5), V(0.3, 0.3, 0.9), V(0, 1, -0.3)) },
			Joints = { Waist = E(5, 25, 0) },
		},
		{
			T = 0.72,
			Ease = "In",
			Weapon = { Main = W(V(0.8, 0.0, -1.9), V(0.1, 0.1, -1), V(0, 1, 0.1)) },
			Joints = { Waist = E(-12, -10, 0) },
		},
	},
	Trail = { 0.15, 0.75 },
}

-- Chains / flails (the client chain simulator adds the physical whip) -------------
A.ChainSwingA = {
	Keys = concat(
		swingKeys("Main", 100, 125, { T0 = 0, T1 = 0.28, Steps = 1, Radius = 0.55, Height = 0.1, Elevation = 35 }),
		swingKeys("Main", 125, -110, { T0 = 0.3, T1 = 0.62, Steps = 6, Radius = 0.6, Height = 0.1, Elevation = 10 })
	),
	Trail = { 0.3, 0.7 },
}
A.ChainSwingB = {
	Keys = concat(
		swingKeys("Main", -90, -115, { T0 = 0, T1 = 0.28, Steps = 1, Radius = 0.55, Height = 0.0, Elevation = 35 }),
		swingKeys("Main", -115, 115, { T0 = 0.3, T1 = 0.62, Steps = 6, Radius = 0.6, Height = 0.1, Elevation = 10 })
	),
	Trail = { 0.3, 0.7 },
}
do
	local keys = {}
	for i = 0, 12 do
		local theta = 90 - i * 90
		table.insert(keys, {
			T = 0.08 + i * 0.055,
			Ease = "Linear",
			Weapon = {
				Main = W(
					V(0.4 + math.sin(rad(theta)) * 0.35, 1.3, -0.4 - math.cos(rad(theta)) * 0.35),
					V(math.sin(rad(theta)), 0.25, -math.cos(rad(theta))),
					V(-math.cos(rad(theta)), 0, -math.sin(rad(theta)))
				),
			},
			Joints = { Waist = E(4, -8, 0), LeftShoulder = E(20, 0, -30) },
		})
	end
	A.ChainWhirl = { Keys = keys, Trail = { 0.08, 0.8 } }
end
A.ChainSlam = {
	Keys = concat(
		overheadKeys("Main", 90, 175, { T0 = 0, T1 = 0.42, Steps = 2, High = 1.4 }),
		overheadKeys("Main", 175, -20, { T0 = 0.45, T1 = 0.58, Steps = 5, Crouch = 0.5, High = 1.4 })
	),
	Trail = { 0.45, 0.7 },
}
A.FlailSwing = {
	Keys = concat(
		swingKeys("Main", 110, 135, { T0 = 0, T1 = 0.35, Steps = 1, Radius = 0.6, Height = 0.2, Elevation = 40 }),
		swingKeys("Main", 135, -100, { T0 = 0.38, T1 = 0.66, Steps = 6, Radius = 0.6, Height = 0.05, Elevation = 15 })
	),
	Trail = { 0.38, 0.72 },
}
A.FlailSwingB = {
	Keys = concat(
		swingKeys("Main", -90, -120, { T0 = 0, T1 = 0.35, Steps = 1, Radius = 0.6, Height = 0.1, Elevation = 40 }),
		swingKeys("Main", -120, 110, { T0 = 0.38, T1 = 0.66, Steps = 6, Radius = 0.6, Height = 0.05, Elevation = 15 })
	),
	Trail = { 0.38, 0.72 },
}
A.FlailSlam = {
	Keys = concat(
		overheadKeys("Main", 90, 180, { T0 = 0, T1 = 0.5, Steps = 2, High = 1.5 }),
		overheadKeys("Main", 180, -25, { T0 = 0.52, T1 = 0.64, Steps = 5, Crouch = 0.6, High = 1.5 })
	),
	Trail = { 0.52, 0.75 },
}

-- Arm weapon (joint poses; Extend telescopes the segmented arm) -----------------
local GUARD_L = { LeftShoulder = E(42, 0, -10), LeftElbow = E(92, 0, 0) }
local function withGuard(joints)
	for k, v in GUARD_L do
		if joints[k] == nil then
			joints[k] = v
		end
	end
	return joints
end
A.PunchA = {
	Keys = {
		pose(
			0,
			withGuard({ RightShoulder = E(40, 0, 15), RightElbow = E(95, 0, 0), Waist = E(0, 18, 0) }),
			{ Extend = 0 }
		),
		pose(
			0.32,
			withGuard({
				RightShoulder = E(88, 0, 4),
				RightElbow = E(4, 0, 0),
				Waist = E(-4, -22, 0),
				RightHip = E(-10, 0, 0),
				LeftHip = E(15, 0, 0),
			}),
			{ Ease = "In", Extend = 0.7 }
		),
		pose(
			0.6,
			withGuard({ RightShoulder = E(80, 0, 6), RightElbow = E(12, 0, 0), Waist = E(-2, -18, 0) }),
			{ Extend = 0.4 }
		),
	},
	Trail = { 0.2, 0.45 },
}
A.PunchB = {
	Keys = {
		pose(
			0,
			withGuard({ RightShoulder = E(20, 0, 30), RightElbow = E(100, 0, 0), Waist = E(0, 25, 0) }),
			{ Extend = 0 }
		),
		pose(
			0.34,
			withGuard({
				RightShoulder = E(115, 0, 10),
				RightElbow = E(30, 0, 0),
				Waist = E(-10, -20, 0),
				Root = CFrame.new(0, 0.15, 0),
			}),
			{ Ease = "In", Extend = 0.5 }
		),
		pose(
			0.6,
			withGuard({ RightShoulder = E(100, 0, 10), RightElbow = E(40, 0, 0), Waist = E(-6, -15, 0) }),
			{ Extend = 0.2 }
		),
	},
	Trail = { 0.2, 0.45 },
}
A.PunchC = {
	Keys = {
		pose(0, withGuard({ RightShoulder = E(40, 0, 15), RightElbow = E(95, 0, 0) }), { Extend = 0 }),
		pose(
			0.17,
			withGuard({ RightShoulder = E(88, 0, 4), RightElbow = E(4, 0, 0), Waist = E(0, -15, 0) }),
			{ Ease = "In", Extend = 0.6 }
		),
		pose(0.27, withGuard({ RightShoulder = E(50, 0, 12), RightElbow = E(80, 0, 0) }), { Extend = 0.1 }),
		pose(
			0.37,
			withGuard({ RightShoulder = E(90, 0, 2), RightElbow = E(2, 0, 0), Waist = E(0, -18, 0) }),
			{ Ease = "In", Extend = 0.7 }
		),
		pose(0.47, withGuard({ RightShoulder = E(50, 0, 12), RightElbow = E(80, 0, 0) }), { Extend = 0.1 }),
		pose(
			0.58,
			withGuard({
				RightShoulder = E(92, 0, 0),
				RightElbow = E(0, 0, 0),
				Waist = E(-6, -25, 0),
				RightHip = E(-10, 0, 0),
			}),
			{ Ease = "In", Extend = 1 }
		),
	},
	Trail = { 0.12, 0.65 },
}
A.PunchSlam = {
	Keys = {
		pose(0, {
			RightShoulder = E(160, 0, 10),
			RightElbow = E(30, 0, 0),
			LeftShoulder = E(150, 0, -10),
			Waist = E(10, 0, 0),
		}, { Extend = 0 }),
		pose(0.45, {
			RightShoulder = E(170, 0, 5),
			RightElbow = E(10, 0, 0),
			LeftShoulder = E(160, 0, -5),
			Waist = E(14, 0, 0),
			Root = CFrame.new(0, 0.2, 0),
		}, { Ease = "Out", Extend = 0.2 }),
		pose(0.58, {
			RightShoulder = E(40, 0, 5),
			RightElbow = E(0, 0, 0),
			LeftShoulder = E(30, 0, -5),
			Waist = E(-30, 0, 0),
			Root = CFrame.new(0, -0.5, 0),
			RightHip = E(40, 0, 0),
			LeftHip = E(40, 0, 0),
			RightKnee = E(-60, 0, 0),
			LeftKnee = E(-60, 0, 0),
		}, { Ease = "In", Extend = 1 }),
		pose(0.8, {
			RightShoulder = E(45, 0, 5),
			RightElbow = E(10, 0, 0),
			Waist = E(-25, 0, 0),
			Root = CFrame.new(0, -0.4, 0),
		}, { Extend = 0.6 }),
	},
	Trail = { 0.45, 0.65 },
}
A.DashPunch = {
	Keys = {
		pose(
			0,
			withGuard({ RightShoulder = E(30, 0, 20), RightElbow = E(100, 0, 0), Waist = E(-20, 25, 0) }),
			{ Extend = 0 }
		),
		pose(
			0.4,
			withGuard({
				RightShoulder = E(90, 0, 0),
				RightElbow = E(0, 0, 0),
				Waist = E(-25, -20, 0),
				Root = E(-12, 0, 0),
				RightHip = E(40, 0, 0),
				LeftHip = E(-30, 0, 0),
			}),
			{ Ease = "In", Extend = 1 }
		),
		pose(
			0.7,
			withGuard({ RightShoulder = E(85, 0, 0), RightElbow = E(5, 0, 0), Waist = E(-15, -15, 0) }),
			{ Extend = 0.7 }
		),
	},
	Trail = { 0.25, 0.6 },
}

-- Guns ------------------------------------------------------------------------
local AIM_R = W(V(0.55, 0.4, -2.05), V(0, 1, 0), V(0, 0, -1))
local AIM_L = W(V(-0.55, 0.4, -2.05), V(0, 1, 0), V(0, 0, -1))
local KICK_R = W(V(0.55, 0.62, -1.85), V(0, 0.92, 0.38), V(0, 0.38, -0.92))
local KICK_L = W(V(-0.55, 0.62, -1.85), V(0, 0.92, 0.38), V(0, 0.38, -0.92))
local LOW_R = AnimationLibrary.Holds.DualPistols.Weapon.Liz
local LOW_L = AnimationLibrary.Holds.DualPistols.Weapon.Patty
A.PistolShotR = {
	Keys = {
		{ T = 0, Weapon = { Liz = AIM_R, Patty = LOW_L }, Joints = { Waist = E(0, -15, 0) } },
		{ T = 0.15, Ease = "Out", Weapon = { Liz = AIM_R, Patty = LOW_L }, Recoil = "Liz" },
		{ T = 0.3, Ease = "Out", Weapon = { Liz = KICK_R, Patty = LOW_L } },
		{ T = 0.7, Weapon = { Liz = AIM_R, Patty = LOW_L } },
	},
	BlendIn = 0.05,
}
A.PistolShotL = {
	Keys = {
		{ T = 0, Weapon = { Liz = LOW_R, Patty = AIM_L }, Joints = { Waist = E(0, 15, 0) } },
		{ T = 0.15, Ease = "Out", Weapon = { Liz = LOW_R, Patty = AIM_L }, Recoil = "Patty" },
		{ T = 0.3, Ease = "Out", Weapon = { Liz = LOW_R, Patty = KICK_L } },
		{ T = 0.7, Weapon = { Liz = LOW_R, Patty = AIM_L } },
	},
	BlendIn = 0.05,
}
do
	local keys = { { T = 0, Weapon = { Liz = AIM_R, Patty = AIM_L } } }
	for i = 0, 5 do
		local t = 0.05 + i * 0.12
		local right = i % 2 == 0
		table.insert(keys, {
			T = t,
			Weapon = {
				Liz = right and AIM_R or KICK_R:Lerp(AIM_R, 0.6),
				Patty = right and KICK_L:Lerp(AIM_L, 0.6) or AIM_L,
			},
			Recoil = right and "Liz" or "Patty",
		})
		table.insert(
			keys,
			{ T = t + 0.05, Weapon = { Liz = right and KICK_R or AIM_R, Patty = right and AIM_L or KICK_L } }
		)
	end
	table.insert(keys, { T = 0.85, Weapon = { Liz = AIM_R, Patty = AIM_L } })
	A.PistolRapid = { Keys = keys, BlendIn = 0.06 }
end
A.PistolCharged = {
	Keys = {
		{
			T = 0,
			Weapon = { Liz = AIM_R, Patty = AIM_L },
			Joints = { Waist = E(-4, 0, 0), RightHip = E(10, 0, 0), LeftHip = E(-10, 0, 0) },
		},
		{
			T = 0.58,
			Weapon = { Liz = AIM_R * CFrame.new(0.1, 0, 0), Patty = AIM_L * CFrame.new(-0.1, 0, 0) },
			Recoil = "Both",
		},
		{ T = 0.66, Ease = "Out", Weapon = { Liz = KICK_R, Patty = KICK_L }, Joints = { Waist = E(6, 0, 0) } },
		{ T = 0.9, Weapon = { Liz = AIM_R, Patty = AIM_L } },
	},
}

-- Drill -----------------------------------------------------------------------
local DRILL_FORWARD = W(V(0.6, -0.35, -1.85), V(0, 1, -0.05), V(0, -0.05, -1))
A.DrillThrust = {
	Keys = {
		{
			T = 0,
			Weapon = { Main = W(V(1.0, -0.6, -0.2), V(0, 1, 0), V(0, 0, -1)) },
			Joints = { Waist = E(0, 22, 0) },
			Drill = true,
		},
		{
			T = 0.35,
			Ease = "In",
			Weapon = { Main = DRILL_FORWARD },
			Joints = { Waist = E(-10, -15, 0), RightHip = E(25, 0, 0), RightKnee = E(-25, 0, 0) },
			Drill = true,
		},
		{ T = 0.75, Weapon = { Main = DRILL_FORWARD * CFrame.new(0, 0, 0.1) }, Drill = true },
	},
}
A.DrillGrind = {
	Keys = {
		{
			T = 0,
			Weapon = { Main = DRILL_FORWARD },
			Joints = { Waist = E(-8, -10, 0), RightHip = E(25, 0, 0), LeftHip = E(-10, 0, 0) },
			Drill = true,
		},
		{ T = 0.3, Weapon = { Main = DRILL_FORWARD * CFrame.new(0.04, 0.03, 0) }, Drill = true },
		{ T = 0.5, Weapon = { Main = DRILL_FORWARD * CFrame.new(-0.04, -0.03, 0) }, Drill = true },
		{ T = 0.7, Weapon = { Main = DRILL_FORWARD * CFrame.new(0.03, -0.02, 0) }, Drill = true },
		{ T = 0.85, Weapon = { Main = DRILL_FORWARD }, Drill = true },
	},
}
A.DrillDash = {
	Keys = {
		{
			T = 0,
			Weapon = { Main = DRILL_FORWARD },
			Joints = { Waist = E(-25, -5, 0), Root = E(-12, 0, 0), RightHip = E(35, 0, 0), LeftHip = E(-30, 0, 0) },
			Drill = true,
		},
		{
			T = 0.6,
			Weapon = { Main = DRILL_FORWARD },
			Joints = { Waist = E(-25, -5, 0), Root = E(-12, 0, 0) },
			Drill = true,
		},
	},
}

-- Spider rig (arms gesture, legs animated by the weapon animator) -----------------
A.SpiderStrikeA = {
	Keys = {
		pose(
			0,
			{ RightShoulder = E(30, 0, 30), LeftShoulder = E(30, 0, -30), Waist = E(5, 0, 0) },
			{ Spider = "Rear" }
		),
		pose(
			0.38,
			{ RightShoulder = E(60, 0, 15), LeftShoulder = E(60, 0, -15), Waist = E(-12, 0, 0) },
			{ Ease = "In", Spider = "StrikeFront" }
		),
		pose(0.7, { Waist = E(-6, 0, 0) }, { Spider = "StrikeFront" }),
	},
	Trail = { 0.25, 0.5 },
}
A.SpiderStrikeB = {
	Keys = {
		pose(0, { Waist = E(5, 10, 0) }, { Spider = "Rear" }),
		pose(0.28, { Waist = E(-10, -10, 0) }, { Ease = "In", Spider = "StrikeRight" }),
		pose(0.42, { Waist = E(0, 10, 0) }, { Spider = "Rear" }),
		pose(0.56, { Waist = E(-10, 10, 0) }, { Ease = "In", Spider = "StrikeLeft" }),
	},
	Trail = { 0.2, 0.62 },
}
A.SpiderSweep = {
	Keys = {
		pose(
			0,
			{ Waist = E(0, 35, 0), RightShoulder = E(20, 0, 50), LeftShoulder = E(20, 0, -50) },
			{ Spider = "Raised" }
		),
		pose(
			0.47,
			{ Waist = E(-6, -45, 0), RightShoulder = E(20, 0, 60), LeftShoulder = E(20, 0, -60) },
			{ Ease = "In", Spider = "Sweep" }
		),
		pose(0.75, { Waist = E(-3, -30, 0) }, { Spider = "Sweep" }),
	},
	Trail = { 0.3, 0.65 },
}
A.SpiderSlam = {
	Keys = {
		pose(
			0,
			{ Waist = E(10, 0, 0), RightShoulder = E(120, 0, 20), LeftShoulder = E(120, 0, -20) },
			{ Spider = "Raised" }
		),
		pose(
			0.5,
			{ Waist = E(14, 0, 0), RightShoulder = E(150, 0, 20), LeftShoulder = E(150, 0, -20) },
			{ Spider = "Raised" }
		),
		pose(0.6, {
			Waist = E(-25, 0, 0),
			Root = CFrame.new(0, -0.45, 0),
			RightShoulder = E(40, 0, 20),
			LeftShoulder = E(40, 0, -20),
			RightKnee = E(-45, 0, 0),
			LeftKnee = E(-45, 0, 0),
			RightHip = E(30, 0, 0),
			LeftHip = E(30, 0, 0),
		}, { Ease = "In", Spider = "Slam" }),
		pose(0.85, { Waist = E(-15, 0, 0), Root = CFrame.new(0, -0.3, 0) }, { Spider = "Slam" }),
	},
	Trail = { 0.5, 0.66 },
}

-- Ability gestures (left hand released from two-handed weapons) -----------------
local FREE_LEFT = { Left = true }
A.CastSpell = {
	Keys = {
		pose(
			0,
			{ LeftShoulder = E(40, 0, -30), LeftElbow = E(60, 0, 0), Waist = E(0, 15, 0) },
			{ Release = FREE_LEFT }
		),
		pose(
			0.4,
			{ LeftShoulder = E(95, 0, -5), LeftElbow = E(5, 0, 0), LeftWrist = E(-30, 0, 0), Waist = E(-6, -20, 0) },
			{ Ease = "Out", Release = FREE_LEFT }
		),
		pose(
			0.8,
			{ LeftShoulder = E(90, 0, -5), LeftElbow = E(10, 0, 0), Waist = E(-4, -15, 0) },
			{ Release = FREE_LEFT }
		),
	},
}
A.Roar = {
	Keys = {
		pose(0, { Waist = E(-15, 0, 0), Neck = E(-15, 0, 0), LeftShoulder = E(20, 0, -20) }, { Release = FREE_LEFT }),
		pose(
			0.35,
			{ Waist = E(12, 0, 0), Neck = E(20, 0, 0), LeftShoulder = E(30, 0, -75), LeftElbow = E(30, 0, 0) },
			{ Ease = "Out", Release = FREE_LEFT }
		),
		pose(0.8, { Waist = E(8, 0, 0), Neck = E(10, 0, 0), LeftShoulder = E(25, 0, -60) }, { Release = FREE_LEFT }),
	},
}
A.GolemSlam = {
	Keys = {
		pose(0, {
			RightShoulder = E(150, 0, 15),
			LeftShoulder = E(150, 0, -15),
			RightElbow = E(30, 0, 0),
			LeftElbow = E(30, 0, 0),
			Waist = E(10, 0, 0),
		}, { Release = { Left = true, Right = true } }),
		pose(0.7, {
			RightShoulder = E(170, 0, 10),
			LeftShoulder = E(170, 0, -10),
			RightElbow = E(15, 0, 0),
			LeftElbow = E(15, 0, 0),
			Waist = E(16, 0, 0),
			Root = CFrame.new(0, 0.15, 0),
		}, { Release = { Left = true, Right = true } }),
		pose(0.8, {
			RightShoulder = E(30, 0, 10),
			LeftShoulder = E(30, 0, -10),
			Waist = E(-35, 0, 0),
			Root = CFrame.new(0, -0.6, 0),
			RightHip = E(45, 0, 0),
			LeftHip = E(45, 0, 0),
			RightKnee = E(-70, 0, 0),
			LeftKnee = E(-70, 0, 0),
		}, { Ease = "In", Release = { Left = true, Right = true } }),
		pose(
			0.95,
			{ Waist = E(-25, 0, 0), Root = CFrame.new(0, -0.5, 0) },
			{ Release = { Left = true, Right = true } }
		),
	},
}
A.Pulse = {
	Keys = {
		pose(
			0,
			{ LeftShoulder = E(30, 0, -20), RightShoulder = E(30, 0, 20), Waist = E(-10, 0, 0) },
			{ Release = { Left = true } }
		),
		pose(
			0.35,
			{ LeftShoulder = E(20, 0, -95), RightShoulder = E(20, 0, 95), Waist = E(10, 0, 0) },
			{ Ease = "Out", Release = { Left = true } }
		),
	},
}
A.Heal = {
	Keys = {
		pose(0, { LeftShoulder = E(60, 0, -10), LeftElbow = E(60, 0, 0) }, { Release = FREE_LEFT }),
		pose(
			0.4,
			{ LeftShoulder = E(150, 0, -15), LeftElbow = E(10, 0, 0), Neck = E(15, 0, 0) },
			{ Ease = "Out", Release = FREE_LEFT }
		),
		pose(0.85, { LeftShoulder = E(140, 0, -15), LeftElbow = E(15, 0, 0) }, { Release = FREE_LEFT }),
	},
}
A.Blink = {
	Keys = {
		pose(0, {
			Waist = E(-20, 0, 0),
			Root = CFrame.new(0, -0.3, 0),
			RightKnee = E(-40, 0, 0),
			LeftKnee = E(-40, 0, 0),
			RightHip = E(30, 0, 0),
			LeftHip = E(30, 0, 0),
		}),
		pose(0.5, { Waist = E(-5, 0, 0) }, { Ease = "Out" }),
	},
}
A.Hurt = {
	Keys = {
		pose(0, { Waist = E(18, 0, 6), Neck = E(14, 0, 0), Root = CFrame.new(0, 0, 0.15) }, { Ease = "Out" }),
		pose(0.6, { Waist = E(6, 0, 2) }),
	},
	BlendIn = 0.03,
}

AnimationLibrary.Actions = A :: { [string]: Action }

-- Spider leg pose presets. Hip = { lift, yawForward }, Knee = { bend } in degrees, mirrored per
-- side by the animator. "Front" applies to the four front legs, "Right"/"Left" to one side.
AnimationLibrary.SpiderPoses = {
	Rest = { Hip = { 0, 0 }, Knee = { 0 } },
	Rear = { Front = { Hip = { 25, -20 }, Knee = { 25 } }, Hip = { 6, -5 }, Knee = { 6 } },
	StrikeFront = { Front = { Hip = { -15, 45 }, Knee = { -30 } }, Hip = { -4, 8 }, Knee = { -6 } },
	StrikeRight = { Right = { Hip = { -10, 40 }, Knee = { -25 } } },
	StrikeLeft = { Left = { Hip = { -10, 40 }, Knee = { -25 } } },
	Raised = { Hip = { 35, 0 }, Knee = { 30 } },
	Sweep = { Hip = { -10, 32 }, Knee = { -15 } },
	Slam = { Hip = { -35, 10 }, Knee = { -40 } },
}

function AnimationLibrary.GetHold(style: string?): Hold
	return AnimationLibrary.Holds[style or ""] or AnimationLibrary.Holds.SwordOneHand
end

function AnimationLibrary.GetAction(name: string?): Action?
	return name and AnimationLibrary.Actions[name] or nil
end

return AnimationLibrary
