--[[
	StudentAppearance
	Applies the "Create Your Student" choices to a character: skin tone (blended with the race's
	tint, e.g. Zombie / Golem), uniform colors, and part-built hairstyles. "Keep" options preserve
	the player's own avatar clothing/hair.
]]

local Modules = script.Parent.Parent
local GeometryKit = require(Modules.Core.GeometryKit)
local RaceConfig = require(Modules.Config.RaceConfig)
local StudentConfig = require(Modules.Config.StudentConfig)

local StudentAppearance = {}

StudentAppearance.FolderName = "StudentCosmetics"

local function pick(list, index, default)
	return list[index] or list[default or 1]
end

local function getBodyColors(character: Model): BodyColors
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if not bodyColors then
		bodyColors = Instance.new("BodyColors")
		bodyColors.Parent = character
	end
	return bodyColors :: BodyColors
end

local function hairKit(character: Model, folder: Model, anchored: boolean)
	local head = character:FindFirstChild("Head") :: BasePart?
	local attachment = head and head:FindFirstChild("HairAttachment") :: Attachment?
	if not head or not attachment then
		return nil
	end
	return GeometryKit.new({
		Model = folder,
		Root = head,
		Origin = head.CFrame * attachment.CFrame,
		Scale = math.clamp(head.Size.Y / 1.2, 0.7, 1.6),
		Anchored = anchored,
	})
end

local Hairstyles = {}

Hairstyles.Spiked = function(kit, color)
	kit:Block("HairCap", Vector3.new(1.3, 0.3, 1.3), CFrame.new(0, -0.05, 0.02), color)
	local spikes = {
		{ Vector3.new(0, 0, 0), Vector3.new(0, 0.95, 0.15) },
		{ Vector3.new(-0.4, -0.05, 0), Vector3.new(-0.85, 0.65, 0.1) },
		{ Vector3.new(0.4, -0.05, 0), Vector3.new(0.85, 0.65, 0.1) },
		{ Vector3.new(0, -0.05, 0.4), Vector3.new(0, 0.55, 0.95) },
		{ Vector3.new(-0.3, -0.05, 0.35), Vector3.new(-0.7, 0.4, 0.85) },
		{ Vector3.new(0.3, -0.05, 0.35), Vector3.new(0.7, 0.4, 0.85) },
	}
	for _, spike in spikes do
		kit:Spike("HairSpike", spike[1], spike[2], 0.55, 0.28, color)
		kit:Spike("HairSpike", spike[1], spike[2], 0.55, 0.28, color, Vector3.zAxis)
	end
end

Hairstyles.Pigtails = function(kit, color)
	kit:Block("HairCap", Vector3.new(1.32, 0.32, 1.32), CFrame.new(0, -0.08, 0.02), color)
	kit:Block("HairBack", Vector3.new(1.3, 0.9, 0.22), CFrame.new(0, -0.5, 0.6), color)
	for _, side in { -1, 1 } do
		kit:Ball("Tie", 0.22, Vector3.new(0.72 * side, -0.3, 0.2), Color3.fromRGB(196, 28, 40))
		kit:Cylinder("Tail", Vector3.new(0.78 * side, -0.35, 0.25), Vector3.new(0.95 * side, -1.35, 0.35), 0.42, color)
		kit:Ball("TailEnd", 0.4, Vector3.new(0.95 * side, -1.38, 0.35), color)
	end
end

Hairstyles.Swept = function(kit, color)
	kit:Block("HairCap", Vector3.new(1.34, 0.34, 1.34), CFrame.new(0, -0.06, 0.04), color)
	kit:Block("HairBack", Vector3.new(1.3, 0.7, 0.24), CFrame.new(0, -0.4, 0.6), color)
	kit:Triangle(
		"Fringe",
		Vector3.new(-0.66, 0.02, -0.66),
		Vector3.new(0.5, 0.02, -0.66),
		Vector3.new(0.55, -0.5, -0.7),
		0.12,
		color
	)
	kit:Triangle(
		"Fringe",
		Vector3.new(-0.66, 0.02, -0.66),
		Vector3.new(-0.2, -0.32, -0.7),
		Vector3.new(-0.66, -0.45, -0.66),
		0.12,
		color
	)
