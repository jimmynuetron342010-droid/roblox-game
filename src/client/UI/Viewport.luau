--[[
	Viewport
	3D previews inside the UI (ViewportFrames do not run physics, so models are built anchored and
	posed with PosePreview.SolveJoints):
	  * Viewport.Character — PreviewRig wearing the student's look + a race's features/aura
	  * Viewport.Weapon    — any weapon model, auto-framed
	Slow turntable rotation unless reduced motion is on.
]]

local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local PosePreview = require(Modules.Animation.PosePreview)
local PreviewRig = require(Modules.Rig.PreviewRig)
local RaceAppearance = require(Modules.Race.RaceAppearance)
local StudentAppearance = require(Modules.Race.StudentAppearance)
local StudentConfig = require(Modules.Config.StudentConfig)
local WeaponBuilder = require(Modules.WeaponBuilder)

local Theme = require(script.Parent.Theme)

local Viewport = {}

local function newViewport(parent: Instance?, size: UDim2?): (ViewportFrame, Camera)
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = size or UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(150, 140, 170)
	viewport.LightColor = Color3.fromRGB(255, 244, 232)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport, camera
end

-- Keeps a model slowly turning around `center` while the viewport is visible.
local function turntable(viewport: ViewportFrame, model: Model, center: Vector3, speed: number)
	if Theme.ReducedMotion() then
		return
	end
	local initial = model:GetPivot()
	local angle = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not viewport.Parent or not model.Parent then
			connection:Disconnect()
			return
		end
		if viewport.Visible then
			angle += dt * speed
			model:PivotTo(CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(-center) * initial)
		end
	end)
end

export type CharacterOptions = {
	Student: any?,
	RaceId: string?,
	Stage: number?,
	Spin: boolean?,
	Framing: "Portrait" | "Full" | nil,
}

function Viewport.Character(parent: Instance?, options: CharacterOptions)
	local viewport, camera = newViewport(parent)
	local student = options.Student or { SkinTone = 2, HairColor = 1, HairStyle = 2, Uniform = 2, Wavelength = "Calm" }
	local skin = StudentConfig.SkinTones[student.SkinTone] or StudentConfig.SkinTones[2]
	local uniform = StudentConfig.Uniforms[student.Uniform] or StudentConfig.Uniforms[2]
	local rig = PreviewRig.Build({
		Origin = CFrame.new(0, 3, 0),
		Anchored = true,
		SkinColor = skin,
		TorsoColor = uniform.Primary,
		LegColor = uniform.Primary:Lerp(Color3.new(0, 0, 0), 0.25),
	})
	-- Relaxed stance (arms slightly out, weight on one leg).
	local function pose(part: string, joint: string, rotation: CFrame)
		local p = rig:FindFirstChild(part)
		local motor = p and p:FindFirstChild(joint) :: Motor6D?
		if motor then
			motor.Transform = rotation
		end
	end
	pose("RightUpperArm", "RightShoulder", CFrame.Angles(math.rad(8), 0, math.rad(10)))
	pose("LeftUpperArm", "LeftShoulder", CFrame.Angles(math.rad(-6), 0, math.rad(-12)))
	pose("RightLowerArm", "RightElbow", CFrame.Angles(math.rad(14), 0, 0))
	pose("LeftLowerArm", "LeftElbow", CFrame.Angles(math.rad(10), 0, 0))
	pose("RightUpperLeg", "RightHip", CFrame.Angles(0, 0, math.rad(4)))
	pose("LeftUpperLeg", "LeftHip", CFrame.Angles(0, 0, math.rad(-6)))
	PosePreview.SolveJoints(rig.PrimaryPart :: BasePart, { rig })
	pcall(StudentAppearance.Apply, rig, student, options.RaceId, true)
	-- StudentAppearance sets BodyColors; ViewportFrames ignore BodyColors, so tint parts directly.
	local bodyColors = rig:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		for _, name in
			{ "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" }
		do
			local p = rig:FindFirstChild(name) :: BasePart?
			if p then
				p.Color = bodyColors.HeadColor3
			end
		end
	end
	if options.RaceId and options.RaceId ~= "" then
		pcall(RaceAppearance.Apply, rig, options.RaceId, options.Stage or 1, true)
	end
	rig.Parent = viewport
	local focus = options.Framing == "Portrait" and Vector3.new(0, 4.3, 0) or Vector3.new(0, 2.6, 0)
	local distance = options.Framing == "Portrait" and 8 or 15
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(-distance * 0.35, distance * 0.12, -distance), focus)
	if options.Spin then
		turntable(viewport, rig, rig:GetPivot().Position, 0.5)
	end
	return viewport, rig
end

function Viewport.Weapon(parent: Instance?, weaponId: string, form: string?, spin: boolean?)
	local viewport, camera = newViewport(parent)
	local ok, model = pcall(function(): Model
		return (WeaponBuilder.Build(weaponId, { Form = form, Anchored = true, Origin = CFrame.new() }))
	end)
	if not ok then
		return viewport, nil
	end
	local weaponModel = model :: Model
	weaponModel.Parent = viewport
	local cf, size = weaponModel:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 0.9
	camera.CFrame =
		CFrame.lookAt(cf.Position + Vector3.new(distance * 0.85, distance * 0.25, -distance * 0.45), cf.Position)
	if spin then
		turntable(viewport, weaponModel, cf.Position, 0.6)
	end
	return viewport, weaponModel
end

return Viewport
