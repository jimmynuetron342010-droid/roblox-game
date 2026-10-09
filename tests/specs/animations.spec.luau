local fs = require("@lune/fs")

local Loader = require("../harness/Loader")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new({ IsServer = false })
local roblox = Loader.roblox
local CFrame = roblox.CFrame

local WeaponBuilder = loader.RequirePath("ReplicatedStorage.Modules.WeaponBuilder")
local WeaponConfig = loader.RequirePath("ReplicatedStorage.Modules.WeaponConfig")
local PreviewRig = loader.RequirePath("ReplicatedStorage.Modules.Rig.PreviewRig")

local ROOT = "assets/RBX_ANIMSAVES"

local function load(path: string)
	local instances = roblox.deserializeModel(fs.readFile(path))
	return instances[1]
end

local function components(cf)
	return { cf:GetComponents() }
end

local function sameCFrame(a, b, tolerance: number): boolean
	local ca, cb = components(a), components(b)
	for i = 1, 12 do
		if math.abs(ca[i] - cb[i]) > tolerance then
			return false
		end
	end
	return true
end

local function finite(cf): boolean
	for _, value in components(cf) do
		if value ~= value or math.abs(value) == math.huge then
			return false
		end
	end
	return true
end

-- name -> pose (flattened by "Parent/Child" path)
local function flatten(keyframe)
	local out = {}
	local function walk(pose, path)
		local key = path .. "/" .. pose.Name
		out[key] = pose
		for _, child in pose:GetChildren() do
			walk(child, key)
		end
	end
	for _, pose in keyframe:GetChildren() do
		walk(pose, "")
	end
	return out
end

describe("Baked weapon animations (ServerStorage.RBX_ANIMSAVES)", function()
	for _, id in WeaponConfig.Order do
		local weapon = WeaponConfig.Weapons[id]
		for _, form in weapon.FormOrder or { false } do
			local name = form and (id .. "_" .. form) or id
			it(name .. ": Idle/Walk/Run loops and every moveset attack are exported and valid", function()
				local config = WeaponConfig.Resolve(id, form or nil)
				local folder = ROOT .. "/" .. name
				expect(fs.isDir(folder)).toBe(true)
				expect(fs.isFile("assets/AnimationRigs/" .. name .. "Rig.rbxm")).toBe(true)

				-- Rig with the weapon equipped: every pose must map to a real Motor6D (Part0 → Part1).
				local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
				WeaponBuilder.Equip(rig, id, { Form = form or nil, Drawn = true })
				local joints = {}
				for _, descendant in rig:GetDescendants() do
					if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
						joints[descendant.Part0.Name .. ">" .. descendant.Part1.Name] = true
					end
				end

				local expected = { Idle = true, Walk = true, Run = true }
				for _, attackId in config.Moveset.M1 do
					expected[attackId] = false
				end
				expected[config.Moveset.Z] = false
				expected[config.Moveset.X] = false

				for clip, looped in expected do
					local path = folder .. "/" .. clip .. ".rbxm"
					if not fs.isFile(path) then
						error("missing clip " .. path)
					end
					local sequence = load(path)
					expect(sequence.ClassName).toBe("KeyframeSequence")
					expect(sequence.Name).toBe(clip)
					expect(sequence.Loop).toBe(looped)
					local keyframes = sequence:GetChildren()
					table.sort(keyframes, function(a, b)
						return a.Time < b.Time
					end)
					expect(#keyframes).toBeAtLeast(3)
					expect(keyframes[1].Time).toBeNear(0, 1e-6)
					if not looped then
						local attack = WeaponConfig.Attacks[clip]
						expect(keyframes[#keyframes].Time).toBeNear(attack.Duration, 1 / 30)
					end
					for _, keyframe in keyframes do
						local poses = flatten(keyframe)
						for key, pose in poses do
							if not finite(pose.CFrame) then
								error(clip .. ": non-finite pose " .. key)
							end
							local parent = pose.Parent
							if parent and parent:IsA("Pose") then
								if not joints[parent.Name .. ">" .. pose.Name] then
									error(clip .. ": pose " .. key .. " does not match any Motor6D on the rig")
								end
							end
						end
					end
					if looped then
						-- Seamless: the last keyframe equals the first.
						local first, last = flatten(keyframes[1]), flatten(keyframes[#keyframes])
						for key, pose in first do
							if not last[key] or not sameCFrame(pose.CFrame, last[key].CFrame, 1e-3) then
								error(clip .. ": loop seam at " .. key)
							end
						end
					end
				end
			end)
		end
	end
end)
