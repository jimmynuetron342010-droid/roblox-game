--[[
	RemoteGuard
	Wraps every client -> server remote with:
	  * per-player, per-remote token-bucket rate limiting
	  * error isolation (a failing handler never breaks the remote for other players)
	  * a consistent { Ok = false, Reason = ... } failure shape for RemoteFunctions
	Handlers still validate their own arguments with Shared.Core.Validate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Modules.Core.Net)

local RemoteGuard = {}

type Bucket = { Tokens: number, Updated: number }

local buckets: { [Player]: { [string]: Bucket } } = {}
local violations: { [Player]: number } = {}

local function allow(player: Player, key: string, perSecond: number, burst: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { Tokens = burst, Updated = now }
		playerBuckets[key] = bucket
	end
	bucket.Tokens = math.min(burst, bucket.Tokens + (now - bucket.Updated) * perSecond)
	bucket.Updated = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	violations[player] = (violations[player] or 0) + 1
	if violations[player] % 50 == 0 then
		warn(string.format("[RemoteGuard] %s exceeded rate limit on %s (%d drops)", player.Name, key, violations[player]))
	end
	return false
end

RemoteGuard.Allow = allow

-- RemoteEvent handler: handler(player, ...)
function RemoteGuard.OnEvent(name: string, perSecond: number, burst: number, handler: (Player, ...any) -> ())
	local remote = Net.Event(name)
	remote.OnServerEvent:Connect(function(player, ...)
		if not allow(player, name, perSecond, burst) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[RemoteGuard] %s handler error for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

-- RemoteFunction handler: handler(player, ...) -> result table
function RemoteGuard.OnInvoke(name: string, perSecond: number, burst: number, handler: (Player, ...any) -> any)
	local remote = Net.Function(name)
	remote.OnServerInvoke = function(player, ...)
		if not allow(player, name, perSecond, burst) then
			return { Ok = false, Reason = "RateLimited" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[RemoteGuard] %s invoke error for %s: %s", name, player.Name, tostring(result)))
			return { Ok = false, Reason = "ServerError" }
		end
		return result
	end
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	violations[player] = nil
end)

return RemoteGuard
