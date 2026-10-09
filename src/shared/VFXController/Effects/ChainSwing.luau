--[[
	Effect 4 — Chain Swing
	The chain is the real linked model, swung by the client chain simulator. At the strike this
	effect whips the outer links outward (impulse into the simulation), streaks air off the chain
	end and briefly lengthens the chain-end trail for a motion-blur feel. No energy rope.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local duration = p.Duration or 0.6
	Shared.BoostTrail(vfx, p.Weapon, duration, nil, cfg.TrailLifetime)
	local root = Shared.Root(p)
	local strike = Shared.HitTimes(p)[1]
	local params = p.Params or {}
	-- Whip: push the chain end outward along the swing (right-to-left unless mirrored).
	vfx.Delay(math.max(0, strike - 0.12), function()
		if root and vfx.Hooks.ChainImpulse then
			local side = params.Mirror and 1 or -1
			local impulse = (root.CFrame.RightVector * side + root.CFrame.LookVector * 0.8).Unit * cfg.WhipImpulse
			if params.Heavy then
				impulse *= 0.8
			end
			vfx.Hooks.ChainImpulse(p.Character, impulse, 0.22)
		end
	end)
	vfx.Delay(strike, function()
		local tip = Shared.TipPosition(p)
		if tip and root then
			vfx.Emit("Streak", CFrame.lookAt(tip, tip + root.CFrame.LookVector), cfg.AirStreaks)
			vfx.Sound(cfg.Sound, tip, 0.6)
		end
	end)
end
