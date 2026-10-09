--[[
	Notifier
	Toast notifications to a single player (or everyone). Kinds: Info, Success, Warning, Reward, Rare.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Modules.Core.Net)

local Notifier = {}

local remote: RemoteEvent? = nil
local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.Event("Notify")
	end
	return remote :: RemoteEvent
end

function Notifier.Send(player: Player, text: string, kind: string?, extra: { [string]: any }?)
	local payload = { Text = text, Kind = kind or "Info" }
	for k, v in (extra or {}) :: { [string]: any } do
		payload[k] = v
	end
	getRemote():FireClient(player, payload)
end

function Notifier.All(text: string, kind: string?, extra: { [string]: any }?)
	for _, player in Players:GetPlayers() do
		Notifier.Send(player, text, kind, extra)
	end
end

return Notifier
