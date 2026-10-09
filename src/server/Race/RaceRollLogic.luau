--[[
	RaceRollLogic
	Pure, server-authoritative race rolling. The result is decided *here, before* any animation:
	the client only ever animates an outcome it has already been told.

	Safety layers (all enforced server-side):
	  1. Request ids are remembered in the profile -> retries/double clicks return the *same* result
	     and are never charged twice (survives reconnects because it is saved).
	  2. A pending keep/replace decision blocks further rolls until resolved.
	  3. A cooldown between accepted rolls (server clock).
	  4. Currency is validated and deducted in the same step as the roll.
	The caller (RaceService) additionally holds a per-player busy lock around this call.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local GameConfig = require(Modules.Config.GameConfig)
local RaceConfig = require(Modules.Config.RaceConfig)
local WeightedRoll = require(Modules.Core.WeightedRoll)
local Validate = require(Modules.Core.Validate)

local ProfileCore = require(script.Parent.Parent.Data.ProfileCore)

local RaceRollLogic = {}

RaceRollLogic.Payments = { Token = true, Souls = true }

export type RollContext = {
	Now: number, -- monotonic seconds (os.clock on the server)
	UnixTime: number, -- for history timestamps
	Rng: any, -- Random
	LastRollAt: number?,
}

local function currencySnapshot(profile)
	return { Souls = profile.Currency.Souls, RaceRolls = profile.Currency.RaceRolls }
end

function RaceRollLogic.Roll(profile, requestId: any, payment: any, ctx: RollContext)
	if not Validate.RequestId(requestId) then
		return { Ok = false, Reason = "BadRequest" }
	end

	-- 1. Idempotency: identical request id -> identical answer, no second charge.
	local previous = ProfileCore.GetRequestResult(profile, requestId)
	if previous then
		local replay = table.clone(previous)
		replay.Replayed = true
		return replay
	end

	if not profile.Student.Created then
		return { Ok = false, Reason = "NoStudent" }
	end

	-- 2. Unresolved choice blocks further rolls.
	if profile.Race.Pending.RaceId then
		return { Ok = false, Reason = "PendingChoice", Pending = table.clone(profile.Race.Pending) }
	end

	-- 3. Cooldown.
	if ctx.LastRollAt and ctx.Now - ctx.LastRollAt < GameConfig.RaceRoll.Cooldown then
		return { Ok = false, Reason = "Cooldown" }
	end

	-- 4. Currency.
	if not Validate.OneOf(payment, RaceRollLogic.Payments) then
		return { Ok = false, Reason = "BadPayment" }
	end
	local currency = profile.Currency
	if payment == "Token" then
		if currency.RaceRolls < GameConfig.RaceRoll.TokenCost then
			return { Ok = false, Reason = "InsufficientFunds", Currency = currencySnapshot(profile) }
		end
		currency.RaceRolls -= GameConfig.RaceRoll.TokenCost
	else
		if currency.Souls < GameConfig.RaceRoll.SoulsCost then
			return { Ok = false, Reason = "InsufficientFunds", Currency = currencySnapshot(profile) }
		end
		currency.Souls -= GameConfig.RaceRoll.SoulsCost
	end

	-- The roll itself.
	local entry = WeightedRoll.Pick(RaceConfig.RollTable, ctx.Rng)
	local race = RaceConfig.ById[entry.Id]
	local raceData = profile.Race
	local isNew = raceData.Discovered[race.Id] == nil
	if isNew then
		raceData.Discovered[race.Id] = ctx.UnixTime
	end
	raceData.TotalRolls += 1

	local active = raceData.Active
	local outcome
	local result = {
		Ok = true,
		RequestId = requestId,
		RaceId = race.Id,
		Rarity = race.Rarity,
		IsNew = isNew,
		Previous = active,
		Payment = payment,
	}

	if active == "" then
		-- First race: applied immediately, nothing to replace.
		raceData.Active = race.Id
		ProfileCore.EnsureRaceProgress(profile, race.Id)
		result.Applied = true
		result.NeedsConfirm = false
		outcome = "Applied"
	elseif active == race.Id then
		-- Same race again: nothing changes, mastery is kept; small consolation "Soul Echo".
		local progress = ProfileCore.EnsureRaceProgress(profile, race.Id)
		progress.XP += RaceRollLogic.SoulEchoXP
		result.Applied = false
		result.NeedsConfirm = false
		result.SameRace = true
		result.SoulEchoXP = RaceRollLogic.SoulEchoXP
		outcome = "SameRace"
	else
		raceData.Pending = { RaceId = race.Id, RequestId = requestId, At = ctx.UnixTime }
		result.Applied = false
		result.NeedsConfirm = true
		outcome = "Pending"
	end

	ProfileCore.PushHistory(profile, { RaceId = race.Id, At = ctx.UnixTime, Outcome = outcome })
	result.Currency = currencySnapshot(profile)
	ProfileCore.RememberRequest(profile, requestId, result)
	return result
end

RaceRollLogic.SoulEchoXP = 100

-- Accept or decline a pending roll. Mastery progress for *every* race is preserved either way.
function RaceRollLogic.Resolve(profile, requestId: any, accept: any)
	if not Validate.RequestId(requestId) or not Validate.Boolean(accept) then
		return { Ok = false, Reason = "BadRequest" }
	end
	local memoKey = "resolve:" .. requestId
	local previous = ProfileCore.GetRequestResult(profile, memoKey)
	if previous then
		local replay = table.clone(previous)
		replay.Replayed = true
		return replay
	end

	local pending = profile.Race.Pending
	if not pending.RaceId or pending.RequestId ~= requestId then
		return { Ok = false, Reason = "NoPending" }
	end

	local previousRace = profile.Race.Active
	local history = profile.Race.History
	if accept then
		profile.Race.Active = pending.RaceId
		ProfileCore.EnsureRaceProgress(profile, pending.RaceId)
	end
	-- Mark the matching history entry with the final decision.
	for i = #history, 1, -1 do
		local entry = history[i]
		if entry.RaceId == pending.RaceId and entry.Outcome == "Pending" then
			entry.Outcome = accept and "Accepted" or "Declined"
			break
		end
	end
	profile.Race.Pending = {}

	local result = {
		Ok = true,
		Accepted = accept,
		Active = profile.Race.Active,
		Previous = previousRace,
		RaceId = pending.RaceId,
	}
	ProfileCore.RememberRequest(profile, memoKey, result)
	return result
end

return RaceRollLogic
