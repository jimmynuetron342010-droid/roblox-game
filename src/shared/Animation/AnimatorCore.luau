--[[
	AnimatorCore
	Procedural animation for one R15 character holding a weapon. Shared by:
	  * the client AnimationController (every visible armed character, every frame)
	  * PosePreview (ViewportFrame portraits and the offline render tests)

	Per update it writes Motor6D.Transform for the body, solves both arms with IK onto the weapon
	grips (or applies joint poses), and animates the weapon's own moving parts (chain links,
	drill bit, pistol slides, spider legs, segmented arm).

	Layers (bottom -> top):
	  1. Locomotion: breathing idle, loose walk (hip sway, torso counter-twist, springy arms),
	     run, airborne
	  2. Hold style: weapon pose / free-arm pose (AnimationLibrary.Holds)
	  3. Action: keyframed attack or gesture, blended in/out over the layers below
	Everything is blended with `Presence` so drawing/holstering eases in and out of Roblox's
	default Animate script.
]]

local AnimationLibrary = require(script.Parent.AnimationLibrary)
local ChainSimulator = require(script.Parent.ChainSimulator)
local RigMath = require(script.Parent.RigMath)

local AnimatorCore = {}
AnimatorCore.__index = AnimatorCore

local BODY_JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
}
AnimatorCore.BodyJoints = BODY_JOINTS

local IDENTITY = CFrame.new()
local E = RigMath.Euler
local rad = math.rad

-- ── Small damped spring for secondary motion ────────────────────────────────
local Spring = {}
Spring.__index = Spring
function Spring.new(frequency: number, damping: number)
	return setmetatable({ X = 0, V = 0, F = frequency, D = damping }, Spring)
end
function Spring:Step(target: number, dt: number): number
	local f = self.F * 2 * math.pi
	local accel = f * f * (target - self.X) - 2 * self.D * f * self.V
	self.V += accel * dt
	self.X += self.V * dt
	return self.X
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local EASES = {
	Linear = function(x)
		return x
	end,
	In = function(x)
		return x * x
	end,
	Out = function(x)
		return 1 - (1 - x) * (1 - x)
	end,
	InOut = smoothstep,
}

-- ── Construction ──────────────────────────────────────────────────────────────
function AnimatorCore.new(character: Model)
	local self = setmetatable({}, AnimatorCore)
	self.Character = character
	self.Root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Motors = {} :: { [string]: Motor6D }
	for joint, partName in BODY_JOINTS do
		local part = character:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(joint)
		if motor and motor:IsA("Motor6D") then
			self.Motors[joint] = motor
		end
	end
	self.Valid = self.Root ~= nil
		and self.Motors.Root ~= nil
		and self.Motors.Waist ~= nil
		and self.Motors.RightShoulder ~= nil
	local function gripCF(handName, attachmentName)
		local hand = character:FindFirstChild(handName)
		local attachment = hand and hand:FindFirstChild(attachmentName)
		if attachment and attachment:IsA("Attachment") then
			return attachment.CFrame
		end
		return CFrame.new(0, -0.15, 0) * CFrame.Angles(rad(-90), 0, 0)
	end
	self.RightGrip = gripCF("RightHand", "RightGripAttachment")
	self.LeftGrip = gripCF("LeftHand", "LeftGripAttachment")

	self.Time = 0
	self.Phase = 0
	self.WalkWeight = 0
	self.RunWeight = 0
	self.AirWeight = 0
	self.Presence = 0
	self.Springs = {
		ArmR = Spring.new(2.2, 0.35),
		ArmL = Spring.new(2.2, 0.35),
		HeadYaw = Spring.new(1.6, 0.5),
		Lean = Spring.new(1.4, 0.6),
	}
	self.Weapon = nil
	self.Hold = nil
	self.Action = nil
	self.Chains = {}
	self.DrillAngle = 0
	self.Recoil = {}
	-- When uploaded animation tracks drive the body (WeaponConfig.AnimationIds /
	-- AnimationLibrary.UploadedIds), only the weapon's own moving parts stay procedural.
	self.MuteBody = false
	return self
