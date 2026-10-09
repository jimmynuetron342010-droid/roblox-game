--[[
	UI test environment (Lune)
	Boots the *real* client (Main.client.luau, UIController, HUD and every screen) on top of:
	  * MockInstance — strict Instances validated against the Roblox API dump
	  * mock services (Players, TweenService, RunService, UserInputService, GuiService, ...)
	  * MockServer — answers remotes with the real server logic (RaceRollLogic, ProfileCore,
	    StatCalculator, LoadoutService.CleanSettings, CharacterService rules)
	Only modules that need the 3D engine are stubbed: VFXController, VFXClient,
	AnimationController and the UI Viewport (which builds 3D models into ViewportFrames).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = require("../harness/Loader")
local MockInstance = require("./MockInstance")

local Signal = MockInstance.Signal
local Vector2 = roblox.Vector2
local Enum = roblox.Enum

local Env = {}

export type Options = {
	Viewport: Vector2?,
	Inset: number?,
	Touch: boolean?,
	Gamepad: boolean?,
	ReducedMotion: boolean?,
}

local function service(className: string, name: string?)
	local instance = MockInstance.new(className, nil, true)
	instance.Name = name or className
	return instance
end

function Env.new(options: Options?)
	local opts = options or {}
	local viewport = opts.Viewport or Vector2.new(1920, 1080)
	local self = { Options = opts }

	-- ── Services ──────────────────────────────────────────────────────────────
	local players = service("Players")
	local localPlayer = MockInstance.new("Player", nil, true)
	localPlayer.Name = "TestStudent"
	MockInstance.SetInternal(localPlayer, "UserId", 1001)
	MockInstance.SetInternal(localPlayer, "DisplayName", "TestStudent")
	local playerGui = MockInstance.new("PlayerGui", localPlayer, true)
	playerGui.Name = "PlayerGui"
	MockInstance.SetInternal(players, "LocalPlayer", localPlayer)
	localPlayer.Parent = players
	local otherPlayers = {}
	MockInstance.Override(players, "GetPlayers", function()
		local list = { localPlayer }
		for _, other in otherPlayers do
			table.insert(list, other)
		end
		return list
	end)
	MockInstance.Override(players, "GetPlayerByUserId", function(_, userId)
		for _, p in { localPlayer, table.unpack(otherPlayers) } do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end)
	MockInstance.Override(localPlayer, "GetMouse", function()
		return { Hit = roblox.CFrame.new(), Target = nil, Icon = "" }
	end)
	self.Players = players
	self.Player = localPlayer
	self.PlayerGui = playerGui
	function self.AddPlayer(name: string, userId: number, attributes: { [string]: any })
		local other = MockInstance.new("Player", nil, true)
		other.Name = name
		MockInstance.SetInternal(other, "UserId", userId)
		MockInstance.SetInternal(other, "DisplayName", name)
		for key, value in attributes do
			other:SetAttribute(key, value)
		end
		other.Parent = players
		table.insert(otherPlayers, other)
		return other
	end

	local workspace = service("Workspace")
	local camera = MockInstance.new("Camera", workspace, true)
	camera.Name = "Camera"
	MockInstance.SetInternal(camera, "ViewportSize", viewport)
	local topInset = opts.Inset or 58
	MockInstance.SetInternal(workspace, "CurrentCamera", camera)
	local serverClock = 1000
	MockInstance.Override(workspace, "GetServerTimeNow", function()
		return serverClock + os.clock()
	end)
	MockInstance.Override(workspace, "Raycast", function()
		return nil
	end)
	self.Workspace = workspace

	local renderStepped, heartbeat, stepped =
		Signal.new("RenderStepped"), Signal.new("Heartbeat"), Signal.new("Stepped")
	local runService = {
		RenderStepped = renderStepped,
		Heartbeat = heartbeat,
		Stepped = stepped,
		PreRender = renderStepped,
		PostSimulation = heartbeat,
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
		BindToRenderStep = function() end,
		UnbindFromRenderStep = function() end,
	}
	-- Advances every frame-driven system (HUD refresh, turntables, cooldown sweeps).
	function self.Step(frames: number?, dt: number?)
		for _ = 1, frames or 1 do
			renderStepped:Fire(dt or 1 / 60)
			stepped:Fire(os.clock(), dt or 1 / 60)
			heartbeat:Fire(dt or 1 / 60)
			task.wait()
		end
	end

	local tweenService = {
		Create = function(_, instance, _info, goal)
			assert(MockInstance.Is(instance), "TweenService:Create expects an Instance")
			local completed = Signal.new("Tween.Completed")
			local tween = { Completed = completed, PlaybackState = "Begin" }
			function tween.Play()
				for key, value in goal do
					instance[key] = value -- validates property names and types like Roblox
				end
				completed:Fire(Enum.PlaybackState.Completed)
			end
			function tween.Cancel() end
			function tween.Pause() end
			function tween.Destroy() end
			return tween
		end,
	}

	local touch = opts.Touch == true
	local lastInput = touch and Enum.UserInputType.Touch
		or (opts.Gamepad and Enum.UserInputType.Gamepad1 or Enum.UserInputType.MouseMovement)
	local userInputService = {
		TouchEnabled = touch,
		KeyboardEnabled = not touch,
		MouseEnabled = not touch,
		GamepadEnabled = opts.Gamepad == true,
		InputBegan = Signal.new("InputBegan"),
		InputEnded = Signal.new("InputEnded"),
		InputChanged = Signal.new("InputChanged"),
		LastInputTypeChanged = Signal.new("LastInputTypeChanged"),
		WindowFocusReleased = Signal.new("WindowFocusReleased"),
		GetLastInputType = function()
			return lastInput
		end,
		GetMouseLocation = function()
			return Vector2.new(0, 0)
		end,
		IsKeyDown = function()
			return false
		end,
		MouseBehavior = Enum.MouseBehavior.Default,
	}
	self.UserInputService = userInputService

	local guiService = { SelectedObject = nil, MenuIsOpen = false, ReducedMotionEnabled = opts.ReducedMotion == true }
	function guiService.GetGuiInset()
		return Vector2.new(0, topInset), Vector2.new(0, 0)
	end
	self.GuiService = guiService

	local services = {
		Players = players,
		Workspace = workspace,
		RunService = runService,
		TweenService = tweenService,
		UserInputService = userInputService,
		GuiService = guiService,
		ContextActionService = {
			BindAction = function() end,
			BindActionAtPriority = function() end,
			UnbindAction = function() end,
			SetTitle = function() end,
		},
		ProximityPromptService = {
			PromptTriggered = Signal.new("PromptTriggered"),
			PromptShown = Signal.new("PromptShown"),
		},
		SoundService = {
			PlayLocalSound = function() end,
		},
		Lighting = service("Lighting"),
		Debris = { AddItem = function() end },
		StarterGui = { SetCoreGuiEnabled = function() end, SetCore = function() end },
		TextService = {},
	}
	self.Services = services
	self.ProximityPromptService = services.ProximityPromptService

	-- ── Loader with strict Instances ─────────────────────────────────────────
	local TweenInfo = {
		new = function(...)
			return { Args = table.pack(...) }
		end,
	}
	-- `task` wrapper: errors inside threads spawned by game code are recorded, not just printed.
	local function guard(fn, label)
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
		Services = services,
		IsServer = false,
		Globals = {
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(MockInstance.Errors, "[warn] " .. table.concat(parts, " "))
				print("[warn]", ...)
			end,
			Instance = MockInstance.InstanceGlobal,
			typeof = MockInstance.TypeOf,
			TweenInfo = TweenInfo,
			workspace = workspace,
			task = guardedTask,
		},
	})
	self.Loader = loader

	-- ── Simulated server + remotes ────────────────────────────────────────────
	local MockServer = require("./MockServer")
	local server = MockServer.new(loader, self)
	self.Server = server

	local remotes = {}
	local function remoteEvent(name: string)
		if not remotes[name] then
			local remote = { OnClientEvent = Signal.new("Remote:" .. name), Name = name }
			function remote.FireServer(_, ...)
				server:OnEvent(name, ...)
			end
			function remote.IsA(_, className)
				return className == "RemoteEvent"
			end
			remotes[name] = remote
		end
		return remotes[name]
	end
	local function remoteFunction(name: string)
		if not remotes[name] then
			local remote = { Name = name }
			function remote.InvokeServer(_, ...)
				task.wait() -- network round trip
				return server:Invoke(name, ...)
			end
			function remote.IsA(_, className)
				return className == "RemoteFunction"
			end
			remotes[name] = remote
		end
		return remotes[name]
	end
	function self.FireClient(name: string, ...)
		remoteEvent(name).OnClientEvent:Fire(...)
	end
	self.Stub = function(path: string, value)
		loader.Cache[loader.Find(path)] = { value = value }
	end
	self.Stub("ReplicatedStorage.Modules.Core.Net", { Event = remoteEvent, Function = remoteFunction })

	-- 3D-only modules.
	local vfxCalls = {}
	self.VFXCalls = vfxCalls
	self.Stub(
		"ReplicatedStorage.Modules.VFXController",
		setmetatable({}, {
			__index = function(_, key)
				return function(...)
					table.insert(vfxCalls, { key, ... })
				end
			end,
		})
	)
	-- Controllers that only drive 3D visuals: same public surface, no engine work.
	local function noopController(signals: { string })
		local stub = { Init = function() end, Start = function() end }
		for _, name in signals do
			stub[name] = Signal.new(name)
		end
		return setmetatable(stub, {
			__index = function()
				return function()
					return nil
				end
			end,
		})
	end
	self.Stub(
		"StarterPlayer.StarterPlayerScripts.Client.Controllers.VFXClient",
		noopController({ "Knockback", "Rejected", "AbilityFailed", "Notice" })
	)
	self.Stub("StarterPlayer.StarterPlayerScripts.Client.Controllers.AnimationController", noopController({}))

	-- Viewport: real ViewportFrames, but the 3D content is described instead of built.
	self.Stub("StarterPlayer.StarterPlayerScripts.Client.UI.Viewport", {
		Character = function(parent, options)
			local frame = MockInstance.new("ViewportFrame")
			frame.BackgroundTransparency = 1
			frame.Size = roblox.UDim2.fromScale(1, 1)
			frame:SetAttribute(
				"Preview",
				string.format("Character %s %s", options.RaceId or "", options.Framing or "Full")
			)
			frame:SetAttribute("PreviewRace", options.RaceId or "")
			frame:SetAttribute("PreviewSkin", (options.Student and options.Student.SkinTone) or 2)
			frame:SetAttribute("PreviewUniform", (options.Student and options.Student.Uniform) or 2)
			frame.Parent = parent
			return frame, nil
		end,
		Weapon = function(parent, weaponId, form)
			local frame = MockInstance.new("ViewportFrame")
			frame.BackgroundTransparency = 1
			frame.Size = roblox.UDim2.fromScale(1, 1)
			frame:SetAttribute("Preview", "Weapon " .. weaponId .. (form and (" " .. form) or ""))
			frame:SetAttribute("PreviewWeapon", weaponId .. (form and ("-" .. form) or ""))
			frame.Parent = parent
			return frame, nil
		end,
	})

	return setmetatable(self, { __index = Env })
