--[[
	PosePreview
	Poses a character/PreviewRig + weapon without physics: runs AnimatorCore for a short settle
	period, optionally scrubs to a point in an action, then solves every Weld/Motor6D so part
	CFrames are correct. Used by ViewportFrame portraits (no joint solving happens inside
	ViewportFrames) and by the offline render tests.
]]

local AnimatorCore = require(script.Parent.AnimatorCore)

local PosePreview = {}

local function transformOf(joint: Instance): CFrame
	if joint:IsA("Motor6D") then
		local ok, value = pcall(function()
			return (joint :: Motor6D).Transform
		end)
		if ok and value then
			return value
		end
	end
	return CFrame.new()
end

-- Solves part CFrames from `root` through every JointInstance found under `containers`.
function PosePreview.SolveJoints(root: BasePart, containers: { Instance })
	local joints = {}
	for _, container in containers do
		for _, descendant in container:GetDescendants() do
			if descendant:IsA("Motor6D") or descendant:IsA("Weld") then
				table.insert(joints, descendant)
			end
		end
	end
	local solved = { [root] = true }
	local progress = true
	while progress do
		progress = false
		for _, joint in joints do
			local j = joint :: any
			local part0, part1 = j.Part0, j.Part1
			if part0 and part1 and solved[part0] and not solved[part1] then
				part1.CFrame = part0.CFrame * j.C0 * transformOf(joint) * j.C1:Inverse()
				solved[part1] = true
				progress = true
			end
		end
	end
	return solved
end

export type PoseOptions = {
	Weapon: Model?,
	HoldStyle: string?,
	Action: string?,
	ActionTime: number?, -- normalized 0..1
	Speed: number?,
	Settle: number?, -- seconds of idle simulation before sampling
	Time: number?, -- extra idle time offset (breathing phase)
}

-- Returns the animator used (callers may keep stepping it).
function PosePreview.Pose(rig: Model, options: PoseOptions)
	local animator = AnimatorCore.new(rig)
	animator:SetWeapon(options.Weapon, options.HoldStyle)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local ctx = { Speed = options.Speed or 0, Grounded = true, Present = true, RootCFrame = root.CFrame }
	local dt = 1 / 30
	local settle = (options.Settle or 1.5) + (options.Time or 0)
	for _ = 1, math.max(1, math.floor(settle / dt)) do
		animator:Update(dt, ctx)
	end
	if options.Action then
		animator:PlayAction(options.Action, 1)
		local target = math.clamp(options.ActionTime or 0.5, 0, 0.999)
		local steps = math.max(1, math.floor(target / (1 / 120)))
		for _ = 1, steps do
			animator:Update(target / steps, ctx)
		end
	end
	local containers: { Instance } = { rig }
	PosePreview.SolveJoints(root, containers)
	return animator
end

return PosePreview
