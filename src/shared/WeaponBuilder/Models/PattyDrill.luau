--[[
	Drill Form
	Cylindrical armored housing with white bands, a skull emblem and a rear cap; a tiered conical
	bit with two helical grooves spins on the Motor6D "BitSpin" while drilling.
	Model space: grip at origin, drill axis -Z (forward when the arm aims).
	Components: Housing, Bit
]]

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle
	local R = d.HousingRadius

	local housing = kit:Group("Housing")
	local z0, z1 = 0.75, 0.75 - d.HousingLength
	kit:Cylinder(
		"Housing",
		Vector3.new(0, 0.1, z0),
		Vector3.new(0, 0.1, z1),
		R * 2,
		p.Housing,
		Enum.Material.Metal,
		housing
	)
	kit:Cylinder(
		"RearCap",
		Vector3.new(0, 0.1, z0 + 0.14),
		Vector3.new(0, 0.1, z0),
		R * 1.5,
		p.Accent,
		Enum.Material.Metal,
		housing
	)
	for i = 0, d.Bands - 1 do
		local z = z0 - 0.15 - i * (d.HousingLength - 0.3) / math.max(d.Bands - 1, 1)
		kit:Cylinder(
			"Band",
			Vector3.new(0, 0.1, z + 0.06),
			Vector3.new(0, 0.1, z - 0.06),
			R * 2.12,
			p.Band,
			Enum.Material.SmoothPlastic,
			housing
		)
	end
	kit:Ball(
		"Skull",
		0.42,
		Vector3.new(R + 0.02, 0.1, z0 - d.HousingLength * 0.5),
		p.Skull,
		Enum.Material.SmoothPlastic,
		housing
	)
	for _, dz in { -0.08, 0.08 } do
		kit:Ball(
			"SkullEye",
			0.1,
			Vector3.new(R + 0.2, 0.15, z0 - d.HousingLength * 0.5 + dz),
			p.Accent,
			Enum.Material.SmoothPlastic,
			housing
		)
	end
	kit:Cylinder(
		"Collar",
		Vector3.new(0, 0.1, z1 + 0.04),
		Vector3.new(0, 0.1, z1 - 0.12),
		R * 1.9,
		p.BitDark,
		Enum.Material.Metal,
		housing
	)

	-- Bit: tiered cone + helical grooves, all welded to the first tier which spins.
	local bit = kit:Group("Bit")
	local tiers = 6
	local start = z1 - 0.12
	local tierLength = d.BitLength / tiers
	local root: BasePart? = nil
	local radiusAt = function(z)
		local t = math.clamp((start - z) / d.BitLength, 0, 1)
		return d.BitRadius * (1 - t) + 0.06
	end
	for i = 0, tiers - 1 do
		local za = start - i * tierLength
		local zb = za - tierLength
		local r = radiusAt(za + -tierLength * 0.5)
		local tier = kit:Cylinder(
			"Tier",
			Vector3.new(0, 0.1, za + 0.02),
			Vector3.new(0, 0.1, zb),
			r * 2,
			i % 2 == 0 and p.Bit or p.BitDark,
			Enum.Material.Metal,
			bit
		)
		if root then
			kit:Reweld(tier, root)
		else
			root = tier
		end
	end
	local rootPart = root :: BasePart
	for helix = 0, 1 do
		local segmentsPerHelix = 9
		local prev = nil
		for k = 0, segmentsPerHelix do
			local t = k / segmentsPerHelix
			local z = start - t * d.BitLength * 0.95
			local angle = helix * math.pi + t * math.pi * 3
			local r = radiusAt(z) + 0.03
			local point = Vector3.new(math.cos(angle) * r, 0.1 + math.sin(angle) * r, z)
			if prev then
				local groove = kit:Bar(
					"Groove",
					prev,
					point,
					0.09,
					0.07,
					p.Band:Lerp(p.Bit, 0.4),
					Vector3.zAxis,
					Enum.Material.Metal,
					bit
				)
				kit:Reweld(groove, rootPart)
			end
			prev = point
		end
	end
	local tip = kit:Ball("Tip", 0.16, Vector3.new(0, 0.1, start - d.BitLength - 0.02), p.Bit, Enum.Material.Metal, bit)
	kit:Reweld(tip, rootPart)
	kit:Motor("BitSpin", handle, rootPart, CFrame.new(0, 0.1, start))

	kit:Attachment("Impact", handle, CFrame.new(0, 0.1, start - d.BitLength))
	kit:Attachment("DrillContact", handle, CFrame.new(0, 0.1, start - d.BitLength * 0.75))
end
