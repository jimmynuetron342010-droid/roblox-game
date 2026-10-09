--[[
	Ability effects (racial abilities, techniques, spells, transformations).
	Unlike ordinary weapon attacks these may show the character's soul (soft motes, auras), but they
	stay readable: short, low bloom, and every dangerous wind-up shows a ground telegraph so players
	(and bosses) can react.

	p.Kind selects the visual; extra fields depend on the kind (Position, Radius, Duration, Color...).
]]

local Modules = script.Parent.Parent.Parent
local ProjectileController = require(Modules.ProjectileController)
local VFXConfig = require(Modules.VFXConfig)
local Shared = require(script.Parent._Shared)

local function ground(vfx, position: Vector3)
	local result = vfx.GroundAt(position, 12)
	return result and result.Position or position, result and result.Normal or Vector3.yAxis, result
end

-- Flat telegraph: a translucent disc + edge ring that fills over `duration`.
local function telegraph(vfx, position: Vector3, radius: number, duration: number, color: Color3)
	local point, normal = ground(vfx, position)
	local disc = vfx.AcquirePart("TelegraphDisc", function()
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		return p
	end)
	local edge = vfx.AcquirePart("TelegraphDisc", function()
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		return p
	end)
	disc.Color = color
	edge.Color = color
	local base = CFrame.lookAt(point + normal * 0.06, point + normal * 1.06) * CFrame.Angles(0, math.rad(90), 0)
	local t = 0
	vfx.AddTask(function(dt)
		t += dt
		local alpha = math.clamp(t / duration, 0, 1)
		edge.Size = Vector3.new(0.05, radius * 2, radius * 2)
		edge.CFrame = base
		edge.Transparency = 0.8
		disc.Size = Vector3.new(0.07, radius * 2 * alpha, radius * 2 * alpha)
		disc.CFrame = base * CFrame.new(0.01, 0, 0)
		disc.Transparency = VFXConfig.Abilities.TelegraphTransparency + 0.25 * (1 - alpha)
		if alpha >= 1 then
			vfx.ReleasePart(disc)
			vfx.ReleasePart(edge)
			return false
		end
		return true
	end)
end

-- Character-local aura emitter for the duration of a buff.
local function aura(vfx, character: Model?, color: Color3, duration: number, rate: number)
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	if not torso then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BuffAura"
	emitter.Texture = VFXConfig.Textures.Spark
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.5
	emitter.LightInfluence = 0.2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 3, 0)
	emitter.Rate = vfx.Count(rate)
	emitter.Parent = torso
	vfx.Delay(duration, function()
		emitter.Enabled = false
		vfx.Delay(1, function()
			emitter:Destroy()
		end)
	end)
end

local Kinds = {}

Kinds.Telegraph = function(vfx, p)
	telegraph(vfx, p.Position, p.Radius or 10, p.Duration or 1, p.Color or VFXConfig.Abilities.TelegraphColor)
end

Kinds.Slam = function(vfx, p)
	vfx.Play("GroundSlam", { Position = p.Position, Delay = 0, Params = { Radius = p.Radius or 14 } })
	if p.Aftershock then
		vfx.Delay(0.35, function()
			vfx.Ring(p.Position, Vector3.yAxis, p.Aftershock, 0.5, Color3.fromRGB(255, 170, 90), 0.3)
		end)
	end
end

Kinds.Judgment = function(vfx, p)
	local point, normal = ground(vfx, p.Position)
	local radius = p.Radius or 14
	telegraph(vfx, point, radius, p.Delay or 0.9, Color3.fromRGB(240, 240, 255))
	vfx.Delay(p.Delay or 0.9, function()
		for i = 1, 6 do
			local angle = i / 6 * math.pi * 2
			local base = point + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.55
			vfx.Streak(base + normal * 6, -normal, 12, 0.35, Color3.fromRGB(245, 245, 255), 0.25, 0.1)
		end
		vfx.Streak(point + normal * 8, -normal, 16, 0.9, Color3.fromRGB(255, 255, 255), 0.3, 0.05)
		vfx.Ring(point, normal, radius, 0.45, Color3.fromRGB(245, 245, 255), 0.4)
		vfx.Emit("Soul", CFrame.lookAt(point, point + normal), 40)
		vfx.Flash(point + normal * 2, Color3.fromRGB(235, 240, 255), 4, radius * 1.5, 0.2)
		vfx.Shake(0.6, point, 80)
	end)
end

