local Loader = require("../../tests/harness/Loader")
local loader = Loader.new({ IsServer = false })
local CFrame = Loader.roblox.CFrame
local WeaponBuilder = loader.RequirePath("ReplicatedStorage.Modules.WeaponBuilder")
local WeaponConfig = loader.RequirePath("ReplicatedStorage.Modules.WeaponConfig")
local PreviewRig = loader.RequirePath("ReplicatedStorage.Modules.Rig.PreviewRig")
local PosePreview = loader.RequirePath("ReplicatedStorage.Modules.Animation.PosePreview")
for _, id in WeaponConfig.Order do
	local weapon = WeaponConfig.Weapons[id]
	for _, form in weapon.FormOrder or { false } do
		local config = WeaponConfig.Resolve(id, form or nil)
		local poses = {
			{ "idle", { Speed = 0 } },
			{ "walk", { Speed = 14, Time = 0.37 } },
			{ "run", { Speed = 22, Time = 0.31 } },
		}
		local function addAttack(attackId, label)
			local a = WeaponConfig.Attacks[attackId]
			for _, t in { 0.1, 0.3, 0.5, 0.7, 0.9 } do
				table.insert(poses, { label .. "@" .. t, { Action = a.Animation, ActionTime = t } })
			end
		end
		for i, a in config.Moveset.M1 do
			addAttack(a, "M1" .. i)
		end
		if config.Moveset.Z then
			addAttack(config.Moveset.Z, "Z")
		end
		if config.Moveset.X then
			addAttack(config.Moveset.X, "X")
		end
		local worst = {}
		for _, p in poses do
			local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
			local model = WeaponBuilder.Equip(rig, id, { Form = form or nil, Drawn = true })
			p[2].Weapon = model
			p[2].HoldStyle = config.HoldStyle
			PosePreview.Pose(rig, p[2])
			for _, unit in model:GetChildren() do
				local handle = unit:IsA("Model") and unit:FindFirstChild("Handle")
				local mount = handle and handle:FindFirstChild("MountJoint")
				if
					mount and (unit:GetAttribute("Mount") == "RightHand" or unit:GetAttribute("Mount") == "LeftHand")
				then
					local r = mount.Transform.Position.Magnitude
					if r > 0.1 then
						table.insert(worst, string.format("%s %s=%.2f", p[1], unit.Name, r))
					end
				end
			end
		end
		print((form and id .. "-" .. form or id), config.HoldStyle, #worst > 0 and table.concat(worst, "  ") or "ok")
	end
end
