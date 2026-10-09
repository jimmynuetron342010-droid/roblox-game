--[[
	Segmented Arm (Asura-inspired original weapon)
	Mounted on the right forearm: an armored sleeve of blocky plates, then a chain of cube
	segments with dark joints and red eye studs, ending in a large blocky fist. Each segment is a
	Motor6D so punches can telescope the arm outward (AnimatorCore "Extend").

	Model space: origin at the wrist joint, +Y up the forearm, -Y out past the hand.
	Components: Sleeve, Segments, Fist
]]

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightForearm")
	local kit, handle = unit.Kit, unit.Handle

	-- Forearm sleeve: four plates around the lower arm plus a cuff.
	local sleeve = kit:Group("Sleeve")
	local plates = {
		{ Vector3.new(1.16, 0.95, 0.14), CFrame.new(0, 0.48, -0.56) },
		{ Vector3.new(1.16, 0.95, 0.14), CFrame.new(0, 0.48, 0.56) },
		{ Vector3.new(0.14, 0.95, 1.0), CFrame.new(0.58, 0.48, 0) },
		{ Vector3.new(0.14, 0.95, 1.0), CFrame.new(-0.58, 0.48, 0) },
	}
	for _, plate in plates do
		kit:Block("Plate", plate[1], plate[2], p.Block, Enum.Material.SmoothPlastic, sleeve)
	end
	kit:Block("Cuff", Vector3.new(1.28, 0.16, 1.28), CFrame.new(0, 0.02, 0), p.Dark, Enum.Material.Metal, sleeve)
	kit:Block("CuffTop", Vector3.new(1.28, 0.12, 1.28), CFrame.new(0, 0.98, 0), p.Dark, Enum.Material.Metal, sleeve)
	kit:Cylinder("SleeveEye", Vector3.new(0, 0.55, -0.62), Vector3.new(0, 0.55, -0.68), 0.26, p.Eye, Enum.Material.SmoothPlastic, sleeve)

	-- Segments chained with Motor6Ds (each extends along -Y when the arm telescopes).
	local segmentsGroup = kit:Group("Segments")
	local size = d.SegmentSize
	local spacing = size * 0.92
	local previous: BasePart = handle
	local y = -0.55
	for i = 1, d.Segments do
		local s = size * (1 + (i - 1) * 0.06)
		local joint = kit:Block("Joint", Vector3.new(s * 0.62, spacing * 0.5, s * 0.62), CFrame.new(0, y + spacing * 0.45, 0), p.Joint, Enum.Material.Metal, segmentsGroup)
		local cube = kit:Block("Segment", Vector3.new(s, s * 0.9, s), CFrame.new(0, y, 0), p.Block, Enum.Material.SmoothPlastic, segmentsGroup)
		kit:Reweld(joint, cube)
		local eye = kit:Cylinder("Eye", Vector3.new(0, y, -s / 2 - 0.01), Vector3.new(0, y, -s / 2 - 0.05), s * 0.32, p.Eye, Enum.Material.SmoothPlastic, segmentsGroup)
		kit:Reweld(eye, cube)
		local trim = kit:Block("Trim", Vector3.new(s * 1.04, s * 0.12, s * 1.04), CFrame.new(0, y - s * 0.3, 0), p.Dark, Enum.Material.Metal, segmentsGroup)
		kit:Reweld(trim, cube)
		kit:Motor("Segment" .. i, previous, cube, CFrame.new(0, y + spacing * 0.5, 0))
		previous = cube
		y -= spacing
	end

	-- Fist.
	local fistGroup = kit:Group("Fist")
	local f = d.FistSize
	local fy = y - f * 0.2
	local fist = kit:Block("Fist", Vector3.new(f * 1.05, f, f * 0.95), CFrame.new(0, fy, 0), p.Block, Enum.Material.SmoothPlastic, fistGroup)
	for k = 0, 3 do
		local knuckle = kit:Block("Knuckle", Vector3.new(f * 0.24, f * 0.3, f * 0.3), CFrame.new(-f * 0.39 + k * f * 0.26, fy - f * 0.5, -f * 0.25), p.Dark, Enum.Material.Metal, fistGroup)
		kit:Reweld(knuckle, fist)
	end
	local thumb = kit:Block("Thumb", Vector3.new(f * 0.3, f * 0.55, f * 0.35), CFrame.new(-f * 0.6, fy - f * 0.1, -f * 0.2), p.Block, Enum.Material.SmoothPlastic, fistGroup)
	kit:Reweld(thumb, fist)
	local eye = kit:Cylinder("FistEye", Vector3.new(0, fy + f * 0.1, -f * 0.48), Vector3.new(0, fy + f * 0.1, -f * 0.52), f * 0.3, p.Eye, Enum.Material.SmoothPlastic, fistGroup)
	kit:Reweld(eye, fist)
	kit:Motor("Segment" .. (d.Segments + 1), previous, fist, CFrame.new(0, fy + f * 0.5, 0))

	local trailA = Instance.new("Attachment")
	trailA.Name = "TrailA"
	trailA.CFrame = fist.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(-f * 0.45, fy, 0))
	trailA.Parent = fist
	local trailB = Instance.new("Attachment")
	trailB.Name = "TrailB"
	trailB.CFrame = fist.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(f * 0.45, fy, 0))
	trailB.Parent = fist
	local impact = Instance.new("Attachment")
	impact.Name = "Impact"
	impact.CFrame = fist.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(0, fy - f * 0.55, 0))
	impact.Parent = fist
end
