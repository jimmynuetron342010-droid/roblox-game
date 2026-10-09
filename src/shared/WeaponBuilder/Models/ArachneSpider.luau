--[[
	Arachnid Rig (Arachne-inspired original weapon)
	Back-mounted mechanical spider: a harness plate, a dark armored body with a white ring and a
	red central eye, and eight articulated legs (Motor6D hip + knee each) ending in steel tips.
	Model space: origin at BodyBackAttachment, +Z away from the back, +Y up, +X to the right.
	Components: Harness, Body, Legs
]]

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "Back")
	local kit, handle = unit.Kit, unit.Handle

	local harness = kit:Group("Harness")
	kit:Block("Plate", Vector3.new(1.3, 1.5, 0.2), CFrame.new(0, 0.1, 0.12), p.Joint, Enum.Material.Metal, harness)
	for _, x in { -0.45, 0.45 } do
		kit:Block(
			"Strap",
			Vector3.new(0.2, 1.7, 0.08),
			CFrame.new(x, 0.15, 0.03),
			p.Body,
			Enum.Material.Fabric,
			harness
		)
	end

	local body = kit:Group("Body")
	local center = Vector3.new(0, 0.2, 0.95)
	kit:Ball("Abdomen", d.BodyRadius * 2, center, p.Body, Enum.Material.Metal, body)
	kit:Ring(
		"Ring",
		CFrame.fromMatrix(center, Vector3.xAxis, Vector3.zAxis),
		d.BodyRadius * 1.02,
		0.12,
		14,
		p.Ring,
		Enum.Material.SmoothPlastic,
		body
	)
	kit:Ball("Sclera", 0.62, center + Vector3.new(0, 0, d.BodyRadius * 0.82), p.Ring, Enum.Material.SmoothPlastic, body)
	kit:Ball(
		"Eye",
		0.36,
		center + Vector3.new(0, 0, d.BodyRadius * 0.82 + 0.18),
		p.Eye,
		Enum.Material.SmoothPlastic,
		body
	)
	kit:Cylinder("Mount", Vector3.new(0, 0.2, 0.2), center, 0.4, p.Joint, Enum.Material.Metal, body)

	local legs = kit:Group("Legs")
	local angles = { 55, 20, -15, -50 }
	local index = 0
	for row, phi in angles do
		for _, side in { 1, -1 } do
			index += 1
			local a = math.rad(phi)
			local hip = center + Vector3.new(side * d.BodyRadius * 0.85, math.sin(a) * d.BodyRadius * 0.7, -0.05)
			local up = math.rad(phi * 0.55 + 28)
			local upperDir = Vector3.new(side * math.cos(up), math.sin(up), 0.25 - row * 0.12).Unit
			local knee = hip + upperDir * d.UpperLength
			local lowerDir = Vector3.new(side * 0.5, -0.78, -0.35 - (4 - row) * 0.1).Unit
			local tip = knee + lowerDir * d.LowerLength

			kit:Ball("HipJoint", 0.4, hip, p.Joint, Enum.Material.Metal, legs)
			local upper = kit:Bar("Upper", hip, knee, 0.24, 0.24, p.Leg, Vector3.zAxis, Enum.Material.Metal, legs)
			-- Model-aligned pivots: yaw (Y) swings a leg forward/back, roll (Z) lifts it.
			local hipMotor = kit:Motor("Hip" .. index, handle, upper, CFrame.new(hip))
			hipMotor:SetAttribute("Side", side)
			local kneeBall = kit:Ball("KneeJoint", 0.34, knee, p.Joint, Enum.Material.Metal, legs)
			kit:Reweld(kneeBall, upper)
			local lower =
				kit:Bar("Lower", knee, tip - lowerDir * 0.45, 0.2, 0.2, p.Leg, Vector3.zAxis, Enum.Material.Metal, legs)
			kit:Motor("Knee" .. index, upper, lower, CFrame.new(knee))
			for _, axis in { Vector3.xAxis, Vector3.zAxis } do
				local w1, w2 =
					kit:Spike("Tip", tip - lowerDir * 0.5, tip, 0.22, 0.08, p.Tip, axis, Enum.Material.Metal, legs)
				for _, wedge in { w1, w2 } do
					if wedge then
						kit:Reweld(wedge, lower)
					end
				end
			end
			if index == 1 then
				local trailA = Instance.new("Attachment")
				trailA.Name = "TrailA"
				trailA.CFrame = lower.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(knee))
				trailA.Parent = lower
				local trailB = Instance.new("Attachment")
				trailB.Name = "TrailB"
				trailB.CFrame = lower.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(tip))
				trailB.Parent = lower
				local impact = Instance.new("Attachment")
				impact.Name = "Impact"
				impact.CFrame = trailB.CFrame
				impact.Parent = lower
			end
		end
	end
end
