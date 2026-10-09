--[[
	Validate
	Defensive argument validation for anything that crosses the client -> server boundary.
	Every RemoteEvent / RemoteFunction handler runs its arguments through these helpers and
	rejects anything malformed. Never trust client-provided names, numbers or outcomes.
]]

local Util = require(script.Parent.Util)

local Validate = {}

function Validate.String(value: any, minLength: number?, maxLength: number?, pattern: string?): boolean
	if type(value) ~= "string" then
		return false
	end
	local len = #value
	if len < (minLength or 0) or len > (maxLength or 200) then
		return false
	end
	if pattern and not string.match(value, pattern) then
		return false
	end
	return true
end

-- Identifiers coming from config (race ids, weapon ids, ...). Letters/numbers/underscore only.
function Validate.Identifier(value: any): boolean
	return Validate.String(value, 1, 48, "^[%a_][%w_]*$")
end

-- Client-generated request ids used for idempotency (GUID-like).
function Validate.RequestId(value: any): boolean
	return Validate.String(value, 8, 64, "^[%w%-]+$")
end

function Validate.Number(value: any, min: number?, max: number?): boolean
	if not Util.IsFinite(value) then
		return false
	end
	if min and value < min then
		return false
	end
	if max and value > max then
		return false
	end
	return true
end

function Validate.Integer(value: any, min: number?, max: number?): boolean
	return Validate.Number(value, min, max) and math.floor(value) == value
end

function Validate.Boolean(value: any): boolean
	return type(value) == "boolean"
end

-- Returns a normalized direction or nil if the value is not a sane Vector3.
function Validate.Direction(value: any): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	if not (Util.IsFinite(value.X) and Util.IsFinite(value.Y) and Util.IsFinite(value.Z)) then
		return nil
	end
	local magnitude = value.Magnitude
	if magnitude < 1e-3 or magnitude > 1e3 then
		return nil
	end
	return value / magnitude
end

function Validate.Position(value: any, maxAbs: number?): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local limit = maxAbs or 1e5
	for _, c in { value.X, value.Y, value.Z } do
		if not Util.IsFinite(c) or math.abs(c) > limit then
			return nil
		end
	end
	return value
end

function Validate.OneOf(value: any, allowed: { [any]: any }): boolean
	return value ~= nil and allowed[value] ~= nil
end

-- Shallow table check with a bounded key count to block giant payloads.
function Validate.Table(value: any, maxKeys: number?): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for _ in value do
		count += 1
		if count > (maxKeys or 32) then
			return false
		end
	end
	return true
end

return Validate
