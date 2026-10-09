--[[
	PartnerService — Soul Resonance
	A Demon Weapon origin can pair with a Meister-role player (BuildRules.CanSynchronize). While
	both are alive and within range, they are *synchronized*: the strength of the bonus scales with
	their soul wavelength compatibility (StudentConfig.Compatibility, 0.5 .. 1.0).

	Bonuses (all routed through StatService/StatCalculator, so caps apply):
	  Demon Weapon: damage buff x(1 + 0.10 * compat), Soul Energy costs x(1 - 0.15 * compat),
	                Resonance meter fills 50% faster.
	  Meister:      +5% * compat weapon mastery gain; Wavelength Strike +20%.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local BuildRules = require(Modules.Config.BuildRules)
local StudentConfig = require(Modules.Config.StudentConfig)
local Validate = require(Modules.Core.Validate)

local Server = script.Parent.Parent
local Notifier = require(Server.Core.Notifier)
local RemoteGuard = require(Server.Core.RemoteGuard)

local PartnerService = {}

PartnerService.Range = 45

local DataService
local StatService

local partners: { [Player]: Player } = {}
local invites: { [Player]: { From: Player, At: number } } = {}
local synced: { [Player]: number } = {} -- player -> compatibility while synchronized

local function buildOf(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return nil
	end
	return profile.Race.Active, profile.Loadout.Role, profile.Student.Wavelength
end

local function compatible(a: Player, b: Player): (boolean, number)
	local raceA, roleA, waveA = buildOf(a)
	local raceB, roleB, waveB = buildOf(b)
	if not raceA or not raceB then
		return false, 0
	end
	if not BuildRules.CanSynchronize(raceA, roleA, raceB, roleB) then
		return false, 0
	end
	return true, StudentConfig.Compatibility(waveA, waveB)
end

local function unpair(player: Player, reason: string?)
	local other = partners[player]
	partners[player] = nil
	synced[player] = nil
	player:SetAttribute("PartnerId", nil)
	player:SetAttribute("SyncLevel", nil)
	if other then
		partners[other] = nil
		synced[other] = nil
		if other.Parent then
			other:SetAttribute("PartnerId", nil)
			other:SetAttribute("SyncLevel", nil)
			Notifier.Send(
				other,
				"Your resonance partner left" .. (reason and (" (" .. reason .. ")") or "") .. ".",
				"Info"
			)
			StatService:Recompute(other)
		end
	end
	if player.Parent then
		StatService:Recompute(player)
	end
end

local function action(player: Player, kind: any, targetUserId: any)
	if kind == "Leave" then
		unpair(player)
		return { Ok = true }
	end
	if not Validate.Integer(targetUserId, 1, 1e15) then
		return { Ok = false, Reason = "BadTarget" }
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return { Ok = false, Reason = "BadTarget" }
	end
	if kind == "Invite" then
		local ok, compat = compatible(player, target)
		if not ok then
			return { Ok = false, Reason = "Incompatible" }
		end
		invites[target] = { From = player, At = os.clock() }
		Notifier.Send(
			target,
			string.format(
				"%s wants to synchronize souls (compatibility %d%%). Open the Skills menu to accept.",
				player.DisplayName,
				math.floor(compat * 100)
			),
			"Info",
			{
				Invite = player.UserId,
			}
		)
		return { Ok = true, Compatibility = compat }
	elseif kind == "Accept" then
		local invite = invites[player]
		if not invite or invite.From ~= target or os.clock() - invite.At > 60 then
			return { Ok = false, Reason = "NoInvite" }
		end
		local ok, compat = compatible(player, target)
		if not ok then
			return { Ok = false, Reason = "Incompatible" }
		end
		invites[player] = nil
		unpair(player)
		unpair(target)
		partners[player] = target
		partners[target] = player
		player:SetAttribute("PartnerId", target.UserId)
		target:SetAttribute("PartnerId", player.UserId)
		Notifier.Send(player, "Soul Resonance established with " .. target.DisplayName .. ".", "Success")
		Notifier.Send(target, "Soul Resonance established with " .. player.DisplayName .. ".", "Success")
		return { Ok = true, Compatibility = compat }
	end
	return { Ok = false, Reason = "BadRequest" }
end

function PartnerService:GetSync(player: Player): number?
	return synced[player]
end

function PartnerService:GetPartner(player: Player): Player?
	return partners[player]
end

function PartnerService:IsSyncedWeapon(player: Player): boolean
	local raceId = buildOf(player)
	return synced[player] ~= nil and raceId == "DemonWeapon"
end

function PartnerService:DamageMultiplier(player: Player): number
	local compat = synced[player]
	if compat and self:IsSyncedWeapon(player) then
		return 1 + 0.10 * compat
	end
	return 1
end

function PartnerService:CostMultiplier(player: Player): number
	local compat = synced[player]
	if compat and self:IsSyncedWeapon(player) then
		return 1 - 0.15 * compat
	end
	return 1
end

function PartnerService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
end

function PartnerService:Start()
	RemoteGuard.OnInvoke("PartnerAction", 2, 4, action)
	Players.PlayerRemoving:Connect(function(player)
		unpair(player, "left the game")
		invites[player] = nil
	end)

	-- Meister side bonus as a stat provider (shows up in the Stats breakdown).
	StatService:RegisterProvider("Synchronization", function(player)
		local compat = synced[player]
		if compat and not PartnerService:IsSyncedWeapon(player) then
			return {
				{ Stat = "WeaponMasteryGain", Kind = "Additive", Value = 0.05 * compat, Source = "Synchronization" },
			}
		end
		return {}
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, partner in partners do
				local wasSynced = synced[player] ~= nil
				local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local b = partner.Character and partner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoidA = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				local humanoidB = partner.Character and partner.Character:FindFirstChildOfClass("Humanoid")
				local inRange = a
					and b
					and humanoidA
					and humanoidB
					and humanoidA.Health > 0
					and humanoidB.Health > 0
					and (a.Position - b.Position).Magnitude <= PartnerService.Range
				if inRange then
					local ok, compat = compatible(player, partner)
					if ok then
						synced[player] = compat
					else
						unpair(player, "builds no longer compatible")
					end
				else
					synced[player] = nil
				end
				local isSynced = synced[player] ~= nil
				player:SetAttribute("SyncLevel", synced[player])
				if wasSynced ~= isSynced then
					StatService:Recompute(player)
				end
			end
		end
	end)
end

return PartnerService
