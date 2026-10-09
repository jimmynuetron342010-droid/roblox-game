--[[
	RaceAppearance
	Racial visual identity: part-built features mounted on the character's standard R15 attachments
	(so they fit any avatar), a soul aura whose intensity grows with mastery stage, and the
	Stage III prestige aura. Used by the server on real characters (replicates to everyone) and by
	the client on PreviewRig models for portraits.

	Mastery gates visuals: Stage I = core features + faint aura, Stage II = stronger aura and
	upgraded feature details, Stage III = unique dual-color aura.
]]

local Modules = script.Parent.Parent
local GeometryKit = require(Modules.Core.GeometryKit)
local RaceConfig = require(Modules.Config.RaceConfig)

local RaceAppearance = {}

RaceAppearance.FolderName = "RaceCosmetics"
RaceAppearance.AuraName = "SoulAura"

local function findAttachment(character: Model, name: string): Attachment?
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") and parent.Parent == character then
				return descendant
			end
		end
	end
	return nil
end

-- Creates a GeometryKit whose model space is the given attachment's frame.
local function kitAt(character: Model, folder: Model, attachmentName: string, anchored: boolean, scale: number?)
	local attachment = findAttachment(character, attachmentName)
	if not attachment then
		return nil
	end
	local part = attachment.Parent :: BasePart
	return GeometryKit.new({
		Model = folder,
		Root = part,
		Origin = part.CFrame * attachment.CFrame,
		Scale = scale or 1,
		Anchored = anchored,
		CastShadow = false,
	})
end

local function headScale(character: Model): number
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		return math.clamp(head.Size.Y / 1.2, 0.7, 1.6)
	end
	return 1
end

local Features = {}

Features.WolfEars = function(character, folder, anchored)
	local kit = kitAt(character, folder, "HatAttachment", anchored, headScale(character))
	if not kit then
		return
	end
	local fur = Color3.fromRGB(120, 124, 134)
	local inner = Color3.fromRGB(196, 150, 150)
	for _, side in { -1, 1 } do
		local base = Vector3.new(0.38 * side, -0.05, 0.05)
		kit:Triangle(
			"Ear",
			base + Vector3.new(-0.2, 0, 0),
			base + Vector3.new(0.2, 0, 0),
			base + Vector3.new(0.12 * side, 0.55, 0.08),
			0.14,
			fur
		)
		kit:Triangle(
			"EarInner",
			base + Vector3.new(-0.11, 0.03, -0.06),
			base + Vector3.new(0.11, 0.03, -0.06),
			base + Vector3.new(0.1 * side, 0.4, 0.02),
			0.05,
			inner
		)
	end
end

Features.Claws = function(character, folder, anchored, stage)
	for _, gripName in { "RightGripAttachment", "LeftGripAttachment" } do
		local kit = kitAt(character, folder, gripName, anchored)
		if kit then
			local color = stage >= 2 and Color3.fromRGB(230, 226, 214) or Color3.fromRGB(196, 192, 180)
			for i = -1, 1 do
				-- In grip space -Y points out of the fist (forward when the arm hangs).
				local base = Vector3.new(i * 0.22, -0.05, -0.38)
				kit:Spike("Claw", base, base + Vector3.new(i * 0.05, -0.45, -0.12), 0.12, 0.05, color, Vector3.xAxis)
			end
		end
	end
end

Features.WitchHat = function(character, folder, anchored, stage, appearance)
	local kit = kitAt(character, folder, "HatAttachment", anchored, headScale(character))
	if not kit then
		return
	end
	local hat = Color3.fromRGB(34, 26, 46)
	local band = appearance.AuraColor
	kit:Cylinder("Brim", Vector3.new(0, -0.08, 0), Vector3.new(0, -0.02, 0), 2.3, hat)
	local tiers = { { 1.0, 0.0, 0.35 }, { 0.78, 0.35, 0.75 }, { 0.56, 0.75, 1.15 }, { 0.34, 1.15, 1.5 } }
	for i, tier in tiers do
		local lean = Vector3.new(0, 0, 0.08 * i)
		kit:Cylinder("Cone", Vector3.new(0, tier[2], 0) + lean, Vector3.new(0, tier[3], 0) + lean, tier[1], hat)
	end
	kit:Spike("Tip", Vector3.new(0, 1.45, 0.32), Vector3.new(0, 1.55, 0.9), 0.32, 0.18, hat, Vector3.yAxis)
	kit:Cylinder(
		"Band",
		Vector3.new(0, 0.0, 0.01),
		Vector3.new(0, 0.14, 0.01),
		1.04,
		stage >= 2 and band or Color3.fromRGB(110, 70, 150)
	)
