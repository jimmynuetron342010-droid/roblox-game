--[[
	Loader (Lune)
	Loads the game's real ModuleScripts outside Roblox by building a virtual DataModel from the Rojo
	sourcemap. `require(script.Parent.X)` resolves exactly as it does in Studio. Roblox datatypes
	(Vector3, CFrame, Instance, Enum, ...) come from Lune's roblox library; services that need the
	engine (DataStores, Players, ...) are supplied as mocks by each test.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Polyfills = require("./Polyfills")

local Loader = {}

type Node = {
	Name: string,
	ClassName: string,
	FilePath: string?,
	Parent: any,
	Children: { any },
}

local nodeMeta = {}

local function makeNode(name: string, className: string, filePath: string?, parent: any)
	local node = setmetatable({
		__node = true,
		Name = name,
		ClassName = className,
		FilePath = filePath,
		Parent = parent,
		_children = {},
		_attributes = {},
	}, nodeMeta)
	return node
end

local methods = {}
function methods.FindFirstChild(self, name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	local child = methods.FindFirstChild(self, name)
	if not child then
		error(string.format("WaitForChild: %s has no child %s", self.Name, name))
	end
	return child
end
function methods.GetChildren(self)
	return table.clone(self._children)
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in n._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.IsA(self, className)
	if className == "Instance" then
		return true
	end
	if className == "LuaSourceContainer" then
		return self.ClassName == "ModuleScript" or self.ClassName == "Script" or self.ClassName == "LocalScript"
	end
	return self.ClassName == className
end
function methods.GetFullName(self)
	local parts = {}
	local n = self
	while n and rawget(n, "Parent") ~= nil do
		table.insert(parts, 1, rawget(n, "Name"))
		n = rawget(n, "Parent")
	end
	return table.concat(parts, ".")
end
function methods.GetAttribute(self, key)
	return self._attributes[key]
end
function methods.SetAttribute(self, key, value)
	self._attributes[key] = value
end

nodeMeta.__index = function(self, key)
	if key == "Parent" then
		return nil
	end
	local method = methods[key]
	if method then
		return method
	end
	local child = methods.FindFirstChild(self, key)
	if child then
		return child
	end
	error(string.format("%s is not a valid member of %s", tostring(key), rawget(self, "Name")), 2)
end
nodeMeta.__tostring = function(self)
	return rawget(self, "Name")
end

local function buildTree(entry, parent)
	local filePath = nil
	for _, path in entry.filePaths or {} do
		if string.match(path, "%.luau?$") then
			filePath = path
		end
	end
	local node = makeNode(entry.name, entry.className, filePath, parent)
	for _, childEntry in entry.children or {} do
		table.insert(node._children, buildTree(childEntry, node))
	end
	return node
end

export type LoaderOptions = {
	Services: { [string]: any }?,
	Globals: { [string]: any }?,
	IsServer: boolean?,
	IsStudio: boolean?,
}

function Loader.new(options: LoaderOptions?)
	local opts = options or {}
	local sourcemap = serde.decode("json", fs.readFile("sourcemap.json"))
	local root = buildTree(sourcemap, nil)

	local services = opts.Services or {}
	services.RunService = services.RunService or Polyfills.RunService(opts)
	services.HttpService = services.HttpService or Polyfills.HttpService()

	local self = {
		Root = root,
		Cache = {},
		Services = services,
	}

	local game = {}
	function game.GetService(_, name)
		local service = self.Services[name]
		if service then
			return service
		end
		local node = methods.FindFirstChild(root, name)
		if node then
			return node
		end
		error("Loader: no mock for service " .. name)
	end
	game.FindFirstChild = function(_, name)
		return methods.FindFirstChild(root, name)
	end
	self.Game = game

	local sharedGlobals = Polyfills.Globals(opts)
	for key, value in opts.Globals or {} do
		sharedGlobals[key] = value
	end
	sharedGlobals.game = game
	sharedGlobals.workspace = self.Services.Workspace or sharedGlobals.workspace
	-- Fresh copy of the globals every loaded chunk sees (used to run LocalScripts/Scripts).
	function self.Globals()
		return table.clone(sharedGlobals)
	end

	local function requireNode(node)
		if type(node) ~= "table" or not rawget(node, "__node") then
			error("Loader.require expects a virtual ModuleScript, got " .. typeof(node))
		end
		local cached = self.Cache[node]
		if cached then
			return cached.value
		end
		if node.ClassName ~= "ModuleScript" then
			error("not a ModuleScript: " .. methods.GetFullName(node))
		end
		local source = fs.readFile(node.FilePath)
		local env = table.clone(sharedGlobals)
		env.script = node
		env.require = requireNode
		local chunk = luau.load(source, { debugName = node.FilePath, environment = env })
		local value = chunk()
		self.Cache[node] = { value = value }
		return value
	end
	self.Require = requireNode

	-- Resolve a dotted path like "ReplicatedStorage.Modules.Core.Util".
	function self.Find(path: string)
		local node = root
		for part in string.gmatch(path, "[^%.]+") do
			node = methods.FindFirstChild(node, part)
			assert(node, "Loader.Find: missing " .. path)
		end
		return node
	end

	function self.RequirePath(path: string)
		return requireNode(self.Find(path))
	end

	return self
end

Loader.roblox = roblox
Loader.task = task

return Loader
