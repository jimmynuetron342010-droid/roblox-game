--[[
	Maka's Death Scythe
	Long dark shaft with wrapped grips and metal collars, a reinforced head housing with the scythe's
	eye on both sides, and a long crescent blade: black spine, red serrated edge (zigzag boundary),
	spine teeth and a short counter-spike.

	Components: Shaft, Grips, Head, Blade, Details
]]

local BladeKit = require(script.Parent.Parent.BladeKit)

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle

	local bottom = -d.GripFromBottom
	local top = d.ShaftLength - d.GripFromBottom
	local r = d.ShaftDiameter

	-- Shaft ---------------------------------------------------------------------
	local shaft = kit:Group("Shaft")
	kit:Cylinder(
		"Shaft",
		Vector3.new(0, bottom + 0.2, 0),
		Vector3.new(0, top - 0.1, 0),
		r,
		p.Shaft,
		Enum.Material.Metal,
		shaft
	)
	for _, y in { -1.15, 1.2, top - 0.75 } do
		kit:Cylinder(
			"Collar",
			Vector3.new(0, y - 0.1, 0),
			Vector3.new(0, y + 0.1, 0),
			r + 0.14,
			p.Metal,
			Enum.Material.Metal,
			shaft
		)
		kit:Cylinder(
			"CollarLip",
			Vector3.new(0, y - 0.14, 0),
			Vector3.new(0, y - 0.1, 0),
			r + 0.2,
			p.Metal,
			Enum.Material.Metal,
			shaft
		)
	end
	-- Pommel: cap + downward spike.
	kit:Cylinder(
		"PommelCap",
		Vector3.new(0, bottom, 0),
		Vector3.new(0, bottom + 0.28, 0),
		r + 0.16,
		p.Metal,
		Enum.Material.Metal,
		shaft
	)
	kit:Spike(
		"PommelSpike",
		Vector3.new(0, bottom, 0),
		Vector3.new(0, bottom - 0.6, 0),
		0.32,
		0.12,
		p.Metal,
		Vector3.zAxis,
		Enum.Material.Metal,
		shaft
	)
	kit:Spike(
		"PommelSpike",
		Vector3.new(0, bottom, 0),
		Vector3.new(0, bottom - 0.6, 0),
		0.32,
		0.12,
		p.Metal,
		Vector3.xAxis,
		Enum.Material.Metal,
		shaft
	)

	-- Grips (main hand at origin, support hand higher up) -------------------------
	local grips = kit:Group("Grips")
	for i = 0, 4 do
		local y = -0.5 + i * 0.25
		kit:Cylinder(
			"Wrap",
			Vector3.new(0, y - 0.07, 0),
			Vector3.new(0, y + 0.07, 0),
			r + 0.07,
			p.Grip,
			Enum.Material.Fabric,
			grips
		)
	end
	for i = 0, 3 do
		local y = 1.75 + i * 0.25
		kit:Cylinder(
			"Wrap",
			Vector3.new(0, y - 0.07, 0),
			Vector3.new(0, y + 0.07, 0),
			r + 0.07,
			p.Grip,
			Enum.Material.Fabric,
			grips
		)
	end

	-- Head housing + eye -----------------------------------------------------------
	local head = kit:Group("Head")
	kit:Block(
		"Housing",
		Vector3.new(0.5, 0.95, 0.85),
		CFrame.new(0, top + 0.12, -0.12) * CFrame.Angles(math.rad(-12), 0, 0),
		p.Metal,
		Enum.Material.Metal,
		head
	)
	kit:Block(
		"HousingCap",
		Vector3.new(0.42, 0.22, 0.6),
		CFrame.new(0, top + 0.66, -0.05),
		p.Shaft,
		Enum.Material.Metal,
		head
	)
	for _, side in { -1, 1 } do
		local x = side * 0.26
		kit:Cylinder(
			"EyeSocket",
			Vector3.new(x, top + 0.12, -0.18),
			Vector3.new(x + side * 0.05, top + 0.12, -0.18),
			0.62,
			p.Blade,
			Enum.Material.Metal,
			head
		)
		kit:Ball("Eye", 0.46, Vector3.new(x + side * 0.03, top + 0.12, -0.18), p.Eye, Enum.Material.SmoothPlastic, head)
		kit:Ball(
			"Pupil",
			0.22,
			Vector3.new(x + side * 0.17, top + 0.12, -0.2),
			p.Pupil,
			Enum.Material.SmoothPlastic,
			head
		)
	end
	-- Counter-spike behind the head.
	kit:Spike(
		"BackSpike",
		Vector3.new(0, top + 0.2, 0.25),
		Vector3.new(0, top + 0.55, 1.25),
		0.4,
		0.14,
		p.Blade,
		Vector3.yAxis,
		Enum.Material.Metal,
		head
	)

	-- Blade -----------------------------------------------------------------------
	local blade = kit:Group("Blade")
	local L = d.BladeLength
	local spine, _, edge = BladeKit.Crescent(kit, blade, {
		Spine = {
			Vector3.new(0, top + 0.5, -0.3),
			Vector3.new(0, top + 1.25, -L * 0.38),
			Vector3.new(0, top + 0.95, -L * 0.8),
			Vector3.new(0, top - 0.85, -L),
		},
		Segments = 9,
		Width = d.BladeWidth,
		Taper = 0.8,
		BaseWidthScale = 0.8,
		EdgeSide = -1,
		Split = 0.42,
		ZigZag = 0.16,
		SpineColor = p.Blade,
		EdgeColor = p.Edge,
		SpineThickness = d.Thickness,
		EdgeThickness = d.Thickness * 0.7,
		EdgeMaterial = Enum.Material.SmoothPlastic,
	})
	-- Serrated teeth along the back of the spine.
	for _, index in { 3, 4, 5 } do
		local a, b = spine[index], spine[index + 1]
		local tangent = (b - a).Unit
		local outward = Vector3.new(1, 0, 0):Cross(tangent).Unit
		kit:Spike(
			"SpineTooth",
			a,
			a + outward * 0.32 + tangent * 0.18,
			0.3,
			d.Thickness * 0.9,
			p.Blade,
			tangent,
			Enum.Material.Metal,
			blade
		)
	end

	-- Attachments -----------------------------------------------------------------
	local tip = edge[#edge]
	kit:Attachment("SupportGrip", handle, CFrame.new(0, 2.1, 0))
	kit:Attachment("TrailA", handle, CFrame.new(spine[2]:Lerp(edge[2], 0.5)))
	kit:Attachment("TrailB", handle, CFrame.new(spine[#spine - 1]:Lerp(edge[#edge - 1], 0.4)))
	kit:Attachment("Impact", handle, CFrame.new(tip))
end
