--[[
	Soul's Death Scythe (evolved variant)
	Bone-white segmented shaft with knuckled joints, a dark reinforced head with a red eye, and a
	broad silver crescent with a serrated red edge.

	Components: Shaft, Grips, Head, Blade
]]

local BladeKit = require(script.Parent.Parent.BladeKit)

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle

	local bottom = -d.GripFromBottom
	local top = d.ShaftLength - d.GripFromBottom
	local r = d.ShaftDiameter

	-- Segmented bone shaft ----------------------------------------------------------
	local shaft = kit:Group("Shaft")
	local segments = d.Segments
	local segLength = (top - bottom) / segments
	for i = 0, segments - 1 do
		local y0 = bottom + i * segLength
		local y1 = y0 + segLength
		kit:Cylinder("Bone", Vector3.new(0, y0 + 0.08, 0), Vector3.new(0, y1 - 0.08, 0), r, p.Shaft, Enum.Material.SmoothPlastic, shaft)
		if i < segments - 1 then
			-- Knuckled joint: two balls side by side, like a bone joint.
			kit:Ball("Knuckle", r * 1.35, Vector3.new(r * 0.32, y1, 0), p.Joint, Enum.Material.SmoothPlastic, shaft)
			kit:Ball("Knuckle", r * 1.35, Vector3.new(-r * 0.32, y1, 0), p.Joint, Enum.Material.SmoothPlastic, shaft)
		end
	end
	kit:Ball("BoneEnd", r * 1.5, Vector3.new(r * 0.3, bottom, 0), p.Joint, Enum.Material.SmoothPlastic, shaft)
	kit:Ball("BoneEnd", r * 1.5, Vector3.new(-r * 0.3, bottom, 0), p.Joint, Enum.Material.SmoothPlastic, shaft)

	local grips = kit:Group("Grips")
	for i = 0, 3 do
		local y = -0.4 + i * 0.27
		kit:Cylinder("Wrap", Vector3.new(0, y - 0.07, 0), Vector3.new(0, y + 0.07, 0), r + 0.08, p.Grip, Enum.Material.Fabric, grips)
	end

	-- Head ---------------------------------------------------------------------------
	local head = kit:Group("Head")
	kit:Block("Housing", Vector3.new(0.55, 1.05, 0.95), CFrame.new(0, top + 0.2, -0.15) * CFrame.Angles(math.rad(-10), 0, 0), p.Accent, Enum.Material.Metal, head)
	kit:Block("Crown", Vector3.new(0.6, 0.18, 0.7), CFrame.new(0, top + 0.78, -0.05), p.Joint, Enum.Material.SmoothPlastic, head)
	for _, side in { -1, 1 } do
		local x = side * 0.29
		kit:Cylinder("EyeRim", Vector3.new(x, top + 0.2, -0.2), Vector3.new(x + side * 0.04, top + 0.2, -0.2), 0.58, p.Shaft, Enum.Material.SmoothPlastic, head)
		kit:Ball("Eye", 0.36, Vector3.new(x + side * 0.08, top + 0.2, -0.2), p.Eye, Enum.Material.SmoothPlastic, head)
	end

	-- Blade --------------------------------------------------------------------------
	local blade = kit:Group("Blade")
	local L = d.BladeLength
	local spine, _, edge = BladeKit.Crescent(kit, blade, {
		Spine = {
			Vector3.new(0, top + 0.62, -0.35),
			Vector3.new(0, top + 1.5, -L * 0.35),
			Vector3.new(0, top + 1.25, -L * 0.82),
			Vector3.new(0, top - 0.7, -L),
		},
		Segments = 8,
		Width = d.BladeWidth,
		Taper = 0.75,
		BaseWidthScale = 0.75,
		EdgeSide = -1,
		Split = 0.62,
		ZigZag = 0.13,
		SpineColor = p.Blade,
		EdgeColor = p.Edge,
		SpineThickness = d.Thickness,
		EdgeThickness = d.Thickness * 0.72,
		EdgeMaterial = Enum.Material.SmoothPlastic,
	})

	kit:Attachment("SupportGrip", handle, CFrame.new(0, 2.2, 0))
	kit:Attachment("TrailA", handle, CFrame.new(spine[2]:Lerp(edge[2], 0.5)))
	kit:Attachment("TrailB", handle, CFrame.new(spine[#spine - 1]:Lerp(edge[#edge - 1], 0.4)))
	kit:Attachment("Impact", handle, CFrame.new(edge[#edge]))
end