end

-- Runs a LocalScript from the sourcemap (the client bootstrap).
function Env:RunScript(path: string)
	local node = self.Loader.Find(path)
	local env = self.Loader.Globals()
	env.script = node
	env.require = self.Loader.Require
	local chunk = luau.load(fs.readFile(node.FilePath), { debugName = node.FilePath, environment = env })
	return task.spawn(function()
		local ok, err = xpcall(chunk, debug.traceback)
		if not ok then
			table.insert(MockInstance.Errors, "[" .. path .. "] " .. tostring(err))
		end
	end)
end

-- ── Interaction helpers ───────────────────────────────────────────────────────
function Env:Gui()
	return self.PlayerGui:FindFirstChild("SoulEaterUI")
end

local function visibleChain(instance): boolean
	local node = instance
	while node and MockInstance.Is(node) do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("ScreenGui") then
			return node.Enabled
		end
		node = node.Parent
	end
	return true
end
Env.IsVisible = visibleChain

-- Finds a visible button whose text matches `pattern` (Lua pattern, plain if `plain`).
function Env:FindButton(pattern: string, plain: boolean?, root: any?)
	for _, descendant in (root or self:Gui()):GetDescendants() do
		if descendant:IsA("TextButton") and visibleChain(descendant) then
			if string.find(descendant.Text, pattern, 1, plain) then
				return descendant
			end
		end
	end
	return nil
