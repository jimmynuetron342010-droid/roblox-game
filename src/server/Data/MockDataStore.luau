--[[
	MockDataStore
	In-memory stand-in with the DataStore API surface used by SessionStore. Used automatically in
	Studio when API access is disabled, and by the Lune test-suite (which can share one mock between
	two simulated servers to test session locking).
]]

local MockDataStore = {}
MockDataStore.__index = MockDataStore

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

function MockDataStore.new()
	return setmetatable({ _data = {}, FailNext = 0, Writes = 0 }, MockDataStore)
end

function MockDataStore:_maybeFail()
	if self.FailNext > 0 then
		self.FailNext -= 1
		error("MockDataStore: simulated request failure")
	end
end

function MockDataStore:GetAsync(key: string)
	self:_maybeFail()
	return deepCopy(self._data[key])
end

function MockDataStore:SetAsync(key: string, value: any)
	self:_maybeFail()
	self._data[key] = deepCopy(value)
	self.Writes += 1
end

function MockDataStore:UpdateAsync(key: string, transform: (any) -> any)
	self:_maybeFail()
	local result = transform(deepCopy(self._data[key]))
	if result ~= nil then
		self._data[key] = deepCopy(result)
		self.Writes += 1
	end
	return deepCopy(result)
end

function MockDataStore:RemoveAsync(key: string)
	self:_maybeFail()
	local old = self._data[key]
	self._data[key] = nil
	return deepCopy(old)
end

-- Test helper: inspect raw stored record.
function MockDataStore:Peek(key: string)
	return deepCopy(self._data[key])
end

return MockDataStore
