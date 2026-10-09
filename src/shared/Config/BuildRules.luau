--[[
	BuildRules
	Keeps Race, Combat Role, Weapon and Magic specialization independent *and* coherent.
	  * Race   -> passives, stat modifiers, appearance, racial ability (C)
	  * Role   -> technique (V) and small modifiers
	  * Weapon -> moveset, reach, combos, weapon arts (M1 / Z / X)
	  * Magic  -> only for magic-capable origins; decides what Witchcraft/Sorcery casts

	Example: a Witch never becomes a Demon Weapon just because both touch "magic"-like systems, and
	a Demon Weapon cannot pick the Meister role (it partners *with* Meisters instead).
]]

local CombatRoleConfig = require(script.Parent.CombatRoleConfig)
local MagicConfig = require(script.Parent.MagicConfig)

local BuildRules = {}

-- Roles each origin may use. Anything not listed falls back to DefaultRoles.
BuildRules.DefaultRoles = { "Meister", "Assassin", "Technician" }
BuildRules.RaceRoles = {
	DemonWeapon = { "PartnerWeapon", "Technician" },
}

function BuildRules.AllowedRoles(raceId: string?): { string }
	return (raceId and BuildRules.RaceRoles[raceId]) or BuildRules.DefaultRoles
end

function BuildRules.IsRoleAllowed(raceId: string?, roleId: string?): boolean
	if not roleId or not CombatRoleConfig.ById[roleId] then
		return false
	end
	-- Before a race is rolled, any default role may be chosen at character creation.
	return table.find(BuildRules.AllowedRoles(raceId), roleId) ~= nil
end

function BuildRules.DefaultRole(raceId: string?): string
	return BuildRules.AllowedRoles(raceId)[1]
end

function BuildRules.CanUseMagic(raceId: string?): boolean
	return raceId ~= nil and MagicConfig.RaceGroups[raceId] ~= nil
end

function BuildRules.IsSchoolAllowed(raceId: string?, schoolId: string?, level: number): boolean
	if not schoolId or not raceId then
		return false
	end
	local school = MagicConfig.ById[schoolId]
	if not school then
		return false
	end
	return MagicConfig.RaceGroups[raceId] == school.Group and level >= school.UnlockLevel
end

-- Resonance (synchronization) pairs a Demon Weapon origin with a Meister-role partner.
function BuildRules.CanSynchronize(raceA: string?, roleA: string?, raceB: string?, roleB: string?): boolean
	local aIsWeapon = raceA == "DemonWeapon"
	local bIsWeapon = raceB == "DemonWeapon"
	if aIsWeapon and roleB == "Meister" and not bIsWeapon then
		return true
	end
	if bIsWeapon and roleA == "Meister" and not aIsWeapon then
		return true
	end
	return false
end

-- Repairs a loadout after a race change (e.g. the new race cannot use the old role or school).
-- Returns the corrected role/school and a list of human readable changes.
function BuildRules.Sanitize(
	raceId: string?,
	roleId: string?,
	schoolId: string?,
	level: number
): (string, string?, { string })
	local changes = {}
	local role = roleId
	if not BuildRules.IsRoleAllowed(raceId, role) then
		role = BuildRules.DefaultRole(raceId)
		local roleDef = CombatRoleConfig.ById[role]
		table.insert(changes, "Combat role changed to " .. roleDef.DisplayName .. " (not available to this origin).")
	end
	local school = schoolId
	if BuildRules.CanUseMagic(raceId) then
		if not BuildRules.IsSchoolAllowed(raceId, school, level) then
			school = MagicConfig.DefaultSchool(raceId)
			if school then
				table.insert(changes, "Magic school set to " .. MagicConfig.ById[school].DisplayName .. ".")
			end
		end
	elseif school ~= nil then
		school = nil
		table.insert(changes, "Magic school unequipped (this origin cannot use magic schools).")
	end
	assert(role ~= nil, "role must resolve")
	return role :: string, school, changes
end

return BuildRules
