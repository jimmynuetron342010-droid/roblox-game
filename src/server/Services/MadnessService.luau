--[[
	MadnessService
	Separate systems that are deliberately NOT races:
	  * Madness wavelengths — Madness Wraith auras raise a 0-100 meter. High Madness increases
	    damage dealt *and* taken; it decays when you leave the wavelength.
	  * Black Blood — quest unlock. Below 40% health it hardens (+30% Defense for 5s, 30s cooldown)
	    at the cost of +10 Madness.
	  * Kishin Awakening — endgame transformation (AbilityService) fueled by Madness.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)
local FXBroadcast = require(Server.Core.FXBroadcast)

local MadnessService = {}

MadnessService.Max = 100
MadnessService.DecayPerSecond = 4
MadnessService.Thresholds = {
	{ At = 80, Outgoing = 1.12, Incoming = 1.15 },
	{ At = 50, Outgoing = 1.08, Incoming = 1.10 },
}
MadnessService.BlackBlood = { HealthFraction = 0.4, Duration = 5, Cooldown = 30, Defense = 0.3, Madness = 10 }

local DataService
local StatService

type State = { Value: number, LastAura: number, Peaked: boolean, LastHardening: number }
local states: { [Player]: State } = {}

local function state(player: Player): State
	local s = states[player]
	if not s then
		s = { Value = 0, LastAura = -math.huge, Peaked = false, LastHardening = -math.huge }
		states[player] = s
	end
	return s
end

function MadnessService:Get(player: Player): number
	return state(player).Value
end

function MadnessService:Set(player: Player, value: number)
	local s = state(player)
	s.Value = math.clamp(value, 0, MadnessService.Max)
	player:SetAttribute("Madness", math.floor(s.Value + 0.5))
end

function MadnessService:Add(player: Player, amount: number, source: string?)
	local s = state(player)
	if amount > 0 then
		s.LastAura = os.clock()
	end
	self:Set(player, s.Value + amount)
	if s.Value >= MadnessService.Max and not s.Peaked then
		s.Peaked = true
		Notifier.Send(player, "Your Madness peaked! Leave the wavelength to recover.", "Warning")
		GameEvents.Fire(player, "MadnessPeak", { Source = source })
	elseif s.Value < 60 then
		s.Peaked = false
	end
end

local function tier(player: Player)
	local value = state(player).Value
	for _, threshold in MadnessService.Thresholds do
		if value >= threshold.At then
			return threshold
		end
	end
	return nil
end

function MadnessService:OutgoingMultiplier(player: Player): number
	local t = tier(player)
	return t and t.Outgoing or 1
end

function MadnessService:IncomingMultiplier(player: Player): number
	local t = tier(player)
	return t and t.Incoming or 1
end

-- Called by CombatService after a player takes damage.
function MadnessService:OnDamaged(player: Player, healthFraction: number)
	local profile = DataService:GetProfile(player)
	if not profile or not profile.Unlocks.BlackBlood then
		return
	end
	local config = MadnessService.BlackBlood
	local s = state(player)
	if healthFraction <= config.HealthFraction and healthFraction > 0 and os.clock() - s.LastHardening >= config.Cooldown then
		s.LastHardening = os.clock()
		StatService:AddBuff(player, "BlackBlood", config.Duration, {
			{ Stat = "Defense", Kind = "Multiplicative", Value = config.Defense },
		})
		self:Add(player, config.Madness, "BlackBlood")
		GameEvents.Fire(player, "BlackBloodHardened", {})
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			FXBroadcast.Broadcast({ Type = "BlackBlood", Character = character }, root.Position)
		end
	end
end

function MadnessService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
end

function MadnessService:Start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		local step = accumulator
		accumulator = 0
		for player, s in states do
			if s.Value > 0 and os.clock() - s.LastAura > 1 then
				MadnessService:Set(player, s.Value - MadnessService.DecayPerSecond * step)
			end
		end
	end)
end

return MadnessService
