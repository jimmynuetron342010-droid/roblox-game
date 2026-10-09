--[[
	Net
	Single access point for ReplicatedStorage.Remotes. The remotes themselves are declared in
	default.project.json so they exist in Explorer before any script runs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder: Folder? = nil

local function getFolder(): Folder
	if not folder then
		folder = ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder
		assert(folder, "ReplicatedStorage.Remotes is missing")
	end
	return folder :: Folder
end

function Net.Event(name: string): RemoteEvent
	local remote = getFolder():WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "Missing RemoteEvent " .. name)
	return remote :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	local remote = getFolder():WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteFunction"), "Missing RemoteFunction " .. name)
	return remote :: RemoteFunction
end

return Net
