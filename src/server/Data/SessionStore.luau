--[[
	SessionStore
	Session-locked persistence on top of any DataStore-like object (real GlobalDataStore or
	MockDataStore). Prevents two servers from editing the same profile (item/currency duplication):

	  record = { Data = <profile>, SessionLock = { JobId, Time } | nil, SavedAt }

	Load acquires the lock with UpdateAsync. If another live server holds it, Load reports
	"Locked"; a lock whose heartbeat is older than `staleAfter` seconds is treated as abandoned
	(server crash) and is taken over. Save refuses to write if the lock now belongs to someone else.
]]

export type StoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

local SessionStore = {}
SessionStore.__index = SessionStore

function SessionStore.new(store: StoreLike, jobId: string, staleAfter: number, clock: (() -> number)?)
	return setmetatable({
		Store = store,
		JobId = jobId,
		StaleAfter = staleAfter,
		Clock = clock or os.time,
	}, SessionStore)
end

-- Returns (status, data) where status is "Ok" | "Locked" | "Error".
-- `makeDefault` builds a fresh profile for brand new players.
function SessionStore:Load(key: string, makeDefault: () -> any): (string, any)
	local status = "Error"
	local loaded = nil
	local ok, err = pcall(function()
		self.Store:UpdateAsync(key, function(record)
			local now = self.Clock()
			if type(record) == "table" and type(record.SessionLock) == "table" then
				local lock = record.SessionLock
				local isOurs = lock.JobId == self.JobId
				local age = now - (tonumber(lock.Time) or 0)
				if not isOurs and age < self.StaleAfter then
					status = "Locked"
					return nil -- abort the write; someone else owns the session
				end
			end
			local data = (type(record) == "table" and record.Data) or makeDefault()
			loaded = data
			status = "Ok"
			return {
				Data = data,
				SessionLock = { JobId = self.JobId, Time = now },
				SavedAt = type(record) == "table" and record.SavedAt or now,
			}
		end)
	end)
	if not ok then
		return "Error", err
	end
	return status, loaded
end

-- Returns "Ok" | "LockLost" | "Error".
function SessionStore:Save(key: string, data: any, release: boolean): (string, any)
	local status = "Error"
	local ok, err = pcall(function()
		self.Store:UpdateAsync(key, function(record)
			local now = self.Clock()
			if type(record) == "table" and type(record.SessionLock) == "table" then
				if record.SessionLock.JobId ~= self.JobId then
					status = "LockLost"
					return nil
				end
			end
			status = "Ok"
			return {
				Data = data,
				SessionLock = (not release) and { JobId = self.JobId, Time = now } or nil,
				SavedAt = now,
			}
		end)
	end)
	if not ok then
		return "Error", err
	end
	return status, nil
end

return SessionStore
