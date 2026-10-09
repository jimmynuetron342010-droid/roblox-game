--[[
	Effect 1 — Basic Slash
	The curved trail itself is the weapon's real Trail (TrailA/TrailB on the blade), switched on by
	the animator during the swing window, so it follows the blade's actual path. This effect adds
	the metallic glint at the strike and a few air-slice streaks off the tip.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local times = Shared.HitTimes(p)
	local strike = times[1]
	local previous: Vector3? = nil
	-- Track the tip just before the strike to know the swing direction.
	vfx.Delay(math.max(0, strike - 0.03), function()
		previous = Shared.TipPosition(p)
	end)
	vfx.Delay(strike, function()
		local tip = Shared.TipPosition(p)
		if not tip then
			return
		end
		local direction = previous and (tip - previous) or Vector3.new(0, 0, -1)
		if direction.Magnitude < 1e-3 then
			direction = Vector3.new(0, 0, -1)
		end
		vfx.Emit("Glint", CFrame.new(tip), 1, {
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.3, cfg.GlintSize),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
		vfx.Emit("Streak", CFrame.lookAt(tip, tip + direction.Unit), cfg.AirStreaks)
		vfx.Sound(cfg.Sound, tip, 0.5)
	end)
end
