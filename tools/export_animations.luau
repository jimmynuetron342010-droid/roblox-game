--[[
	export_animations.luau (Lune)
	Bakes the procedural weapon animations (AnimatorCore + AnimationLibrary) into Roblox
	KeyframeSequences, so every clip can be opened, edited and published in Roblox Studio:

	  assets/RBX_ANIMSAVES/<Weapon>/<Clip>.rbxm   → ServerStorage.RBX_ANIMSAVES.<Weapon>.<Clip>
	  assets/AnimationRigs/<Weapon>Rig.rbxm       → ServerStorage.AnimationRigs (R15 rig + weapon)

	Clips per weapon (and per Tsubaki form): Idle, Walk, Run (looping) and every attack in its
	moveset (M1 combo, Z, X). Loops are made seamless with a crossfade over one cycle.
	Pose hierarchy follows the R15 Motor6D tree; hand-held weapons add a "Handle" pose under the
	hand so the weapon's MountJoint is animated too.

	Usage: lune run tools/export_animations.luau [weaponFilter]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Loader = require("../tests/harness/Loader")

local loader = Loader.new({ IsServer = false })
local CFrame = roblox.CFrame
local Instance = roblox.Instance
local Enum = roblox.Enum

local WeaponBuilder = loader.RequirePath("ReplicatedStorage.Modules.WeaponBuilder")
local WeaponConfig = loader.RequirePath("ReplicatedStorage.Modules.WeaponConfig")
local PreviewRig = loader.RequirePath("ReplicatedStorage.Modules.Rig.PreviewRig")
local AnimatorCore = loader.RequirePath("ReplicatedStorage.Modules.Animation.AnimatorCore")

local filter = process.args[1]
if filter == "" then
	filter = nil
end

local IDLE_FPS = 15 -- slow breathing loop
local LOOP_FPS = 30 -- walk / run cycles are short
local ACTION_FPS = 30
local SIM_DT = 1 / 120
local WALK_SPEED, RUN_SPEED = 14, 22

-- R15 pose tree: part -> parent part (the Motor6D's Part0).
local function motorTree(rig)
	local motors = {}
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			table.insert(motors, descendant)
		end
	end
	return motors
end

-- Motor6D.Transform of every exported joint at this instant.
local function capture(motors)
	local frame = {}
	for _, motor in motors do
		frame[motor] = motor.Transform
	end
	return frame
end

local function lerpFrames(a, b, alpha)
	local out = {}
	for motor, value in a do
		out[motor] = value:Lerp(b[motor] or value, alpha)
	end
	return out
end

local function newAnimator(rig, model, holdStyle)
	local animator = AnimatorCore.new(rig)
	animator:SetWeapon(model, holdStyle)
	return animator
end

local function step(animator, rig, seconds, speed)
	local root = rig:FindFirstChild("HumanoidRootPart")
	local ctx = { Speed = speed, Grounded = true, Present = true, RootCFrame = root.CFrame }
	local steps = math.max(1, math.floor(seconds / SIM_DT + 0.5))
	for _ = 1, steps do
		animator:Update(seconds / steps, ctx)
	end
end

local function isIdentity(value): boolean
	local components = { value:GetComponents() }
	local identity = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	for index, number in components do
		if math.abs(number - identity[index]) > 1e-4 then
			return false
		end
	end
	return true
end

-- Builds the KeyframeSequence instance tree from sampled frames.
local function buildSequence(rig, name: string, motors, frames, loop: boolean, priority)
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = loop
	sequence.Priority = priority
	-- Joints that are ever away from their rest pose get weight 1; ancestors are kept (weight 0)
	-- so the pose tree mirrors the rig.
	local active = {}
	for _, motor in motors do
		for _, frame in frames do
			if not isIdentity(frame.Pose[motor]) then
				active[motor] = true
				break
			end
		end
	end
	local function needed(motor): boolean
		if active[motor] then
			return true
		end
		for _, other in motors do
			if other.Part0 == motor.Part1 and needed(other) then
				return true
			end
		end
		return false
	end
	local root = rig:FindFirstChild("HumanoidRootPart")
	for _, frame in frames do
		local keyframe = Instance.new("Keyframe")
		keyframe.Name = "Keyframe"
		keyframe.Time = frame.Time
		local rootPose = Instance.new("Pose")
		rootPose.Name = "HumanoidRootPart"
		rootPose.Weight = 0
		rootPose.Parent = keyframe
		local function addChildren(parentPart, parentPose)
			for _, motor in motors do
				if motor.Part0 == parentPart and needed(motor) then
					local pose = Instance.new("Pose")
					pose.Name = motor.Part1.Name
					pose.CFrame = frame.Pose[motor]
					pose.Weight = active[motor] and 1 or 0
					pose.EasingStyle = Enum.PoseEasingStyle.Linear
					pose.Parent = parentPose
					addChildren(motor.Part1, pose)
				end
			end
		end
		addChildren(root, rootPose)
		keyframe.Parent = sequence
	end
	return sequence
end

-- Seamless loop: L(t) = (1 - t/T) * S(t + T) + (t/T) * S(t), sampled over two cycles.
local function bakeLoop(rig, model, holdStyle, speed, period, motors, fps)
	local animator = newAnimator(rig, model, holdStyle)
	step(animator, rig, 3, speed) -- settle springs and blend weights
	local count = math.max(2, math.floor(period * fps + 0.5))
	local dt = period / count
	local samples = {}
	for i = 0, 2 * count do
		samples[i] = capture(motors)
		step(animator, rig, dt, speed)
	end
	local frames = {}
	for i = 0, count do
		local alpha = i / count
		local blended = lerpFrames(samples[i + count], samples[i], alpha)
		table.insert(frames, { Time = i * dt, Pose = blended })
	end
	return frames
end

local function bakeAction(rig, model, holdStyle, animation: string, duration: number, motors)
	local animator = newAnimator(rig, model, holdStyle)
	step(animator, rig, 2, 0)
	if not animator:PlayAction(animation, duration) then
		return nil
	end
	local count = math.max(2, math.floor(duration * ACTION_FPS + 0.5))
	local dt = duration / count
	local frames = {}
	for i = 0, count do
		table.insert(frames, { Time = i * dt, Pose = capture(motors) })
		step(animator, rig, dt, 0)
	end
	return frames
end

-- Walk/run cycle length measured from the animator's own phase advance.
local function cyclePeriod(rig, model, holdStyle, speed)
	local animator = newAnimator(rig, model, holdStyle)
	step(animator, rig, 3, speed)
	local before = animator.Phase
	step(animator, rig, 0.1, speed)
	local advance = (animator.Phase - before) % (math.pi * 2)
	return (math.pi * 2) / (advance / 0.1)
end

local function serialize(path: string, instance)
	fs.writeFile(path, roblox.serializeModel({ instance }))
end

fs.writeDir("assets/RBX_ANIMSAVES")
fs.writeDir("assets/AnimationRigs")

local total = 0
for _, id in WeaponConfig.Order do
	if not filter or string.find(id, filter, 1, true) then
		local weapon = WeaponConfig.Weapons[id]
		for _, form in weapon.FormOrder or { false } do
			local name = form and (id .. "_" .. form) or id
			local config = WeaponConfig.Resolve(id, form or nil)
			local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
			rig.Name = name .. "Rig"
			local model = WeaponBuilder.Equip(rig, id, { Form = form or nil, Drawn = true })
			local motors = {}
			for _, motor in motorTree(rig) do
				-- Body joints + the weapon's mount joints (chain links, drill bits etc. stay procedural).
				if not motor:IsDescendantOf(model) or motor.Name == "MountJoint" then
					table.insert(motors, motor)
				end
			end
			local folder = "assets/RBX_ANIMSAVES/" .. name
			if fs.isDir(folder) then
				fs.removeDir(folder)
			end
			fs.writeDir(folder)
			local holdStyle = config.HoldStyle
			local clips = {
				{
					"Idle",
					bakeLoop(rig, model, holdStyle, 0, (2 * math.pi) / 1.7, motors, IDLE_FPS),
					true,
					Enum.AnimationPriority.Idle,
				},
				{
					"Walk",
					bakeLoop(
						rig,
						model,
						holdStyle,
						WALK_SPEED,
						cyclePeriod(rig, model, holdStyle, WALK_SPEED),
						motors,
						LOOP_FPS
					),
					true,
					Enum.AnimationPriority.Movement,
				},
				{
					"Run",
					bakeLoop(
						rig,
						model,
						holdStyle,
						RUN_SPEED,
						cyclePeriod(rig, model, holdStyle, RUN_SPEED),
						motors,
						LOOP_FPS
					),
					true,
					Enum.AnimationPriority.Movement,
				},
			}
			local attacks = {}
			for _, attackId in config.Moveset.M1 do
				table.insert(attacks, attackId)
			end
			for _, key in { "Z", "X" } do
				if config.Moveset[key] then
					table.insert(attacks, config.Moveset[key])
				end
			end
			local seen = {}
			for _, attackId in attacks do
				local attack = WeaponConfig.Attacks[attackId]
				if attack and not seen[attackId] then
					seen[attackId] = true
					local frames = bakeAction(rig, model, holdStyle, attack.Animation, attack.Duration, motors)
					if frames then
						table.insert(clips, { attackId, frames, false, Enum.AnimationPriority.Action })
					end
				end
			end
			for _, clip in clips do
				local sequence = buildSequence(rig, clip[1], motors, clip[2], clip[3], clip[4])
				sequence:SetAttribute("Weapon", id)
				sequence:SetAttribute("Form", form or "")
				sequence:SetAttribute("Source", "Baked from AnimatorCore by tools/export_animations.luau")
				serialize(folder .. "/" .. clip[1] .. ".rbxm", sequence)
				total += 1
			end
			-- Reset to the idle pose and save the rig (with weapon) for the Animation Editor.
			for _, motor in motors do
				motor.Transform = CFrame.new()
			end
			serialize("assets/AnimationRigs/" .. name .. "Rig.rbxm", rig)
			print(string.format("%-26s %d clips", name, #clips))
		end
	end
end
print("total clips:", total)
