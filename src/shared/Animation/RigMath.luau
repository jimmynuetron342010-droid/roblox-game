--[[
	RigMath
	Pure CFrame math for procedural animation on R15 rigs:
	  * forward kinematics from Motor6D C0 * Transform * C1^-1 (no physics step needed)
	  * shortest-arc rotations
	  * analytic two-bone IK (shoulder -> elbow -> wrist) with a pole vector
	Works on real characters and on PreviewRig models alike.
]]

local RigMath = {}

local EPS = 1e-5

-- Rotation taking unit vector `from` to unit vector `to` (shortest arc).
function RigMath.RotationBetween(from: Vector3, to: Vector3): CFrame
	local a, b = from.Unit, to.Unit
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 1 - EPS then
		return CFrame.new()
	end
	if dot < -1 + EPS then
		local axis = math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis
		axis = a:Cross(axis).Unit
		return CFrame.fromAxisAngle(axis, math.pi)
	end
	return CFrame.fromAxisAngle(a:Cross(b).Unit, math.acos(dot))
end

-- World CFrame of a motor's Part1 given Part0's world CFrame.
function RigMath.ChildWorld(part0World: CFrame, motor: Motor6D, transform: CFrame?): CFrame
	return part0World * motor.C0 * (transform or motor.Transform) * motor.C1:Inverse()
end

export type ArmJoints = {
	Shoulder: Motor6D,
	Elbow: Motor6D,
	Wrist: Motor6D,
	Grip: CFrame, -- grip attachment CFrame inside the hand
}

export type ArmSolution = {
	Shoulder: CFrame,
	Elbow: CFrame,
	Wrist: CFrame,
	Hand: CFrame, -- resulting hand world CFrame
	Reached: boolean,
}

--[[
	Solves an arm so that the hand's grip frame matches `gripTarget` (world).
	`torsoWorld` is the UpperTorso world CFrame (after the Waist transform this frame).
	`pole` is a world-space hint for where the elbow should point.
]]
function RigMath.SolveArm(torsoWorld: CFrame, arm: ArmJoints, gripTarget: CFrame, pole: Vector3): ArmSolution
	local shoulder, elbow, wrist = arm.Shoulder, arm.Elbow, arm.Wrist

	-- Desired hand frame and the wrist pivot that hand implies.
	local handTarget = gripTarget * arm.Grip:Inverse()
	local wristTarget = (handTarget * wrist.C1).Position

	-- Bone vectors in their parent joint spaces (Transform = identity).
	local upperRest = (shoulder.C1:Inverse() * elbow.C0).Position
	local lowerRest = (elbow.C1:Inverse() * wrist.C0).Position
	local a, b = upperRest.Magnitude, lowerRest.Magnitude

	local shoulderFrame = torsoWorld * shoulder.C0
	local s = shoulderFrame.Position
	local toTarget = wristTarget - s
	local distance = toTarget.Magnitude
	local reached = distance <= a + b and distance >= math.abs(a - b)
	local d = math.clamp(distance, math.abs(a - b) + 1e-3, a + b - 1e-3)
	local dir = distance > EPS and toTarget / distance or Vector3.new(0, -1, 0)

	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local poleDir = pole - dir * pole:Dot(dir)
	if poleDir.Magnitude < EPS then
		poleDir = Vector3.new(0, -1, 0) - dir * (-dir.Y)
		if poleDir.Magnitude < EPS then
			poleDir = Vector3.zAxis
		end
	end
	poleDir = poleDir.Unit
	local elbowPos = s + dir * (a * cosA) + poleDir * (a * sinA)
	local wristPos = s + dir * d

	-- Shoulder: rotate the rest upper bone onto (elbow - shoulder).
	local upperWanted = shoulderFrame:VectorToObjectSpace(elbowPos - s)
	local shoulderT = RigMath.RotationBetween(upperRest, upperWanted)
	local upperWorld = shoulderFrame * shoulderT * shoulder.C1:Inverse()

	-- Elbow: rotate the rest lower bone onto (wrist - elbow).
	local elbowFrame = upperWorld * elbow.C0
	local lowerWanted = elbowFrame:VectorToObjectSpace(wristPos - elbowFrame.Position)
	local elbowT = RigMath.RotationBetween(lowerRest, lowerWanted)
	local lowerWorld = elbowFrame * elbowT * elbow.C1:Inverse()

	-- Wrist: orient the hand exactly (rotation only).
	local wristFrame = lowerWorld * wrist.C0
	local wristT = (wristFrame:Inverse() * handTarget * wrist.C1).Rotation
	local handWorld = wristFrame * wristT * wrist.C1:Inverse()

	return {
		Shoulder = shoulderT,
		Elbow = elbowT,
		Wrist = wristT,
		Hand = handWorld,
		Reached = reached,
	}
end

-- Euler-degree helper used by animation data: { rx, ry, rz } -> rotation CFrame.
function RigMath.Euler(values: { number }?): CFrame
	if not values then
		return CFrame.new()
	end
	return CFrame.Angles(math.rad(values[1] or 0), math.rad(values[2] or 0), math.rad(values[3] or 0))
end

-- { x, y, z, rx, ry, rz } -> CFrame
function RigMath.Frame(values: { number }): CFrame
	return CFrame.new(values[1] or 0, values[2] or 0, values[3] or 0)
		* CFrame.Angles(math.rad(values[4] or 0), math.rad(values[5] or 0), math.rad(values[6] or 0))
end

-- Builds a weapon frame from a grip position, a shaft direction (+Y) and the blade-facing
-- direction (-Z). All in the same space.
function RigMath.WeaponFrame(position: Vector3, shaft: Vector3, facing: Vector3): CFrame
	local y = shaft.Unit
	local f = facing - y * facing:Dot(y)
	if f.Magnitude < EPS then
		f = Vector3.new(0, 0, -1) - y * (-y.Z)
		if f.Magnitude < EPS then
			f = Vector3.xAxis
		end
	end
	local z = -f.Unit
	local x = y:Cross(z).Unit
	return CFrame.fromMatrix(position, x, y, z)
end

return RigMath
