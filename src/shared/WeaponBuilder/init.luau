--[[
	WeaponBuilder
	Builds, spawns, equips, holsters and destroys the procedural 3D weapons.

	MODEL HIERARCHY (every weapon)
	  Model "EquippedWeapon"        attributes: WeaponId, Form
	    Model <Unit>                "Main" (or "Liz"/"Patty" for the twin pistols)
	      Part "Handle"             PrimaryPart / root. Invisible, origin = grip point.
	        Attachment "Grip"       where the hand holds (identity = model origin)
	        Attachment "SupportGrip" second hand (two-handed weapons, optional)
	        Attachment "TrailA"/"TrailB" + Trail "SlashTrail"   blade trail (disabled until swings)
	        Attachment "Impact"     main contact point (tip)
	        Attachment "Muzzle"     guns only
	        Motor6D "MountJoint"    joins the Handle to the character (hand/forearm/back)
	      Model "Shaft"/"Blade"/"Chain"/...   named component groups; every part welded to Handle,
	                                           or Motor6D-jointed for moving pieces
	                                           (chain links, drill bit, gun slide, spider legs)

	MODEL SPACE CONVENTION (studs, relative to the grip)
	  +Y  along the handle toward the business end (blade above the fist)
	  -Z  the facing/edge side (barrels point -Z)
	  X   thickness of flat blades
	With Roblox's RightGripAttachment this makes a raised arm hold blades upward and aimed
	guns point forward — the same convention Roblox Tools use.

	CUSTOM MESHES
	  Put a MeshPart named "<WeaponId>_<GroupName>" (e.g. "MakaScythe_Blade") in
	  ReplicatedStorage.WeaponAssets with its pivot at the weapon's grip point. The procedural group
	  is replaced by your mesh automatically. See docs/BLENDER_WORKFLOW.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent
local GeometryKit = require(Modules.Core.GeometryKit)
local WeaponConfig = require(Modules.WeaponConfig)

local Models = script:WaitForChild("Models")

local WeaponBuilder = {}

WeaponBuilder.EquippedName = "EquippedWeapon"

export type Unit = {
	Name: string,
	Model: Model,
	Handle: BasePart,
	Kit: any,
	Mount: string,
}

export type BuildOptions = {
	Origin: CFrame?,
	Anchored: boolean?,
	Form: string?,
	Scale: number?,
	Palette: { [string]: Color3 }?, -- per-build color overrides
}

local builderCache: { [string]: any } = {}

local function getBuilder(name: string)
	local builder = builderCache[name]
	if not builder then
		local module = Models:FindFirstChild(name)
		assert(module, "WeaponBuilder: no model module " .. name)
		builder = require(module :: ModuleScript)
		builderCache[name] = builder
	end
	return builder
end

local function mergePalette(base: { [string]: Color3 }, overrides: { [string]: Color3 }?)
	local palette = table.clone(base)
	for key, color in (overrides or {}) :: { [string]: Color3 } do
		if typeof(color) == "Color3" then
			palette[key] = color
		end
	end
	return palette
end

local function newHandle(unitModel: Model, origin: CFrame, anchored: boolean): BasePart
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CFrame = origin
	handle.Anchored = anchored
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = unitModel
	unitModel.PrimaryPart = handle
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Parent = handle
	return handle
end

-- Replaces procedural component groups with user-supplied MeshParts when present.
local function applyMeshOverrides(weaponId: string, unit: Unit)
	local assets = ReplicatedStorage:FindFirstChild("WeaponAssets")
	if not assets then
		return
	end
	for _, group in unit.Model:GetChildren() do
		if group:IsA("Model") then
			local override = assets:FindFirstChild(weaponId .. "_" .. group.Name)
			if override and override:IsA("BasePart") then
				group:ClearAllChildren()
				local mesh = override:Clone()
				mesh.Anchored = unit.Handle.Anchored
				mesh.CanCollide = false
				mesh.CanQuery = false
				mesh.CanTouch = false
				mesh.Massless = true
				mesh:PivotTo(unit.Handle.CFrame)
				mesh.Parent = group
				if not unit.Handle.Anchored then
					local weld = Instance.new("Weld")
					weld.Name = "Weld"
					weld.Part0 = unit.Handle
					weld.Part1 = mesh
					weld.C0 = unit.Handle.CFrame:Inverse() * mesh.CFrame
					weld.Parent = mesh
				end
			end
		end
	end
end

-- Adds the slash trail between TrailA/TrailB (on whichever part the builder put them: the Handle
-- for rigid weapons, a leg or chain link for articulated ones).
local function addTrail(unit: Unit, trailConfig)
	local a = unit.Model:FindFirstChild("TrailA", true) :: Attachment?
	local b = unit.Model:FindFirstChild("TrailB", true) :: Attachment?
	if not a or not b or not trailConfig then
		return
	end
	local trail = Instance.new("Trail")
	trail.Name = "SlashTrail"
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Enabled = false
	trail.FaceCamera = false
	trail.Lifetime = trailConfig.Lifetime
	trail.MinLength = 0.05
	trail.LightEmission = 0.25
	trail.LightInfluence = 0.6
	trail.Color = ColorSequence.new(trailConfig.Color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, trailConfig.Transparency),
		NumberSequenceKeypoint.new(0.6, math.min(1, trailConfig.Transparency + 0.35)),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Parent = a.Parent
end

--[[
	Builds a weapon model. Returns (model, units).
	The model is NOT parented; callers decide (character, workspace display, ViewportFrame).
]]
function WeaponBuilder.Build(weaponId: string, options: BuildOptions?): (Model, { Unit })
	local opts = options or {}
	local config = WeaponConfig.Resolve(weaponId, opts.Form)
	assert(config, "WeaponBuilder.Build: unknown weapon " .. tostring(weaponId))
	local origin = opts.Origin or CFrame.new()
	local anchored = opts.Anchored == true
	local scale = (opts.Scale or 1) * (config.Scale or 1)

	local model = Instance.new("Model")
	model.Name = WeaponBuilder.EquippedName
	model:SetAttribute("WeaponId", weaponId)
	model:SetAttribute("Form", config.Form or "")

	local units: { Unit } = {}
	local api = {
		Config = config,
		Dimensions = config.Dimensions,
		Palette = mergePalette(config.Palette, opts.Palette),
		Scale = scale,
		Form = config.Form,
		Anchored = anchored,
	}

	-- Creates a unit (independently mounted sub-model). `localOrigin` offsets it for previews.
	function api.Unit(name: string, mount: string, localOrigin: CFrame?): Unit
		local unitModel = Instance.new("Model")
		unitModel.Name = name
		unitModel:SetAttribute("Mount", mount)
		unitModel.Parent = model
		local unitOrigin = origin * (localOrigin or CFrame.new())
		local handle = newHandle(unitModel, unitOrigin, anchored)
		local kit = GeometryKit.new({
			Model = unitModel,
			Root = handle,
			Origin = unitOrigin,
			Scale = scale,
			Anchored = anchored,
		})
		local unit = { Name = name, Model = unitModel, Handle = handle, Kit = kit, Mount = mount }
		table.insert(units, unit)
		return unit
	end

	getBuilder(config.Builder)(api)

	for _, unit in units do
		applyMeshOverrides(weaponId, unit)
		addTrail(unit, config.Trail)
	end
	model.PrimaryPart = units[1].Handle
	return model, units
end

-- Static display copy in the world (anchored), e.g. weapon racks or a shop pedestal.
function WeaponBuilder.Spawn(weaponId: string, cframe: CFrame, parent: Instance?, options: BuildOptions?): Model
	local opts = table.clone(options or {})
	opts.Origin = cframe
	opts.Anchored = true
	local model = WeaponBuilder.Build(weaponId, opts)
	model.Name = "Display_" .. weaponId
	model.Parent = parent or workspace
	return model
end

-- ── Mounting ──────────────────────────────────────────────────────────────────
local R15_TO_R6 = {
	RightHand = "Right Arm",
	LeftHand = "Left Arm",
	RightLowerArm = "Right Arm",
	UpperTorso = "Torso",
}

local function findBodyPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	if not part and R15_TO_R6[name] then
		part = character:FindFirstChild(R15_TO_R6[name])
	end
	return part :: BasePart?
end

local function attachmentCFrame(part: BasePart, name: string, fallback: CFrame): CFrame
	local attachment = part:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment.CFrame
	end
	return fallback
end

local GRIP_FALLBACK = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

-- Holstered placement on the back for each weapon category (relative to BodyBackAttachment).
WeaponBuilder.HolsterOffsets = {
	Scythe = CFrame.new(0, 0.2, 0.25) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-35), 0, 0),
	Sword = CFrame.new(0.3, 0.1, 0.2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(140), 0, 0),
	Modular = CFrame.new(0.3, 0.1, 0.2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(140), 0, 0),
	Shuriken = CFrame.new(0, 0.2, 0.25) * CFrame.Angles(0, math.rad(90), 0),
	Chain = CFrame.new(-0.4, -0.2, 0.25) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(180), 0, 0),
	Flail = CFrame.new(-0.4, -0.2, 0.25) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(180), 0, 0),
	Guns = CFrame.new(0, -0.9, 0.3) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(90), 0, 0),
	Drill = CFrame.new(0, 0.1, 0.55) * CFrame.Angles(math.rad(-90), 0, 0),
	Gauntlet = CFrame.new(0, 0, 0.4) * CFrame.Angles(math.rad(-90), 0, 0),
	Rig = CFrame.new(),
}