end

Features.Stitches = function(character, folder, anchored)
	local kit = kitAt(character, folder, "FaceFrontAttachment", anchored, headScale(character))
	if not kit then
		return
	end
	local thread = Color3.fromRGB(40, 30, 30)
	kit:Block("Stitch", Vector3.new(0.5, 0.04, 0.03), CFrame.new(-0.25, -0.2, -0.01) * CFrame.Angles(0, 0, 0.5), thread)
	for i = 0, 3 do
		kit:Block(
			"StitchCross",
			Vector3.new(0.03, 0.14, 0.03),
			CFrame.new(-0.42 + i * 0.12, -0.2 + i * 0.065, -0.01) * CFrame.Angles(0, 0, 0.5),
			thread
		)
	end
end

Features.Bolt = function(character, folder, anchored)
	local kit = kitAt(character, folder, "NeckAttachment", anchored)
	if not kit then
		return
	end
	local metal = Color3.fromRGB(150, 150, 160)
	for _, side in { -1, 1 } do
		kit:Cylinder(
			"Bolt",
			Vector3.new(0.45 * side, 0.2, 0),
			Vector3.new(0.75 * side, 0.2, 0),
			0.18,
			metal,
			Enum.Material.Metal
		)
	end
end

Features.Wrappings = function(character, folder, anchored, stage)
	local cloth = stage >= 2 and Color3.fromRGB(226, 214, 186) or Color3.fromRGB(206, 192, 160)
	local kit = kitAt(character, folder, "BodyFrontAttachment", anchored)
	if kit then
		for i = 0, 3 do
			kit:Block(
				"Wrap",
				Vector3.new(2.1, 0.16, 0.06),
				CFrame.new(0, -0.6 + i * 0.4, -0.02) * CFrame.Angles(0, 0, (i % 2 == 0) and 0.18 or -0.18),
				cloth,
				Enum.Material.Fabric
			)
		end
	end
	for _, name in { "RightShoulderAttachment", "LeftShoulderAttachment" } do
		local armKit = kitAt(character, folder, name, anchored)
		if armKit then
			for i = 0, 2 do
				armKit:Block(
					"ArmWrap",
					Vector3.new(1.06, 0.14, 1.06),
					CFrame.new(0, -0.35 - i * 0.32, 0) * CFrame.Angles(0, 0, 0.12),
					cloth,
					Enum.Material.Fabric
				)
			end
		end
	end
end

