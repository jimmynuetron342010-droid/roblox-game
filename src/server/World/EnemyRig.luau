--[[
	EnemyRig
	Procedural enemy bodies. Each rig has HumanoidRootPart + Humanoid (server network owner) and
	Motor6D joints ("Root", "RightArm", "LeftArm", "Neck") so clients can animate them cheaply.
	Designs are original: hooded Kishin Eggs, translucent Shrouded Eggs, the Madness Wraith, the
	bandaged Pharaoh, and wooden training dummies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeometryKit = require(ReplicatedStorage.Modules.Core.GeometryKit)

local EnemyRig = {}

local function newRoot(model: Model, cframe: CFrame, scale: number): BasePart
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = cframe
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function motorPart(kit, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local part = kit:Part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material, Shape = shape })
	part.CanCollide = false
	return part
end

local function humanoid(model: Model, hipHeight: number, health: number)
	local h = Instance.new("Humanoid")
	h.RigType = Enum.HumanoidRigType.R15
	h.HipHeight = hipHeight
	h.MaxHealth = health
	h.Health = health
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.BreakJointsOnDeath = false
	h.RequiresNeck = false
	h.Parent = model
	return h
end

-- Hooded figure used by Kishin Eggs, Shrouded Eggs and the Madness Wraith.
local function hooded(def, cframe: CFrame, options)
	local scale = def.Scale
	local colors = def.Colors
	local model = Instance.new("Model")
	model.Name = def.Id
	local root = newRoot(model, cframe, scale)
	local kit = GeometryKit.new({ Model = model, Root = root, Origin = cframe, Scale = scale })

	local torso = motorPart(kit, "Torso", Vector3.new(1.8, 1.9, 1.1), CFrame.new(0, 0.2, 0), colors.Body, Enum.Material.Fabric)
	kit:Motor("Root", root, torso, CFrame.new(0, 0, 0))
	-- Ragged cloak flaring toward the ground.
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local base = Vector3.new(math.cos(a) * 0.75, -0.6, math.sin(a) * 0.45)
		local tip = Vector3.new(math.cos(a) * 1.15, -2.0 - (i % 2) * 0.35, math.sin(a) * 0.8)
		local w1, w2 = kit:Spike("Cloak", base, tip, 0.9, 0.08, colors.Body:Lerp(colors.Accent, 0.25), nil, Enum.Material.Fabric)
		for _, w in { w1, w2 } do
			if w then
				kit:Reweld(w, torso)
			end
		end
	end
	local head = motorPart(kit, "Head", Vector3.new(1.25, 1.25, 1.25), CFrame.new(0, 1.65, 0), colors.Body, Enum.Material.Fabric, Enum.PartType.Ball)
	kit:Motor("Neck", torso, head, CFrame.new(0, 1.15, 0))
	local hood = kit:Block("Hood", Vector3.new(1.45, 1.1, 1.45), CFrame.new(0, 1.85, 0.12), colors.Accent, Enum.Material.Fabric)
	kit:Reweld(hood, head)
	for _, side in { -1, 1 } do
		local eye = kit:Ball("Eye", 0.22, Vector3.new(side * 0.25, 1.65, -0.58), colors.Eyes, Enum.Material.Neon)
		kit:Reweld(eye, head)
	end
	for _, side in { -1, 1 } do
		local name = side == 1 and "RightArm" or "LeftArm"
		local arm = motorPart(kit, name, Vector3.new(0.45, 1.7, 0.45), CFrame.new(side * 1.1, 0.0, 0), colors.Body, Enum.Material.Fabric)
		kit:Motor(name, torso, arm, CFrame.new(side * 1.0, 0.8, 0))
		for k = -1, 1 do
			local w1, w2 = kit:Spike("Claw", Vector3.new(side * 1.1 + k * 0.12, -0.8, 0), Vector3.new(side * 1.12 + k * 0.14, -1.35, -0.15), 0.12, 0.05, colors.Accent:Lerp(Color3.new(1, 1, 1), 0.3))
			for _, w in { w1, w2 } do
				if w then
					kit:Reweld(w, arm)
				end
			end
		end
	end
	if options and options.Shards then
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			local shard = kit:Block("Shard", Vector3.new(0.3, 0.9, 0.3), CFrame.new(math.cos(a) * 1.8, 1.2, math.sin(a) * 1.8) * CFrame.Angles(0.4, a, 0.3), colors.Accent, Enum.Material.Glass)
			kit:Reweld(shard, torso)
		end
	end
	return model, root, humanoid(model, 1.6 * scale, def.MaxHealth)
end

local function pharaoh(def, cframe: CFrame)
	local s = def.Scale
	local c = def.Colors
	local model = Instance.new("Model")
	model.Name = def.Id
	local root = newRoot(model, cframe, s)
	local kit = GeometryKit.new({ Model = model, Root = root, Origin = cframe, Scale = s })
	local gold = Color3.fromRGB(214, 170, 60)
	local torso = motorPart(kit, "Torso", Vector3.new(2, 2, 1.1), CFrame.new(0, 0.1, 0), c.Body, Enum.Material.Fabric)
	kit:Motor("Root", root, torso, CFrame.new())
	for i = 0, 4 do
		local wrap = kit:Block("Wrap", Vector3.new(2.06, 0.18, 1.16), CFrame.new(0, -0.7 + i * 0.4, 0) * CFrame.Angles(0, 0, (i % 2 == 0) and 0.15 or -0.15), c.Body:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Fabric)
		kit:Reweld(wrap, torso)
	end
	local collar = kit:Block("Collar", Vector3.new(2.3, 0.35, 1.3), CFrame.new(0, 1.05, 0), gold, Enum.Material.Metal)
	kit:Reweld(collar, torso)
	local skirt = kit:Block("Skirt", Vector3.new(2.1, 1.2, 1.2), CFrame.new(0, -1.5, 0), gold:Lerp(c.Body, 0.5), Enum.Material.Fabric)
	kit:Reweld(skirt, torso)
	local head = motorPart(kit, "Head", Vector3.new(1.2, 1.3, 1.1), CFrame.new(0, 1.85, 0), c.Body, Enum.Material.Fabric)
	kit:Motor("Neck", torso, head, CFrame.new(0, 1.2, 0))
	-- Nemes headdress: striped flaps.
	for i = 0, 3 do
		local color = (i % 2 == 0) and c.Accent or gold
		local flapL = kit:Block("Nemes", Vector3.new(0.3, 1.5 - i * 0.1, 0.9), CFrame.new(-0.7 - i * 0.02, 1.55 - i * 0.05, 0.05), color, Enum.Material.SmoothPlastic)
		local flapR = kit:Block("Nemes", Vector3.new(0.3, 1.5 - i * 0.1, 0.9), CFrame.new(0.7 + i * 0.02, 1.55 - i * 0.05, 0.05), color, Enum.Material.SmoothPlastic)
		kit:Reweld(flapL, head)
		kit:Reweld(flapR, head)
	end
	local crown = kit:Block("Crown", Vector3.new(1.4, 0.35, 1.2), CFrame.new(0, 2.55, 0), gold, Enum.Material.Metal)
	kit:Reweld(crown, head)
	for _, side in { -1, 1 } do
		local eye = kit:Ball("Eye", 0.2, Vector3.new(side * 0.25, 1.95, -0.55), c.Eyes, Enum.Material.Neon)
		kit:Reweld(eye, head)
		local name = side == 1 and "RightArm" or "LeftArm"
		local arm = motorPart(kit, name, Vector3.new(0.6, 2.1, 0.6), CFrame.new(side * 1.3, 0.05, 0), c.Body, Enum.Material.Fabric)
		kit:Motor(name, torso, arm, CFrame.new(side * 1.2, 0.95, 0))
		local bracer = kit:Block("Bracer", Vector3.new(0.7, 0.5, 0.7), CFrame.new(side * 1.3, -0.6, 0), gold, Enum.Material.Metal)
		kit:Reweld(bracer, arm)
	end
	return model, root, humanoid(model, 2.2 * s, def.MaxHealth)
end

local function dummy(def, cframe: CFrame)
	local model = Instance.new("Model")
	model.Name = def.Id
	local root = newRoot(model, cframe, 1)
	root.Anchored = true
	local kit = GeometryKit.new({ Model = model, Root = root, Origin = cframe, Anchored = true })
	local wood = Color3.fromRGB(140, 100, 64)
	kit:Cylinder("Post", Vector3.new(0, -3, 0), Vector3.new(0, 1.5, 0), 0.5, wood, Enum.Material.Wood)
	kit:Block("Body", Vector3.new(1.8, 2.2, 1), CFrame.new(0, 0.3, 0), Color3.fromRGB(196, 170, 110), Enum.Material.Fabric)
	kit:Cylinder("Arms", Vector3.new(-1.8, 0.9, 0), Vector3.new(1.8, 0.9, 0), 0.35, wood, Enum.Material.Wood)
	kit:Ball("Head", 1.2, Vector3.new(0, 2.0, 0), Color3.fromRGB(196, 170, 110), Enum.Material.Fabric)
	kit:Cylinder("Target", Vector3.new(0, 0.4, -0.52), Vector3.new(0, 0.4, -0.56), 1.2, Color3.fromRGB(200, 40, 50))
	kit:Cylinder("TargetInner", Vector3.new(0, 0.4, -0.55), Vector3.new(0, 0.4, -0.6), 0.6, Color3.fromRGB(240, 240, 240))
	kit:Block("Base", Vector3.new(2.4, 0.4, 2.4), CFrame.new(0, -3, 0), wood, Enum.Material.WoodPlanks)
	return model, root, humanoid(model, 0, def.MaxHealth)
end

function EnemyRig.Build(def, cframe: CFrame)
	local model, root, h
	if def.Id == "Pharaoh" then
		model, root, h = pharaoh(def, cframe)
	elseif def.Id == "TrainingDummy" then
		model, root, h = dummy(def, cframe)
	else
		model, root, h = hooded(def, cframe, { Shards = def.Id == "MadnessWraith" })
	end
	model:SetAttribute("EnemyType", def.Id)
	if def.Hidden then
		model:SetAttribute("Hidden", true)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				part:SetAttribute("BaseTransparency", part.Transparency)
				part.Transparency = 0.78
			end
		end
	end
	return model, root, h
end

return EnemyRig
