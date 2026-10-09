--[[
	Format
	Display helpers shared by the Stats, Race Roll and Race Index screens so numbers always read the
	same way everywhere ("+12%", "-0.4 s", "x1.20").
]]

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local StatDefinitions = require(Modules.Config.StatDefinitions)

local Format = {}

local function trim(n: number, decimals: number): string
	local text = string.format("%." .. decimals .. "f", n)
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

Format.Trim = trim

function Format.Percent(fraction: number, signed: boolean?): string
	local value = trim(fraction * 100, 1) .. "%"
	if signed and fraction > 0 then
		return "+" .. value
	end
	return value
end

-- Final stat value in its natural unit.
function Format.StatValue(statId: string, value: number): string
	if statId == "DamageReduction" then
		return Format.Percent(value)
	end
	local def = StatDefinitions.ById[statId]
	local format = def and def.Format or "Decimal"
	if format == "Integer" then
		return tostring(math.floor(value + 0.5))
	elseif format == "Percent" then
		return Format.Percent(value)
	elseif format == "PercentPerSecond" then
		return Format.Percent(value) .. "/s"
	elseif format == "PerSecond" then
		return trim(value, 1) .. "/s"
	elseif format == "Studs" then
		return trim(value, 1) .. " studs"
	elseif format == "Multiplier" then
		return "x" .. trim(value, 2)
	end
	return trim(value, 2)
end

-- A modifier as shown on race / mastery cards ("+25% Max Health").
function Format.Modifier(modifier: { Stat: string, Value: number, Kind: string? }): string
	local def = StatDefinitions.ById[modifier.Stat]
	local name = def and def.DisplayName or modifier.Stat
	if modifier.Kind == "Flat" then
		return string.format("%s%s %s", modifier.Value >= 0 and "+" or "", trim(modifier.Value, 2), name)
	elseif modifier.Kind == "Multiplicative" then
		return string.format("x%s %s", trim(1 + modifier.Value, 2), name)
	end
	return string.format("%s %s", Format.Percent(modifier.Value, true), name)
end

-- Signed difference between two final values in the stat's unit.
function Format.Delta(statId: string, delta: number): string
	local text = Format.StatValue(statId, math.abs(delta))
	return (delta >= 0 and "+" or "-") .. text
end

function Format.StatName(statId: string): string
	if statId == "DamageReduction" then
		return "Damage Reduction"
	end
	local def = StatDefinitions.ById[statId]
	return def and def.DisplayName or statId
end

return Format