end

-- Binds (or clears) the equipped weapon model and its hold style.
function AnimatorCore:SetWeapon(weaponModel: Model?, holdStyle: string?)
	self.Weapon = weaponModel
	self.Hold = weaponModel and AnimationLibrary.GetHold(holdStyle) or nil
	self.HoldStyle = holdStyle
	self.Chains = {}
	self.Units = {}
	if not weaponModel then
		return
	end
	for _, unit in weaponModel:GetChildren() do
		if unit:IsA("Model") then
			local handle = unit:FindFirstChild("Handle")
			if handle then
				local info = {
					Name = unit.Name,
					Model = unit,
					Handle = handle,
					Mount = unit:GetAttribute("Mount"),
					MountJoint = handle:FindFirstChild("MountJoint"),
					Support = handle:FindFirstChild("SupportGrip"),
					Slide = unit:FindFirstChild("Slide", true),
					BitSpin = unit:FindFirstChild("BitSpin", true),
					Segments = {},
					Hips = {},
					Knees = {},
				}
				local chainMotors = {}
				for _, descendant in unit:GetDescendants() do
					if descendant:IsA("Motor6D") then
						local name = descendant.Name
						if name == "ChainJoint" then
							table.insert(chainMotors, descendant)
						elseif string.sub(name, 1, 7) == "Segment" then
							info.Segments[tonumber(string.sub(name, 8)) or 0] = descendant
						elseif string.sub(name, 1, 3) == "Hip" then
							info.Hips[tonumber(string.sub(name, 4)) or 0] = descendant
						elseif string.sub(name, 1, 4) == "Knee" then
							info.Knees[tonumber(string.sub(name, 5)) or 0] = descendant
						end
					end
				end
				if #chainMotors > 0 then
					info.Chain = ChainSimulator.new(chainMotors)
				end
				table.insert(self.Units, info)
			end
		end
	end
end

-- Starts a keyframed action lasting `duration` seconds.
function AnimatorCore:PlayAction(name: string, duration: number)
	local action = AnimationLibrary.GetAction(name)
	if not action then
		return false
	end
	self.Action = { Name = name, Def = action, Start = self.Time, Duration = math.max(duration, 0.05) }
	return true
end

function AnimatorCore:StopAction()
	self.Action = nil
end

-- Pushes the outer half of any simulated chain (whip at the strike of a chain swing).
function AnimatorCore:AddChainImpulse(impulse: Vector3, duration: number)
	self.ExternalImpulse = impulse
	self.ExternalImpulseUntil = self.Time + duration
end

function AnimatorCore:IsTrailActive(): boolean
	local action = self.Action
	if not action or not action.Def.Trail then
		return false
	end
	local u = (self.Time - action.Start) / action.Duration
	return u >= action.Def.Trail[1] and u <= action.Def.Trail[2]
end

-- ── Pose evaluation ───────────────────────────────────────────────────────────
type Pose = { [string]: CFrame }

local function getJoint(pose: Pose, name: string): CFrame
	return pose[name] or IDENTITY
end

