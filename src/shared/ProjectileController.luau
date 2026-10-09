--[[
	ProjectileController
	One kinematic model for every projectile, used twice:
	  * Server (`Simulate`): authoritative. Sphere-casts each step, reports the first hit, applies
	    lifetime/range limits. CombatService turns hits into damage.
	  * Client (`Visual`): draws the same flight (shuriken model, tracer, spell bolt) from the same
	    origin/direction/speed so what players see matches what the server decided.
	All active projectiles are stepped by a single Heartbeat connection.
]]

local RunService = game:GetService("RunService")

local ProjectileController = {}

export type Spec = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Range: number,
	Radius: number?,
	Gravity: number?,
	Lifetime: number?,
	Ignore: { Instance }?,
	Include: { Instance }?, -- if set, only these can be hit
	Pierce: number?,
	Homing: { Target: Model?, Turn: number }?,
	OnStep: ((Vector3, Vector3, number) -> ())?,
	OnHit: ((RaycastResult) -> boolean?)?, -- return true to keep flying (pierce)
	OnEnd: (() -> ())?,
}

type Active = {
	Spec: Spec,
	Position: Vector3,
	Velocity: Vector3,
	Travelled: number,
	Age: number,
	Params: RaycastParams,
	PierceLeft: number,
	Done: boolean,
}

local active: { Active } = {}
local connection: RBXScriptConnection? = nil

local function finish(projectile: Active)
	if projectile.Done then
		return
	end
	projectile.Done = true
	if projectile.Spec.OnEnd then
		local ok, err = pcall(projectile.Spec.OnEnd)
		if not ok then
			warn("[Projectile] OnEnd: " .. tostring(err))
		end
	end
end

local function step(projectile: Active, dt: number)
	local spec = projectile.Spec
	projectile.Age += dt
	if spec.Homing and spec.Homing.Target and spec.Homing.Target.Parent then
		local target = spec.Homing.Target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if target then
			local desired = (target.Position - projectile.Position).Unit * projectile.Velocity.Magnitude
			local turn = math.clamp(spec.Homing.Turn * dt, 0, 1)
			projectile.Velocity = projectile.Velocity:Lerp(desired, turn)
		end
	end
	if spec.Gravity then
		projectile.Velocity += Vector3.new(0, -spec.Gravity, 0) * dt
	end
	local displacement = projectile.Velocity * dt
	local result: RaycastResult?
	local radius = spec.Radius or 0
	if radius > 0 then
		result = workspace:Spherecast(projectile.Position, radius, displacement, projectile.Params)
	else
		result = workspace:Raycast(projectile.Position, displacement, projectile.Params)
	end
	if result then
		projectile.Position = result.Position
		local keepGoing = false
		if spec.OnHit then
			local ok, value = pcall(spec.OnHit, result)
			keepGoing = ok and value == true
			if not ok then
				warn("[Projectile] OnHit: " .. tostring(value))
			end
		end
		if keepGoing and projectile.PierceLeft > 0 then
			projectile.PierceLeft -= 1
			-- Ignore the model we passed through.
			local list = projectile.Params.FilterDescendantsInstances
			local model = result.Instance:FindFirstAncestorOfClass("Model") or result.Instance
			table.insert(list, model)
			projectile.Params.FilterDescendantsInstances = list
		else
			finish(projectile)
			return
		end
	else
		projectile.Position += displacement
	end
	projectile.Travelled += displacement.Magnitude
	if spec.OnStep then
		spec.OnStep(projectile.Position, projectile.Velocity.Unit, dt)
	end
	if projectile.Travelled >= spec.Range or projectile.Age >= (spec.Lifetime or 3) then
		finish(projectile)
	end
end

local function ensureLoop()
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		local i = 1
		while i <= #active do
			local projectile = active[i]
			if not projectile.Done then
				local ok, err = pcall(step, projectile, dt)
				if not ok then
					warn("[Projectile] step: " .. tostring(err))
					finish(projectile)
				end
			end
			if projectile.Done then
				active[i] = active[#active]
				active[#active] = nil
			else
				i += 1
			end
		end
	end)
end

local function launch(spec: Spec): Active
	local params = RaycastParams.new()
	if spec.Include then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = spec.Include
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = table.clone(spec.Ignore or {})
		local vfxFolder = workspace:FindFirstChild("ClientVFX")
		if vfxFolder then
			table.insert(ignore, vfxFolder)
		end
		params.FilterDescendantsInstances = ignore
	end
	local direction = spec.Direction.Magnitude > 0 and spec.Direction.Unit or Vector3.new(0, 0, -1)
	local projectile = {
		Spec = spec,
		Position = spec.Origin,
		Velocity = direction * spec.Speed,
		Travelled = 0,
		Age = 0,
		Params = params,
		PierceLeft = spec.Pierce or 0,
		Done = false,
	}
	table.insert(active, projectile)
	ensureLoop()
	return projectile
end

-- Server: authoritative simulation.
function ProjectileController.Simulate(spec: Spec)
	return launch(spec)
end

-- Client: visual-only flight with the same kinematics.
function ProjectileController.Visual(spec: Spec)
	return launch(spec)
end

function ProjectileController.ActiveCount(): number
	return #active
end

-- Closed-form position for tests and prediction.
function ProjectileController.PositionAt(
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravity: number?,
	t: number
): Vector3
	local v = direction.Unit * speed
	local g = Vector3.new(0, -(gravity or 0), 0)
	return origin + v * t + g * (0.5 * t * t)
end

return ProjectileController
