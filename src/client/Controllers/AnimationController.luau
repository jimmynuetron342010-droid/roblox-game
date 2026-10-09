--[[
	AnimationController
	Runs AnimatorCore (procedural idle / loose walk / run / attacks / IK hands / chains) for every
	armed character near the camera, plus light procedural motion for enemies.

	* Updates in RunService.Stepped, i.e. after Roblox's Animator has written its tracks, so
	  weapon stances override the default Animate script only while a weapon is drawn and blend
	  back smoothly when holstered.
	* Distance LOD: full rate within 70 studs, 20 Hz to 180 studs, frozen beyond.
	* Weapon trails are switched on exactly during each action's trail window.
	* If you upload real animations (WeaponConfig.AnimationIds), you can play them through the
	  Animator as usual; the procedural layer only drives a character while it has a drawn weapon.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AnimatorCore = require(Modules.Animation.AnimatorCore)
local VFXController = require(Modules.VFXController)

local AnimationController = {}

type Entry = {
	Character: Model,
	Animator: any,
	Humanoid: Humanoid,
	Root: BasePart,
	Weapon: Model?,
	Accumulator: number,
	Trails: { Trail },
	Connections: { RBXScriptConnection },
}

local entries: { [Model]: Entry } = {}
local enemyEntries: { [Model]: { Time: number, Motors: { [string]: Motor6D }, Seed: number } } = {}
local camera = workspace.CurrentCamera

local function collectTrails(weapon: Model?): { Trail }
	local trails = {}
	if weapon then
		for _, descendant in weapon:GetDescendants() do
			if descendant:IsA("Trail") and descendant.Name == "SlashTrail" then
				table.insert(trails, descendant)
			end
		end
	end
	return trails
end

local function refreshWeapon(entry: Entry)
	local weapon = entry.Character:FindFirstChild("EquippedWeapon")
	if weapon and not weapon:IsA("Model") then
		weapon = nil
	end
	if weapon == entry.Weapon then
		return
	end
	-- Turn off trails of the old weapon.
	for _, trail in entry.Trails do
		trail.Enabled = false
	end
	entry.Weapon = weapon :: Model?
	entry.Animator:SetWeapon(weapon, entry.Character:GetAttribute("HoldStyle"))
	entry.Trails = collectTrails(weapon :: Model?)
end

local function track(character: Model)
	if entries[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or not character:FindFirstChild("UpperTorso") then
		return -- R6 rigs keep Roblox's default animations
	end
	-- Wait until the rig's Motor6Ds exist.
	character:WaitForChild("LowerTorso", 5)
	local entry: Entry = {
		Character = character,
		Animator = AnimatorCore.new(character),
		Humanoid = humanoid,
		Root = root,
		Weapon = nil,
		Accumulator = 0,
		Trails = {},
		Connections = {},
	}
	entries[character] = entry
	refreshWeapon(entry)
	table.insert(
		entry.Connections,
		character.ChildAdded:Connect(function(child)
			if child.Name == "EquippedWeapon" then
				task.defer(refreshWeapon, entry)
			end
		end)
	)
	table.insert(
		entry.Connections,
		character.ChildRemoved:Connect(function(child)
			if child.Name == "EquippedWeapon" then
				refreshWeapon(entry)
			end
		end)
	)
	table.insert(
		entry.Connections,
		character:GetAttributeChangedSignal("HoldStyle"):Connect(function()
			entry.Weapon = nil
			refreshWeapon(entry)
		end)
	)
	table.insert(
		entry.Connections,
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				AnimationController.Untrack(character)
			end
		end)
	)
	VFXController.IgnoreForRaycasts(character)
end

function AnimationController.Untrack(character: Model)
	local entry = entries[character]
	if not entry then
		return
	end
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	for _, trail in entry.Trails do
		trail.Enabled = false
	end
	entries[character] = nil
end

function AnimationController.Get(character: Model?)
	return character and entries[character] or nil
end

-- Plays a keyframed action (attack or gesture) on a character.
function AnimationController.PlayAction(character: Model?, actionName: string?, duration: number)
	local entry = character and entries[character]
	if entry and actionName then
		refreshWeapon(entry)
		entry.Animator:PlayAction(actionName, duration)
	end
end

function AnimationController.StopAction(character: Model?)
	local entry = character and entries[character]
	if entry then
		entry.Animator:StopAction()
		for _, trail in entry.Trails do
			trail.Enabled = false
		end
	end
end

local function present(entry: Entry): boolean
	if entry.Humanoid.Health <= 0 or not entry.Weapon then
		return false
	end
	if entry.Character:GetAttribute("WeaponDrawn") ~= true then
		return false
	end
	local state = entry.Humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Climbing
		and state ~= Enum.HumanoidStateType.Seated
end

local function updateEntry(entry: Entry, dt: number)
	local velocity = entry.Root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	entry.Animator:Update(dt, {
		Speed = speed,
		Grounded = entry.Humanoid.FloorMaterial ~= Enum.Material.Air,
		Present = present(entry),
		RootCFrame = entry.Root.CFrame,
		HipHeight = entry.Humanoid.HipHeight,
	})
	local trailOn = entry.Animator:IsTrailActive()
	for _, trail in entry.Trails do
		if trail.Enabled ~= trailOn then
			trail.Enabled = trailOn
		end
	end
end

-- ── Enemies: light procedural motion driven by attributes ─────────────────────
local function trackEnemy(model: Model)
	if enemyEntries[model] then
		return
	end
	local motors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end
	enemyEntries[model] = { Time = 0, Motors = motors, Seed = math.random() * 10 }
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			enemyEntries[model] = nil
		end
	end)
	VFXController.IgnoreForRaycasts(model)
end

local function updateEnemy(model: Model, data, dt: number)
	data.Time += dt
	local t = data.Time + data.Seed
	local motors = data.Motors
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local dead = humanoid and humanoid.Health <= 0
	if motors.Root then
		local sink = dead and math.min(data.Time - (data.DeadAt or data.Time), 1.2) * 2 or 0
		if dead and not data.DeadAt then
			data.DeadAt = data.Time
		end
		motors.Root.Transform = CFrame.new(0, math.sin(t * 2.2) * 0.18 - sink, 0)
			* CFrame.Angles(math.sin(t * 1.1) * 0.04, 0, math.sin(t * 1.6) * 0.05)
	end
	local attackStart = model:GetAttribute("AttackStart")
	local windUp = model:GetAttribute("AttackWindUp") or 0.5
	local raise, strike = 0, 0
	if attackStart then
		local elapsed = workspace:GetServerTimeNow() - attackStart
		if elapsed >= 0 and elapsed < windUp then
			raise = math.clamp(elapsed / windUp, 0, 1)
		elseif elapsed >= windUp and elapsed < windUp + 0.35 then
			raise = 1 - (elapsed - windUp) / 0.35
			strike = 1 - raise
		end
	end
	local sway = math.sin(t * 1.8) * 0.12
	if motors.RightArm then
		motors.RightArm.Transform = CFrame.Angles(raise * 2.4 - strike * 0.9 + sway, 0, 0)
	end
	if motors.LeftArm then
		motors.LeftArm.Transform = CFrame.Angles(raise * 2.2 - strike * 0.8 - sway, 0, 0)
	end
	if motors.Neck then
		motors.Neck.Transform = CFrame.Angles(math.sin(t * 0.9) * 0.08 - raise * 0.25, math.sin(t * 0.6) * 0.2, 0)
	end
end

function AnimationController:Init() end

function AnimationController:Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(track, character)
		end)
		if player.Character then
			task.spawn(track, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	task.spawn(function()
		local enemies = workspace:WaitForChild("Enemies", 60)
		if not enemies then
			return
		end
		enemies.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.defer(trackEnemy, child)
			end
		end)
		for _, child in enemies:GetChildren() do
			if child:IsA("Model") then
				trackEnemy(child)
			end
		end
	end)

	VFXController.Hooks.ChainImpulse = function(character: Model, impulse: Vector3, duration: number)
		local entry = entries[character]
		if entry then
			entry.Animator:AddChainImpulse(impulse, duration)
		end
	end

	RunService.Stepped:Connect(function(_, dt)
		local cameraPosition = camera and camera.CFrame.Position or Vector3.zero
		for _, entry in entries do
			if entry.Character.Parent then
				local distance = (entry.Root.Position - cameraPosition).Magnitude
				if distance < 70 then
					updateEntry(entry, dt + entry.Accumulator)
					entry.Accumulator = 0
				elseif distance < 180 then
					entry.Accumulator += dt
					if entry.Accumulator >= 1 / 20 then
						updateEntry(entry, entry.Accumulator)
						entry.Accumulator = 0
					end
				end
			end
		end
		for model, data in enemyEntries do
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - cameraPosition).Magnitude < 160 then
				updateEnemy(model, data, dt)
			end
		end
	end)
end

return AnimationController
