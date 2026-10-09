--[[
	Effect 5 — Ground Slam
	At the impact point on the ground: an expanding dust ring, rock fragments, a thin 3D shockwave
	ring made of geometry segments, a low warm flash and a distance-attenuated camera shake.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local root = Shared.Root(p)
	local strike = p.Delay or Shared.HitTimes(p)[1]
	local radius = (p.Params and p.Params.Radius) or cfg.Radius
	vfx.Delay(strike, function()
		local position = p.Position
		if not position and root then
			local offset = 6
			if p.Attack and p.Attack.Hits and p.Attack.Hits[1] then
				offset = p.Attack.Hits[1].Offset or offset
			end
			position = root.CFrame * Vector3.new(0, 0, -offset)
		end
		if not position then
			return
		end
		local ground = vfx.GroundAt(position, 10)
		local point = ground and ground.Position or position
		local normal = ground and ground.Normal or Vector3.yAxis
		local color = vfx.SurfaceColor(ground)
		vfx.EmitRing(point, normal, radius * 0.35, cfg.DustCount, color)
		vfx.Emit(
			"Dust",
			CFrame.lookAt(point, point + normal),
			math.floor(cfg.DustCount * 0.4),
			{ Color = ColorSequence.new(color) }
		)
		vfx.Debris(point, normal, color, cfg.DebrisCount, cfg.DebrisSpeed, 0.6)
		vfx.Ring(point, normal, radius, cfg.RingLifetime, color:Lerp(Color3.new(1, 1, 1), 0.35), cfg.RingThickness)
		vfx.Flash(point + normal * 1.5, Color3.fromRGB(255, 200, 150), 2.5, radius, 0.15)
		vfx.Shake(cfg.Shake, point, cfg.ShakeRange)
		vfx.Sound(cfg.Sound, point, 1)
	end)
end
