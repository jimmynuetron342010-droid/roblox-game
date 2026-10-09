--[[
	Twin Pistols (Liz & Patty)
	Two distinct stylized pistols: angled grip with a skull emblem, white frame, a sliding top
	(Motor6D "Slide" for recoil), barrel, trigger guard and trigger, hammer, sights and trim.
	  Liz   — right hand, red trim, compact barrel
	  Patty — left hand, blue trim, longer barrel with a two-ring muzzle brake
	Model space: grip axis +Y, barrel points -Z. "Muzzle" attachment sits at the barrel exit.
]]

local function buildPistol(api, name: string, mount: string, trim: Color3, longBarrel: boolean, previewOffset: CFrame)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit(name, mount, previewOffset)
	local kit, handle = unit.Kit, unit.Handle

	local frame = kit:Group("Frame")
	kit:Block("Grip", Vector3.new(0.34, d.GripLength + 0.1, 0.56), CFrame.new(0, -0.08, 0.1) * CFrame.Angles(math.rad(14), 0, 0), p.Grip, Enum.Material.SmoothPlastic, frame)
	kit:Block("GripPanel", Vector3.new(0.38, d.GripLength * 0.7, 0.4), CFrame.new(0, -0.12, 0.12) * CFrame.Angles(math.rad(14), 0, 0), p.Body, Enum.Material.SmoothPlastic, frame)
	kit:Ball("Skull", 0.24, Vector3.new(0.19, -0.1, 0.12), p.Body, Enum.Material.SmoothPlastic, frame)
	for _, x in { 0.2, -0.2 } do
		kit:Ball("SkullEye", 0.07, Vector3.new(x * 1.08, -0.07, 0.09), p.Skull, Enum.Material.SmoothPlastic, frame)
	end
	kit:Block("Body", Vector3.new(0.4, 0.34, d.BodyLength), CFrame.new(0, 0.5, -0.3), p.Body, Enum.Material.SmoothPlastic, frame)
	kit:Block("TrimL", Vector3.new(0.02, 0.08, d.BodyLength * 0.9), CFrame.new(0.205, 0.5, -0.3), trim, Enum.Material.SmoothPlastic, frame)
	kit:Block("TrimR", Vector3.new(0.02, 0.08, d.BodyLength * 0.9), CFrame.new(-0.205, 0.5, -0.3), trim, Enum.Material.SmoothPlastic, frame)
	-- Trigger guard + trigger.
	kit:Bar("GuardFront", Vector3.new(0, 0.34, -0.66), Vector3.new(0, 0.02, -0.6), 0.08, 0.08, p.Grip, Vector3.xAxis, Enum.Material.Metal, frame)
	kit:Bar("GuardBottom", Vector3.new(0, 0.02, -0.62), Vector3.new(0, 0.05, -0.26), 0.08, 0.08, p.Grip, Vector3.xAxis, Enum.Material.Metal, frame)
	kit:Spike("Trigger", Vector3.new(0, 0.33, -0.4), Vector3.new(0, 0.12, -0.36), 0.1, 0.06, p.Metal, Vector3.zAxis, Enum.Material.Metal, frame)
	kit:Block("Hammer", Vector3.new(0.12, 0.2, 0.12), CFrame.new(0, 0.78, 0.45) * CFrame.Angles(math.rad(-25), 0, 0), p.Metal, Enum.Material.Metal, frame)

	-- Barrel (static) + muzzle.
	local barrelGroup = kit:Group("Barrel")
	local barrelLength = d.BarrelLength * (longBarrel and 1.2 or 1)
	local z0 = -0.3 - d.BodyLength / 2
	local z1 = z0 - barrelLength
	kit:Cylinder("Barrel", Vector3.new(0, 0.6, z0 + 0.1), Vector3.new(0, 0.6, z1), 0.28, p.Barrel, Enum.Material.Metal, barrelGroup)
	kit:Cylinder("MuzzleRing", Vector3.new(0, 0.6, z1 + 0.12), Vector3.new(0, 0.6, z1), 0.36, trim, Enum.Material.Metal, barrelGroup)
	if longBarrel then
		kit:Cylinder("BrakeRing", Vector3.new(0, 0.6, z1 + 0.42), Vector3.new(0, 0.6, z1 + 0.3), 0.36, trim, Enum.Material.Metal, barrelGroup)
	end
	kit:Block("FrontSight", Vector3.new(0.06, 0.12, 0.1), CFrame.new(0, 0.79, z1 + 0.15), p.Metal, Enum.Material.Metal, barrelGroup)

	-- Slide (animated recoil).
	local slideGroup = kit:Group("SlideAssembly")
	local slide = kit:Block("SlideBody", Vector3.new(0.38, 0.24, d.BodyLength * 0.98), CFrame.new(0, 0.79, -0.32), p.Body:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.SmoothPlastic, slideGroup)
	local stripe = kit:Block("SlideStripe", Vector3.new(0.4, 0.05, d.BodyLength * 0.6), CFrame.new(0, 0.8, -0.3), trim, Enum.Material.SmoothPlastic, slideGroup)
	kit:Reweld(stripe, slide)
	local rear = kit:Block("RearSight", Vector3.new(0.14, 0.1, 0.08), CFrame.new(0, 0.95, 0.12), p.Metal, Enum.Material.Metal, slideGroup)
	kit:Reweld(rear, slide)
	kit:Motor("Slide", handle, slide, CFrame.new(0, 0.79, -0.32))

	kit:Attachment("Muzzle", handle, CFrame.new(0, 0.6, z1 - 0.02))
	kit:Attachment("Impact", handle, CFrame.new(0, 0.6, z1))
end

return function(api)
	buildPistol(api, "Liz", "RightHand", api.Palette.LizTrim, false, CFrame.new(0.9, 0, 0))
	buildPistol(api, "Patty", "LeftHand", api.Palette.PattyTrim, true, CFrame.new(-0.9, 0, 0))
end
