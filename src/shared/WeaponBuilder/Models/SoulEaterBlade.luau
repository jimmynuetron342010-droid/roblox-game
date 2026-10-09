--[[
	Soul Eater Blade (sword form)
	Broad black blade with a white edge and a red "eye", a skull-motif guard with spiked quillons,
	a wrapped grip and a skull pommel.

	Components: Grip, Guard, Blade
]]

local BladeKit = require(script.Parent.Parent.BladeKit)

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle

	-- Grip -------------------------------------------------------------------------------
	local grip = kit:Group("Grip")
	local gl = d.GripLength
	kit:Cylinder("GripCore", Vector3.new(0, -gl / 2 - 0.05, 0), Vector3.new(0, gl / 2 + 0.05, 0), 0.26, p.Grip, Enum.Material.Fabric, grip)
	for i = 0, 3 do
		local y = -gl / 2 + 0.15 + i * (gl - 0.3) / 3
		kit:Cylinder("Wrap", Vector3.new(0, y - 0.04, 0), Vector3.new(0, y + 0.04, 0), 0.3, p.Guard, Enum.Material.Metal, grip)
	end
	kit:Ball("Pommel", 0.38, Vector3.new(0, -gl / 2 - 0.2, 0), p.Skull, Enum.Material.SmoothPlastic, grip)
	kit:Ball("PommelEye", 0.1, Vector3.new(0, -gl / 2 - 0.2, -0.17), p.Eye, Enum.Material.SmoothPlastic, grip)

	-- Guard with skull ------------------------------------------------------------------------
	local guard = kit:Group("Guard")
	local gy = gl / 2 + 0.12
	kit:Bar("Crossguard", Vector3.new(0, gy, 0.75), Vector3.new(0, gy, -0.95), 0.32, 0.26, p.Guard, Vector3.xAxis, Enum.Material.Metal, guard)
	kit:Spike("Quillon", Vector3.new(0, gy, -0.9), Vector3.new(0, gy - 0.35, -1.45), 0.28, 0.2, p.Guard, Vector3.yAxis, Enum.Material.Metal, guard)
	kit:Spike("Quillon", Vector3.new(0, gy, 0.7), Vector3.new(0, gy - 0.3, 1.15), 0.26, 0.2, p.Guard, Vector3.yAxis, Enum.Material.Metal, guard)
	kit:Ball("Skull", 0.62, Vector3.new(0, gy + 0.05, -0.1), p.Skull, Enum.Material.SmoothPlastic, guard)
	kit:Block("SkullJaw", Vector3.new(0.4, 0.18, 0.36), CFrame.new(0, gy - 0.22, -0.12), p.Skull, Enum.Material.SmoothPlastic, guard)
	for _, side in { -1, 1 } do
		kit:Ball("Socket", 0.17, Vector3.new(side * 0.25, gy + 0.1, -0.22), p.Grip, Enum.Material.SmoothPlastic, guard)
	end

	-- Blade --------------------------------------------------------------------------------------
	local blade = kit:Group("Blade")
	local L, width = d.BladeLength, d.BladeWidth
	local base = gy + 0.25
	local back, front = {}, {}
	local steps = 7
	for i = 0, steps do
		local t = i / steps
		local y = base + L * t
		-- Back (+Z) stays fairly straight; the edge (-Z) swells, then sweeps to the point.
		local backZ = 0.28 - 0.18 * t
		local frontZ = backZ - width * (1 + 0.25 * math.sin(math.pi * t * 0.8)) * (1 - t ^ 3)
		table.insert(back, Vector3.new(0, y + (t == 1 and 0.0 or 0), backZ))
		table.insert(front, Vector3.new(0, y - 0.25 * t * t, frontZ))
	end
	front[#front] = back[#back] + Vector3.new(0, 0.25, -0.05)
	local mid = BladeKit.Between(kit, blade, back, front, 0.55, p.Blade, p.Edge, d.Thickness, d.Thickness * 0.7)
	-- Red eye notch near the base, on both faces.
	for _, side in { -1, 1 } do
		kit:Ball("BladeEye", 0.26, Vector3.new(side * 0.04, base + 0.55, back[2].Z - 0.35), p.Eye, Enum.Material.SmoothPlastic, blade)
	end

	kit:Attachment("TrailA", handle, CFrame.new(mid[2]))
	kit:Attachment("TrailB", handle, CFrame.new(mid[#mid - 1]))
	kit:Attachment("Impact", handle, CFrame.new(front[#front]))
end
