--[[
	AbilitySlots
	Which ability a key slot resolves to for a given build (shared so the client can predict the
	gesture and the HUD can show the right icon/cooldown, and the server stays authoritative).
	  C = racial ability (may unlock at a mastery stage)
	  V = combat role technique
	  B = Kishin Awakening (endgame unlock)
]]

local Modules = script.Parent.Parent
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local RaceConfig = require(Modules.Config.RaceConfig)

local AbilitySlots = {}

AbilitySlots.Slots = { "C", "V", "B" }

-- Returns (abilityId?, stage, reasonIfUnavailable?)
function AbilitySlots.Resolve(profile, slot: string): (string?, number, string?)
	if not profile then
		return nil, 1, "Loading"
	end
	local raceId = profile.Race.Active
	local stage = 1
	if raceId ~= "" and profile.Race.Progress[raceId] then
		stage = profile.Race.Progress[raceId].Stage
	end
	if slot == "C" then
		local race = RaceConfig.ById[raceId]
		if not race then
			return nil, stage, "NoRace"
		end
		if not race.AbilityId then
			return nil, stage, "NoAbility"
		end
		if stage < race.AbilityUnlockStage then
			return nil, stage, "Locked"
		end
		return race.AbilityId, stage, nil
	elseif slot == "V" then
		local role = CombatRoleConfig.ById[profile.Loadout.Role]
		if not role then
			return nil, stage, "NoRole"
		end
		return role.TechniqueId, 1, nil
	elseif slot == "B" then
		if not profile.Unlocks.KishinAwakening then
			return nil, stage, "Locked"
		end
		return "KishinAwakening", 1, nil
	end
	return nil, stage, "BadSlot"
end

return AbilitySlots
