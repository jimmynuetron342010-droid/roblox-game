--[[
	DataService
	Owns every player's profile for the duration of their session.

	* Loads with a session lock (SessionStore) and retries; kicks with a friendly message if the
	  profile is still locked by another server, so items/currency can never be duplicated.
	* Autosaves every GameConfig.Data.AutosaveInterval seconds (also refreshes the lock heartbeat).
	* Saves + releases on leave and on server shutdown (BindToClose).
	* Replicates a trimmed snapshot of the profile to its owner (ProfileChanged), coalesced so bursts
	  of changes cost one network message.
	* Falls back to an in-memory MockDataStore inside Studio when API access is disabled.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage.Modules
local GameConfig = require(Modules.Config.GameConfig)
local Net = require(Modules.Core.Net)
local Signal = require(Modules.Core.Signal)

local Server = script.Parent.Parent
local MockDataStore = require(Server.Data.MockDataStore)
local ProfileCore = require(Server.Data.ProfileCore)
local SessionStore = require(Server.Data.SessionStore)
local RemoteGuard = require(Server.Core.RemoteGuard)

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player, profile)
DataService.ProfileReleasing = Signal.new() -- (player, profile)

type Session = {
	Data: any,
	Dirty: boolean,
	ReplicatePending: boolean,
	LastSave: number,
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local sessionStore
local usingMock = false
local profileChanged: RemoteEvent

local function keyFor(player: Player): string
	return GameConfig.Data.KeyPrefix .. tostring(player.UserId)
end

local function resolveStore()
	local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)
	if ok then
		-- Probe: Studio without API access throws on the first request.
		local probeOk, probeErr = pcall(function()
			return store:GetAsync("__probe")
		end)
		if probeOk then
			return SessionStore.new(store, jobId, GameConfig.Data.SessionLockStaleAfter)
		end
		warn("[DataService] DataStore unavailable: " .. tostring(probeErr))
	else
		warn("[DataService] GetDataStore failed: " .. tostring(store))
	end
	if RunService:IsStudio() and GameConfig.Debug.UseMockDataStoreWhenUnavailable then
		warn(
			"[DataService] Using in-memory MockDataStore (Studio). Enable 'Studio Access to API Services' to test real saves."
		)
		usingMock = true
		return SessionStore.new(MockDataStore.new(), jobId, GameConfig.Data.SessionLockStaleAfter)
	end
	error("[DataService] No DataStore available")
end

local function newProfile()
	local profile = ProfileCore.Template()
	profile.CreatedAt = os.time()
	return profile
end

local function applyStudioDebug(profile)
	if not (GameConfig.Debug.Enabled and RunService:IsStudio()) then
		return
	end
	-- Generous testing resources inside Studio only.
	profile.Currency.RaceRolls = math.max(profile.Currency.RaceRolls, GameConfig.Debug.StartingRolls)
	profile.Currency.Souls = math.max(profile.Currency.Souls, GameConfig.Debug.StartingSouls)
	profile.Level = math.max(profile.Level, GameConfig.Debug.StartingLevel)
end

local function loadPlayer(player: Player)
	if loading[player] or sessions[player] then
		return
	end
	loading[player] = true
	local key = keyFor(player)
	local status, data
	for attempt = 1, GameConfig.Data.LoadRetries do
		status, data = sessionStore:Load(key, newProfile)
		if status == "Ok" then
			break
		end
		warn(string.format("[DataService] load %s attempt %d: %s %s", player.Name, attempt, status, tostring(data)))
		if not player.Parent then
			break
		end
		task.wait(GameConfig.Data.RetryDelay * attempt)
	end
	loading[player] = nil

	if status ~= "Ok" then
		if player.Parent then
			if status == "Locked" then
				player:Kick("Your save is still in use on another server. Please rejoin in a minute.")
			else
				player:Kick("Could not load your save data. Please rejoin.")
			end
		end
		return
	end

	local profile = ProfileCore.Migrate(data)
	applyStudioDebug(profile)

	if not player.Parent then
		-- Left while loading: release the lock immediately.
		sessionStore:Save(key, profile, true)
		return
	end

	sessions[player] = {
		Data = profile,
		Dirty = false,
		ReplicatePending = false,
		LastSave = os.clock(),
	}
	player:SetAttribute("ProfileLoaded", true)
	DataService.ProfileLoaded:Fire(player, profile)
	DataService:Replicate(player)
end

local function savePlayer(player: Player, release: boolean)
	local session = sessions[player]
	if not session then
		return
	end
	local status, err = sessionStore:Save(keyFor(player), session.Data, release)
	if status == "Ok" then
		session.Dirty = false
		session.LastSave = os.clock()
	else
		warn(string.format("[DataService] save %s failed: %s %s", player.Name, status, tostring(err)))
	end
	return status
end

function DataService:Init()
	sessionStore = resolveStore()
	profileChanged = Net.Event("ProfileChanged")
end

function DataService:Start()
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			DataService.ProfileReleasing:Fire(player, session.Data)
			savePlayer(player, true)
			sessions[player] = nil
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		for player in sessions do
			remaining += 1
			task.spawn(function()
				local session = sessions[player]
				if session then
					DataService.ProfileReleasing:Fire(player, session.Data)
				end
				savePlayer(player, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Autosave + lock heartbeat.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player in sessions do
				task.spawn(savePlayer, player, false)
			end
		end
	end)

	RemoteGuard.OnInvoke("GetProfile", 2, 4, function(player)
		local session = sessions[player]
		if not session then
			return { Ok = false, Reason = "Loading" }
		end
		return { Ok = true, Profile = ProfileCore.ClientView(session.Data), ServerTime = workspace:GetServerTimeNow() }
	end)
end

function DataService:GetProfile(player: Player)
	local session = sessions[player]
	return session and session.Data or nil
end

function DataService:WaitForProfile(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and not sessions[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return self:GetProfile(player)
end

function DataService:IsUsingMock(): boolean
	return usingMock
end

-- Marks a profile changed: schedules a save (autosave) and a coalesced client update.
function DataService:MarkDirty(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.Dirty = true
	if not session.ReplicatePending then
		session.ReplicatePending = true
		task.delay(0.15, function()
			if sessions[player] == session then
				session.ReplicatePending = false
				DataService:Replicate(player)
			end
		end)
	end
end

function DataService:Replicate(player: Player)
	local session = sessions[player]
	if session and player.Parent then
		profileChanged:FireClient(player, ProfileCore.ClientView(session.Data))
	end
end

-- Immediate save, used after purchases such as race rolls to shrink the loss window.
function DataService:SaveNow(player: Player)
	task.spawn(savePlayer, player, false)
end

function DataService:GetAllSessions()
	return sessions
end

return DataService
