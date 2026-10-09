--[[
	Effect 2 — Heavy Slash
	Wider, longer-lived blade trail, a bigger glint, and — when the blade meets the ground — a dust
	burst, debris, a warm impact flash and a short camera shake.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local duration = p.Duration or 1
	Shared.BoostTrail(vfx, p.Weapon, duration, cfg.TrailWidthScale, cfg.TrailLifetime)
	local strike = Shared.HitTimes(p)[1]
	vfx.Delay(strike, function()
		local tip = Shared.TipPosition(p)
		if not tip then
			return
		end
		vfx.Emit("Glint", CFrame.new(tip), 1, {
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.3, cfg.GlintSize),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
		local ground = vfx.GroundAt(tip, 7)
		if ground then
			local color = vfx.SurfaceColor(ground)
			vfx.Emit("Dust", CFrame.lookAt(ground.Position, ground.Position + ground.Normal), cfg.DustCount, {
				Color = ColorSequence.new(color),
			})
			vfx.Debris(ground.Position, ground.Normal, color, cfg.DebrisCount, 26, 0.45)
			vfx.Flash(ground.Position + ground.Normal, Color3.fromRGB(255, 210, 160), cfg.FlashBrightness, cfg.FlashRange, 0.12)
			vfx.Shake(cfg.Shake, ground.Position, 50)
		else
			vfx.Shake(cfg.Shake * 0.5, tip, 40)
		end
		vfx.Sound(cfg.Sound, tip, 0.8)
	end)
end
