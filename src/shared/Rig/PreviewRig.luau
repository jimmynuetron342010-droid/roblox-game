--[[
	PreviewRig
	Builds a block-style R15 character (same part names, joints and attachments as Roblox's R15 rig).
	Used for:
	  * ViewportFrame portraits (race reveal, collection index, character creator)
	  * the offline render/test pipeline (weapons held by an R15 character)
	Real player characters bring their own (possibly scaled) rig; all game code reads joint C0/C1
	and attachment CFrames from the actual instances, never from these constants.
]]

local PreviewRig = {}

-- name, size, parent joint name, joint name, C0 (in parent), C1 (in part)
PreviewRig.Parts = {
	{
		"LowerTorso",
		Vector3.new(2, 0.4, 1),
		"HumanoidRootPart",
		"Root",
		Vector3.new(0, -1, 0),
		Vector3.new(0, -0.2, 0),
	},
	{ "UpperTorso", Vector3.new(2, 1.6, 1), "LowerTorso", "Waist", Vector3.new(0, 0.2, 0), Vector3.new(0, -0.8, 0) },
	{ "Head", Vector3.new(1.2, 1.2, 1.2), "UpperTorso", "Neck", Vector3.new(0, 0.8, 0), Vector3.new(0, -0.5, 0) },
	{
		"RightUpperArm",
		Vector3.new(1, 1.169, 1),
		"UpperTorso",
		"RightShoulder",
		Vector3.new(1, 0.563, 0),
		Vector3.new(-0.5, 0.42, 0),
	},
	{
		"RightLowerArm",
		Vector3.new(1, 1.052, 1),
		"RightUpperArm",
		"RightElbow",
		Vector3.new(0, -0.334, 0),
		Vector3.new(0, 0.259, 0),
	},
	{
		"RightHand",
		Vector3.new(1, 0.3, 1),
		"RightLowerArm",
		"RightWrist",
		Vector3.new(0, -0.501, 0),
		Vector3.new(0, 0.125, 0),
	},
	{
		"LeftUpperArm",
		Vector3.new(1, 1.169, 1),
		"UpperTorso",
		"LeftShoulder",
		Vector3.new(-1, 0.563, 0),
		Vector3.new(0.5, 0.42, 0),
	},
	{
		"LeftLowerArm",
		Vector3.new(1, 1.052, 1),
		"LeftUpperArm",
		"LeftElbow",
		Vector3.new(0, -0.334, 0),
		Vector3.new(0, 0.259, 0),
	},
	{
		"LeftHand",
		Vector3.new(1, 0.3, 1),
		"LeftLowerArm",
		"LeftWrist",
		Vector3.new(0, -0.501, 0),
		Vector3.new(0, 0.125, 0),
	},
	{
		"RightUpperLeg",
		Vector3.new(1, 1.217, 1),
		"LowerTorso",
		"RightHip",
		Vector3.new(0.5, -0.2, 0),
		Vector3.new(0, 0.421, 0),
	},
	{
		"RightLowerLeg",
		Vector3.new(1, 1.193, 1),
		"RightUpperLeg",
		"RightKnee",
		Vector3.new(0, -0.41, 0),
		Vector3.new(0, 0.294, 0),
	},
	{
		"RightFoot",
		Vector3.new(1, 0.3, 1),
		"RightLowerLeg",
		"RightAnkle",
		Vector3.new(0, -0.547, 0),
		Vector3.new(0, 0.101, 0),
	},
	{
		"LeftUpperLeg",
		Vector3.new(1, 1.217, 1),
		"LowerTorso",
		"LeftHip",
		Vector3.new(-0.5, -0.2, 0),
		Vector3.new(0, 0.421, 0),
	},
	{
		"LeftLowerLeg",
		Vector3.new(1, 1.193, 1),
		"LeftUpperLeg",
		"LeftKnee",
		Vector3.new(0, -0.41, 0),
		Vector3.new(0, 0.294, 0),
	},
	{
		"LeftFoot",
		Vector3.new(1, 0.3, 1),
		"LeftLowerLeg",
		"LeftAnkle",
		Vector3.new(0, -0.547, 0),
		Vector3.new(0, 0.101, 0),
	},
}

-- Accessory/grip attachments (part, name, position, orientation in degrees).
PreviewRig.Attachments = {
	{ "Head", "HatAttachment", Vector3.new(0, 0.6, 0), Vector3.zero },
	{ "Head", "HairAttachment", Vector3.new(0, 0.6, 0), Vector3.zero },
	{ "Head", "FaceFrontAttachment", Vector3.new(0, 0, -0.6), Vector3.zero },
	{ "Head", "FaceCenterAttachment", Vector3.zero, Vector3.zero },
	{ "UpperTorso", "BodyFrontAttachment", Vector3.new(0, 0, -0.5), Vector3.zero },
	{ "UpperTorso", "BodyBackAttachment", Vector3.new(0, 0, 0.5), Vector3.zero },
	{ "UpperTorso", "NeckAttachment", Vector3.new(0, 0.8, 0), Vector3.zero },
	{ "UpperTorso", "RightCollarAttachment", Vector3.new(1, 0.8, 0), Vector3.zero },
	{ "UpperTorso", "LeftCollarAttachment", Vector3.new(-1, 0.8, 0), Vector3.zero },
	{ "LowerTorso", "WaistBackAttachment", Vector3.new(0, 0, 0.5), Vector3.zero },
	{ "LowerTorso", "WaistFrontAttachment", Vector3.new(0, 0, -0.5), Vector3.zero },
	{ "RightUpperArm", "RightShoulderAttachment", Vector3.new(0, 0.58, 0), Vector3.zero },
	{ "LeftUpperArm", "LeftShoulderAttachment", Vector3.new(0, 0.58, 0), Vector3.zero },
	{ "RightHand", "RightGripAttachment", Vector3.new(0, -0.15, 0), Vector3.new(-90, 0, 0) },
	{ "LeftHand", "LeftGripAttachment", Vector3.new(0, -0.15, 0), Vector3.new(-90, 0, 0) },
}

export type BuildOptions = {
	Origin: CFrame?, -- HumanoidRootPart CFrame
	SkinColor: Color3?,
	TorsoColor: Color3?,
	LegColor: Color3?,
	Anchored: boolean?,
	Humanoid: boolean?,
}

local function orientation(degrees: Vector3): CFrame
	return CFrame.fromOrientation(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

function PreviewRig.Build(options: BuildOptions?): Model
	local opts = options or {}
	local origin = opts.Origin or CFrame.new(0, 3, 0)
	local skin = opts.SkinColor or Color3.fromRGB(241, 194, 158)
	local torso = opts.TorsoColor or Color3.fromRGB(40, 40, 52)
	local legs = opts.LegColor or Color3.fromRGB(30, 30, 40)

	local model = Instance.new("Model")
	model.Name = "PreviewRig"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = origin
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local parts = { HumanoidRootPart = root }
	for _, def in PreviewRig.Parts do
		local name, size, parentName, jointName, c0, c1 = def[1], def[2], def[3], def[4], def[5], def[6]
		local parent = parts[parentName]
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = parent.CFrame * CFrame.new(c0) * CFrame.new(c1):Inverse()
		part.Anchored = opts.Anchored == true
		part.CanCollide = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if string.find(name, "Torso") then
			part.Color = torso
		elseif string.find(name, "Leg") or string.find(name, "Foot") then
			part.Color = legs
		else
			part.Color = skin
		end
		part.Parent = model
		parts[name] = part

		local parentAttachment = Instance.new("Attachment")
		parentAttachment.Name = jointName .. "RigAttachment"
		parentAttachment.CFrame = CFrame.new(c0)
		parentAttachment.Parent = parent
		local childAttachment = Instance.new("Attachment")
		childAttachment.Name = jointName .. "RigAttachment"
		childAttachment.CFrame = CFrame.new(c1)
		childAttachment.Parent = part

		local motor = Instance.new("Motor6D")
		motor.Name = jointName
		motor.Part0 = parent
		motor.Part1 = part
		motor.C0 = CFrame.new(c0)
		motor.C1 = CFrame.new(c1)
		motor.Transform = CFrame.new()
		motor.Parent = part
	end

	for _, def in PreviewRig.Attachments do
		local attachment = Instance.new("Attachment")
		attachment.Name = def[2]
		attachment.CFrame = CFrame.new(def[3]) * orientation(def[4])
		attachment.Parent = parts[def[1]]
	end

	if opts.Humanoid then
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.Parent = model
	end

	return model
end

--[[
	Forward kinematics without a physics step: recomputes every part's CFrame from the root and the
	current Motor6D C0 * Transform * C1^-1. Needed inside ViewportFrames (no joint solving there)
	and for offline rendering.
]]
function PreviewRig.SolvePose(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local solved = { [root] = true }
	local function solve(part: BasePart)
		for _, def in PreviewRig.Parts do
			local child = model:FindFirstChild(def[1]) :: BasePart?
			if child and not solved[child] then
				local motor = child:FindFirstChild(def[4]) :: Motor6D?
				if motor and motor.Part0 == part then
					child.CFrame = part.CFrame * motor.C0 * motor.Transform * motor.C1:Inverse()
					solved[child] = true
					solve(child)
				end
			end
		end
	end
	solve(root)
end

return PreviewRig
