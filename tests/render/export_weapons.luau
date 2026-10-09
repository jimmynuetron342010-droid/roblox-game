--[[
	export_weapons.luau (Lune)
	Equips every weapon on a PreviewRig with the real WeaponBuilder, poses it with the real
	AnimatorCore (idle / walk / any action frame) and writes scenes.json for render.mjs.

	Usage: lune run tests/render/export_weapons.luau [weaponFilter] [pose]
	  pose: Idle | Walk | Run | <ActionName>@<0..1>   (default Idle)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("../harness/Loader")
local SceneExport = require("./SceneExport")

local loader = Loader.new({ IsServer = false })
local roblox = Loader.roblox
local CFrame = roblox.CFrame

local WeaponBuilder = loader.RequirePath("ReplicatedStorage.Modules.WeaponBuilder")
local WeaponConfig = loader.RequirePath("ReplicatedStorage.Modules.WeaponConfig")
local PreviewRig = loader.RequirePath("ReplicatedStorage.Modules.Rig.PreviewRig")
local PosePreview = loader.RequirePath("ReplicatedStorage.Modules.Animation.PosePreview")

local filter = process.args[1]
if filter == "" then
	filter = nil
end
local poseArg = process.args[2] or "Idle"
local scenes = {}

local function poseOptions(config)
	local options = { HoldStyle = config.HoldStyle }
	if poseArg == "Walk" then
		options.Speed = 14
		options.Time = 0.37
	elseif poseArg == "Run" then
		options.Speed = 22
		options.Time = 0.31
	elseif poseArg ~= "Idle" then
		local name, t = string.match(poseArg, "^(%w+)@([%d%.]+)$")
		if name == "M1" or name == "Z" or name == "X" then
			-- Resolve the weapon's own attack for this slot.
			local attackId = name == "M1" and config.Moveset.M1[1] or config.Moveset[name]
			name = WeaponConfig.Attacks[attackId].Animation
		end
		options.Action = name
		options.ActionTime = tonumber(t)
	end
	return options
end

for _, id in WeaponConfig.Order do
	if not filter or string.find(id, filter, 1, true) then
		local weapon = WeaponConfig.Weapons[id]
		for _, form in weapon.FormOrder or { false } do
			local name = form and (id .. "-" .. form) or id
			local config = WeaponConfig.Resolve(id, form or nil)
			local rig = PreviewRig.Build({ Origin = CFrame.new(0, 3, 0) })
			local model = WeaponBuilder.Equip(rig, id, { Form = form or nil })
			local options = poseOptions(config)
			options.Weapon = model
			PosePreview.Pose(rig, options)
			local tag = string.gsub(poseArg, "[^%w]", "_")
			table.insert(scenes, {
				name = name .. "_" .. tag,
				groundY = 0,
				parts = SceneExport.Collect({ rig }),
				views = {
					{ name = "front", fit = { -0.75, 0.35, -1 }, padding = 0.85, fov = 35 },
					{ name = "side", fit = { 1, 0.25, -0.15 }, padding = 0.85, fov = 35 },
				},
			})
			if poseArg == "Idle" then
				local solo = WeaponBuilder.Build(id, { Form = form or nil, Anchored = true, Origin = CFrame.new(0, 3.2, 0) })
				table.insert(scenes, {
					name = name .. "_model",
					groundY = -1.5,
					parts = SceneExport.Collect({ solo }),
					views = {
						{ name = "profile", fit = { 1, 0.05, 0 }, padding = 1.0, fov = 35, ground = false },
						{ name = "three_quarter", fit = { 0.8, 0.45, -0.7 }, padding = 1.0, fov = 35, ground = false },
					},
				})
			end
			print(string.format("%-28s parts: %d", name, WeaponBuilder.CountParts(model)))
		end
	end
end

fs.writeDir("tests/renders/out")
fs.writeFile("tests/renders/out/scenes.json", serde.encode("json", scenes))
print("scenes:", #scenes)
