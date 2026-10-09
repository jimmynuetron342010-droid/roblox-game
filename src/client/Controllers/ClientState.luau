--[[
	ClientState
	Client-side cache of the server's view of this player: profile snapshot (ProfileChanged),
	stat breakdown (StatsChanged), and player settings applied to the VFX system.
	The client never edits these values; it only displays them and asks the server for changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Modules.Core.Net)
local Signal = require(Modules.Core.Signal)
local VFXController = require(Modules.VFXController)

local ClientState = {}

ClientState.Profile = nil :: any
ClientState.Stats = nil :: any
ClientState.ProfileChanged = Signal.new()
ClientState.StatsChanged = Signal.new()
ClientState.Player = Players.LocalPlayer

local function applySettings(settings)
	if not settings then
		return
	end
	VFXController.SetQuality(settings.VFXQuality or "Auto")
	VFXController.SetReducedMotion(settings.ReducedMotion == true or ClientState.SystemReducedMotion())
	VFXController.SetCameraShake(settings.CameraShake ~= false)
end

-- Respects the OS / Roblox accessibility "reduced motion" preference when available.
function ClientState.SystemReducedMotion(): boolean
	local ok, value = pcall(function()
		return (game:GetService("GuiService") :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

function ClientState.ReducedMotion(): boolean
	local profile = ClientState.Profile
	return ClientState.SystemReducedMotion() or (profile and profile.Settings.ReducedMotion == true) or false
end

function ClientState:SetProfile(profile)
	ClientState.Profile = profile
	applySettings(profile and profile.Settings)
	ClientState.ProfileChanged:Fire(profile)
end

function ClientState:Init()
	Net.Event("ProfileChanged").OnClientEvent:Connect(function(profile)
		ClientState:SetProfile(profile)
	end)
	Net.Event("StatsChanged").OnClientEvent:Connect(function(stats)
		ClientState.Stats = stats
		ClientState.StatsChanged:Fire(stats)
	end)
end

function ClientState:Start()
	task.spawn(function()
		local getProfile = Net.Function("GetProfile")
		for _ = 1, 60 do
			local ok, result = pcall(function()
				return getProfile:InvokeServer()
			end)
			if ok and type(result) == "table" and result.Ok then
				ClientState:SetProfile(result.Profile)
				return
			end
			task.wait(0.5)
		end
	end)
end

-- Yields until the first profile arrives.
function ClientState:WaitForProfile()
	while not ClientState.Profile do
		task.wait(0.1)
	end
	return ClientState.Profile
end

return ClientState
