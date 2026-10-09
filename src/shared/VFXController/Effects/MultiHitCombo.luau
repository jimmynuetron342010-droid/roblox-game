--[[
	Effect 3 — Multi-Hit Combo
	Successive slashes (or punches) with alternating directions. Each hit has its own timing window
	(from the attack's Hits list). The trail lifetime is shortened for the combo so old slashes
	never pile up on screen.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local duration = p.Duration or 1
	Shared.BoostTrail(vfx, p.Weapon, duration, nil, cfg.TrailLifetime)
	local params = p.Params or {}
	for index, t in Shared.HitTimes(p) do
		vfx.Delay(t, function()
			local tip = Shared.TipPosition(p)
			if not tip then
				return
			end
			local root = Shared.Root(p)
			local forward = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
			if params.Punch then
				-- Air puff + small pressure ring in front of the fist.
				vfx.Emit("Puff", CFrame.lookAt(tip, tip + forward), cfg.PuffCount)
				vfx.Ring(tip, forward, 1.6, 0.18, Color3.fromRGB(235, 235, 240), 0.12)
				vfx.Shake(0.08, tip, 30)
			else
				local side = (index % 2 == 0) and -1 or 1
				local right = root and root.CFrame.RightVector or Vector3.xAxis
				vfx.Emit("Glint", CFrame.new(tip), 1)
				vfx.Emit("Streak", CFrame.lookAt(tip, tip + (right * side + forward * 0.4).Unit), 2)
			end
			vfx.Sound(cfg.Sound, tip, 0.45, 1 + index * 0.04)
		end)
	end
end
