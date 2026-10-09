local Loader = require("../harness/Loader")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new({ IsServer = false })
local roblox = Loader.roblox
local CFrame = roblox.CFrame

local WeaponBuilder = loader.RequirePath("ReplicatedStorage.Modules.WeaponBuilder")
local WeaponConfig = loader.RequirePath("ReplicatedStorage.Modules.WeaponConfig")
local PreviewRig = loader.RequirePath("ReplicatedStorage.Modules.Rig.PreviewRig")
local PosePreview = loader.RequirePath("ReplicatedStorage.Modules.Animation.PosePreview")
local AnimationLibrary = loader.RequirePath("ReplicatedStorage.Modules.Animation.AnimationLibrary")

local PART_BUDGET = 160 -- per weapon model (all units), keeps 20+ armed players cheap

-- Every (weapon, form) combination.
local variants = {}
for _, id in WeaponConfig.Order do
	local weapon = WeaponConfig.Weapons[id]
	for _, form in weapon.FormOrder or { false } do
		table.insert(variants, { Id = id, Form = form or nil, Name = form and (id .. "-" .. form) or id })
	end
end

local function units(model)
	local out = {}
	for _, child in model:GetChildren() do
		if child:IsA("Model") and child:FindFirstChild("Handle") then
			table.insert(out, child)
		end
	end
	return out
end

-- Parts reachable from the handle through Welds / Motor6Ds / WeldConstraints.
local function connected(unit)
	local handle = unit:FindFirstChild("Handle")
	local edges = {}
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			local a, b = descendant.Part0, descendant.Part1
			if a and b then
				edges[a] = edges[a] or {}
				edges[b] = edges[b] or {}
				table.insert(edges[a], b)
				table.insert(edges[b], a)
			end
		end
	end
	local seen = { [handle] = true }
	local queue = { handle }
	while #queue > 0 do
		local part = table.remove(queue)
		for _, other in edges[part] or {} do
			if not seen[other] then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	return seen
end

