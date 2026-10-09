--[[
	Util
	Small, dependency-free helpers shared by client and server.
]]

local Util = {}

-- Recursively copies a table (no metatables, no cycles expected in data tables).
function Util.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[Util.DeepCopy(k)] = Util.DeepCopy(v)
	end
	return copy :: any
end

-- Fills in keys that exist in `template` but are missing from `target` (used for data migrations).
function Util.Reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if target[k] == nil then
			target[k] = Util.DeepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
			-- Only reconcile "record" style tables (non-empty templates). Empty template tables are
			-- dictionaries/arrays whose keys are data, not schema.
			Util.Reconcile(target[k], v)
		end
	end
	return target
end

function Util.Round(n: number, decimals: number?): number
	local m = 10 ^ (decimals or 0)
	return math.floor(n * m + 0.5) / m
end

function Util.IsFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Util.FormatPercent(fraction: number, decimals: number?): string
	local value = Util.Round(fraction * 100, decimals or 0)
	local sign = value > 0 and "+" or ""
	return string.format("%s%s%%", sign, tostring(value))
end

function Util.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function Util.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Util.Keys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	return keys
end

function Util.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent exponential smoothing factor.
function Util.Damp(speed: number, dt: number): number
	return 1 - math.exp(-speed * dt)
end

function Util.FreezeDeep<T>(t: T): T
	if type(t) == "table" and not table.isfrozen(t :: any) then
		for _, v in t :: any do
			Util.FreezeDeep(v)
		end
		table.freeze(t :: any)
	end
	return t
end

return Util
