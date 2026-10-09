--[[
	Signal
	Minimal synchronous signal used for server-internal gameplay events
	(enemy killed, ability used, ...). Handlers are isolated: one failing handler
	does not prevent the others from running.
]]

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local connection = { Connected = true }
	local handlers = self._handlers
	function connection.Disconnect(conn)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, handler)
	return connection :: any
end

function Signal:Fire(...: any)
	-- Copy so handlers may disconnect while iterating.
	for _, handler in table.clone(self._handlers) do
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[Signal] handler error: " .. tostring(err))
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