Kinds.Buff = function(vfx, p)
	local root = Shared.Root(p)
	local color = p.Color or VFXConfig.Abilities.SoulColor
	if root then
		vfx.Emit("Soul", CFrame.new(root.Position), 24, { Color = ColorSequence.new(color) })
		vfx.Ring(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, 6, 0.35, color, 0.2)
		vfx.Flash(root.Position, color, 2, 10, 0.2)
	end
	aura(vfx, p.Character, color, p.Duration or 6, p.Rate or 18)
end

Kinds.Heal = function(vfx, p)
	local root = Shared.Root(p)
	local position = p.Position or (root and root.Position)
	if not position then
		return
	end
	local color = p.Color or Color3.fromRGB(140, 255, 160)
	vfx.Ring(position - Vector3.new(0, 2.8, 0), Vector3.yAxis, p.Radius or 6, 0.6, color, 0.2)
	local t = 0
	local duration = p.Duration or 3
	vfx.AddTask(function(dt)
		t += dt
		if math.floor(t * 8) ~= math.floor((t - dt) * 8) then
			vfx.Emit("Soul", CFrame.lookAt(position - Vector3.new(0, 2, 0), position + Vector3.new(0, 4, 0)), 3, {
				Color = ColorSequence.new(color),
			})
		end
		return t < duration
	end)
end

Kinds.Blink = function(vfx, p)
	for _, position in { p.From, p.To } do
		if position then
			vfx.Emit("Puff", CFrame.new(position), 14, {
				Color = ColorSequence.new(Color3.fromRGB(40, 36, 50)),
			})
		end
	end
end

Kinds.Pulse = function(vfx, p)
	local root = Shared.Root(p)
	local position = p.Position or (root and root.Position)
	if not position then
		return
	end
	local color = p.Color or Color3.fromRGB(120, 180, 255)
	vfx.Ring(position - Vector3.new(0, 1, 0), Vector3.yAxis, p.Radius or 12, 0.35, color, 0.35)
	vfx.Emit("Soul", CFrame.new(position), 30, { Color = ColorSequence.new(color), Speed = NumberRange.new(14, 22) })
	vfx.Shake(0.2, position, 40)
end

Kinds.Cone = function(vfx, p)
	local root = Shared.Root(p)
	if not root then
		return
	end
	local cf = root.CFrame
	for i = 0, 3 do
		vfx.Delay(i * 0.05, function()
			local origin = cf.Position + cf.LookVector * (1.5 + i * 2.5)
			vfx.Emit("Spark", CFrame.lookAt(origin, origin + cf.LookVector), 18, {
				Color = ColorSequence.new(p.Color or Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 80, 20)),
				SpreadAngle = Vector2.new(30, 30),
			})
			vfx.Emit("Smoke", CFrame.lookAt(origin, origin + cf.LookVector), 4)
		end)
	end
	vfx.Flash(cf.Position + cf.LookVector * 6, Color3.fromRGB(255, 150, 60), 3, 14, 0.25)
end

Kinds.AreaBlast = function(vfx, p)
	local point, normal = ground(vfx, p.Position)
	telegraph(vfx, point, p.Radius or 10, p.Delay or 0.6, p.Color or Color3.fromRGB(110, 220, 130))
	vfx.Delay(p.Delay or 0.6, function()
		for i = 1, 5 do
			local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * (p.Radius or 10)
			vfx.Delay(i * 0.04, function()
				vfx.Emit("Puff", CFrame.lookAt(point + offset, point + offset + normal), 8, {
					Color = ColorSequence.new(p.Color or Color3.fromRGB(150, 230, 150)),
				})
				vfx.Flash(point + offset + normal, p.Color or Color3.fromRGB(150, 255, 150), 2, 8, 0.12)
			end)
		end
		vfx.Shake(0.25, point, 50)
	end)
end

Kinds.Well = function(vfx, p)
	local point = ground(vfx, p.Position)
	local radius, duration = p.Radius or 12, p.Duration or 2
	local t = 0
	vfx.AddTask(function(dt)
		t += dt
		local angle = t * 6
		for k = 0, 2 do
			local a = angle + k * 2.1
			local spot = point + Vector3.new(math.cos(a) * radius * 0.8, 1, math.sin(a) * radius * 0.8)
			vfx.Emit("Soul", CFrame.lookAt(spot, point + Vector3.new(0, 1, 0)), 1, {
				Color = ColorSequence.new(p.Color or Color3.fromRGB(120, 90, 220)),
				Speed = NumberRange.new(10, 16),
			})
		end
		return t < duration
	end)
	vfx.Ring(point, Vector3.yAxis, radius, duration, p.Color or Color3.fromRGB(120, 90, 220), 0.2)
end

