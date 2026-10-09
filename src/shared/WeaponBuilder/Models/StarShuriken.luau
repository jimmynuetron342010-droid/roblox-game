--[[
	Black☆Star's Star Weapon (shuriken form)
	Four faceted blades with a raised center ridge (two-tone bevel), a dark hub and a white ring.
	The hub is held in the fist; the star lies in the YZ plane.

	Components: Hub, Blades
]]

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle

	local hub = kit:Group("Hub")
	local hubRadius = d.HubRadius
	kit:Cylinder("HubDisc", Vector3.new(-0.14, 0, 0), Vector3.new(0.14, 0, 0), hubRadius * 2, p.Hub, Enum.Material.Metal, hub)
	kit:Ring("HubRing", CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis), hubRadius * 1.08, 0.1, 12, p.Ring, Enum.Material.SmoothPlastic, hub)
	kit:Cylinder("HubCore", Vector3.new(-0.18, 0, 0), Vector3.new(0.18, 0, 0), hubRadius * 0.7, p.Edge, Enum.Material.Metal, hub)

	local blades = kit:Group("Blades")
	local R = d.Radius
	local ridge = d.Thickness * 0.75
	for i = 0, d.Points - 1 do
		local angle = math.rad(45 + i * 360 / d.Points)
		local dir = Vector3.new(0, math.cos(angle), math.sin(angle))
		local perp = Vector3.new(0, -math.sin(angle), math.cos(angle))
		local base = dir * (hubRadius * 0.85)
		local left = base + perp * 0.38
		local right = base - perp * 0.38
		local tip = dir * R
		for _, face in { 1, -1 } do
			local raised = base + dir * 0.12 + Vector3.new(ridge * face, 0, 0)
			kit:Triangle("Facet", left, tip, raised, 0.04, face == 1 and p.Blade or p.Edge, Enum.Material.Metal, blades)
			kit:Triangle("Facet", raised, tip, right, 0.04, face == 1 and p.Edge or p.Blade, Enum.Material.Metal, blades)
		end
	end

	local topDir = Vector3.new(0, math.cos(math.rad(45)), math.sin(math.rad(45)))
	kit:Attachment("TrailA", handle, CFrame.new(topDir * hubRadius))
	kit:Attachment("TrailB", handle, CFrame.new(topDir * R))
	kit:Attachment("Impact", handle, CFrame.new(topDir * R))
end
