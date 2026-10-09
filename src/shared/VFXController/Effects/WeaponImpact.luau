--[[
	Effect 10 — Weapon Impact
	Impact response by weapon type:
	  Blade — sharp metallic sparks + a brief directional streak + small flash
	  Heavy — dust burst + debris + stronger flash + small shake
	  Gun   — compact flash + a few sparks + surface-colored dust
	  Chain — metal-on-metal sparks + flash
]]

return function(vfx, p, cfg)
	local position: Vector3? = p.Position
	if not position then
		return
	end
	local normal = p.Normal or Vector3.yAxis
	local direction = p.Direction or -normal
	local kind = p.ImpactType or "Blade"
	local settings = cfg[kind] or cfg.Blade
	-- Sparks bounce off the surface (reflected travel direction).
	local reflected = direction - 2 * direction:Dot(normal) * normal
	if reflected.Magnitude < 1e-3 then
		reflected = normal
	end
	local sprayCF = CFrame.lookAt(position, position + (reflected.Unit + normal * 0.4).Unit)
	local surface = p.Material and { Material = p.Material, Instance = p.Instance } or nil
	local hitsCharacter = p.Instance and p.Instance.Parent and p.Instance.Parent:FindFirstChildOfClass("Humanoid")

	if kind == "Blade" then
		vfx.Emit("Spark", sprayCF, settings.Sparks)
		if settings.Streak then
			vfx.Streak(position, direction, 2.4, 0.08, Color3.fromRGB(255, 245, 225), 0.09)
		end
		vfx.Flash(position, Color3.fromRGB(255, 230, 190), settings.Flash, 7, 0.07)
	elseif kind == "Heavy" then
		local color = surface and vfx.SurfaceColor(surface :: any) or Color3.fromRGB(150, 145, 140)
		vfx.Emit("Dust", sprayCF, settings.Dust, { Color = ColorSequence.new(color) })
		if not hitsCharacter then
			vfx.Debris(position, normal, color, settings.Debris, 22, 0.4)
		end
		vfx.Emit("Spark", sprayCF, 6)
		vfx.Flash(position, Color3.fromRGB(255, 210, 160), settings.Flash, 10, 0.1)
		vfx.Shake(settings.Shake, position, 45)
	elseif kind == "Gun" then
		vfx.Emit("Spark", sprayCF, settings.Sparks, { Speed = NumberRange.new(10, 20) })
		if not hitsCharacter then
			local color = surface and vfx.SurfaceColor(surface :: any) or Color3.fromRGB(150, 145, 140)
			vfx.Emit("Dust", sprayCF, settings.Dust, {
				Color = ColorSequence.new(color),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.4) }),
			})
		end
		vfx.Flash(position, Color3.fromRGB(255, 220, 160), settings.Flash, 5, 0.05)
	else -- Chain
		vfx.Emit("Spark", sprayCF, settings.Sparks)
		vfx.Flash(position, Color3.fromRGB(230, 230, 255), settings.Flash, 7, 0.07)
	end
	vfx.Sound(cfg.Sound, position, 0.6)
end