function AnimatorCore:_locomotion(dt: number, ctx): Pose
	local hold = self.Hold
	local loco = hold and hold.Locomotion or { ArmSwing = 1, Bounce = 0.14, HipSway = 7, Twist = 9, Lean = 5 }
	local stance = hold and hold.Stance or 0.5
	local speed = ctx.Speed or 0
	local grounded = ctx.Grounded ~= false

	local k = 1 - math.exp(-dt * 8)
	self.WalkWeight += (smoothstep(speed / 12) - self.WalkWeight) * k
	self.RunWeight += (smoothstep((speed - 17) / 6) - self.RunWeight) * k
	self.AirWeight += ((grounded and 0 or 1) - self.AirWeight) * (1 - math.exp(-dt * 10))
	local stride = 6.2 + self.RunWeight * 2.5
	self.Phase = (self.Phase + dt * (speed / stride) * math.pi * 2) % (math.pi * 2)

	local t, phase = self.Time, self.Phase
	local w, r, air = self.WalkWeight, self.RunWeight, self.AirWeight
	local s, c = math.sin(phase), math.cos(phase)
	local breath = math.sin(t * 1.7)
	local idleShift = math.sin(t * 0.45)

	local hipAmp = 26 + r * 22
	local kneeAmp = 34 + r * 46
	local swingR = math.max(0, c)
	local swingL = math.max(0, -c)

	local pose: Pose = {}
	local bob = (loco.Bounce * (1 + r)) * 0.5 * (math.cos(2 * phase) - 1) * w
	pose.Root = CFrame.new(0, bob - 0.06 * stance * (1 - w) - air * 0.1, 0)
		* E({ -3 * r, (loco.Twist * 0.5) * s * w, loco.HipSway * s * w * (1 - r * 0.5) + 1.2 * idleShift * (1 - w) })
	local lean = self.Springs.Lean:Step(-(loco.Lean * w + 9 * r), dt)
	pose.Waist = E({ lean + breath * 1.4 * (1 - w), -loco.Twist * s * w, -loco.HipSway * 0.5 * s * w })
	local headYaw = self.Springs.HeadYaw:Step(loco.Twist * 0.6 * s * w, dt)
	pose.Neck = E({ -breath * 1.0 * (1 - w) - lean * 0.4, headYaw, 0 })

	local spread = 5 + stance * 5
	local idleKnee = 6 * stance
	pose.RightHip = E({ hipAmp * s * w + idleKnee * (1 - w) + air * 25, 0, spread * (1 - w) })
	pose.LeftHip = E({ -hipAmp * s * w + idleKnee * (1 - w) - air * 8, 0, -spread * (1 - w) })
	pose.RightKnee = E({ -(kneeAmp * swingR * w) - idleKnee * 1.6 * (1 - w) - 6 * w - air * 45, 0, 0 })
	pose.LeftKnee = E({ -(kneeAmp * swingL * w) - idleKnee * 1.6 * (1 - w) - 6 * w - air * 30, 0, 0 })
	pose.RightAnkle =
		E({ (kneeAmp * swingR * w) * 0.35 + idleKnee * 0.6 * (1 - w) - (hipAmp * s * w) * 0.3, 0, -spread * (1 - w) })
	pose.LeftAnkle =
		E({ (kneeAmp * swingL * w) * 0.35 + idleKnee * 0.6 * (1 - w) + (hipAmp * s * w) * 0.3, 0, spread * (1 - w) })

	-- Loose, slightly lagging arm swing (springs give the overshoot).
	local armTarget = (32 + r * 25) * loco.ArmSwing * w
	local armR = self.Springs.ArmR:Step(-armTarget * math.sin(phase - 0.35), dt)
	local armL = self.Springs.ArmL:Step(armTarget * math.sin(phase - 0.35), dt)
	pose.RightShoulder = E({ armR + breath * 1.5 * (1 - w) + air * 20, 0, 6 + air * 25 })
	pose.LeftShoulder = E({ armL + breath * 1.5 * (1 - w) + air * 20, 0, -6 - air * 25 })
	pose.RightElbow = E({ 14 + (10 + r * 60) * w * (0.6 + 0.4 * math.abs(s)), 0, 0 })
	pose.LeftElbow = E({ 14 + (10 + r * 60) * w * (0.6 + 0.4 * math.abs(s)), 0, 0 })
	return pose
end

