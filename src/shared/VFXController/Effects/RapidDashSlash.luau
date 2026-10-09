--[[
	Effect 9 — Rapid Dash Slash
	Dust kicks up where the dash starts and ends; during the dash a few fading afterimage silhouettes
	(body parts only, pooled — skipped on Low quality) trail the character. The blade trails come
	from the weapon's real Trail during the swing windows.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local root = Shared.Root(p)
	if not root then
		return
	end
	local duration = p.Duration or 0.6
	local function dust(position: Vector3)
		local ground = vfx.GroundAt(position, 6)
		if ground then
			vfx.Emit(
				"Dust",
				CFrame.lookAt(ground.Position, ground.Position + ground.Normal + root.CFrame.LookVector * -0.6),
				cfg.DustCount,
				{
					Color = ColorSequence.new(vfx.SurfaceColor(ground)),
				}
			)
		end
	end
	dust(root.Position)
	local t, ghostTimer = 0, 0
	local dashWindow = duration * 0.7
	vfx.AddTask(function(dt)
		t += dt
		ghostTimer += dt
		if t < dashWindow and ghostTimer >= cfg.AfterimageInterval and p.Character and p.Character.Parent then
			ghostTimer = 0
			vfx.Afterimage(
				p.Character,
				Color3.fromRGB(200, 205, 225),
				cfg.AfterimageTransparency,
				cfg.AfterimageLifetime
			)
		end
		if t >= dashWindow then
			if root.Parent then
				dust(root.Position)
			end
			return false
		end
		return true
	end)
	vfx.Sound(cfg.Sound, root.Position, 0.7)
end
