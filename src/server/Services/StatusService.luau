--[[
	StatusService
	Status effects for any combatant model (players and enemies):
	  Root, Slow, Stagger, Burn, Judged, Cursed, Invulnerable
	Durations are scaled by the applier's Status Effectiveness and the target's Status Resistance
	(StatCalculator.StatusDuration). Active statuses are mirrored to model attributes
	("Status_<Name>" = server expiry time) so clients can draw effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage.Modules
local StatCalculator = require(Modules.Core.StatCalculator)
local Signal = require(Modules.Core.Signal)

local StatusService = {}

StatusService.Changed = Signal.new() -- (model)
StatusService.Applied = Signal.new() -- (model, statusName, info)

-- Set by CombatService: function(model, damage, sourceInfo)
StatusService.DamageTick = nil :: ((Model, number, any) -> ())?

export type StatusInfo = {
	Duration: number,
	Magnitude: number?,
	Source: string?,
	Applier: Model?,
	ApplierStats: { [string]: number }?,
	TargetStats: { [string]: number }?,
	TickDamage: number?,
}

type Active = { Expires: number, Magnitude: number, Source: string?, Applier: Model?, TickDamage: number? }

local active: { [Model]: { [string]: Active } } = {}

local KNOWN = {
	Root = true,
	Slow = true,
	Stagger = true,
	Burn = true,
	Judged = true,
	Cursed = true,
	Invulnerable = true,
	Pull = true,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

function StatusService:Apply(model: Model, name: string, info: StatusInfo): number
	if not KNOWN[name] or not model or not model.Parent then
		return 0
	end
	local duration = info.Duration
	if name ~= "Invulnerable" then
		duration = StatCalculator.StatusDuration(info.Duration, info.ApplierStats, info.TargetStats)
	end
	if duration <= 0 then
		return 0
	end
	local statuses = active[model]
	if not statuses then
		statuses = {}
		active[model] = statuses
		model.Destroying:Connect(function()
			active[model] = nil
		end)
	end
	local expires = now() + duration
	local existing = statuses[name]
	if existing and existing.Expires > expires and (existing.Magnitude or 0) >= (info.Magnitude or 0) then
		return existing.Expires - now()
	end
	statuses[name] = {
		Expires = expires,
		Magnitude = info.Magnitude or 0,
		Source = info.Source,
		Applier = info.Applier,
		TickDamage = info.TickDamage,
	}
	model:SetAttribute("Status_" .. name, expires)
	StatusService.Applied:Fire(model, name, info)
	StatusService.Changed:Fire(model)
	return duration
end

function StatusService:Remove(model: Model, name: string)
	local statuses = active[model]
	if statuses and statuses[name] then
		statuses[name] = nil
		model:SetAttribute("Status_" .. name, nil)
		StatusService.Changed:Fire(model)
	end
end

function StatusService:Cleanse(model: Model, names: { string }?)
	local list = names or { "Root", "Slow", "Burn", "Judged", "Cursed" }
	for _, name in list do
		self:Remove(model, name)
	end
end

function StatusService:Has(model: Model, name: string): boolean
	local statuses = active[model]
	local status = statuses and statuses[name]
	return status ~= nil and status.Expires > now()
end

function StatusService:Magnitude(model: Model, name: string): number
	local statuses = active[model]
	local status = statuses and statuses[name]
	if status and status.Expires > now() then
		return status.Magnitude
	end
	return 0
end

-- Combined movement multiplier from Root/Slow (0 when rooted).
function StatusService:MoveMultiplier(model: Model): number
	if self:Has(model, "Root") then
		return 0
	end
	return 1 - math.clamp(self:Magnitude(model, "Slow"), 0, 0.8)
end

function StatusService:CanAct(model: Model): boolean
	return not self:Has(model, "Stagger")
end

-- Outgoing damage multiplier (Judged reduces damage dealt).
function StatusService:OutgoingMultiplier(model: Model): number
	return 1 - math.clamp(self:Magnitude(model, "Judged"), 0, 0.5)
end

-- Fractional Defense reduction (Cursed).
function StatusService:DefenseShred(model: Model): number
	return math.clamp(self:Magnitude(model, "Cursed"), 0, 0.5)
end

function StatusService:Init() end

function StatusService:Start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		local step = accumulator
		accumulator = 0
		local t = now()
		for model, statuses in active do
			local changed = false
			for name, status in statuses do
				if status.Expires <= t then
					statuses[name] = nil
					model:SetAttribute("Status_" .. name, nil)
					changed = true
				elseif name == "Burn" and status.TickDamage and StatusService.DamageTick then
					StatusService.DamageTick(model, status.TickDamage * step, status)
				end
			end
			if changed then
				StatusService.Changed:Fire(model)
			end
		end
	end)
end

return StatusService