Features.Hood = function(character, folder, anchored, stage, appearance)
	local kit = kitAt(character, folder, "HatAttachment", anchored, headScale(character))
	if not kit then
		return
	end
	local cloth = Color3.fromRGB(26, 40, 70)
	kit:Block("HoodBack", Vector3.new(1.45, 1.35, 0.14), CFrame.new(0, -0.55, 0.68), cloth, Enum.Material.Fabric)
	kit:Block("HoodTop", Vector3.new(1.45, 0.14, 1.4), CFrame.new(0, 0.1, 0.05), cloth, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		kit:Block(
			"HoodSide",
			Vector3.new(0.14, 1.2, 1.3),
			CFrame.new(0.72 * side, -0.5, 0.05),
			cloth,
			Enum.Material.Fabric
		)
	end
	if stage >= 2 then
		kit:Block("HoodTrim", Vector3.new(1.5, 0.08, 0.08), CFrame.new(0, 0.12, -0.66), appearance.AuraColor)
	end
	local collar = kitAt(character, folder, "LeftCollarAttachment", anchored)
	if collar then
		-- Floating focus orb (sorcerer's instrument), slightly above the shoulder.
		collar:Ball("FocusOrb", 0.32, Vector3.new(-0.2, 0.75, 0.2), appearance.AuraColor, Enum.Material.Glass)
	end
end

Features.SanzuLines = function(character, folder, anchored, stage)
	local kit = kitAt(character, folder, "HairAttachment", anchored, headScale(character))
	if not kit then
		return
	end
	-- Lines connect around the head as mastery grows (1 at Stage I ... 3 at Stage III).
	local white = Color3.fromRGB(245, 245, 250)
	for i = 1, math.clamp(stage, 1, 3) do
		local y = -0.15 - (i - 1) * 0.22
		kit:Block("SanzuLine", Vector3.new(1.32, 0.07, 0.05), CFrame.new(0, y, -0.62), white)
		kit:Block("SanzuLineSide", Vector3.new(0.05, 0.07, 0.62), CFrame.new(-0.66, y, -0.31), white)
	end
end

Features.SkullRing = function(character, folder, anchored)
	local kit = kitAt(character, folder, "RightGripAttachment", anchored)
	if not kit then
		return
	end
	kit:Ball("SkullRing", 0.22, Vector3.new(0.42, 0.05, -0.1), Color3.fromRGB(238, 236, 230))
end

Features.StonePlates = function(character, folder, anchored, stage, appearance)
	local stone = Color3.fromRGB(110, 104, 98)
	for _, name in { "RightShoulderAttachment", "LeftShoulderAttachment" } do
		local kit = kitAt(character, folder, name, anchored)
		if kit then
			kit:Block(
				"ShoulderStone",
				Vector3.new(1.25, 0.45, 1.2),
				CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, 0.1),
				stone,
				Enum.Material.Slate
			)
		end
	end
	local chest = kitAt(character, folder, "BodyFrontAttachment", anchored)
	if chest then
		chest:Block("ChestStone", Vector3.new(1.5, 1.1, 0.25), CFrame.new(0, 0.1, -0.08), stone, Enum.Material.Slate)
		local coreColor = appearance.AuraColor
		chest:Ball(
			"Core",
			0.42,
			Vector3.new(0, 0.15, -0.24),
			coreColor,
			stage >= 2 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		)
	end
end

Features.BladeFin = function(character, folder, anchored, stage)
	local kit = kitAt(character, folder, "RightElbowRigAttachment", anchored)
	if not kit then
		return
	end
	local black = Color3.fromRGB(26, 22, 30)
	local red = Color3.fromRGB(196, 22, 36)
	-- A partial-transformation blade along the back of the forearm (+Z is behind the arm).
	local base0, base1 = Vector3.new(0, -0.1, 0.5), Vector3.new(0, -0.9, 0.5)
	local tip = Vector3.new(0, 0.3, 1.25 + 0.15 * stage)
	kit:Triangle("Fin", base0, base1, tip, 0.08, black, Enum.Material.Metal)
	kit:Triangle(
		"FinEdge",
		base0 + Vector3.new(0, 0.05, 0.25),
		tip,
		tip + Vector3.new(0, -0.35, -0.1),
		0.06,
		red,
		Enum.Material.Metal
	)
end

RaceAppearance.Features = Features

-- Soft soul aura. Rate and colors scale with mastery; Stage III adds a second, prestige layer.
local function buildAura(character: Model, raceId: string, stage: number, appearance)
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: any
	if not torso then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = RaceAppearance.AuraName
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(appearance.AuraColor)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.4, 0.28 + stage * 0.06),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.9, 1.6)
	emitter.Rate = 2 + stage * 3
	emitter.Speed = NumberRange.new(0.4, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.6, 0)
	emitter.LockedToPart = false
	emitter:SetAttribute("Race", raceId)
	emitter.Parent = torso
	if stage >= 3 then
		local prestige = emitter:Clone()
		prestige.Name = RaceAppearance.AuraName .. "Prestige"
		prestige.Color = ColorSequence.new(appearance.AuraColor, appearance.EyeColor)
		prestige.Rate = 6
		prestige.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		prestige.Speed = NumberRange.new(1, 2.2)
		prestige.Parent = torso
	end
end

function RaceAppearance.Clear(character: Model)
	local folder = character:FindFirstChild(RaceAppearance.FolderName)
	if folder then
		folder:Destroy()
	end
	for _, descendant in character:GetDescendants() do
		if
			descendant:IsA("ParticleEmitter")
			and string.sub(descendant.Name, 1, #RaceAppearance.AuraName) == RaceAppearance.AuraName
		then
			descendant:Destroy()
		end
	end
end

-- Applies (or re-applies) a race's look. `anchored` = true for static previews.
function RaceAppearance.Apply(character: Model, raceId: string, stage: number, anchored: boolean?)
	RaceAppearance.Clear(character)
	local race = RaceConfig.ById[raceId]
	if not race then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = RaceAppearance.FolderName
	folder.Parent = character
	for _, featureId in race.Appearance.Features do
		local builder = Features[featureId]
		if builder then
			local ok, err = pcall(builder, character, folder, anchored == true, stage, race.Appearance)
			if not ok then
				warn("[RaceAppearance] feature " .. featureId .. " failed: " .. tostring(err))
			end
		end
	end
	buildAura(character, raceId, stage, race.Appearance)
	character:SetAttribute("AppearanceRace", raceId)
	character:SetAttribute("AppearanceStage", stage)
end

return RaceAppearance
