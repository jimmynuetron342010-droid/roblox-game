--[[
	Polyfills (Lune)
	Globals that exist inside Roblox but not in Lune: Random, warn, time(), tick(), RunService, etc.
]]

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Polyfills = {}

-- xorshift-style deterministic PRNG with Roblox's Random API surface.
local Random = {}
Random.__index = Random

function Random.new(seed: number?)
	local s = seed or os.clock() * 1e6
	local state = math.floor(s) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ _state = state }, Random)
end

function Random:_next(): number
	-- Park-Miller minimal standard generator.
	self._state = (self._state * 48271) % 2147483647
	return self._state
end

function Random:NextNumber(min: number?, max: number?): number
	local r = (self:_next() - 1) / 2147483646
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * r
end

function Random:NextInteger(min: number, max: number): number
	assert(min <= max, "NextInteger: min > max")
	local span = max - min + 1
	return min + (self:_next() % span)
end

function Random:NextUnitVector()
	local v
	repeat
		v = roblox.Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
	until v.Magnitude > 1e-3 and v.Magnitude <= 1
	return v.Unit
end

function Random:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

function Random:Clone()
	return setmetatable({ _state = self._state }, Random)
end

Polyfills.Random = Random

local clockOffset = 0
function Polyfills.AdvanceClock(seconds: number)
	clockOffset += seconds
end
function Polyfills.Now(): number
	return os.clock() + clockOffset
end

function Polyfills.RunService(opts)
	return {
		IsServer = function()
			return opts.IsServer ~= false
		end,
		IsClient = function()
			return opts.IsServer == false
		end,
		IsStudio = function()
			return opts.IsStudio == true
		end,
		Heartbeat = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		},
		Stepped = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		},
	}
end

function Polyfills.HttpService()
	local counter = 0
	return {
		GenerateGUID = function(_, braces)
			counter += 1
			local guid = string.format("%08x-0000-4000-8000-%012x", counter, counter * 7919)
			return braces and ("{" .. guid .. "}") or guid
		end,
		JSONEncode = function(_, value)
			return require("@lune/serde").encode("json", value)
		end,
		JSONDecode = function(_, value)
			return require("@lune/serde").decode("json", value)
		end,
	}
end

-- Lune 0.10.5's CFrame.lookAt (and the two-argument CFrame.new(pos, target)) flip the Z component
-- of the look direction: lookAt(origin, origin + Z) faces -Z. fromMatrix / Angles / components are
-- correct, so rebuild Roblox's lookAt on top of fromMatrix for everything the harness runs.
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return roblox.CFrame.new(at)
	end
	local back = -look.Unit
	local upHint = up or roblox.Vector3.new(0, 1, 0)
	local right = upHint:Cross(back)
	if right.Magnitude < 1e-6 then
		-- Looking straight along the up hint: pick any perpendicular right vector.
		right = roblox.Vector3.new(0, 0, 1):Cross(back)
		if right.Magnitude < 1e-6 then
			right = roblox.Vector3.new(1, 0, 0)
		end
	end
	right = right.Unit
	local upAxis = back:Cross(right).Unit
	return roblox.CFrame.fromMatrix(at, right, upAxis, back)
end
Polyfills.LookAt = lookAt

Polyfills.CFrame = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local count = select("#", ...)
		local a, b = ...
		if count == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return roblox.CFrame.new(...)
	end,
}, { __index = roblox.CFrame })

function Polyfills.Globals(opts)
	opts = opts or {}
	local g = {}
	for key, value in roblox do
		if type(key) == "string" and string.match(key, "^%u") then
			g[key] = value
		end
	end
	g.CFrame = Polyfills.CFrame
	g.task = task
	g.Random = Random
	g.warn = function(...)
		if not opts.SilenceWarnings then
			print("[warn]", ...)
		end
	end
	g.time = function()
		return Polyfills.Now()
	end
	g.tick = function()
		return os.time() + clockOffset
	end
	g.os = setmetatable({
		clock = function()
			return Polyfills.Now()
		end,
	}, { __index = os })
	return g
end

return Polyfills
