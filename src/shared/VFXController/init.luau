--[[
	VFXController (client)
	Plays the reusable effects in ./Effects. Effects never decide gameplay: damage and hit detection
	live on the server (CombatService); this module only draws.

	PERFORMANCE
	  * Emitter "hosts": one anchored invisible part per emitter template. To spawn particles the host
	    is moved and :Emit(n) is called — emitters are reused, never created per hit.
	  * Part pools for debris, ring segments, tracers, streaks, muzzle petals, shells, afterimages.
	  * One RenderStepped loop updates every transient effect (no per-effect connections).
	  * Quality tiers scale particle counts, debris, afterimages and lights (VFXConfig.Quality).
	  * Everything lives in workspace.ClientVFX (local only) and is cleaned up automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = script.Parent
local VFXConfig = require(Modules.VFXConfig)
local WeaponConfig = require(Modules.WeaponConfig)

local Effects = script:WaitForChild("Effects")

local VFXController = {}

VFXController.Config = VFXConfig
VFXController.Hooks = {
	-- Set by the AnimationController: function(character, impulse: Vector3, duration: number)
	ChainImpulse = nil :: any,
}

local folder: Folder? = nil
local hosts: { [string]: BasePart } = {}
local emitters: { [string]: ParticleEmitter } = {}
local partPools: { [string]: { BasePart } } = {}
local tasks: { (number) -> boolean } = {}
local effectModules: { [string]: any } = {}
local settings = {
	QualityName = "Auto",
	Quality = VFXConfig.Quality.High,
	ReducedMotion = false,
	CameraShake = true,
}
local shake = { Intensity = 0, Seed = math.random() * 1000 }
local raycastParams: RaycastParams? = nil
local FAR = CFrame.new(0, -10000, 0)

-- ── Templates ──────────────────────────────────────────────────────────────────
local function ns(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

local function baseEmitter(name: string, texture: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.Rate = 0
	emitter.Enabled = true
	emitter.LockedToPart = false
	emitter.EmissionDirection = Enum.NormalId.Front
	return emitter
end

local templateBuilders = {}

templateBuilders.Spark = function()
	local e = baseEmitter("Spark", VFXConfig.Textures.Spark)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214), Color3.fromRGB(255, 150, 60))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = ns({ { 0, 0.16 }, { 1, 0 } })
	e.Lifetime = NumberRange.new(0.15, 0.35)
	e.Speed = NumberRange.new(16, 34)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Drag = 4
	e.Acceleration = Vector3.new(0, -70, 0)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	pcall(function()
		e.Squash = ns({ { 0, 1.8 }, { 1, 1 } })
	end)
	return e
end

templateBuilders.Glint = function()
	local e = baseEmitter("Glint", VFXConfig.Textures.Spark)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = ns({ { 0, 0.1 }, { 0.3, 1.2 }, { 1, 0 } })
	e.Lifetime = NumberRange.new(0.12, 0.14)
	e.Speed = NumberRange.new(0, 0)
	e.Rotation = NumberRange.new(0, 90)
	e.ZOffset = 0.5
	return e
end

templateBuilders.Dust = function()
	local e = baseEmitter("Dust", VFXConfig.Textures.Smoke)
	e.Color = ColorSequence.new(Color3.fromRGB(160, 150, 140))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Size = ns({ { 0, 0.8 }, { 1, 3.4 } })
	e.Transparency = ns({ { 0, 0.45 }, { 0.6, 0.75 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Drag = 3.5
	e.Acceleration = Vector3.new(0, 3, 0)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Rotation = NumberRange.new(0, 360)
	return e
end

templateBuilders.DustRing = function()
	local e = templateBuilders.Dust()
	e.Name = "DustRing"
	e.Shape = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Speed = NumberRange.new(18, 30)
	e.SpreadAngle = Vector2.new(5, 5)
	e.Drag = 4
	return e
end

templateBuilders.Smoke = function()
	local e = baseEmitter("Smoke", VFXConfig.Textures.Smoke)
	e.Color = ColorSequence.new(Color3.fromRGB(200, 196, 190))
	e.LightInfluence = 1
	e.Size = ns({ { 0, 0.3 }, { 1, 1.6 } })
	e.Transparency = ns({ { 0, 0.55 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(0.6, 1.0)
	e.Speed = NumberRange.new(1.5, 4)
	e.SpreadAngle = Vector2.new(20, 20)
	e.Drag = 2
	e.Acceleration = Vector3.new(0, 2.5, 0)
	e.RotSpeed = NumberRange.new(-30, 30)
	return e
end

templateBuilders.Streak = function()
	local e = baseEmitter("Streak", VFXConfig.Textures.Spark)
	e.Color = ColorSequence.new(Color3.fromRGB(235, 240, 255))
	e.LightEmission = 0.4
	e.LightInfluence = 0.2
	e.Transparency = ns({ { 0, 0.55 }, { 1, 1 } })
	e.Size = ns({ { 0, 0.18 }, { 1, 0.05 } })
	e.Lifetime = NumberRange.new(0.1, 0.18)
	e.Speed = NumberRange.new(30, 45)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Drag = 6
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	pcall(function()
		e.Squash = ns({ { 0, 3 }, { 1, 2 } })
	end)
	return e
end

templateBuilders.Puff = function()
	local e = baseEmitter("Puff", VFXConfig.Textures.Smoke)
	e.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240))
	e.LightInfluence = 0.6
	e.Size = ns({ { 0, 0.4 }, { 1, 2.2 } })
	e.Transparency = ns({ { 0, 0.6 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(0.25, 0.4)
	e.Speed = NumberRange.new(8, 14)
	e.SpreadAngle = Vector2.new(90, 90)
	e.Drag = 8
	return e
end

-- Soft glowing motes for *ability* effects (never used on ordinary weapon attacks).
templateBuilders.Soul = function()
	local e = baseEmitter("Soul", VFXConfig.Textures.Spark)
	e.Color = ColorSequence.new(VFXConfig.Abilities.SoulColor)
	e.LightEmission = 0.8
	e.LightInfluence = 0
	e.Size = ns({ { 0, 0.2 }, { 0.5, 0.6 }, { 1, 0 } })
	e.Transparency = ns({ { 0, 0.2 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(0.5, 1.0)
	e.Speed = NumberRange.new(4, 10)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Acceleration = Vector3.new(0, 4, 0)
	return e
end

local function getTemplate(name: string): ParticleEmitter
	local assets = ReplicatedStorage:FindFirstChild("VFXAssets")
	local custom = assets and assets:FindFirstChild(name)
	if custom and custom:IsA("ParticleEmitter") then
		local clone = custom:Clone()
		clone.Rate = 0
		clone.Enabled = true
		clone.LockedToPart = false
		return clone
	end
	return templateBuilders[name]()
end

local function newHost(name: string): BasePart
	local part = Instance.new("Part")
	part.Name = "Host_" .. name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = FAR
	part.Parent = folder
	return part
end

-- ── Quality / settings ─────────────────────────────────────────────────────────
local function autoQuality(): string
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Medium"
	end
	if ok and type(level) == "number" and level > 0 then
		if level <= 3 then
			return "Low"
		elseif level <= 7 then
			return "Medium"
		end
	end
	return "High"
end

function VFXController.SetQuality(name: string)
	settings.QualityName = name
	local resolved = name == "Auto" and autoQuality() or name
	settings.Quality = VFXConfig.Quality[resolved] or VFXConfig.Quality.High
end

function VFXController.SetReducedMotion(enabled: boolean)
	settings.ReducedMotion = enabled
end

function VFXController.SetCameraShake(enabled: boolean)
	settings.CameraShake = enabled
end

function VFXController.GetQuality()
	return settings.Quality
end

-- ── Helpers exposed to effect modules ─────────────────────────────────────────
function VFXController.Count(n: number): number
	return math.max(0, math.floor(n * settings.Quality.Particles + 0.5))
end

-- Emits `count` particles of a template at `cframe` (emission direction = cframe.LookVector).
function VFXController.Emit(template: string, cframe: CFrame, count: number, overrides: { [string]: any }?)
	local emitter = emitters[template]
	local host = hosts[template]
	if not emitter or not host or count <= 0 then
		return
	end
	host.CFrame = cframe
	local restore = {}
	if overrides then
		for key, value in overrides do
			restore[key] = (emitter :: any)[key];
			(emitter :: any)[key] = value
		end
	end
	emitter:Emit(VFXController.Count(count))
	for key, value in restore do
		(emitter :: any)[key] = value
	end
end

-- Host shape scaling for ring emitters (Cylinder shape uses the host's size).
function VFXController.EmitRing(position: Vector3, normal: Vector3, radius: number, count: number, color: Color3?)
	local host = hosts.DustRing
	if not host then
		return
	end
	host.Size = Vector3.new(radius * 0.5, 0.2, radius * 0.5)
	local up = normal.Magnitude > 0 and normal.Unit or Vector3.yAxis
	local right = up:Cross(Vector3.zAxis)
	if right.Magnitude < 1e-3 then
		right = up:Cross(Vector3.xAxis)
	end
	right = right.Unit
	local cf = CFrame.fromMatrix(position + up * 0.3, right, up)
	VFXController.Emit("DustRing", cf, count, color and { Color = ColorSequence.new(color) } or nil)
	host.Size = Vector3.new(0.2, 0.2, 0.2)
end

local function acquirePart(kind: string, factory: () -> BasePart): BasePart
	local pool = partPools[kind]
	if not pool then
		pool = {}
		partPools[kind] = pool
	end
	local part = table.remove(pool)
	if not part then
		part = factory()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder
	end
	part:SetAttribute("PoolKind", kind)
	return part
end

local function releasePart(part: BasePart)
	local kind = part:GetAttribute("PoolKind")
	part.CFrame = FAR
	if kind and partPools[kind] and #partPools[kind] < 120 then
		table.insert(partPools[kind], part)
	else
		part:Destroy()
	end
end

VFXController.AcquirePart = acquirePart
VFXController.ReleasePart = releasePart

-- Registers a per-frame updater; return false from it to finish.
function VFXController.AddTask(update: (number) -> boolean)
	table.insert(tasks, update)
end

function VFXController.Delay(seconds: number, callback: () -> ())
	local elapsed = 0
	VFXController.AddTask(function(dt)
		elapsed += dt
		if elapsed >= seconds then
			local ok, err = pcall(callback)
			if not ok then
				warn("[VFX] delayed callback: " .. tostring(err))
			end
			return false
		end
		return true
	end)
end

-- Brief point light flash.
function VFXController.Flash(position: Vector3, color: Color3, brightness: number, range: number, lifetime: number)
	if not settings.Quality.Lights then
		return
	end
	local holder = acquirePart("LightHolder", function()
		local p = Instance.new("Part")
		p.Transparency = 1
		p.Size = Vector3.new(0.1, 0.1, 0.1)
		local light = Instance.new("PointLight")
		light.Shadows = false
		light.Parent = p
		return p
	end)
	local light = holder:FindFirstChildOfClass("PointLight") :: PointLight
	holder.CFrame = CFrame.new(position)
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Enabled = true
	local t = 0
	VFXController.AddTask(function(dt)
		t += dt
		local alpha = t / lifetime
		light.Brightness = brightness * math.max(0, 1 - alpha)
		if alpha >= 1 then
			light.Enabled = false
			releasePart(holder)
			return false
		end
		return true
	end)
end

-- Neon streak part that shrinks/fades (impact streaks, air slices).
function VFXController.Streak(
	position: Vector3,
	direction: Vector3,
	length: number,
	width: number,
	color: Color3,
	lifetime: number,
	transparency: number?
)
	local part = acquirePart("Streak", function()
		local p = Instance.new("Part")
		p.Material = Enum.Material.Neon
		return p
	end)
	local dir = direction.Magnitude > 1e-3 and direction.Unit or Vector3.zAxis
	part.Color = color
	part.Transparency = transparency or 0.15
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt(position, position + dir)
	local t = 0
	local start = transparency or 0.15
	VFXController.AddTask(function(dt)
		t += dt
		local alpha = math.clamp(t / lifetime, 0, 1)
		part.Size = Vector3.new(width * (1 - alpha * 0.7), width * (1 - alpha * 0.7), length * (1 - alpha * 0.5))
		part.Transparency = start + (1 - start) * alpha
		if alpha >= 1 then
			releasePart(part)
			return false
		end
		return true
	end)
end

-- Raycast straight down for a ground point (ignores characters and VFX).
function VFXController.GroundAt(position: Vector3, maxDistance: number?): RaycastResult?
	if not raycastParams then
		return nil
	end
	return workspace:Raycast(position + Vector3.new(0, 1.5, 0), Vector3.new(0, -(maxDistance or 12), 0), raycastParams)
end

function VFXController.Raycast(origin: Vector3, direction: Vector3, ignore: { Instance }?): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { folder :: any }
	for _, item in (ignore or {}) :: { Instance } do
		table.insert(list, item)
	end
	params.FilterDescendantsInstances = list
	return workspace:Raycast(origin, direction, params)
end

function VFXController.SurfaceColor(result: RaycastResult?): Color3
	if not result then
		return VFXConfig.SurfaceColors.Default
	end
	local byMaterial = VFXConfig.SurfaceColors[result.Material.Name]
	if byMaterial then
		return byMaterial
	end
	local instance = result.Instance
	if instance and instance:IsA("BasePart") then
		return instance.Color:Lerp(VFXConfig.SurfaceColors.Default, 0.4)
	end
	return VFXConfig.SurfaceColors.Default
end

-- Ballistic rock fragments.
function VFXController.Debris(
	position: Vector3,
	normal: Vector3,
	color: Color3,
	count: number,
	speed: number,
	size: number?
)
	local n = math.min(count, settings.Quality.Debris)
	for _ = 1, n do
		local rock = acquirePart("Rock", function()
			local p = Instance.new("Part")
			p.Material = Enum.Material.Slate
			return p
		end)
		local s = (size or 0.5) * (0.6 + math.random() * 0.8)
		rock.Size = Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.5))
		rock.Color = color:Lerp(Color3.new(0, 0, 0), math.random() * 0.25)
		rock.Transparency = 0
		local up = normal.Magnitude > 0 and normal.Unit or Vector3.yAxis
		local spread = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 1.6
		local velocity = (up * (0.8 + math.random() * 0.6) + spread).Unit * speed * (0.6 + math.random() * 0.5)
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		local cf = CFrame.new(position + up * 0.3)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local t, lifetime = 0, 0.9 + math.random() * 0.4
		local floor = position.Y - 0.2
		VFXController.AddTask(function(dt)
			t += dt
			velocity += Vector3.new(0, -workspace.Gravity * 0.45, 0) * dt
			local p = cf.Position + velocity * dt
			if p.Y < floor and velocity.Y < 0 then
				p = Vector3.new(p.X, floor, p.Z)
				velocity = Vector3.new(velocity.X * 0.4, -velocity.Y * 0.25, velocity.Z * 0.4)
				spin *= 0.4
			end
			cf = CFrame.new(p) * (cf - cf.Position) * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			rock.CFrame = cf
			if t > lifetime - 0.25 then
				rock.Transparency = math.clamp((t - (lifetime - 0.25)) / 0.25, 0, 1)
			end
			if t >= lifetime then
				releasePart(rock)
				return false
			end
			return true
		end)
	end
end

-- Expanding 3D shockwave ring built from thin segments (no flat decals).
function VFXController.Ring(
	position: Vector3,
	normal: Vector3,
	radius: number,
	lifetime: number,
	color: Color3,
	thickness: number
)
	local segments = settings.Quality.RingSegments
	local up = normal.Magnitude > 0 and normal.Unit or Vector3.yAxis
	local right = up:Cross(Vector3.zAxis)
	if right.Magnitude < 1e-3 then
		right = up:Cross(Vector3.xAxis)
	end
	right = right.Unit
	local frame = CFrame.fromMatrix(position + up * 0.15, right, up)
	local parts = {}
	for i = 1, segments do
		local part = acquirePart("RingSeg", function()
			local p = Instance.new("Part")
			p.Material = Enum.Material.SmoothPlastic
			return p
		end)
		part.Color = color
		parts[i] = part
	end
	local t = 0
	VFXController.AddTask(function(dt)
		t += dt
		local alpha = math.clamp(t / lifetime, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		local r = radius * (0.2 + 0.8 * eased)
		local segLength = 2 * math.pi * r / segments * 1.08
		for i, part in parts do
			local angle = (i / segments) * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			part.Size = Vector3.new(thickness * (1 - alpha * 0.6), thickness * 0.5 * (1 - alpha), segLength)
			part.CFrame = frame * CFrame.new(offset) * CFrame.Angles(0, -angle, 0)
			part.Transparency = 0.25 + 0.75 * alpha
		end
		if alpha >= 1 then
			for _, part in parts do
				releasePart(part)
			end
			return false
		end
		return true
	end)
end

-- Fading copy of a character's body parts (dash afterimages). Cheap: body parts only.
function VFXController.Afterimage(character: Model, color: Color3, transparency: number, lifetime: number)
	if settings.Quality.Afterimages <= 0 then
		return
	end
	local ghosts = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and child.Transparency < 0.9 then
			local ghost = acquirePart("Ghost", function()
				local p = Instance.new("Part")
				p.Material = Enum.Material.SmoothPlastic
				return p
			end)
			ghost.Size = child.Size
			ghost.CFrame = child.CFrame
			ghost.Color = color
			ghost.Transparency = transparency
			table.insert(ghosts, ghost)
		end
	end
	local t = 0
	VFXController.AddTask(function(dt)
		t += dt
		local alpha = math.clamp(t / lifetime, 0, 1)
		for _, ghost in ghosts do
			ghost.Transparency = transparency + (1 - transparency) * alpha
		end
		if alpha >= 1 then
			for _, ghost in ghosts do
				releasePart(ghost)
			end
			return false
		end
		return true
	end)
end

-- 3D muzzle flash: neon petals + core, lasting a couple of frames.
function VFXController.MuzzleFlash(cframe: CFrame, size: number, color: Color3, lifetime: number)
	local parts = {}
	local core = acquirePart("FlashCore", function()
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		return p
	end)
	core.Color = color
	core.Size = Vector3.new(size * 0.45, size * 0.45, size * 0.45)
	core.CFrame = cframe * CFrame.new(0, 0, -size * 0.15)
	core.Transparency = 0.1
	table.insert(parts, core)
	for i = 0, 3 do
		local petal = acquirePart("FlashPetal", function()
			local p = Instance.new("Part")
			p.Material = Enum.Material.Neon
			return p
		end)
		petal.Color = color
		petal.Transparency = 0.2
		petal.Size = Vector3.new(size * 0.1, size * 0.1, size * (0.6 + (i % 2) * 0.3))
		local angle = i * math.pi / 2 + math.random() * 0.4
		petal.CFrame = cframe
			* CFrame.Angles(0, 0, angle)
			* CFrame.Angles(math.rad(18), 0, 0)
			* CFrame.new(0, 0, -size * 0.35)
		table.insert(parts, petal)
	end
	local t = 0
	VFXController.AddTask(function(dt)
		t += dt
		if t >= lifetime then
			for _, part in parts do
				releasePart(part)
			end
			return false
		end
		return true
	end)
end

-- ── Camera shake ──────────────────────────────────────────────────────────────
function VFXController.Shake(intensity: number, position: Vector3?, range: number?)
	if settings.ReducedMotion or not settings.CameraShake then
		return
	end
	local scale = settings.Quality.ShakeScale
	if position then
		local camera = workspace.CurrentCamera
		local distance = camera and (camera.CFrame.Position - position).Magnitude or 0
		scale *= math.clamp(1 - distance / (range or 60), 0, 1)
	end
	shake.Intensity = math.min(VFXConfig.CameraShake.MaxIntensity, shake.Intensity + intensity * scale)
end

local function updateShake(dt: number)
	if shake.Intensity <= 0.001 then
		shake.Intensity = 0
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local config = VFXConfig.CameraShake
	local t = os.clock() * config.Frequency
	local amount = math.rad(config.MaxAngleDegrees) * shake.Intensity
	local rx = math.noise(t, shake.Seed) * amount
	local ry = math.noise(shake.Seed, t) * amount
	camera.CFrame *= CFrame.Angles(rx, ry, 0)
	shake.Intensity = math.max(0, shake.Intensity - config.Decay * dt * shake.Intensity - dt * 0.2)
end

-- ── Sounds (placeholder aware) ────────────────────────────────────────────────
function VFXController.Sound(soundId: string?, position: Vector3?, volume: number?, pitch: number?)
	if WeaponConfig.IsPlaceholder(soundId) then
		return
	end
	local holder = acquirePart("SoundHolder", function()
		local p = Instance.new("Part")
		p.Transparency = 1
		p.Size = Vector3.new(0.1, 0.1, 0.1)
		local sound = Instance.new("Sound")
		sound.RollOffMaxDistance = 120
		sound.Parent = p
		return p
	end)
	local sound = holder:FindFirstChildOfClass("Sound") :: Sound
	holder.CFrame = CFrame.new(position or Vector3.zero)
	sound.SoundId = soundId :: string
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = (pitch or 1) * (0.95 + math.random() * 0.1)
	sound:Play()
	VFXController.Delay(3, function()
		sound:Stop()
		releasePart(holder)
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────
function VFXController.Init()
	if folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "ClientVFX"
	f.Parent = workspace
	folder = f
	for name in templateBuilders do
		local host = newHost(name)
		local emitter = getTemplate(name)
		emitter.Parent = host
		hosts[name] = host
		emitters[name] = emitter
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { f }
	raycastParams = params

	for _, module in Effects:GetChildren() do
		if module:IsA("ModuleScript") and string.sub(module.Name, 1, 1) ~= "_" then
			effectModules[module.Name] = require(module) :: any
		end
	end

	VFXController.SetQuality("Auto")
	RunService:BindToRenderStep("SoulEaterVFX", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local i = 1
		while i <= #tasks do
			local ok, keep = pcall(tasks[i], dt)
			if ok and keep then
				i += 1
			else
				if not ok then
					warn("[VFX] task error: " .. tostring(keep))
				end
				tasks[i] = tasks[#tasks]
				tasks[#tasks] = nil
			end
		end
		updateShake(dt)
	end)
end

-- Excludes characters from ground raycasts as they spawn.
function VFXController.IgnoreForRaycasts(instance: Instance)
	if raycastParams then
		local list = raycastParams.FilterDescendantsInstances
		table.insert(list, instance)
		raycastParams.FilterDescendantsInstances = list
	end
end

-- Plays one of the 10 weapon effects (or an ability effect) by module name.
function VFXController.Play(effectName: string, params: { [string]: any })
	local module = effectModules[effectName]
	if not module then
		warn("[VFX] unknown effect " .. tostring(effectName))
		return
	end
	local base = VFXConfig.Effects[effectName]
	if base and base.Enabled == false then
		return
	end
	local config = table.clone(base or {})
	for k, v in params.Params or {} do
		config[k] = v
	end
	local ok, err = pcall(module, VFXController, params, config)
	if not ok then
		warn(string.format("[VFX] %s failed: %s", effectName, tostring(err)))
	end
end

function VFXController.ActiveTaskCount(): number
	return #tasks
end

return VFXController
