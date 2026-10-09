--[[
	WeightedRoll
	Integer-weight selection. Weights are expressed in basis points (1/100th of a percent)
	so the published probability table is exact and never suffers float drift.
]]

export type Entry = { Id: string, Weight: number }

local WeightedRoll = {}

function WeightedRoll.Total(entries: { Entry }): number
	local total = 0
	for _, entry in entries do
		total += entry.Weight
	end
	return total
end

-- Validates that all weights are positive integers and (optionally) sum to `expectedTotal`.
function WeightedRoll.Validate(entries: { Entry }, expectedTotal: number?): (boolean, string?)
	local seen = {}
	for _, entry in entries do
		if type(entry.Id) ~= "string" or seen[entry.Id] then
			return false, "duplicate or invalid id: " .. tostring(entry.Id)
		end
		seen[entry.Id] = true
		if type(entry.Weight) ~= "number" or entry.Weight <= 0 or math.floor(entry.Weight) ~= entry.Weight then
			return false, "weight must be a positive integer for " .. entry.Id
		end
	end
	local total = WeightedRoll.Total(entries)
	if expectedTotal and total ~= expectedTotal then
		return false, string.format("weights sum to %d, expected %d", total, expectedTotal)
	end
	return true, nil
end

-- `rng` must expose NextInteger(min, max) (Roblox Random object on the server).
function WeightedRoll.Pick(entries: { Entry }, rng: any): Entry
	local total = WeightedRoll.Total(entries)
	assert(total > 0, "WeightedRoll.Pick: empty table")
	local roll = rng:NextInteger(1, total)
	local cumulative = 0
	for _, entry in entries do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry
		end
	end
	return entries[#entries]
end

function WeightedRoll.Probabilities(entries: { Entry }): { [string]: number }
	local total = WeightedRoll.Total(entries)
	local result = {}
	for _, entry in entries do
		result[entry.Id] = entry.Weight / total
	end
	return result
end

return WeightedRoll
