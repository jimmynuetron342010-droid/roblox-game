--[[
	Server test environment (Lune)
	Boots the real server (Main.server.luau and all 16 services) on strict MockInstances with:
	  * mock Players / RunService / TextService / DataStoreService (Studio → MockDataStore path)
	  * remotes the test can drive like a client (Invoke / Fire) and inspect (Inbox)
	  * characters spawned as R15 rigs (PreviewRig + Humanoid) when the server loads them
	Only the physics engine is absent: humanoids do not walk on their own (tests teleport).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = require("../harness/Loader")
local MockInstance = require("../ui/MockInstance")

local Signal = MockInstance.Signal
local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum

local ServerEnv = {}
ServerEnv.__index = ServerEnv

local function service(className: string)
	local instance = MockInstance.new(className, nil, true)
	instance.Name = className
	return instance
end

function ServerEnv.new()
	local self = setmetatable({}, ServerEnv)
	self.Inbox = {} -- [player] = { { Name, Args } }

	local players = service("Players")
	local list = {}
	MockInstance.Override(players, "GetPlayers", function()
		return table.clone(list)
	end)
	MockInstance.Override(players, "GetPlayerByUserId", function(_, userId)
		for _, p in list do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end)
	MockInstance.Override(players, "GetPlayerFromCharacter", function(_, model)
		for _, p in list do
			if model ~= nil and p.Character == model then
				return p
			end
		end
		return nil
	end)
	self.Players = players
	self.PlayerList = list

	local workspace = service("Workspace")
	local camera = MockInstance.new("Camera", workspace, true)
	camera.Name = "Camera"
	MockInstance.SetInternal(workspace, "CurrentCamera", camera)
	MockInstance.Override(workspace, "GetServerTimeNow", function()
		return 1000 + os.clock()
	end)
	MockInstance.Override(workspace, "Raycast", function(_, origin, direction)
		if direction.Y < 0 and origin.Y > 0 and origin.Y + direction.Y <= 0 then
			local t = origin.Y / -direction.Y
			return {
				Position = origin + direction * t,
				Normal = Vector3.new(0, 1, 0),
				Material = Enum.Material.Concrete,
				Instance = workspace,
				Distance = (direction * t).Magnitude,
			}
		end
		return nil
	end)
	MockInstance.Override(workspace, "Spherecast", function()
		return nil
	end)
	self.Workspace = workspace

	local heartbeat, stepped = Signal.new("Heartbeat"), Signal.new("Stepped")
	self.Heartbeat = heartbeat
	local runService = {
		Heartbeat = heartbeat,
		Stepped = stepped,
		PostSimulation = heartbeat,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
	}

	local function params(defaults)
		return {
			new = function()
				return table.clone(defaults)
			end,
		}
	end
	local guard = function(fn, label)
		if type(fn) ~= "function" then
			return fn
		end
		return function(...)
			local ok, err = xpcall(fn, debug.traceback, ...)
			if not ok then
				table.insert(MockInstance.Errors, "[" .. label .. "] " .. tostring(err))
			end
		end
	end
	local guardedTask = setmetatable({
		spawn = function(fn, ...)
			return task.spawn(guard(fn, "task.spawn"), ...)
		end,
		defer = function(fn, ...)
			return task.defer(guard(fn, "task.defer"), ...)
		end,
		delay = function(seconds, fn, ...)
			return task.delay(seconds, guard(fn, "task.delay"), ...)
		end,
	}, { __index = task })

	local loader = Loader.new({
		IsServer = true,
		IsStudio = true,
		Services = {
			Players = players,
			Workspace = workspace,
			RunService = runService,
			Lighting = service("Lighting"),
			TextService = {
				FilterStringAsync = function(_, text)
					return {
						GetNonChatStringForBroadcastAsync = function()
							return (string.gsub(text, "[Bb][Aa][Dd][Ww][Oo][Rr][Dd]", "#######"))
						end,
					}
				end,
			},
			DataStoreService = {
				GetDataStore = function()
					error("Studio API access disabled (test)")
				end,
			},
			ServerStorage = service("ServerStorage"),
		},
		Globals = {
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				local text = table.concat(parts, " ")
				-- The Studio MockDataStore fallback notice is expected here.
				if not string.find(text, "MockDataStore", 1, true) and not string.find(text, "(test)", 1, true) then
					table.insert(MockInstance.Errors, "[warn] " .. text)
				end
			end,
			Instance = MockInstance.InstanceGlobal,
			typeof = MockInstance.TypeOf,
			workspace = workspace,
			task = guardedTask,
			RaycastParams = params({ FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {} }),
			OverlapParams = params({
				FilterType = Enum.RaycastFilterType.Exclude,
				FilterDescendantsInstances = {},
				MaxParts = 0,
			}),
			TweenInfo = {
				new = function(...)
					return table.pack(...)
				end,
			},
		},
	})
	self.Loader = loader
	loader.Game.JobId = "test-server"
	loader.Game.PlaceId = 0
	loader.Game.BindToClose = function(_, callback)
		self.CloseCallback = callback
	end
	loader.Game.GetService = loader.Game.GetService

	-- Remotes the test drives as the client.
	local remotes = {}
	local function remote(name: string, className: string)
		if not remotes[name] then
			local r = { Name = name, ClassName = className }
			function r.IsA(_, cls)
				return cls == className or cls == "Instance"
			end
			if className == "RemoteEvent" then
				r.OnServerEvent = Signal.new("Remote:" .. name)
				function r.FireClient(_, player, ...)
					self.Inbox[player] = self.Inbox[player] or {}
					table.insert(self.Inbox[player], { Name = name, Args = table.pack(...) })
				end
				function r.FireAllClients(_, ...)
					for _, p in list do
						r.FireClient(nil, p, ...)
					end
				end
			end
			remotes[name] = r
		end
		return remotes[name]
	end
	self.Remotes = remotes
	loader.Cache[loader.Find("ReplicatedStorage.Modules.Core.Net")] = {
		value = {
			Event = function(name)
				return remote(name, "RemoteEvent")
			end,
			Function = function(name)
				return remote(name, "RemoteFunction")
			end,
		},
	}
	return self
end

function ServerEnv:Boot()
	local node = self.Loader.Find("ServerScriptService.Server.Main")
	local env = self.Loader.Globals()
	env.script = node
	env.require = self.Loader.Require
	local chunk = luau.load(fs.readFile(node.FilePath), { debugName = node.FilePath, environment = env })
	local ok, err = xpcall(chunk, debug.traceback)
	if not ok then
		table.insert(MockInstance.Errors, "[Main.server] " .. tostring(err))
	end
end

-- Frame events carry the real elapsed time, so Heartbeat-driven systems (regen, AI) and
-- clock-driven ones (cooldowns) stay in step, exactly like the engine.
function ServerEnv:Step(frames: number?)
	for _ = 1, frames or 1 do
		local now = os.clock()
		local dt = math.clamp(now - (self.LastStep or now - 1 / 60), 1 / 240, 0.1)
		self.LastStep = now
		self.Heartbeat:Fire(dt)
		task.wait()
	end
end

function ServerEnv:Wait(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		self:Step(1)
	end
end

function ServerEnv:WaitFor(description: string, predicate: () -> any, timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		self:Step(1)
	end
	error("Timed out waiting for: " .. description, 2)
end

-- A player joins; the server spawns them as an R15 rig when it calls LoadCharacter.
function ServerEnv:AddPlayer(name: string, userId: number)
	local player = MockInstance.new("Player", nil, true)
	player.Name = name
	MockInstance.SetInternal(player, "UserId", userId)
	MockInstance.SetInternal(player, "DisplayName", name)
	local PreviewRig = self.Loader.RequirePath("ReplicatedStorage.Modules.Rig.PreviewRig")
	local function load()
		local old = player.Character
		if old then
			old:Destroy()
		end
		local spawn = self.Workspace:FindFirstChild("SpawnLocation", true)
		local origin = spawn and (spawn.CFrame * CFrame.new(0, 4, 0)) or CFrame.new(0, 5, 0)
		local rig = PreviewRig.Build({ Origin = origin, Humanoid = true })
		rig.Name = name
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		if humanoid then
			MockInstance.new("Animator", humanoid)
		end
		rig.Parent = self.Workspace
		MockInstance.SetInternal(player, "Character", rig)
		player.CharacterAdded:Fire(rig)
	end
	MockInstance.Override(player, "LoadCharacterAsync", load)
	MockInstance.Override(player, "LoadCharacter", load)
	player.Parent = self.Players
	table.insert(self.PlayerList, player)
	self.Players.PlayerAdded:Fire(player)
	return player
end

function ServerEnv:RemovePlayer(player)
	local index = table.find(self.PlayerList, player)
	if index then
		table.remove(self.PlayerList, index)
	end
	self.Players.PlayerRemoving:Fire(player)
	self:Step(2)
	player.Parent = nil
end

-- Client → server calls.
function ServerEnv:Invoke(player, name: string, ...)
	local r = self.Remotes[name]
	assert(r and r.OnServerInvoke, "no server handler for " .. name)
	return r.OnServerInvoke(player, ...)
end

function ServerEnv:Fire(player, name: string, ...)
	local r = self.Remotes[name]
	assert(r and r.OnServerEvent, "no RemoteEvent " .. name)
	r.OnServerEvent:Fire(player, ...)
end

-- Messages the server sent to `player` (optionally filtered by remote name).
function ServerEnv:Received(player, name: string?)
	local out = {}
	for _, message in self.Inbox[player] or {} do
		if not name or message.Name == name then
			table.insert(out, message)
		end
	end
	return out
end

return ServerEnv