-- Mount CFrame for a unit, drawn (in hand) or holstered (on the back).
local function mountFor(character: Model, unit: Unit, config, drawn: boolean): (BasePart?, CFrame)
	local mount = unit.Mount
	if mount == "Back" then
		local torso = findBodyPart(character, "UpperTorso")
		if not torso then
			return nil, CFrame.new()
		end
		return torso, attachmentCFrame(torso, "BodyBackAttachment", CFrame.new(0, 0, 0.5))
	end
	if not drawn then
		local torso = findBodyPart(character, "UpperTorso")
		if not torso then
			return nil, CFrame.new()
		end
		local back = attachmentCFrame(torso, "BodyBackAttachment", CFrame.new(0, 0, 0.5))
		local offset = WeaponBuilder.HolsterOffsets[config.Category] or CFrame.new()
		if unit.Name == "Patty" then
			offset = CFrame.new(0.9, 0, 0) * offset
		elseif unit.Name == "Liz" then
			offset = CFrame.new(-0.9, 0, 0) * offset
		end
		return torso, back * offset
	end
	if mount == "RightHand" then
		local hand = findBodyPart(character, "RightHand")
		return hand, hand and attachmentCFrame(hand, "RightGripAttachment", GRIP_FALLBACK) or CFrame.new()
	elseif mount == "LeftHand" then
		local hand = findBodyPart(character, "LeftHand")
		return hand, hand and attachmentCFrame(hand, "LeftGripAttachment", GRIP_FALLBACK) or CFrame.new()
	elseif mount == "RightForearm" then
		local forearm = findBodyPart(character, "RightLowerArm")
		if forearm and forearm.Name == "Right Arm" then
			return forearm, CFrame.new(0, -0.6, 0)
		end
		return forearm,
			forearm and attachmentCFrame(forearm, "RightWristRigAttachment", CFrame.new(0, -0.5, 0)) or CFrame.new()
	end
	return nil, CFrame.new()
