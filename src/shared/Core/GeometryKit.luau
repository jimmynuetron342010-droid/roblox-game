--[[
	GeometryKit
	Procedural modeling toolkit used by every weapon builder, cosmetic and map prop.

	Everything is described in *model space* (studs, relative to the model origin, usually the grip)
	and converted to world space with `Origin`. A uniform `Scale` multiplies every position and size.
	All parts are welded to `Root` (Weld with explicit C0, deterministic), are massless, and do not
	collide — weapons and cosmetics should never fight the character's physics.

	Curved shapes (scythe blades, crescents) are built from real triangles: each triangle is two
	WedgeParts (the standard Roblox "3D triangle" technique), so blades have exact silhouettes with no
	gaps. This is still primitive geometry: for production-grade smooth bevels, replace a component
	with a MeshPart from Blender (see docs/BLENDER_WORKFLOW.md and WeaponBuilder overrides).
]]

export type Options = {
	Model: Model,
	Root: BasePart?,
	Origin: CFrame?,
	Scale: number?,
	Anchored: boolean?, -- true for ViewportFrame previews / static props
	NoWelds: boolean?,
	DefaultMaterial: Enum.Material?,
	CastShadow: boolean?,
}

local GeometryKit = {}
GeometryKit.__index = GeometryKit

local EPSILON = 1e-4

function GeometryKit.new(options: Options)
	local self = setmetatable({}, GeometryKit)
	self.Model = options.Model
	self.Root = options.Root
	self.Origin = options.Origin or CFrame.new()
	self.Scale = options.Scale or 1
	self.Anchored = options.Anchored == true
	self.NoWelds = options.NoWelds == true or self.Anchored
	self.DefaultMaterial = options.DefaultMaterial or Enum.Material.SmoothPlastic
	self.CastShadow = options.CastShadow ~= false
	self.PartCount = 0
	return self
end

-- Model-space point/CFrame -> world.
function GeometryKit:ToWorldPoint(p: Vector3): Vector3
	return self.Origin * (p * self.Scale)
end

function GeometryKit:ToWorldCFrame(cf: CFrame): CFrame
	return self.Origin * (CFrame.new(cf.Position * self.Scale) * cf.Rotation)
end

function GeometryKit:Group(name: string, parent: Instance?): Model
	local group = Instance.new("Model")
	group.Name = name
	group.Parent = parent or self.Model
	return group
end

function GeometryKit:Weld(part: BasePart, to: BasePart?)
	local anchor = to or self.Root
	if self.NoWelds or not anchor or anchor == part then
		return nil
	end
	local weld = Instance.new("Weld")
	weld.Name = "Weld"
	weld.Part0 = anchor
	weld.Part1 = part
	weld.C0 = anchor.CFrame:Inverse() * part.CFrame
	weld.C1 = CFrame.new()
	weld.Parent = part
	return weld
end

export type PartSpec = {
	Name: string,
	Class: string?, -- "Part" | "WedgePart" | "CornerWedgePart"
	Shape: Enum.PartType?,
	Size: Vector3, -- model space (scaled)
	CFrame: CFrame?, -- model space
	WorldCFrame: CFrame?, -- already in world space (used by triangles)
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	Parent: Instance?,
	WeldTo: BasePart?,
	NoScaleSize: boolean?,
}

function GeometryKit:Part(spec: PartSpec): BasePart
	local part = Instance.new(spec.Class or "Part") :: BasePart
	part.Name = spec.Name
	if spec.Shape and part:IsA("Part") then
		(part :: Part).Shape = spec.Shape
	end
	local size = spec.NoScaleSize and spec.Size or spec.Size * self.Scale
	part.Size = Vector3.new(math.max(size.X, 0.01), math.max(size.Y, 0.01), math.max(size.Z, 0.01))
	part.CFrame = spec.WorldCFrame or self:ToWorldCFrame(spec.CFrame or CFrame.new())
	part.Color = spec.Color or Color3.fromRGB(128, 128, 128)
	part.Material = spec.Material or self.DefaultMaterial
	part.Transparency = spec.Transparency or 0
	part.Reflectance = spec.Reflectance or 0
	part.Anchored = self.Anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = self.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = spec.Parent or self.Model
	self.PartCount += 1
	if part ~= self.Root then
		self:Weld(part, spec.WeldTo)
	end
	return part
end

function GeometryKit:Block(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, parent: Instance?): BasePart
	return self:Part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material, Parent = parent })
end

