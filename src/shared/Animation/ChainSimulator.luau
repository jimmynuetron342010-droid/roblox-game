--[[
	ChainSimulator
	Verlet rope driving a ChainKit chain's Motor6D.Transform values, so chain weapons hang, sway
	with walking and whip through swings like linked metal. Purely cosmetic and client-side.
]]

local RigMath = require(script.Parent.RigMath)

local ChainSimulator = {}
ChainSimulator.__index = ChainSimulator

ChainSimulator.Gravity = Vector3.new(0, -90, 0) -- softened so the chain reads well at game scale
ChainSimulator.Damping = 0.985
ChainSimulator.Iterations = 6

export type Simulator = {
	Motors: { Motor6D },
	Points: { Vector3 },
	Previous: { Vector3 },
	Spacing: { number },
}

-- `motors` must be ordered from the anchor outward (ChainKit order).
function ChainSimulator.new(motors: { Motor6D })
	local self = setmetatable({}, ChainSimulator)
	table.sort(motors, function(a, b)
		return (a:GetAttribute("ChainIndex") or 0) < (b:GetAttribute("ChainIndex") or 0)
	end)
	self.Motors = motors
	self.Points = {}
	self.Previous = {}
	self.Spacing = {}
	for i, motor in motors do
		self.Spacing[i] = motor:GetAttribute("Spacing") or 0.4
	end
	self.Initialized = false
	return self
end

-- Joint-space rest direction of every link is +Y (ChainKit pivots are built along +Y).
local REST = Vector3.yAxis

-- Places the rope along its rest pose (used on first update / after teleports).
function ChainSimulator:Reset(anchorWorld: CFrame)
	local frame = anchorWorld
	local points = { frame.Position }
	for i, motor in self.Motors do
		local joint = frame * motor.C0
		local tip = joint * (REST * self.Spacing[i])
		table.insert(points, tip)
		frame = joint * motor.C1:Inverse()
	end
	self.Points = points
	self.Previous = table.clone(points)
	self.Initialized = true
end

-- `anchorWorld` = world CFrame of the part the first link hangs from (usually the Handle).
-- `impulse` (optional) adds velocity to the outer half of the chain (attack whips).
-- `floorY` (optional) keeps links above the ground so chains pile up instead of sinking.
function ChainSimulator:Step(anchorWorld: CFrame, dt: number, impulse: Vector3?, floorY: number?)
	if not self.Initialized then
		self:Reset(anchorWorld)
	end
	local points, previous = self.Points, self.Previous
	local count = #points
	local firstJoint = anchorWorld * self.Motors[1].C0
	points[1] = firstJoint.Position
	previous[1] = points[1]

	local dtc = math.clamp(dt, 1 / 240, 1 / 30)
	for i = 2, count do
		local p = points[i]
		local velocity = (p - previous[i]) * ChainSimulator.Damping
		if impulse and i > count / 2 then
			velocity += impulse * dtc * ((i - count / 2) / (count / 2))
		end
		previous[i] = p
		points[i] = p + velocity + ChainSimulator.Gravity * dtc * dtc
	end
	for _ = 1, ChainSimulator.Iterations do
		for i = 1, count - 1 do
			local a, b = points[i], points[i + 1]
			local delta = b - a
			local length = delta.Magnitude
			if length > 1e-5 then
				local rest = self.Spacing[i]
				local diff = (length - rest) / length
				if i == 1 then
					points[i + 1] = b - delta * diff
				else
					points[i] = a + delta * diff * 0.5
					points[i + 1] = b - delta * diff * 0.5
				end
			end
		end
	end
	if floorY then
		local limit = floorY + 0.15
		for i = 2, count do
			local p = points[i]
			if p.Y < limit then
				points[i] = Vector3.new(p.X, limit, p.Z)
				-- Ground friction: kill most horizontal sliding.
				local prev = previous[i]
				previous[i] = Vector3.new(p.X + (prev.X - p.X) * 0.4, limit, p.Z + (prev.Z - p.Z) * 0.4)
			end
		end
	end
	-- Teleport / huge-stretch guard.
	if (points[count] - points[1]).Magnitude > 3 * count then
		self:Reset(anchorWorld)
	end
end

-- Writes Motor6D.Transform so each link points at the next simulated point.
function ChainSimulator:Apply(anchorWorld: CFrame)
	local frame = anchorWorld
	for i, motor in self.Motors do
		local joint = frame * motor.C0
		local desired = self.Points[i + 1] - joint.Position
		local transform = CFrame.new()
		if desired.Magnitude > 1e-4 then
			transform = RigMath.RotationBetween(REST, joint:VectorToObjectSpace(desired))
		end
		motor.Transform = transform
		frame = joint * transform * motor.C1:Inverse()
	end
end

return ChainSimulator
