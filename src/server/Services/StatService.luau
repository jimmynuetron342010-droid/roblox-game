--[[
	StatService
	The ONLY place that turns modifiers into character stats. Gameplay code never edits Humanoid
	health/speed or resource pools directly; it adds buffs or modifier providers here.

	Modifier sources, in order:
	  1. BuildModifiers.FromProfile — race, race mastery, role, weapon mastery (permanent)
	  2. Providers registered by other services — synchronization, madness, black blood (dynamic)
	  3. Buffs — timed effects from abilities (Multiplicative modifiers + damage multipliers)
	All of them go through StatCalculator (additive vs multiplicative, soft/hard caps).

	Also owns server-authoritative resources (Stamina, Soul Energy), regeneration, combat tagging,
	sprinting and dash validation. Values are mirrored to Player attributes for the HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage.Modules
local BuildModifiers = require(Modules.Core.BuildModifiers)
local GameConfig = require(Modules.Config.GameConfig)
local Net = require(Modules.Core.Net)
local Signal = require(Modules.Core.Signal)
local StatCalculator = require(Modules.Core.StatCalculator)
local StatDefinitions = require(Modules.Config.StatDefinitions)
local Validate = require(Modules.Core.Validate)

local Server = script.Parent.Parent
local RemoteGuard = require(Server.Core.RemoteGuard)

local StatService = {}

StatService.StatsChanged = Signal.new() -- (player, computed)

type Buff = {
	Id: string,
	Expires: number,
	Modifiers: { any },
	DamageBuff: number?,
	DamageBuffTags: { [string]: boolean }?,
	Data: { [string]: any }?,
}

type PlayerState = {
	Computed: any,
	Buffs: { [string]: Buff },
	Stamina: number,
	SoulEnergy: number,
	LastCombat: number,
	Sprinting: boolean,
	LastDash: number,
	LastStaminaUse: number,
}

local states: { [Player]: PlayerState } = {}
local providers: { [string]: (Player, any) -> { any } } = {}
local DataService
local StatusService
local statsChangedRemote: RemoteEvent
local fxBroadcast

local function newState(): PlayerState
	return {
		Computed = StatCalculator.Compute(1, {}),
		Buffs = {},
		Stamina = GameConfig.Combat.BaseStamina,
		SoulEnergy = 100,
		LastCombat = -math.huge,
		Sprinting = false,
		LastDash = -math.huge,
		LastStaminaUse = -math.huge,
	}
end

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = newState()
		states[player] = state
	end
	return state
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

-- Compact breakdown for the Stats panel (sources + cap state per stat).
local function clientBreakdown(computed)
	local out = { Values = computed.Values, DamageReduction = computed.DamageReduction, Lines = {} }
	for id, b in computed.Breakdown do
		local sources = {}
		for _, entry in b.Additive do
			table.insert(sources, { entry.Source, entry.Value, "Add" })
		end
		for _, entry in b.Multiplicative do
			table.insert(sources, { entry.Source, entry.Value, "Mul" })
		end
		out.Lines[id] = { Cap = b.CapState, Sources = sources, Raw = b.RawBonus }
	end
	return out
end

function StatService:RegisterProvider(name: string, provider: (Player, any) -> { any })
	providers[name] = provider
end

function StatService:Recompute(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	local state = getState(player)
	local mods = BuildModifiers.FromProfile(profile)
	for name, provider in providers do
		local ok, extra = pcall(provider, player, profile)
		if ok and type(extra) == "table" then
			for _, modifier in extra do
				table.insert(mods, modifier)
			end
		elseif not ok then
			warn(string.format("[StatService] provider %s failed: %s", name, tostring(extra)))
		end
	end
	local t = os.clock()
	for _, buff in state.Buffs do
		if buff.Expires > t then
			for _, modifier in buff.Modifiers do
				table.insert(mods, {
					Stat = modifier.Stat,
					Kind = modifier.Kind or "Multiplicative",
					Value = modifier.Value,
					Source = "Buff:" .. buff.Id,
				})
			end
		end
	end

	local computed = StatCalculator.Compute(profile.Level, mods)
	state.Computed = computed
	state.Stamina = math.min(state.Stamina, computed.Values.StaminaMax)
	state.SoulEnergy = math.min(state.SoulEnergy, computed.Values.SoulEnergyMax)

	self:ApplyToCharacter(player)
	player:SetAttribute("StaminaMax", computed.Values.StaminaMax)
	player:SetAttribute("SoulEnergyMax", computed.Values.SoulEnergyMax)
	player:SetAttribute("SoulPerception", computed.Values.SoulPerception)
	player:SetAttribute("DodgeDistance", computed.Values.DodgeDistance)
	player:SetAttribute("AttackSpeed", computed.Values.AttackSpeed)
	statsChangedRemote:FireClient(player, clientBreakdown(computed))
	StatService.StatsChanged:Fire(player, computed)
end

function StatService:ApplyToCharacter(player: Player)
	local humanoid = getHumanoid(player)
	local state = states[player]
	if not humanoid or not state then
		return
	end
	local newMax = math.max(1, math.floor(state.Computed.Values.MaxHealth + 0.5))
	if humanoid.MaxHealth ~= newMax then
		local ratio = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
		humanoid.MaxHealth = newMax
		if humanoid.Health > 0 then
			humanoid.Health = math.clamp(newMax * ratio, 1, newMax)
		end
	end
	self:UpdateWalkSpeed(player)
end

function StatService:UpdateWalkSpeed(player: Player)
	local humanoid = getHumanoid(player)
	local state = states[player]
	if not humanoid or not state then
		return
	end
	local character = player.Character :: Model
	local base = state.Computed.Values.MoveSpeed
	local speed = base
	if state.Sprinting and state.Stamina > 0 then
		speed = math.min(base * GameConfig.Combat.SprintMultiplier, StatDefinitions.MaxSprintSpeed)
	end
	local statusMultiplier = StatusService:MoveMultiplier(character)
	local lock = character:GetAttribute("MovementLock")
	if lock and lock > workspace:GetServerTimeNow() then
		statusMultiplier = 0
	end
	humanoid.WalkSpeed = speed * statusMultiplier
	humanoid.JumpHeight = statusMultiplier == 0 and 0 or 7.2
end

function StatService:Get(player: Player)
	return getState(player).Computed
end

function StatService:GetValues(player: Player): { [string]: number }
	return getState(player).Computed.Values
end

-- Timed buff. Re-applying refreshes it (buffs of the same id never stack).
function StatService:AddBuff(
	player: Player,
	id: string,
	duration: number,
	modifiers: { any }?,
	damageBuff: number?,
	damageBuffTags: { [string]: boolean }?,
	data: { [string]: any }?
)
	local state = getState(player)
	state.Buffs[id] = {
		Id = id,
		Expires = os.clock() + duration,
		Modifiers = modifiers or {},
		DamageBuff = damageBuff,
		DamageBuffTags = damageBuffTags,
		Data = data,
	}
	player:SetAttribute("Buff_" .. id, workspace:GetServerTimeNow() + duration)
	self:Recompute(player)
end

function StatService:RemoveBuff(player: Player, id: string)
	local state = states[player]
	if state and state.Buffs[id] then
		state.Buffs[id] = nil
		player:SetAttribute("Buff_" .. id, nil)
		self:Recompute(player)
	end
end

function StatService:HasBuff(player: Player, id: string): boolean
	local state = states[player]
	local buff = state and state.Buffs[id]
	return buff ~= nil and buff.Expires > os.clock()
end

function StatService:GetBuffData(player: Player, id: string)
	local state = states[player]
	local buff = state and state.Buffs[id]
	return buff and buff.Expires > os.clock() and buff.Data or nil
end

-- Multiplicative damage buffs that apply to a hit with these tags.
function StatService:DamageBuffs(player: Player, tags: { [string]: boolean }): { number }
	local out = {}
	local state = states[player]
	if not state then
		return out
	end
	local t = os.clock()
	for _, buff in state.Buffs do
		if buff.DamageBuff and buff.Expires > t then
			local applies = true
			if buff.DamageBuffTags then
				applies = false
				for tag in buff.DamageBuffTags do
					if tags[tag] then
						applies = true
						break
					end
				end
			end
			if applies then
				table.insert(out, buff.DamageBuff)
			end
		end
	end
	return out
end

-- ── Resources ─────────────────────────────────────────────────────────────────
function StatService:GetStamina(player: Player): number
	return getState(player).Stamina
end

function StatService:GetSoulEnergy(player: Player): number
	return getState(player).SoulEnergy
end

function StatService:SpendStamina(player: Player, amount: number): boolean
	local state = getState(player)
	if amount <= 0 then
		return true
	end
	if state.Stamina < amount then
		return false
	end
	state.Stamina -= amount
	state.LastStaminaUse = os.clock()
	player:SetAttribute("Stamina", state.Stamina)
	return true
end

function StatService:SpendSoulEnergy(player: Player, amount: number): boolean
	local state = getState(player)
	if amount <= 0 then
		return true
	end
	if state.SoulEnergy < amount then
		return false
	end
	state.SoulEnergy -= amount
	player:SetAttribute("SoulEnergy", state.SoulEnergy)
	return true
end

function StatService:RestoreStamina(player: Player, fraction: number)
	local state = getState(player)
	state.Stamina =
		math.min(state.Computed.Values.StaminaMax, state.Stamina + state.Computed.Values.StaminaMax * fraction)
	player:SetAttribute("Stamina", state.Stamina)
end

function StatService:AddSoulEnergy(player: Player, amount: number)
	local state = getState(player)
	state.SoulEnergy = math.clamp(state.SoulEnergy + amount, 0, state.Computed.Values.SoulEnergyMax)
	player:SetAttribute("SoulEnergy", state.SoulEnergy)
end

function StatService:TagCombat(player: Player)
	getState(player).LastCombat = os.clock()
	player:SetAttribute("InCombat", true)
end

function StatService:InCombat(player: Player): boolean
	return os.clock() - getState(player).LastCombat < GameConfig.Combat.CombatTagDuration
end

-- ── Movement ──────────────────────────────────────────────────────────────────
local function handleMovement(player: Player, action: any, value: any)
	local state = getState(player)
	local character = player.Character
	local humanoid = getHumanoid(player)
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	if action == "Sprint" then
		if not Validate.Boolean(value) then
			return
		end
		state.Sprinting = value and state.Stamina > 5
		StatService:UpdateWalkSpeed(player)
	elseif action == "Perception" then
		if not Validate.Boolean(value) then
			return
		end
		player:SetAttribute("PerceptionActive", value and state.SoulEnergy > 1 or nil)
	elseif action == "Dash" then
		local direction = Validate.Direction(value)
		if not direction then
			return
		end
		local t = os.clock()
		if t - state.LastDash < GameConfig.Combat.DashCooldown * 0.85 then
			return
		end
		if StatusService:MoveMultiplier(character) == 0 then
			return
		end
		if not StatService:SpendStamina(player, GameConfig.Combat.DashStaminaCost) then
			return
		end
		state.LastDash = t
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and fxBroadcast then
			fxBroadcast.Broadcast({
				Type = "Dash",
				Character = character,
				Origin = root.Position,
				Direction = Vector3.new(direction.X, 0, direction.Z),
			}, root.Position, player)
		end
	end
end

function StatService:Init(registry)
	DataService = registry.DataService
	StatusService = registry.StatusService
	statsChangedRemote = Net.Event("StatsChanged")
	fxBroadcast = require(Server.Core.FXBroadcast)
end

function StatService:Start()
	DataService.ProfileLoaded:Connect(function(player)
		getState(player)
		StatService:Recompute(player)
		local state = getState(player)
		state.Stamina = state.Computed.Values.StaminaMax
		state.SoulEnergy = state.Computed.Values.SoulEnergyMax
		player:SetAttribute("Stamina", state.Stamina)
		player:SetAttribute("SoulEnergy", state.SoulEnergy)
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	StatusService.Changed:Connect(function(model)
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			StatService:UpdateWalkSpeed(player)
		end
	end)

	RemoteGuard.OnEvent("MovementRequest", 12, 20, handleMovement)

	-- Regeneration / drain / buff expiry at 10 Hz.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		local t = os.clock()
		for player, state in states do
			local values = state.Computed.Values
			local humanoid = getHumanoid(player)

			-- Expire buffs.
			local expired = false
			for id, buff in state.Buffs do
				if buff.Expires <= t then
					state.Buffs[id] = nil
					player:SetAttribute("Buff_" .. id, nil)
					expired = true
				end
			end
			if expired then
				StatService:Recompute(player)
			end

			-- Stamina.
			local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.1
			if state.Sprinting and moving then
				state.Stamina = math.max(0, state.Stamina - GameConfig.Combat.SprintStaminaPerSecond * step)
				if state.Stamina <= 0 then
					state.Sprinting = false
					StatService:UpdateWalkSpeed(player)
				end
			elseif t - state.LastStaminaUse > 0.6 then
				state.Stamina = math.min(values.StaminaMax, state.Stamina + values.StaminaRegen * step)
			end
			player:SetAttribute("Stamina", state.Stamina)

			-- Soul Energy (Soul Perception drains it while active).
			if player:GetAttribute("PerceptionActive") then
				state.SoulEnergy -= GameConfig.SoulPerception.SoulEnergyDrainPerSecond * step
				if state.SoulEnergy <= 0 then
					state.SoulEnergy = 0
					player:SetAttribute("PerceptionActive", nil)
				end
			else
				state.SoulEnergy = math.min(values.SoulEnergyMax, state.SoulEnergy + values.SoulEnergyRegen * step)
			end
			player:SetAttribute("SoulEnergy", state.SoulEnergy)

			-- Health regeneration only outside active damage windows.
			local inCombat = t - state.LastCombat < GameConfig.Combat.CombatTagDuration
			player:SetAttribute("InCombat", inCombat)
			if humanoid and humanoid.Health > 0 and not inCombat and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health =
					math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * values.HealthRegen * step)
			end
		end
	end)
end

return StatService
