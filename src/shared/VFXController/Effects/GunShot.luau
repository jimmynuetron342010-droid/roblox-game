--[[
	Effect 7 — Gun Shot
	A two-frame 3D muzzle flash at the barrel, a light pop, smoke, an ejected shell casing, and a
	short tracer streak that travels to the hit point (never a permanent beam). Liz and Patty look
	different: Patty's flash is wider and smokier (WeaponConfig.Muzzle).
]]

local Modules = script.Parent.Parent.Parent
local WeaponConfig = require(Modules.WeaponConfig)
local Shared = require(script.Parent._Shared)

local function muzzleOf(weapon: Instance?, unitName: string): Attachment?
	local unit = weapon and weapon:FindFirstChild(unitName)
	return Shared.FindAttachment(unit, "Muzzle")
end

local function shell(vfx, cframe: CFrame)
	local part = vfx.AcquirePart("Shell", function()
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Metal
		p.Color = Color3.fromRGB(205, 160, 70)
		p.Size = Vector3.new(0.16, 0.07, 0.07)
		return p
	end)
	part.Transparency = 0
	local velocity = cframe.RightVector * (9 + math.random() * 4) + Vector3.new(0, 10 + math.random() * 4, 0)
	local cf = cframe
	local t = 0
	vfx.AddTask(function(dt)
		t += dt
		velocity += Vector3.new(0, -workspace.Gravity * 0.4, 0) * dt
		cf = CFrame.new(cf.Position + velocity * dt) * (cf - cf.Position) * CFrame.Angles(dt * 25, dt * 12, 0)
		part.CFrame = cf
		if t > 0.6 then
			vfx.ReleasePart(part)
			return false
		end
		return true
	end)
end

local function fireOne(vfx, p, cfg, unitName: string, target: Vector3?)
	local weaponConfig = WeaponConfig.Weapons.TwinPistols
	local muzzleConfig = weaponConfig.Muzzle[unitName] or weaponConfig.Muzzle.Liz
	local muzzle = muzzleOf(p.Weapon, unitName)
	local root = Shared.Root(p)
	local muzzleCF = muzzle and muzzle.WorldCFrame or (root and root.CFrame * CFrame.new(unitName == "Liz" and 0.8 or -0.8, 0.5, -2.2))
	if not muzzleCF then
		return
	end
	local forward = p.Direction or muzzleCF.LookVector
	local flashCF = CFrame.lookAt(muzzleCF.Position, muzzleCF.Position + forward)
	vfx.MuzzleFlash(flashCF, muzzleConfig.FlashSize, muzzleConfig.FlashColor, cfg.FlashLifetime)
	vfx.Flash(muzzleCF.Position, muzzleConfig.FlashColor, cfg.LightBrightness, cfg.LightRange, 0.06)
	vfx.Emit("Smoke", flashCF, muzzleConfig.Smoke)
	if cfg.ShellCasings then
		shell(vfx, muzzleCF * CFrame.new(0, 0.2, 0.9))
	end

	-- Tracer: a short neon dash running to the hit point.
	local hitPoint = target
	local hitResult: RaycastResult? = nil
	if not hitPoint then
		hitResult = vfx.Raycast(muzzleCF.Position, forward * 110, { p.Character })
		hitPoint = hitResult and hitResult.Position or (muzzleCF.Position + forward * 110)
	end
	local travel = (hitPoint - muzzleCF.Position)
	local distance = travel.Magnitude
	local speed = weaponConfig.Projectile.TracerSpeed
	local tracer = vfx.AcquirePart("Tracer", function()
		local part = Instance.new("Part")
		part.Material = Enum.Material.Neon
		return part
	end)
	tracer.Color = muzzleConfig.FlashColor:Lerp(Color3.new(1, 1, 1), 0.4)
	tracer.Transparency = 0.2
	tracer.Size = Vector3.new(weaponConfig.Projectile.TracerWidth, weaponConfig.Projectile.TracerWidth, weaponConfig.Projectile.TracerLength)
	local dir = distance > 0 and travel / distance or forward
	local t = 0
	vfx.AddTask(function(dt)
		t += dt
		local d = math.min(t * speed, distance)
		local head = muzzleCF.Position + dir * d
		tracer.CFrame = CFrame.lookAt(head - dir * weaponConfig.Projectile.TracerLength * 0.5, head)
		if d >= distance then
			vfx.ReleasePart(tracer)
			if not target then
				vfx.Play("WeaponImpact", {
					ImpactType = "Gun",
					Position = hitPoint,
					Normal = hitResult and hitResult.Normal or -dir,
					Direction = dir,
					Material = hitResult and hitResult.Material or nil,
					Instance = hitResult and hitResult.Instance or nil,
				})
			end
			return false
		end
		return true
	end)
	vfx.Sound(unitName == "Patty" and weaponConfig.Sounds.ShotPatty or weaponConfig.Sounds.Shot, muzzleCF.Position, 0.7)
end

return function(vfx, p, cfg)
	local attack = p.Attack
	local hits = attack and attack.Hits or { { Time = 0.04, Hand = (p.Params and p.Params.Hand) or "Right" } }
	local times = Shared.HitTimes(p)
	for index, hit in hits do
		local unitName = (hit.Hand == "Left") and "Patty" or "Liz"
		local target = p.Targets and p.Targets[index] or nil
		vfx.Delay(times[index] or 0, function()
			fireOne(vfx, p, cfg, unitName, target)
		end)
	end
end
