--[[
	Maid
	Collects connections, instances, threads and callbacks so they can be cleaned up together.
	Used to guarantee that weapon models, VFX and listeners never leak across respawns.
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give<T>(task: T): T
	table.insert(self._tasks, task)
	return task
end

local function cleanup(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif type(item) == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		local ok, err = pcall(cleanup, tasks[i])
		if not ok then
			warn("[Maid] cleanup error: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