function GeometryKit:Ball(name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?, parent: Instance?): BasePart
	return self:Part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(position),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- Orthonormal frame whose `axis` (X/Y/Z) points along `direction`.
function GeometryKit.FrameAlong(origin: Vector3, direction: Vector3, axis: string?, upHint: Vector3?): CFrame
	local dir = direction.Magnitude > EPSILON and direction.Unit or Vector3.yAxis
	local hint = upHint or Vector3.yAxis
	if math.abs(dir:Dot(hint)) > 0.98 then
		hint = math.abs(dir:Dot(Vector3.xAxis)) < 0.9 and Vector3.xAxis or Vector3.zAxis
	end
	local a = axis or "X"
	if a == "X" then
		local up = (hint - dir * hint:Dot(dir)).Unit
		return CFrame.fromMatrix(origin, dir, up)
	elseif a == "Y" then
		local right = hint:Cross(dir).Unit
		if right.Magnitude < EPSILON then
			right = Vector3.xAxis
		end
		local back = right:Cross(dir).Unit
		return CFrame.fromMatrix(origin, right, dir, back)
	else -- Z axis along direction (LookVector is -Z, so look *against* direction)
		return CFrame.lookAt(origin, origin - dir, hint)
	end
end

-- Cylinder spanning p0 -> p1 (Roblox cylinders run along their X axis).
function GeometryKit:Cylinder(name: string, p0: Vector3, p1: Vector3, diameter: number, color: Color3, material: Enum.Material?, parent: Instance?): BasePart
	local length = (p1 - p0).Magnitude
	local cf = GeometryKit.FrameAlong((p0 + p1) / 2, p1 - p0, "X")
	return self:Part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(math.max(length, 0.02), diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- Rectangular bar spanning p0 -> p1 with the given cross-section; `up` orients the width.
function GeometryKit:Bar(name: string, p0: Vector3, p1: Vector3, width: number, depth: number, color: Color3, up: Vector3?, material: Enum.Material?, parent: Instance?): BasePart
	local length = (p1 - p0).Magnitude
	local cf = GeometryKit.FrameAlong((p0 + p1) / 2, p1 - p0, "Y", up)
	return self:Part({
		Name = name,
		Size = Vector3.new(width, math.max(length, 0.02), depth),
		CFrame = cf,
		Color = color,
		Material = material,
		Parent = parent,
	})
end

--[[
	Triangle from three model-space points, `thickness` thick, centered on the triangle plane.
	Built from two WedgeParts. Returns both wedges (either may be nil for degenerate triangles).
]]
function GeometryKit:Triangle(
	name: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?
): (BasePart?, BasePart?)
	-- Work in world space so the Origin rotation is applied exactly once.
	local wa, wb, wc = self:ToWorldPoint(a), self:ToWorldPoint(b), self:ToWorldPoint(c)
	local ab, ac, bc = wb - wa, wc - wa, wc - wb
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make `bc` the longest edge (opposite vertex `a`).
	if abd > acd and abd > bcd then
		wc, wa = wa, wc
	elseif acd > bcd and acd > abd then
		wa, wb = wb, wa
	end
	ab, ac, bc = wb - wa, wc - wa, wc - wb
	local normal = ac:Cross(ab)
	if normal.Magnitude < EPSILON or bc.Magnitude < EPSILON then
		return nil, nil
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local t = thickness * self.Scale
	local w1, w2
	local depth1 = math.abs(ab:Dot(back))
	local depth2 = math.abs(ac:Dot(back))
	if height > EPSILON and depth1 > EPSILON then
		w1 = self:Part({
			Name = name,
			Class = "WedgePart",
			Size = Vector3.new(t, height, depth1),
			NoScaleSize = true,
			WorldCFrame = CFrame.fromMatrix((wa + wb) / 2, right, up, back),
			Color = color,
			Material = material,
			Parent = parent,
		})
	end
	if height > EPSILON and depth2 > EPSILON then
		w2 = self:Part({
			Name = name,
			Class = "WedgePart",
			Size = Vector3.new(t, height, depth2),
			NoScaleSize = true,
			WorldCFrame = CFrame.fromMatrix((wa + wc) / 2, -right, up, -back),
			Color = color,
			Material = material,
			Parent = parent,
		})
	end
	return w1, w2
end

-- Quad a-b-c-d (in order around the outline) as two triangles.
function GeometryKit:Quad(name: string, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thickness: number, color: Color3, material: Enum.Material?, parent: Instance?)
	self:Triangle(name, a, b, c, thickness, color, material, parent)
	self:Triangle(name, a, c, d, thickness, color, material, parent)
end

-- Fills the surface between two polylines with matching sample counts.
function GeometryKit:Strip(name: string, lineA: { Vector3 }, lineB: { Vector3 }, thickness: number, color: Color3, material: Enum.Material?, parent: Instance?)
	assert(#lineA == #lineB, "Strip: polylines must have the same number of points")
	for i = 1, #lineA - 1 do
		self:Quad(name, lineA[i], lineA[i + 1], lineB[i + 1], lineB[i], thickness, color, material, parent)
	end
end

-- Isosceles spike: flat triangular blade from `base` to `tip`, `width` wide across `side`.
function GeometryKit:Spike(name: string, base: Vector3, tip: Vector3, width: number, thickness: number, color: Color3, side: Vector3?, material: Enum.Material?, parent: Instance?)
	local axis = tip - base
	local s = side or GeometryKit.FrameAlong(base, axis, "Y").RightVector
	s = (s - axis.Unit * s:Dot(axis.Unit)).Unit
	local left = base - s * (width / 2)
	local right = base + s * (width / 2)
	return self:Triangle(name, left, right, tip, thickness, color, material, parent)
end

-- Ring of short cylinders (torus approximation) around `frame`'s Y axis.
function GeometryKit:Ring(name: string, frame: CFrame, radius: number, tube: number, segments: number, color: Color3, material: Enum.Material?, parent: Instance?)
	local points = {}
	for i = 0, segments do
		local angle = (i / segments) * math.pi * 2
		table.insert(points, frame * Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	for i = 1, segments do
		local p0, p1 = points[i], points[i + 1]
		local dir = (p1 - p0)
		-- Extend slightly so neighboring segments overlap without visible seams.
		local extend = dir.Unit * tube * 0.25
		self:Cylinder(name, p0 - extend, p1 + extend, tube, color, material, parent)
	end
end

-- Attachment on `part` at a model-space CFrame.
function GeometryKit:Attachment(name: string, part: BasePart, cf: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = part.CFrame:Inverse() * self:ToWorldCFrame(cf)
	attachment.Parent = part
	return attachment
end

-- Motor6D from part0 to part1 using their current world CFrames (for animated sub-parts).
function GeometryKit:Motor(name: string, part0: BasePart, part1: BasePart, pivot: CFrame?): Motor6D
	-- Remove any static weld first so the motor alone drives the part.
	local existing = part1:FindFirstChild("Weld")
	if existing then
		existing:Destroy()
	end
	local pivotWorld = pivot and self:ToWorldCFrame(pivot) or part1.CFrame
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:Inverse() * pivotWorld
	motor.C1 = part1.CFrame:Inverse() * pivotWorld
	motor.Transform = CFrame.new()
	motor.Parent = part1
	return motor
end

-- Re-welds `part` to `newAnchor` (used when a sub-assembly should follow an animated part).
function GeometryKit:Reweld(part: BasePart, newAnchor: BasePart)
	local existing = part:FindFirstChild("Weld")
	if existing then
		existing:Destroy()
	end
	return self:Weld(part, newAnchor)
end

--[[
	Curve helpers (pure math, model space)
]]

-- Quadratic/cubic Bezier sampling.
function GeometryKit.Bezier(points: { Vector3 }, t: number): Vector3
	local pts = table.clone(points)
	local n = #pts
	while n > 1 do
		for i = 1, n - 1 do
			pts[i] = pts[i]:Lerp(pts[i + 1], t)
		end
		n -= 1
	end
	return pts[1]
end

function GeometryKit.SampleBezier(points: { Vector3 }, samples: number): { Vector3 }
	local out = {}
	for i = 0, samples do
		table.insert(out, GeometryKit.Bezier(points, i / samples))
	end
	return out
end

-- Offsets a planar polyline sideways (within the plane with normal `planeNormal`).
-- `widths[i]` (or a number) is the offset distance at each point; positive = left of travel.
function GeometryKit.Offset(line: { Vector3 }, widths: { number } | number, planeNormal: Vector3): { Vector3 }
	local out = {}
	local n = #line
	for i = 1, n do
		local prev = line[math.max(i - 1, 1)]
		local nextPoint = line[math.min(i + 1, n)]
		local tangent = (nextPoint - prev)
		if tangent.Magnitude < EPSILON then
			tangent = Vector3.yAxis
		end
		local side = planeNormal:Cross(tangent.Unit).Unit
		local w = type(widths) == "number" and widths or (widths :: { number })[i]
		table.insert(out, line[i] + side * w)
	end
	return out
end

return GeometryKit
