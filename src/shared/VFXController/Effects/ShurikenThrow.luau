--[[
	Effect 6 — Shuriken Throw
	Launches a physical 3D shuriken (the same model as the weapon, pooled) that spins naturally
	around its hub axis while flying, with a subtle air trail and motion streaks. On contact it plays
	a metallic impact spark. Projectile kinematics come from ProjectileController so the visual
	matches the server's simulation.
]]

local Modules = script.Parent.Parent.Parent
local ProjectileController = require(Modules.ProjectileController)
local WeaponBuilder = require(Modules.WeaponBuilder)

local pool: { Model } = {}

local function acquireModel(): Model
	local model = table.remove(pool)
	if model then
		return model
	end
	local built = WeaponBuilder.Build("StarShuriken", { Anchored = true, Scale = 0.75 })
	built.Name = "ThrownShuriken"
	for _, descendant in built:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CastShadow = false
		elseif descendant:IsA("Trail") then
			descendant:Destroy()
		end
	end
	local handle = built.PrimaryPart :: BasePart
	local a0 = Instance.new("Attachment")
	a0.Name = "AirA"
	a0.Position = Vector3.new(0, 0.35, 0)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "AirB"
	a1.Position = Vector3.new(0, -0.35, 0)
	a1.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "AirTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(230, 235, 255))
	trail.Transparency = NumberSequence.new(0.65, 1)
	trail.LightEmission = 0.2
	trail.Enabled = false
	trail.Parent = handle
	return built
end

local function releaseModel(model: Model)
	local handle = model.PrimaryPart
	if handle then
		local trail = handle:FindFirstChild("AirTrail") :: Trail?
		if trail then
			trail.Enabled = false
		end
	end
	model:PivotTo(CFrame.new(0, -10000, 0))
	if #pool < 12 then
		table.insert(pool, model)
	else
		model:Destroy()
	end
end

return function(vfx, p, cfg)
	local spec = p.Projectile or {}
	local count = spec.Count or (p.Params and p.Params.Count) or 1
	local spread = math.rad(spec.Spread or 12)
	local origin = p.Origin
	local direction = p.Direction
	if not origin or not direction then
		return
	end
	local delay = p.Delay or 0
	vfx.Delay(delay, function()
		for i = 1, count do
			local offset = count > 1 and ((i - (count + 1) / 2) * spread) or 0
			local dir = (CFrame.fromAxisAngle(Vector3.yAxis, offset) * direction).Unit
			local model = acquireModel()
			model.Parent = workspace:FindFirstChild("ClientVFX") or workspace
			local handle = model.PrimaryPart :: BasePart
			local trail = handle:FindFirstChild("AirTrail") :: Trail
			trail.Lifetime = cfg.TrailLifetime
			trail.WidthScale = NumberSequence.new(1, 0.2)
			local spin = 0
			local streakTimer = 0
			-- Star plane faces up (horizontal throw), spinning around the hub's X axis.
			local orient = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, math.rad(90))
			model:PivotTo(CFrame.new(origin) * orient)
			trail.Enabled = true
			ProjectileController.Visual({
				Origin = origin,
				Direction = dir,
				Speed = spec.Speed or 120,
				Range = spec.Range or 90,
				Radius = 0.6,
				Ignore = { p.Character },
				OnStep = function(position, _, dt)
					spin += dt * 30
					model:PivotTo(CFrame.new(position) * orient * CFrame.Angles(spin, 0, 0))
					streakTimer += dt
					if streakTimer > 0.06 then
						streakTimer = 0
						vfx.Emit("Streak", CFrame.lookAt(position, position - dir), 1)
					end
				end,
				OnHit = function(result: RaycastResult)
					vfx.Play("WeaponImpact", {
						ImpactType = "Blade",
						Position = result.Position,
						Normal = result.Normal,
						Direction = dir,
						Material = result.Material,
						Instance = result.Instance,
					})
				end,
				OnEnd = function()
					releaseModel(model)
				end,
			})
		end
		vfx.Sound(cfg.Sound, origin, 0.5)
	end)
end
