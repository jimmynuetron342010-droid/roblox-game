--[[
	EnemyService
	Spawns and runs PvE enemies with one 10 Hz AI loop (no per-enemy loops):
	  chase -> telegraphed wind-up -> attack -> recover, leashing back to their spawn.
	Enemies adapt their level to the player engaging them (within the zone's range) so encounters
	stay relevant at multiple progression levels. Rewards and quest/mastery events go to every
	player who contributed damage.

	Counterplay: every attack has a visible wind-up; the Pharaoh boss reacts to Golem slam
	telegraphs by sidestepping out of the radius.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage.Modules
local EnemyConfig = require(Modules.Config.EnemyConfig)
local ProjectileController = require(Modules.ProjectileController)
local StatCalculator = require(Modules.Core.StatCalculator)

local Server = script.Parent.Parent
local EnemyRig = require(Server.World.EnemyRig)
local FXBroadcast = require(Server.Core.FXBroadcast)
local GameEvents = require(Server.Core.GameEvents)

local EnemyService = {}

local CombatService, StatService, StatusService, ProgressionService, MadnessService, PartnerService, DataService

local enemies = {} :: { any }
local folder: Folder

local Enemy = {}
Enemy.__index = Enemy

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

function Enemy:SetLevel(level: number)
	local def = self.Def
	local scaled = EnemyConfig.Scale(def, level)
	local ratio = self.Humanoid.MaxHealth > 0 and self.Humanoid.Health / self.Humanoid.MaxHealth or 1
	self.Level = level
	self.Damage = scaled.Damage
	self.Humanoid.MaxHealth = scaled.MaxHealth
	self.Humanoid.Health = math.max(1, scaled.MaxHealth * ratio)
	local values = {
		Defense = scaled.Defense,
		KnockbackResistance = def.IsBoss and 0.8 or 0.1,
		InterruptResistance = def.IsBoss and 0.6 or 0,
		StatusResistance = def.IsBoss and 0.5 or 0,
		RangedDamageReduction = 0,
		PoisonResistance = 0,
		StatusEffectiveness = 0,
	}
	self.Stats = {
		Level = level,
		Values = values,
		DamageReduction = StatCalculator.DamageReductionFromDefense(values.Defense, level),
	}
	self.Model:SetAttribute("Level", level)
end

function Enemy:OnDamaged(attacker, amount: number)
	self.LastDamaged = os.clock()
	if attacker and attacker.Player then
		self.Contributors[attacker.Player] = (self.Contributors[attacker.Player] or 0) + amount
		if not self.Target or not self.Target.Parent then
			self:Engage(attacker.Player)
		end
	end
	self.Model:SetAttribute("Health", self.Humanoid.Health)
end

function Enemy:Engage(player: Player)
	self.Target = player.Character
	if not self.Engaged then
		self.Engaged = true
		local zone = self.Zone
		local playerLevel = player:GetAttribute("Level") or 1
		self:SetLevel(math.clamp(playerLevel, zone.MinLevel, zone.MaxLevel))
	end
end

local function nearestPlayer(position: Vector3, range: number): (Model?, number)
	local best, bestDistance = nil, range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = character, distance
			end
		end
	end
	return best, bestDistance
end

function Enemy:Combatant()
	return CombatService:GetCombatant(self.Model)
end

-- Melee / ranged / boss attack with a wind-up the players can read.
function Enemy:StartAttack(targetModel: Model)
	local def = self.Def
	local windUp = def.WindUp * (self.Enraged and 0.8 or 1)
	self.Busy = true
	self.NextAttack = os.clock() + def.AttackCooldown * (self.Enraged and 0.8 or 1) + windUp
	local pattern = "Strike"
	if def.IsBoss then
		self.PatternIndex = (self.PatternIndex or 0) % 3 + 1
		pattern = ({ "Slam", "Sweep", "Binding" })[self.PatternIndex]
	elseif def.Ranged then
		pattern = "Bolt"
	end
	self.Model:SetAttribute("Attack", pattern)
	self.Model:SetAttribute("AttackStart", serverNow())
	self.Model:SetAttribute("AttackWindUp", windUp)
	local root = self.Root
	if pattern == "Slam" then
		FXBroadcast.Broadcast({
			Type = "Ability",
			Kind = "Telegraph",
			Position = root.Position,
			Radius = 12,
			Duration = windUp,
			Color = Color3.fromRGB(255, 60, 60),
		}, root.Position)
	elseif pattern == "Sweep" then
		FXBroadcast.Broadcast({
			Type = "Ability",
			Kind = "Telegraph",
			Position = root.Position + root.CFrame.LookVector * 5,
			Radius = 8,
			Duration = windUp,
			Color = Color3.fromRGB(255, 120, 60),
		}, root.Position)
	end
	task.delay(windUp, function()
		self.Busy = false
		local attacker = self:Combatant()
		if not attacker or StatusService:Has(self.Model, "Stagger") then
			return
		end
		local damage = self.Damage
		if pattern == "Strike" then
			local target = CombatService:GetCombatant(targetModel)
			if target and (target.Root.Position - root.Position).Magnitude <= def.AttackRange + 3 then
				CombatService:ApplyDamage(attacker, target, {
					Base = damage,
					Tags = { Melee = true },
					Stagger = 0.25,
					Knockback = 10,
					Direction = target.Root.Position - root.Position,
				})
			end
		elseif pattern == "Bolt" then
			local target = CombatService:GetCombatant(targetModel)
			if target then
				local origin = root.Position + Vector3.new(0, 1.5, 0)
				local dir = (target.Root.Position - origin).Unit
				ProjectileController.Simulate({
					Origin = origin,
					Direction = dir,
					Speed = 55,
					Range = def.AttackRange + 10,
					Radius = 0.8,
					Ignore = { self.Model },
					OnHit = function(result)
						local hit = CombatService:GetCombatant(result.Instance:FindFirstAncestorOfClass("Model"))
						if hit and hit.Player then
							CombatService:ApplyDamage(
								attacker,
								hit,
								{ Base = damage, Tags = { Magic = true }, Ranged = true, Stagger = 0.15 }
							)
						end
						return false
					end,
				})
				FXBroadcast.Broadcast({
					Type = "Ability",
					Kind = "Projectile",
					Origin = origin,
					Direction = dir,
					Speed = 55,
					Range = def.AttackRange + 10,
					Color = Color3.fromRGB(200, 80, 255),
				}, origin)
			end
		elseif pattern == "Slam" then
			for _, target in CombatService:QueryCircle(attacker, root.Position, 12) do
				CombatService:ApplyDamage(attacker, target, {
					Base = damage * 1.6,
					Tags = { Melee = true, Charged = true },
					Stagger = 0.5,
					Knockback = 40,
					Direction = target.Root.Position - root.Position,
				})
			end
			FXBroadcast.Broadcast(
				{ Type = "Ability", Kind = "Slam", Position = root.Position, Radius = 12 },
				root.Position
			)
		elseif pattern == "Sweep" then
			for _, target in CombatService:QueryArc(attacker, root.CFrame.LookVector, 11, 200, 8) do
				CombatService:ApplyDamage(attacker, target, {
					Base = damage,
					Tags = { Melee = true },
					Stagger = 0.35,
					Knockback = 24,
					Direction = root.CFrame.LookVector,
				})
			end
		elseif pattern == "Binding" then
			local target = CombatService:GetCombatant(targetModel)
			if target then
				local origin = root.Position + Vector3.new(0, 2, 0)
				local dir = (target.Root.Position - origin).Unit
				ProjectileController.Simulate({
					Origin = origin,
					Direction = dir,
					Speed = 70,
					Range = 60,
					Radius = 1,
					Ignore = { self.Model },
					OnHit = function(result)
						local hit = CombatService:GetCombatant(result.Instance:FindFirstAncestorOfClass("Model"))
						if hit and hit.Player then
							CombatService:ApplyDamage(attacker, hit, {
								Base = damage * 0.6,
								Tags = { Magic = true },
								Ranged = true,
								Status = { Name = "Root", Duration = 1.0, Source = "PharaohBinding" },
							})
						end
						return false
					end,
				})
				FXBroadcast.Broadcast(
					{ Type = "Ability", Kind = "Wrap", Origin = origin, Direction = dir, Speed = 70, Range = 60 },
					origin
				)
			end
		end
	end)
end

-- Boss reaction to a player's telegraphed area attack (e.g. Colossus Slam).
function Enemy:ReactToTelegraph(position: Vector3, radius: number, windUp: number)
	if not self.Def.IsBoss or self.Dead then
		return
	end
	local offset = self.Root.Position - position
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if distance > radius + 2 or math.random() > 0.7 then
		return
	end
	local away = distance > 0.5 and Vector3.new(offset.X, 0, offset.Z).Unit or self.Root.CFrame.RightVector
	local destination = position + away * (radius + 6)
	task.delay(math.min(windUp * 0.35, 0.4), function()
		if self.Dead then
			return
		end
		self.Humanoid.WalkSpeed = 42
		self.Humanoid:MoveTo(destination)
		self.SidestepUntil = os.clock() + 0.6
		FXBroadcast.Broadcast(
			{ Type = "Dash", Character = self.Model, Origin = self.Root.Position, Direction = away },
			self.Root.Position
		)
	end)
end

function EnemyService:OnTelegraph(position: Vector3, radius: number, windUp: number)
	for _, enemy in enemies do
		enemy:ReactToTelegraph(position, radius, windUp)
	end
end

function EnemyService:OnKilled(enemy, attacker, info)
	if enemy.Dead then
		return
	end
	enemy.Dead = true
	local def = enemy.Def
	if def.Id == "TrainingDummy" then
		enemy.Humanoid.Health = enemy.Humanoid.MaxHealth
		enemy.Dead = false
		return
	end
	local position = enemy.Root.Position
	local killer = attacker and attacker.Player
	FXBroadcast.Broadcast({
		Type = "EnemyDeath",
		Character = enemy.Model,
		Position = position,
		Killer = killer and killer.UserId or 0,
		Boss = def.IsBoss,
	}, position)
	local levelScale = 1 + (enemy.Level - 1) * 0.08
	for player, damage in enemy.Contributors do
		if player.Parent and damage > 0 then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - position).Magnitude <= 120 then
				ProgressionService:AddExp(player, def.Exp * levelScale, "Kill")
				ProgressionService:AddSouls(player, def.Souls)
				local profile = DataService:GetProfile(player)
				if profile then
					profile.Stats.Kills += 1
					if def.IsBoss then
						profile.Stats.BossKills += 1
					end
				end
				local buff = StatService:HasBuff(player, "BeastShift") and "BeastShift" or nil
				local payload = {
					EnemyType = def.Id,
					KishinEgg = def.Tags.KishinEgg == true,
					IsBoss = def.IsBoss,
					Magic = player == killer and info and info.Tags and info.Tags.Magic == true or false,
					Buff = buff,
					Empowered = PartnerService:GetSync(player) ~= nil or StatService:HasBuff(player, "ResonanceSurge"),
					MadnessHigh = MadnessService:Get(player) > 50,
				}
				GameEvents.Fire(player, "EnemyKilled", payload)
				if def.IsBoss then
					GameEvents.Fire(player, "BossKilled", payload)
				end
			end
		end
	end
	task.delay(1.4, function()
		enemy.Model:Destroy()
	end)
	local spawn = enemy.Spawn
	local index = table.find(enemies, enemy)
	if index then
		table.remove(enemies, index)
	end
	task.delay(EnemyConfig.Respawn * (def.IsBoss and 5 or 1), function()
		EnemyService:Spawn(def.Id, spawn, enemy.Zone)
	end)
end

function EnemyService:Spawn(enemyId: string, spawnCFrame: CFrame, zone)
	local def = EnemyConfig.ById[enemyId]
	if not def then
		return nil
	end
	local model, root, humanoid = EnemyRig.Build(def, spawnCFrame)
	model.Parent = folder
	if not root.Anchored then
		root:SetNetworkOwner(nil)
	end
	humanoid.WalkSpeed = def.MoveSpeed
	local enemy = setmetatable({
		Def = def,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Spawn = spawnCFrame,
		Zone = zone or { MinLevel = 1, MaxLevel = 50 },
		Contributors = {},
		NextAttack = 0,
		Busy = false,
		Dead = false,
		Engaged = false,
		Revealed = {},
		LastDamaged = 0,
	}, Enemy)
	enemy:SetLevel(enemy.Zone.MinLevel)
	CombatService:RegisterEnemy(model, enemy)
	table.insert(enemies, enemy)
	humanoid.Died:Connect(function()
		if not enemy.Dead then
			EnemyService:OnKilled(enemy, nil, nil)
		end
	end)
	return enemy
end

local function think(enemy, dt: number)
	local def = enemy.Def
	if enemy.Dead or def.Id == "TrainingDummy" then
		if
			def.Id == "TrainingDummy"
			and os.clock() - enemy.LastDamaged > 4
			and enemy.Humanoid.Health < enemy.Humanoid.MaxHealth
		then
			enemy.Humanoid.Health = enemy.Humanoid.MaxHealth
		end
		return
	end
	local root, humanoid = enemy.Root, enemy.Humanoid
	local fromSpawn = (root.Position - enemy.Spawn.Position).Magnitude

	if def.MadnessAura then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local proot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if proot and (proot.Position - root.Position).Magnitude <= def.MadnessAura.Radius then
				MadnessService:Add(player, def.MadnessAura.PerSecond * dt, def.MadnessAura.Type)
			end
		end
	end

	if def.IsBoss and not enemy.Enraged and humanoid.Health < humanoid.MaxHealth * 0.5 then
		enemy.Enraged = true
		enemy.Model:SetAttribute("Enraged", true)
	end

	local moveMultiplier = StatusService:MoveMultiplier(enemy.Model)
	if StatusService:Has(enemy.Model, "Stagger") then
		moveMultiplier = 0
	end
	if not (enemy.SidestepUntil and os.clock() < enemy.SidestepUntil) then
		humanoid.WalkSpeed = def.MoveSpeed * moveMultiplier * (enemy.Enraged and 1.2 or 1)
	end

	-- Leash: return home and reset if dragged too far.
	if fromSpawn > EnemyConfig.LeashRange then
		enemy.Target = nil
		enemy.Engaged = false
		enemy.Contributors = {}
		humanoid:MoveTo(enemy.Spawn.Position)
		humanoid.Health = humanoid.MaxHealth
		return
	end

	local target = enemy.Target
	local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
	if not target or not target.Parent or not targetHumanoid or targetHumanoid.Health <= 0 then
		local found = nearestPlayer(root.Position, def.AggroRange)
		enemy.Target = found
		target = found
		if found then
			local player = Players:GetPlayerFromCharacter(found)
			if player then
				enemy:Engage(player)
			end
		end
	end
	if not target then
		if fromSpawn > 4 then
			humanoid:MoveTo(enemy.Spawn.Position)
		end
		return
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return
	end
	local distance = (targetRoot.Position - root.Position).Magnitude
	if enemy.Busy then
		root.CFrame =
			CFrame.lookAt(root.Position, Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z))
		humanoid:MoveTo(root.Position)
		return
	end
	if distance <= def.AttackRange then
		humanoid:MoveTo(root.Position)
		if os.clock() >= enemy.NextAttack and moveMultiplier > 0 then
			enemy:StartAttack(target)
		end
	else
		humanoid:MoveTo(targetRoot.Position)
	end
end

function EnemyService:GetEnemies()
	return enemies
end

function EnemyService:Init(registry)
	CombatService = registry.CombatService
	StatService = registry.StatService
	StatusService = registry.StatusService
	ProgressionService = registry.ProgressionService
	MadnessService = registry.MadnessService
	PartnerService = registry.PartnerService
	DataService = registry.DataService
end

function EnemyService:Start()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace

	-- Spawn points come from MapService (parts in workspace.Map.EnemySpawns).
	local deadline = os.clock() + 20
	while not workspace:GetAttribute("MapReady") and os.clock() < deadline do
		task.wait(0.2)
	end
	local map = workspace:FindFirstChild("Map")
	local spawns = map and map:FindFirstChild("EnemySpawns")
	if spawns then
		for _, marker in spawns:GetChildren() do
			if marker:IsA("BasePart") then
				EnemyService:Spawn(marker:GetAttribute("EnemyType"), marker.CFrame, {
					MinLevel = marker:GetAttribute("MinLevel") or 1,
					MaxLevel = marker:GetAttribute("MaxLevel") or 50,
				})
			end
		end
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		for _, enemy in table.clone(enemies) do
			local ok, err = pcall(think, enemy, step)
			if not ok then
				warn("[EnemyService] AI error: " .. tostring(err))
			end
		end
	end)

	-- Divine Soul Perception: Shinigami reveal shrouded souls (mastery objective).
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("PerceptionActive") and player:GetAttribute("Race") == "Shinigami" then
					local character = player.Character
					local proot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local range = player:GetAttribute("SoulPerception") or 60
					if proot then
						for _, enemy in enemies do
							if
								enemy.Def.Hidden
								and not enemy.Revealed[player]
								and (enemy.Root.Position - proot.Position).Magnitude <= range
							then
								enemy.Revealed[player] = true
								GameEvents.Fire(player, "HiddenRevealed", { EnemyType = enemy.Def.Id })
							end
						end
					end
				end
			end
		end
	end)
end

return EnemyService
