--[[
	BuildModifiers
	Collects the *permanent* stat modifiers of a build from a profile: race, race mastery stages,
	combat role and weapon mastery. Shared so the client can preview "before vs after" exactly the
	way the server computes it. Temporary effects (buffs, synchronization, madness) are added on
	the server by StatService on top of this list.
]]

local Modules = script.Parent.Parent
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local RaceConfig = require(Modules.Config.RaceConfig)
local WeaponConfig = require(Modules.WeaponConfig)

local BuildModifiers = {}

export type Overrides = { RaceId: string?, Role: string?, Weapon: string? }

local function append(target, list)
	for _, item in list do
		table.insert(target, item)
	end
end

function BuildModifiers.RaceStage(profile, raceId: string): number
	local progress = profile.Race and profile.Race.Progress and profile.Race.Progress[raceId]
	return progress and progress.Stage or 1
end

function BuildModifiers.FromProfile(profile, overrides: Overrides?)
	local mods = {}
	local o = overrides or {}
	local raceId = o.RaceId or (profile.Race and profile.Race.Active) or ""
	if raceId ~= "" and RaceConfig.ById[raceId] then
		append(mods, RaceConfig.StatModifiers(raceId))
		append(mods, MasteryConfig.StatModifiers(raceId, BuildModifiers.RaceStage(profile, raceId)))
	end
	local role = o.Role or (profile.Loadout and profile.Loadout.Role)
	if role then
		append(mods, CombatRoleConfig.StatModifiers(role))
	end
	local weaponId = o.Weapon or (profile.Loadout and profile.Loadout.Weapon)
	if weaponId and WeaponConfig.Weapons[weaponId] then
		local xp = profile.Weapons and profile.Weapons.Mastery and profile.Weapons.Mastery[weaponId] or 0
		local level = WeaponConfig.MasteryLevel(xp)
		if level > 0 then
			table.insert(mods, {
				Stat = "WeaponDamage",
				Kind = "Additive",
				Value = level * WeaponConfig.MasteryDamagePerLevel,
				Source = "WeaponMastery:" .. weaponId,
			})
		end
	end
	return mods
end

return BuildModifiers