Kinds.Projectile = function(vfx, p)
	local color = p.Color or Color3.fromRGB(170, 110, 255)
	local part = vfx.AcquirePart("SpellBolt", function()
		local b = Instance.new("Part")
		b.Material = Enum.Material.Neon
		return b
	end)
	part.Color = color
	part.Transparency = 0.1
	part.Size = p.Size or Vector3.new(0.25, 0.25, 1.6)
	ProjectileController.Visual({
		Origin = p.Origin,
		Direction = p.Direction,
		Speed = p.Speed or 90,
		Range = p.Range or 70,
		Radius = 0.5,
		Ignore = { p.Character },
		Homing = p.Target and { Target = p.Target, Turn = p.Turn or 6 } or nil,
		OnStep = function(position, direction)
			part.CFrame = CFrame.lookAt(position, position + direction)
			vfx.Emit("Soul", CFrame.new(position), 1, { Color = ColorSequence.new(color), Speed = NumberRange.new(0, 1) })
		end,
		OnHit = function(result)
			vfx.Emit("Soul", CFrame.new(result.Position), 12, { Color = ColorSequence.new(color) })
			vfx.Flash(result.Position, color, 2, 8, 0.1)
		end,
		OnEnd = function()
			vfx.ReleasePart(part)
		end,
	})
end

Kinds.Construct = function(vfx, p)
	local point = ground(vfx, p.Position)
	local parts = {}
	local function piece(size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?)
		local part = vfx.AcquirePart("ConstructPiece", function()
			return Instance.new("Part")
		end)
		part.Shape = shape or Enum.PartType.Block
		part.Material = Enum.Material.Metal
		part.Size = size
		part.Color = color
		part.Transparency = 0
		part.CFrame = CFrame.new(point) * offset
		table.insert(parts, part)
		return part
	end
	piece(Vector3.new(2.2, 0.4, 2.2), CFrame.new(0, 0.2, 0), Color3.fromRGB(60, 62, 70))
	piece(Vector3.new(0.6, 1.6, 0.6), CFrame.new(0, 1.2, 0), Color3.fromRGB(90, 92, 100))
	piece(Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 2.3, 0), Color3.fromRGB(70, 110, 140), Enum.PartType.Ball)
	piece(Vector3.new(0.3, 0.3, 1.4), CFrame.new(0, 2.3, -0.7), Color3.fromRGB(50, 50, 56))
	vfx.Emit("Soul", CFrame.new(point + Vector3.new(0, 1, 0)), 16, { Color = ColorSequence.new(Color3.fromRGB(80, 200, 255)) })
	vfx.Delay(p.Duration or 8, function()
		vfx.Emit("Puff", CFrame.new(point + Vector3.new(0, 1, 0)), 10)
		for _, part in parts do
			vfx.ReleasePart(part)
		end
	end)
end

Kinds.MasteryUp = function(vfx, p)
	local root = Shared.Root(p)
	if not root then
		return
	end
	local color = p.Color or Color3.fromRGB(255, 210, 90)
	vfx.Ring(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, 10, 0.7, color, 0.3)
	vfx.Emit("Soul", CFrame.lookAt(root.Position - Vector3.new(0, 2, 0), root.Position + Vector3.new(0, 4, 0)), 50, {
		Color = ColorSequence.new(color),
		Speed = NumberRange.new(8, 18),
	})
	vfx.Flash(root.Position, color, 3, 16, 0.4)
end

Kinds.Dash = function(vfx, p)
	local position = p.Origin
	if not position then
		return
	end
	local result = vfx.GroundAt(position, 6)
	if result then
		local back = -(p.Direction or Vector3.zAxis)
		vfx.Emit("Dust", CFrame.lookAt(result.Position, result.Position + (result.Normal + back * 0.7).Unit), 8, {
			Color = ColorSequence.new(vfx.SurfaceColor(result)),
		})
	end
end

Kinds.Wrap = function(vfx, p)
	-- Binding Curse: cloth strips flying to the target, then a wrap ring around the feet.
	Kinds.Projectile(vfx, {
		Origin = p.Origin,
		Direction = p.Direction,
		Speed = p.Speed or 90,
		Range = p.Range or 60,
		Character = p.Character,
		Color = Color3.fromRGB(226, 210, 170),
		Size = Vector3.new(0.6, 0.08, 1.4),
	})
end

Kinds.Rooted = function(vfx, p)
	local root = Shared.Root(p)
	if root then
		vfx.Ring(root.Position - Vector3.new(0, 2.6, 0), Vector3.yAxis, 2.2, p.Duration or 1.2, Color3.fromRGB(226, 210, 170), 0.25)
	end
end

return function(vfx, p)
	local kind = Kinds[p.Kind]
	if kind then
		kind(vfx, p)
	end
end
