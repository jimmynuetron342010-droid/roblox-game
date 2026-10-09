--[[
	Ragnarok (compact scythe form)
	Short bone shaft, a skull head, a dark hooked blade with a white edge and a pick spike.

	Components: Shaft, Grips, Skull, Blade
]]

local BladeKit = require(script.Parent.Parent.BladeKit)

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle

	local bottom = -d.GripFromBottom
	local top = d.ShaftLength - d.GripFromBottom
	local r = d.ShaftDiameter

	local shaft = kit:Group("Shaft")
	local segments = 4
	local segLength = (top - bottom) / segments
	for i = 0, segments - 1 do
		local y0 = bottom + i * segLength
		kit:Cylinder(
			"Bone",
			Vector3.new(0, y0 + 0.06, 0),
			Vector3.new(0, y0 + segLength - 0.06, 0),
			r,
			p.Shaft,
			Enum.Material.SmoothPlastic,
			shaft
		)
		kit:Ball("Knuckle", r * 1.3, Vector3.new(0, y0 + segLength, 0), p.Joint, Enum.Material.SmoothPlastic, shaft)
	end
	kit:Ball("BoneEnd", r * 1.5, Vector3.new(0, bottom, 0), p.Joint, Enum.Material.SmoothPlastic, shaft)

	local grips = kit:Group("Grips")
	for i = 0, 2 do
		local y = -0.3 + i * 0.3
		kit:Cylinder(
			"Wrap",
			Vector3.new(0, y - 0.08, 0),
			Vector3.new(0, y + 0.08, 0),
			r + 0.08,
			p.Blade,
			Enum.Material.Fabric,
			grips
		)
	end

	-- Skull head -----------------------------------------------------------------------
	local skull = kit:Group("Skull")
	local sy = top + 0.35
	kit:Ball("Cranium", 0.9, Vector3.new(0, sy + 0.1, -0.05), p.Skull, Enum.Material.SmoothPlastic, skull)
	kit:Block(
		"Jaw",
		Vector3.new(0.5, 0.28, 0.5),
		CFrame.new(0, sy - 0.32, -0.12),
		p.Skull,
		Enum.Material.SmoothPlastic,
		skull
	)
	for _, side in { -1, 1 } do
		kit:Ball("Socket", 0.24, Vector3.new(side * 0.17, sy + 0.12, -0.4), p.Blade, Enum.Material.SmoothPlastic, skull)
		kit:Ball("Glint", 0.09, Vector3.new(side * 0.17, sy + 0.12, -0.5), p.Eye, Enum.Material.SmoothPlastic, skull)
	end
	for i = -1, 1 do
		kit:Block(
			"Tooth",
			Vector3.new(0.09, 0.12, 0.06),
			CFrame.new(i * 0.12, sy - 0.2, -0.38),
			p.Blade,
			Enum.Material.SmoothPlastic,
			skull
		)
	end

	-- Hooked blade + pick ------------------------------------------------------------------
	local blade = kit:Group("Blade")
	local L = d.BladeLength
	local spine, _, edge = BladeKit.Crescent(kit, blade, {
		Spine = {
			Vector3.new(0, sy + 0.35, -0.35),
			Vector3.new(0, sy + 0.85, -L * 0.45),
			Vector3.new(0, sy + 0.4, -L * 0.85),
			Vector3.new(0, sy - 0.9, -L),
		},
		Segments = 7,
		Width = d.BladeWidth,
		Taper = 0.8,
		BaseWidthScale = 0.85,
		EdgeSide = -1,
		Split = 0.6,
		ZigZag = 0.1,
		SpineColor = p.Blade,
		EdgeColor = p.Edge,
		SpineThickness = d.Thickness,
		EdgeThickness = d.Thickness * 0.7,
	})
	kit:Spike(
		"Pick",
		Vector3.new(0, sy + 0.1, 0.35),
		Vector3.new(0, sy - 0.25, 1.45),
		0.42,
		d.Thickness,
		p.Edge,
		Vector3.yAxis,
		Enum.Material.Metal,
		blade
	)

	kit:Attachment("SupportGrip", handle, CFrame.new(0, 1.35, 0))
	kit:Attachment("TrailA", handle, CFrame.new(spine[2]:Lerp(edge[2], 0.5)))
	kit:Attachment("TrailB", handle, CFrame.new(spine[#spine - 1]:Lerp(edge[#edge - 1], 0.4)))
	kit:Attachment("Impact", handle, CFrame.new(edge[#edge]))
end
