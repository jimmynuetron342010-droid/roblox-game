--[[
	LoadoutService
	Validated changes to the combat role, magic school, Tsubaki form and player settings.
	Role/school changes are blocked during combat and always checked against BuildRules so a build
	can never hold contradictory pieces.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local BuildRules = require(Modules.Config.BuildRules)
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local MagicConfig = require(Modules.Config.MagicConfig)
local Validate = require(Modules.Core.Validate)
local WeaponConfig = require(Modules.WeaponConfig)

local Server = script.Parent.Parent
local Notifier = require(Server.Core.Notifier)
local RemoteGuard = require(Server.Core.RemoteGuard)

local LoadoutService = {}

local DataService
local StatService
local WeaponService

LoadoutService.SettingsSchema = {
	ReducedMotion = "boolean",
	FastReveal = "boolean",
	SeenRollAnimation = "boolean",
	CameraShake = "boolean",
	DamageNumbers = "boolean",
	VFXQuality = { Auto = true, Low = true, Medium = true, High = true },
	UIScale = { Min = 0.75, Max = 1.4 },
}

-- Pure settings validation (tests use it). Returns the accepted subset.
function LoadoutService.CleanSettings(input: any)
	local accepted = {}
	if not Validate.Table(input, 16) then
		return accepted
	end
	for key, rule in LoadoutService.SettingsSchema do
		local value = input[key]
		if value ~= nil then
			if rule == "boolean" then
				if type(value) == "boolean" then
					accepted[key] = value
				end
			elseif type(rule) == "table" and rule.Min then
				if Validate.Number(value, rule.Min, rule.Max) then
					accepted[key] = math.floor(value * 100 + 0.5) / 100
				end
			elseif type(rule) == "table" then
				if type(value) == "string" and rule[value] then
					accepted[key] = value
				end
			end
		end
	end
	return accepted
end

local function setLoadout(player: Player, kind: any, value: any)
	local profile = DataService:GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "Loading" }
	end
	if not profile.Student.Created then
		return { Ok = false, Reason = "NoStudent" }
	end
	local raceId = profile.Race.Active ~= "" and profile.Race.Active or nil
	if kind == "Role" then
		if StatService:InCombat(player) then
			return { Ok = false, Reason = "InCombat" }
		end
		if not BuildRules.IsRoleAllowed(raceId, value) then
			return { Ok = false, Reason = "RoleNotAllowed" }
		end
		profile.Loadout.Role = value
		StatService:Recompute(player)
		Notifier.Send(player, "Combat role: " .. CombatRoleConfig.ById[value].DisplayName, "Info")
	elseif kind == "School" then
		if StatService:InCombat(player) then
			return { Ok = false, Reason = "InCombat" }
		end
		if not BuildRules.IsSchoolAllowed(raceId, value, profile.Level) then
			return { Ok = false, Reason = "SchoolNotAllowed" }
		end
		profile.Loadout.School = value
		Notifier.Send(player, "Magic school: " .. MagicConfig.ById[value].DisplayName, "Info")
	elseif kind == "TsubakiForm" then
		local weapon = WeaponConfig.Weapons.TsubakiForms
		if type(value) ~= "string" or not weapon.Forms[value] then
			return { Ok = false, Reason = "BadForm" }
		end
		profile.Loadout.TsubakiForm = value
		if profile.Loadout.Weapon == "TsubakiForms" then
			WeaponService:EquipFromProfile(player)
		end
	else
		return { Ok = false, Reason = "BadRequest" }
	end
	player:SetAttribute("Role", profile.Loadout.Role)
	player:SetAttribute("School", profile.Loadout.School)
	DataService:MarkDirty(player)
	return { Ok = true, Loadout = profile.Loadout }
end

local function updateSettings(player: Player, input: any)
	local profile = DataService:GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "Loading" }
	end
	local accepted = LoadoutService.CleanSettings(input)
	for key, value in accepted do
		profile.Settings[key] = value
	end
	DataService:MarkDirty(player)
	return { Ok = true, Settings = profile.Settings }
end

function LoadoutService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
	WeaponService = registry.WeaponService
end

function LoadoutService:Start()
	RemoteGuard.OnInvoke("SetLoadout", 3, 5, setLoadout)
	RemoteGuard.OnInvoke("UpdateSettings", 3, 6, updateSettings)
	DataService.ProfileLoaded:Connect(function(player, profile)
		player:SetAttribute("Role", profile.Loadout.Role)
		player:SetAttribute("School", profile.Loadout.School)
	end)
end

return LoadoutService