end

Hairstyles.Crop = function(kit, color)
	kit:Block("HairCap", Vector3.new(1.26, 0.22, 1.26), CFrame.new(0, -0.08, 0.02), color)
	kit:Block("HairBack", Vector3.new(1.24, 0.42, 0.16), CFrame.new(0, -0.28, 0.58), color)
end

StudentAppearance.Hairstyles = Hairstyles

local function removeAvatarHair(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") then
			local ok, accessoryType = pcall(function()
				return child.AccessoryType
			end)
			if ok and accessoryType == Enum.AccessoryType.Hair then
				child:Destroy()
			end
		end
	end
end

function StudentAppearance.Apply(character: Model, student, raceId: string?, anchored: boolean?)
	local old = character:FindFirstChild(StudentAppearance.FolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = StudentAppearance.FolderName
	folder.Parent = character

	-- Skin, blended toward the race tint (Zombie pallor, Golem stone, ...).
	local skin = pick(StudentConfig.SkinTones, student.SkinTone, 2)
	local race = raceId and RaceConfig.ById[raceId]
	if race and race.Appearance.SkinTint then
		skin = skin:Lerp(race.Appearance.SkinTint, 0.65)
	end
	local bodyColors = getBodyColors(character)
	bodyColors.HeadColor3 = skin
	bodyColors.LeftArmColor3 = skin
	bodyColors.RightArmColor3 = skin

	local uniform = pick(StudentConfig.Uniforms, student.Uniform, 1)
	if not uniform.Keep then
		for _, child in character:GetChildren() do
			if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
				child:Destroy()
			end
		end
		bodyColors.TorsoColor3 = uniform.Primary
		bodyColors.LeftLegColor3 = uniform.Primary:Lerp(Color3.new(0, 0, 0), 0.25)
		bodyColors.RightLegColor3 = uniform.Primary:Lerp(Color3.new(0, 0, 0), 0.25)
		-- Small uniform details: tie and belt.
		local torso = character:FindFirstChild("UpperTorso") :: BasePart?
		local front = torso and torso:FindFirstChild("BodyFrontAttachment") :: Attachment?
		if torso and front then
			local kit = GeometryKit.new({
				Model = folder,
				Root = torso,
				Origin = torso.CFrame * front.CFrame,
				Anchored = anchored,
			})
			kit:Triangle(
				"Tie",
				Vector3.new(-0.14, 0.62, -0.03),
				Vector3.new(0.14, 0.62, -0.03),
				Vector3.new(0, -0.35, -0.03),
				0.06,
				uniform.Secondary
			)
			kit:Block("Collar", Vector3.new(0.9, 0.12, 0.06), CFrame.new(0, 0.72, -0.02), uniform.Secondary)
		end
		local lower = character:FindFirstChild("LowerTorso") :: BasePart?
		local waist = lower and lower:FindFirstChild("WaistFrontAttachment") :: Attachment?
		if lower and waist then
			local kit = GeometryKit.new({
				Model = folder,
				Root = lower,
				Origin = lower.CFrame * waist.CFrame,
				Anchored = anchored,
			})
			kit:Block("Belt", Vector3.new(2.06, 0.16, 0.08), CFrame.new(0, 0.1, -0.02), Color3.fromRGB(28, 26, 30))
			kit:Block(
				"Buckle",
				Vector3.new(0.26, 0.2, 0.06),
				CFrame.new(0, 0.1, -0.07),
				Color3.fromRGB(200, 196, 180),
				Enum.Material.Metal
			)
		end
	end

	local style = pick(StudentConfig.HairStyles, student.HairStyle, 1)
	if style ~= "Keep" and Hairstyles[style] then
		removeAvatarHair(character)
		local kit = hairKit(character, folder, anchored == true)
		if kit then
			local color = pick(StudentConfig.HairColors, student.HairColor, 1).Color
			Hairstyles[style](kit, color)
		end
	end
end

return StudentAppearance