describe("WeaponConfig", function()
	it("is internally consistent (ids, movesets, attacks, projectiles)", function()
		local ok, err = WeaponConfig.Validate()
		if not ok then
			error(err)
		end
	end)

	it("has 12 weapons, each with placeholder-safe asset ids", function()
		expect(#WeaponConfig.Order).toBe(12)
		for _, id in WeaponConfig.Order do
			local weapon = WeaponConfig.Weapons[id]
			for _, value in weapon.Sounds or {} do
				expect(string.match(value, "^rbxassetid://%d+$") ~= nil).toBeTruthy()
			end
			for _, value in weapon.AnimationIds or {} do
				expect(string.match(value, "^rbxassetid://%d+$") ~= nil).toBeTruthy()
			end
		end
	end)

	it("uses only animations that exist in the AnimationLibrary", function()
		for attackId, attack in WeaponConfig.Attacks do
			if attack.Animation and not AnimationLibrary.GetAction(attack.Animation) then
				error("attack " .. attackId .. " uses missing animation " .. attack.Animation)
			end
		end
	end)
end)

describe("WeaponBuilder models", function()
	for _, variant in variants do
		it(variant.Name .. ": hierarchy, attachments, welds, collision and part budget", function()
			local model =
				WeaponBuilder.Build(variant.Id, { Form = variant.Form, Anchored = false, Origin = CFrame.new() })
			expect(model.Name).toBe(WeaponBuilder.EquippedName)
			expect(model.PrimaryPart ~= nil).toBeTruthy()
			local parts = WeaponBuilder.CountParts(model)
			expect(parts).toBeAtLeast(20)
			expect(parts).toBeAtMost(PART_BUDGET)
			local list = units(model)
			expect(#list).toBeAtLeast(1)
			for _, unit in list do
				local handle = unit:FindFirstChild("Handle")
				expect(unit.PrimaryPart).toBe(handle)
				expect(handle:FindFirstChild("Grip") ~= nil).toBeTruthy()
				expect(unit:GetAttribute("Mount") ~= nil).toBeTruthy()
				local reach = connected(unit)
				for _, descendant in unit:GetDescendants() do
					if descendant:IsA("BasePart") then
						if not reach[descendant] then
							error(descendant:GetFullName() .. " is not welded/jointed to the Handle")
						end
						expect(descendant.CanCollide).toBe(false)
						expect(descendant.CanTouch).toBe(false)
						expect(descendant.Massless).toBe(true)
						expect(descendant.Anchored).toBe(false)
					end
				end
			end
			-- Blades and chains carry slash trail attachments.
			local config = WeaponConfig.Resolve(variant.Id, variant.Form)
			if config.Trail then
				local a = model:FindFirstChild("TrailA", true)
				local b = model:FindFirstChild("TrailB", true)
				expect(a ~= nil and b ~= nil).toBeTruthy()
			end
			WeaponBuilder.Destroy(model)
		end)
	end

	it("Spawn places an anchored, standalone model at the requested CFrame", function()
		local target = CFrame.new(10, 4, -3)
		local display = roblox.Instance.new("Folder")
		local model = WeaponBuilder.Spawn("MakaScythe", target, display, { Anchored = true })
		expect(model.Parent).toBe(display)
		expect((model.PrimaryPart.CFrame.Position - target.Position).Magnitude).toBeAtMost(1e-3)
		expect(model.PrimaryPart.Anchored).toBe(true)
	end)

	it("Equip mounts with a Motor6D, holsters to the back, and Unequip cleans up", function()
		local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
		local model = WeaponBuilder.Equip(rig, "SoulEaterBlade", { Drawn = true })
		expect(model ~= nil).toBeTruthy()
		expect(WeaponBuilder.GetEquipped(rig)).toBe(model)
		local mount = model:FindFirstChild("Handle", true):FindFirstChild("MountJoint")
		expect(mount ~= nil and mount:IsA("Motor6D")).toBeTruthy()
		expect(mount.Part0.Name).toBe("RightHand")
		expect(rig:GetAttribute("EquippedWeapon")).toBe("SoulEaterBlade")
		WeaponBuilder.SetDrawn(rig, false)
		mount = model:FindFirstChild("Handle", true):FindFirstChild("MountJoint")
		expect(mount.Part0.Name ~= "RightHand").toBeTruthy()
		WeaponBuilder.SetDrawn(rig, true)
		mount = model:FindFirstChild("Handle", true):FindFirstChild("MountJoint")
		expect(mount.Part0.Name).toBe("RightHand")
		-- Re-equipping replaces the old model instead of stacking weapons.
		local second = WeaponBuilder.Equip(rig, "TwinPistols", { Drawn = true })
		local count = 0
		for _, child in rig:GetChildren() do
			if child.Name == WeaponBuilder.EquippedName then
				count += 1
			end
		end
		expect(count).toBe(1)
		expect(#units(second)).toBe(2)
		WeaponBuilder.Unequip(rig)
		expect(WeaponBuilder.GetEquipped(rig)).toBe(nil)
		expect(rig:GetAttribute("EquippedWeapon")).toBe(nil)
	end)
end)

describe("Weapons in the character's hands (IK)", function()
	for _, variant in variants do
		it(variant.Name .. ": the hand stays on the grip in idle, walk, run and every attack frame", function()
			local config = WeaponConfig.Resolve(variant.Id, variant.Form)
			local poses = { { Speed = 0 }, { Speed = 14, Time = 0.37 }, { Speed = 22, Time = 0.31 } }
			local attacks = table.clone(config.Moveset.M1)
			table.insert(attacks, config.Moveset.Z)
			table.insert(attacks, config.Moveset.X)
			for _, attackId in attacks do
				for _, t in { 0.15, 0.4, 0.65, 0.9 } do
					table.insert(poses, { Action = WeaponConfig.Attacks[attackId].Animation, ActionTime = t })
				end
			end
			for _, options in poses do
				local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
				local model = WeaponBuilder.Equip(rig, variant.Id, { Form = variant.Form, Drawn = true })
				options.Weapon = model
				options.HoldStyle = config.HoldStyle
				PosePreview.Pose(rig, options)
				for _, unit in units(model) do
					local handle = unit:FindFirstChild("Handle")
					local mount = handle:FindFirstChild("MountJoint")
					local mountPart = unit:GetAttribute("Mount")
					if mount and (mountPart == "RightHand" or mountPart == "LeftHand") then
						-- Any residual the arm could not reach ends up on the mount joint.
						local residual = mount.Transform.Position.Magnitude
						if residual > 0.05 then
							error(string.format("%s: hand misses the grip by %.2f studs", unit.Name, residual))
						end
					end
					local support = handle:FindFirstChild("SupportGrip")
					local hold = AnimationLibrary.GetHold(config.HoldStyle)
					if support and hold.Support and hold.Support.Unit == unit.Name and not options.Action then
						local leftHand = rig:FindFirstChild("LeftHand")
						local attachment = leftHand:FindFirstChild("LeftGripAttachment")
						local handPoint = (leftHand.CFrame * (attachment and attachment.CFrame or CFrame.new())).Position
						local gripPoint = (handle.CFrame * support.CFrame).Position
						local gap = (handPoint - gripPoint).Magnitude
						if gap > 0.35 then
							error(string.format("%s: support hand is %.2f studs from the SupportGrip", unit.Name, gap))
						end
					end
				end
			end
		end)
	end
end)