end

local function joinUnit(character: Model, unit: Unit, config, drawn: boolean)
	local existing = unit.Handle:FindFirstChild("MountJoint")
	if existing then
		existing:Destroy()
	end
	local part, c0 = mountFor(character, unit, config, drawn)
	if not part then
		return false
	end
	local joint = Instance.new("Motor6D")
	joint.Name = "MountJoint"
	joint.Part0 = part
	joint.Part1 = unit.Handle
	joint.C0 = c0
	joint.C1 = CFrame.new()
	joint.Transform = CFrame.new()
	joint.Parent = unit.Handle
	unit.Handle.CFrame = part.CFrame * c0
	return true
end

local function unitsOf(model: Model): { Unit }
	local units = {}
	for _, child in model:GetChildren() do
		if child:IsA("Model") then
			local handle = child:FindFirstChild("Handle")
			if handle then
				table.insert(units, {
					Name = child.Name,
					Model = child,
					Handle = handle :: BasePart,
					Kit = nil,
					Mount = child:GetAttribute("Mount") or "RightHand",
				})
			end
		end
	end
	return units
end

function WeaponBuilder.GetEquipped(character: Model): Model?
	local model = character:FindFirstChild(WeaponBuilder.EquippedName)
	return model and model:IsA("Model") and model or nil
end

-- Builds the weapon and mounts it on the character. Server-side so everyone sees it.
function WeaponBuilder.Equip(character: Model, weaponId: string, options: { Form: string?, Drawn: boolean? }?): Model?
	local opts = options or {}
	WeaponBuilder.Unequip(character)
	local config = WeaponConfig.Resolve(weaponId, opts.Form)
	if not config then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local model, units = WeaponBuilder.Build(weaponId, {
		Form = opts.Form,
		Origin = root and root.CFrame or CFrame.new(),
	})
	local drawn = opts.Drawn ~= false
	for _, unit in units do
		joinUnit(character, unit, config, drawn)
	end
	model:SetAttribute("Drawn", drawn)
	model.Parent = character
	character:SetAttribute("EquippedWeapon", weaponId)
	character:SetAttribute("WeaponForm", config.Form or "")
	character:SetAttribute("WeaponDrawn", drawn)
	return model
end

-- Moves an equipped weapon between hand and back without rebuilding it.
function WeaponBuilder.SetDrawn(character: Model, drawn: boolean)
	local model = WeaponBuilder.GetEquipped(character)
	if not model then
		return
	end
	local config = WeaponConfig.Resolve(model:GetAttribute("WeaponId"), model:GetAttribute("Form"))
	for _, unit in unitsOf(model) do
		joinUnit(character, unit, config, drawn)
	end
	model:SetAttribute("Drawn", drawn)
	character:SetAttribute("WeaponDrawn", drawn)
end

function WeaponBuilder.Unequip(character: Model)
	local model = WeaponBuilder.GetEquipped(character)
	if model then
		model:Destroy()
	end
	character:SetAttribute("EquippedWeapon", nil)
	character:SetAttribute("WeaponForm", nil)
	character:SetAttribute("WeaponDrawn", nil)
end

function WeaponBuilder.Destroy(model: Model?)
	if model then
		model:Destroy()
	end
end

-- Total BasePart count (performance budget checks in tests).
function WeaponBuilder.CountParts(model: Model): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

return WeaponBuilder
