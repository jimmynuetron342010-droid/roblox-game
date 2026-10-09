--[[
	FXBroadcast
	Sends cosmetic combat events (CombatFX) only to players close enough to see them, so busy
	servers do not flood every client. Damage is never decided by these messages — they are
	purely visual. The instigator can be excluded when their client already predicted the effect.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Modules.Core.Net)

local FXBroadcast = {}

FXBroadcast.DefaultRadius = 260

local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.Event("CombatFX")
	end
	return remote :: RemoteEvent
end

function FXBroadcast.Broadcast(payload: { [string]: any }, origin: Vector3?, exclude: Player?, radius: number?)
	local r = radius or FXBroadcast.DefaultRadius
	local event = getRemote()
	payload.ServerTime = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		if player ~= exclude then
			local send = true
			if origin then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - origin).Magnitude > r then
					send = false
				end
			end
			if send then
				event:FireClient(player, payload)
			end
		end
	end
end

function FXBroadcast.To(player: Player, payload: { [string]: any })
	payload.ServerTime = workspace:GetServerTimeNow()
	getRemote():FireClient(player, payload)
end

return FXBroadcast