-- Hold joints are offsets layered on top of locomotion (stance twist, guard arms, ...).
local function applyHoldJoints(pose: Pose, joints: { [string]: CFrame }?, weight: number)
	if not joints then
		return
	end
	for name, value in joints do
		local base = pose[name] or IDENTITY
		pose[name] = IDENTITY:Lerp(value, weight) * base
	end
end

-- Samples an action at normalized time u. Returns (weight, sample).
function AnimatorCore:_sampleAction(u: number)
	local def = self.Action.Def
	local keys = def.Keys
	local blendIn = def.BlendIn or 0.08
	local blendOut = def.BlendOut or 0.22
	local weight = math.min(smoothstep(u / blendIn), smoothstep((1 - u) / blendOut))
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if u >= keys[i].T and u < keys[i + 1].T then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	if u >= keys[#keys].T then
		a, b = keys[#keys], keys[#keys]
	end
	local span = b.T - a.T
	local alpha = span > 0 and math.clamp((u - a.T) / span, 0, 1) or 1
	alpha = (EASES[b.Ease or "Linear"] or EASES.Linear)(alpha)
	return weight, a, b, alpha
end

-- ── Update ────────────────────────────────────────────────────────────────────
--[[
	ctx = {
		Speed: number,            -- horizontal speed (studs/s)
		Grounded: boolean,
		Present: boolean,         -- weapon drawn & animator should drive the rig
		RootCFrame: CFrame?,      -- HumanoidRootPart CFrame (defaults to the part's CFrame)
	}
]]
function AnimatorCore:Update(dt: number, ctx)
	if not self.Valid then
		return
	end
	self.Time += dt
	local presenceTarget = (ctx.Present and self.Hold) and 1 or 0
	self.Presence += (presenceTarget - self.Presence) * (1 - math.exp(-dt * 10))
	if self.Presence < 0.01 and presenceTarget == 0 then
		self.Presence = 0
		return
	end

	local pose = self:_locomotion(dt, ctx)
	local hold = self.Hold
	if hold then
		applyHoldJoints(pose, hold.Joints, 1)
		if hold.Run then
			applyHoldJoints(pose, hold.Run.Joints, self.RunWeight)
		end
	end

	-- Weapon targets from the hold (blended toward the run carry pose).
	local targets: { [string]: CFrame } = {}
	if hold and hold.Weapon then
		for unitName, frame in hold.Weapon do
			local target = frame
			local runFrame = hold.Run and hold.Run.Weapon and hold.Run.Weapon[unitName]
			if runFrame then
				target = target:Lerp(runFrame, self.RunWeight)
			end
			-- Subtle breathing sway on the weapon itself.
			local sway = math.sin(self.Time * 1.7) * (1 - self.WalkWeight)
			targets[unitName] = target * CFrame.Angles(rad(sway * 1.2), 0, rad(sway * 0.8))
		end
	end

	-- Action overlay.
	local release = {}
	local actionParams = {}
	if self.Action then
		local u = (self.Time - self.Action.Start) / self.Action.Duration
		if u >= 1 then
			self.Action = nil
		else
			local weight, a, b, alpha = self:_sampleAction(u)
			for name in BODY_JOINTS do
				local va = a.Joints and a.Joints[name]
				local vb = b.Joints and b.Joints[name]
				if va or vb then
					local base = getJoint(pose, name)
					local sample = (va or base):Lerp(vb or base, alpha)
					pose[name] = base:Lerp(sample, weight)
				end
			end
			for unitName, base in targets do
				local wa = a.Weapon and a.Weapon[unitName]
				local wb = b.Weapon and b.Weapon[unitName]
				if wa or wb then
					local sample = (wa or base):Lerp(wb or base, alpha)
					targets[unitName] = base:Lerp(sample, weight)
				end
			end
			for side in (b.Release or a.Release or {}) :: { [string]: boolean } do
				release[side] = weight > 0.3
			end
			actionParams.Extend = ((a.Extend or 0) + ((b.Extend or 0) - (a.Extend or 0)) * alpha) * weight
			actionParams.Spider = b.Spider or a.Spider
			actionParams.SpiderWeight = weight
			actionParams.Drill = (a.Drill or b.Drill) and weight > 0.2
			if b.Recoil and alpha > 0.5 then
				actionParams.Recoil = b.Recoil
			end
		end
	end
	if self.ExternalImpulse and self.Time < (self.ExternalImpulseUntil or 0) then
		actionParams.Impulse = self.ExternalImpulse
	end
	self.LastActionParams = actionParams

	-- Write body joints.
	local presence = self.Presence
	if not self.MuteBody then
		for name, motor in self.Motors do
			local value = pose[name]
			if value then
				motor.Transform = presence >= 0.999 and value or motor.Transform:Lerp(value, presence)
			end
		end
	end

	-- IK for hand-mounted weapon units.
	local rootCF = ctx.RootCFrame or self.Root.CFrame
	self.FloorY = ctx.FloorY or (rootCF.Y - (self.Root.Size.Y / 2 + (ctx.HipHeight or 2)))
	local lowerWorld = RigMath.ChildWorld(rootCF, self.Motors.Root)
	local torsoWorld = RigMath.ChildWorld(lowerWorld, self.Motors.Waist)
	if not self.MuteBody then
		self:_solveWeapon(torsoWorld, targets, release, presence)
	end
	self:_animateWeaponJoints(dt, torsoWorld, actionParams)
end

function AnimatorCore:_armJoints(side: string)
	local m = self.Motors
	return {
		Shoulder = m[side .. "Shoulder"],
		Elbow = m[side .. "Elbow"],
		Wrist = m[side .. "Wrist"],
		Grip = side == "Right" and self.RightGrip or self.LeftGrip,
	}
end

local function applyArm(arm, solution, presence: number)
	if presence >= 0.999 then
		arm.Shoulder.Transform = solution.Shoulder
		arm.Elbow.Transform = solution.Elbow
		arm.Wrist.Transform = solution.Wrist
	else
		arm.Shoulder.Transform = arm.Shoulder.Transform:Lerp(solution.Shoulder, presence)
		arm.Elbow.Transform = arm.Elbow.Transform:Lerp(solution.Elbow, presence)
		arm.Wrist.Transform = arm.Wrist.Transform:Lerp(solution.Wrist, presence)
	end
end

function AnimatorCore:_solveWeapon(torsoWorld: CFrame, targets: { [string]: CFrame }, release, presence: number)
	if not self.Units then
		return
	end
	local poleRight = torsoWorld:VectorToWorldSpace(Vector3.new(0.9, -1, 0.7))
	local poleLeft = torsoWorld:VectorToWorldSpace(Vector3.new(-0.9, -1, 0.7))
	local leftUsed = false
	for _, unit in self.Units do
		local target = targets[unit.Name]
		local mountJoint = unit.MountJoint
		if target and mountJoint and (unit.Mount == "RightHand" or unit.Mount == "LeftHand") then
			local side = unit.Mount == "RightHand" and "Right" or "Left"
			if not release[side] then
				local arm = self:_armJoints(side)
				if arm.Shoulder and arm.Elbow and arm.Wrist then
					local targetWorld = RigMath.ReachableGrip(torsoWorld, arm, torsoWorld * target)
					local solution =
						RigMath.SolveArm(torsoWorld, arm, targetWorld, side == "Right" and poleRight or poleLeft)
					applyArm(arm, solution, presence)
					-- Absorb any residual (unreachable target) on the weapon's own joint.
					mountJoint.Transform = (solution.Hand * mountJoint.C0):Inverse() * targetWorld
					unit.World = targetWorld
					if side == "Left" then
						leftUsed = true
					end
				end
			else
				mountJoint.Transform = IDENTITY
			end
		end
	end
	-- Support hand on the SupportGrip of two-handed weapons.
	local hold = self.Hold
	if hold and hold.Support and not leftUsed and not release.Left then
		for _, unit in self.Units do
			if unit.Name == hold.Support.Unit and unit.World and unit.Support then
				local arm = self:_armJoints("Left")
				if arm.Shoulder then
					local gripWorld = unit.World
						* unit.Support.CFrame
						* CFrame.Angles(0, rad(hold.Support.Twist or 0), 0)
					local solution = RigMath.SolveArm(torsoWorld, arm, gripWorld, poleLeft)
					applyArm(arm, solution, presence)
				end
			end
		end
	end
end

function AnimatorCore:_animateWeaponJoints(dt: number, torsoWorld: CFrame, params)
	if not self.Units then
		return
	end
	for _, unit in self.Units do
		-- Handle world for units that are not IK driven (back / forearm mounts).
		if not unit.World and unit.MountJoint then
			local part0 = unit.MountJoint.Part0
			local part0World = part0 and part0.CFrame or torsoWorld
			if part0 and part0.Name == "UpperTorso" then
				part0World = torsoWorld
			end
			unit.World = part0World * unit.MountJoint.C0 * unit.MountJoint.Transform
		end
		local handleWorld = unit.World or unit.Handle.CFrame

		if unit.Chain then
			unit.Chain:Step(handleWorld, dt, params.Impulse, self.FloorY)
			unit.Chain:Apply(handleWorld)
		end
		if unit.BitSpin then
			local spinning = params.Drill or (self.Character:GetAttribute("Drilling") == true)
			if spinning then
				self.DrillAngle = (self.DrillAngle + dt * 28) % (math.pi * 2)
				unit.BitSpin.Transform = CFrame.Angles(0, 0, self.DrillAngle)
			end
		end
		if unit.Slide then
			local recoil = self.Recoil[unit.Name] or 0
			if params.Recoil == unit.Name or params.Recoil == "Both" then
				recoil = 1
			end
			recoil = math.max(0, recoil - dt * 9)
			self.Recoil[unit.Name] = recoil
			unit.Slide.Transform = CFrame.new(0, 0, 0.28 * recoil)
		end
		if next(unit.Segments) then
			local extend = params.Extend or 0
			for _, motor in unit.Segments do
				motor.Transform = CFrame.new(0, -0.45 * extend, 0)
			end
		end
		if next(unit.Hips) then
			self:_animateSpider(unit, params)
		end
		unit.World = nil
	end
end

function AnimatorCore:_animateSpider(unit, params)
	local preset = AnimationLibrary.SpiderPoses[params.Spider or "Rest"] or AnimationLibrary.SpiderPoses.Rest
	local weight = params.SpiderWeight or 0
	for index, hip in unit.Hips do
		local knee = unit.Knees[index]
		local mirror = hip:GetAttribute("Side") or ((index % 2 == 1) and 1 or -1)
		local isFront = index <= 4
		local group = (isFront and preset.Front)
			or (mirror == 1 and preset.Right)
			or (mirror == -1 and preset.Left)
			or nil
		local hipOffset = (group and group.Hip) or preset.Hip or { 0, 0 }
		local kneeOffset = (group and group.Knee) or preset.Knee or { 0 }
		local idle = math.sin(self.Time * 2.1 + index * 0.9) * 5
		local lift = rad(idle + (hipOffset[1] or 0) * weight) * mirror
		local yaw = rad((hipOffset[2] or 0) * weight) * mirror
		hip.Transform = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, lift)
		if knee then
			knee.Transform = CFrame.Angles(0, 0, rad(idle * 0.6 + (kneeOffset[1] or 0) * weight) * mirror)
		end
	end
end

-- Restores every joint (call when the weapon is removed or the character is destroyed).
function AnimatorCore:Reset()
	for _, motor in self.Motors do
		motor.Transform = IDENTITY
	end
	self.Action = nil
	self.Presence = 0
end

return AnimatorCore