end

function Env:FindText(pattern: string, plain: boolean?, root: any?)
	for _, descendant in (root or self:Gui()):GetDescendants() do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and visibleChain(descendant) then
			if string.find(descendant.Text, pattern, 1, plain) then
				return descendant
			end
		end
	end
	return nil
end

function Env:Click(button)
	assert(button, "Click: button not found")
	assert(visibleChain(button), "Click: button is not visible: " .. button:GetFullName())
	button.MouseButton1Down:Fire(0, 0)
	button.MouseButton1Up:Fire(0, 0)
	button.MouseButton1Click:Fire()
	button.Activated:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, 1)
	task.wait()
end

function Env:ClickText(pattern: string, plain: boolean?, root: any?)
	local button = self:FindButton(pattern, plain, root)
	if not button then
		error("ClickText: no visible button matching '" .. pattern .. "'", 2)
	end
	self:Click(button)
	return button
end

-- Simulates press-and-hold (mouse) for `seconds`.
function Env:Hold(button, seconds: number)
	button.MouseButton1Down:Fire(0, 0)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		self.Step(1)
	end
	button.MouseButton1Up:Fire(0, 0)
	task.wait()
end

function Env:Type(textBox, text: string)
	textBox.Text = text
	task.wait()
end

function Env:Wait(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		self.Step(1)
	end
end

-- Waits until predicate() is truthy (stepping frames), or errors after `timeout`.
function Env:WaitFor(description: string, predicate: () -> any, timeout: number?)
	local deadline = os.clock() + (timeout or 8)
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		self.Step(1)
	end
	error("Timed out waiting for: " .. description, 2)
end

return Env
