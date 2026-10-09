--[[
	WeaponClient
	Responsive combat on the client WITHOUT client authority:
	  * predicts the attack locally (animation + VFX start instantly), then sends AttackRequest
	  * the server re-validates everything and may Reject (animation is cancelled)
	  * input buffering: a press during the current swing queues the next combo step
	  * abilities (C/V/B), dash, sprint, holster/draw, Tsubaki form switching, knockback
	Damage is never decided here.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AbilityConfig = require(Modules.Config.AbilityConfig)
local AbilitySlots = require(Modules.Core.AbilitySlots)
local GameConfig = require(Modules.Config.GameConfig)
local Net = require(Modules.Core.Net)
local Signal = require(Modules.Core.Signal)
local WeaponConfig = require(Modules.WeaponConfig)

local Controllers = script.Parent
local AnimationController = require(Controllers.AnimationController)
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)
local VFXClient = require(Controllers.VFXClient)

local WeaponClient = {}

WeaponClient.Feedback = Signal.new() -- (text, kind) short combat messages for the HUD

local player = Players.LocalPlayer
local attackRemote: RemoteEvent
local abilityRemote: RemoteEvent
local movementRemote: RemoteEvent
local equipRemote: RemoteFunction

local seq = 0
local combo = { Step = 0, LastM1End = -math.huge, BusyUntil = 0 }
local queued: { Slot: string, At: number }? = nil
local attackHeld = false
local lastDash = -math.huge
local pendingSeqs: { [number]: boolean } = {}

local function character(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if c and humanoid and root and humanoid.Health > 0 then
		return c, humanoid, root
	end
	return nil, nil, nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end

-- Aim: mouse ray on PC, camera look on gamepad/touch.
function WeaponClient.Aim(): (Vector3, Vector3?)
	local camera = workspace.CurrentCamera
	local _, _, root = character()
	if not camera or not root then
		return Vector3.new(0, 0, -1), nil
	end
	local ray
	if
		UserInputService.MouseEnabled
		and not InputController.IsGamepad()
		and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
	then
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	else
		ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances =
		{ player.Character :: Instance, workspace:FindFirstChild("ClientVFX") :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	local hitPosition = result and result.Position or (ray.Origin + ray.Direction * 200)
	local direction = (hitPosition - (root.Position + Vector3.new(0, 1.5, 0)))
	if direction.Magnitude < 1e-3 then
		direction = root.CFrame.LookVector
	end
	return direction.Unit, hitPosition
end

local function faceDirection(root: BasePart, direction: Vector3)
	local f = flat(direction)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + f)
end

local function toast(text: string, kind: string?)
	WeaponClient.Feedback:Fire(text, kind or "Warning")
end

local REASONS = {
	Stamina = "Not enough stamina",
	Cooldown = "On cooldown",
	SoulEnergy = "Not enough Soul Energy",
	Locked = "Locked — keep training this origin's mastery",
	NoRace = "Roll an origin at the Soul Altar first",
	MeterNotFull = "Resonance meter not full",
	NotEnoughMadness = "Madness too low",
	NoSchool = "Choose a magic school in Skills",
	Staggered = "Staggered!",
}

-- ── Lunge / dash movement (client owns its character's physics) ───────────────
local function push(root: BasePart, velocity: Vector3, duration: number)
	local attachment = root:FindFirstChild("SE_PushAttachment") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "SE_PushAttachment"
		a.Parent = root
		attachment = a
	end
	local mover = Instance.new("LinearVelocity")
	mover.Name = "SE_Push"
	mover.Attachment0 = attachment
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = 60000
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.Parent = root
	task.delay(duration, function()
		mover:Destroy()
	end)
end

-- ── Attacks ───────────────────────────────────────────────────────────────────
local function tryAttack(slot: string): boolean
	local c, _, root = character()
	local profile = ClientState.Profile
	if not c or not root or not profile or not profile.Student.Created then
		return false
	end
	local weaponId = c:GetAttribute("EquippedWeapon")
	if not weaponId then
		return false
	end
	local config = WeaponConfig.Resolve(weaponId, c:GetAttribute("WeaponForm"))
	if not config then
		return false
	end
	if (c:GetAttribute("Status_Stagger") or 0) > workspace:GetServerTimeNow() then
		return false
	end
	local now = os.clock()
	if now < combo.BusyUntil - 0.08 then
		queued = { Slot = slot, At = now }
		return false
	end
	local attackId
	local step = combo.Step
	if slot == "M1" then
		if now - combo.LastM1End <= (config.ComboWindow or 0.8) then
			step = step % #config.Moveset.M1 + 1
		else
			step = 1
		end
		attackId = config.Moveset.M1[step]
	else
		attackId = config.Moveset[slot]
		local ready = player:GetAttribute("CD_" .. slot) or 0
		if ready > workspace:GetServerTimeNow() then
			toast(REASONS.Cooldown)
			return false
		end
	end
	local attack = WeaponConfig.Attacks[attackId]
	if not attack then
		return false
	end
	if (player:GetAttribute("Stamina") or 0) < (attack.Stamina or 0) then
		toast(REASONS.Stamina)
		return false
	end
	local attackSpeed = math.max(player:GetAttribute("AttackSpeed") or 1, 0.5)
	local duration = attack.Duration / attackSpeed
	if slot == "M1" then
		combo.Step = step
		combo.LastM1End = now + duration
	end
	combo.BusyUntil = now + duration * 0.85
	seq += 1
	pendingSeqs[seq] = true
	local aim = WeaponClient.Aim()
	faceDirection(root, aim)
	if not c:GetAttribute("WeaponDrawn") then
		task.spawn(function()
			equipRemote:InvokeServer({ Action = "Draw", Drawn = true })
		end)
	end
	AnimationController.PlayAction(c, attack.Animation, duration)
	VFXClient.PlayAttack(c, weaponId, attackId, duration, aim)
	if attack.Lunge then
		local firstHit = (attack.Hits[1] and attack.Hits[1].Time or 0.2) / attackSpeed
		local time = math.max(firstHit + 0.12, 0.15)
		push(root, flat(aim) * (attack.Lunge / time), time)
	end
	attackRemote:FireServer(slot, aim, seq)
	return true
end

function WeaponClient.OnReject(rejectedSeq: number, reason: string?)
	if pendingSeqs[rejectedSeq] then
		pendingSeqs[rejectedSeq] = nil
		combo.BusyUntil = 0
		AnimationController.StopAction(player.Character)
		if reason and REASONS[reason] then
			toast(REASONS[reason])
		end
	end
end

-- ── Abilities ─────────────────────────────────────────────────────────────────
local function tryAbility(slot: string)
	local c, _, root = character()
	local profile = ClientState.Profile
	if not c or not root or not profile then
		return
	end
	local abilityId, stage, reason = AbilitySlots.Resolve(profile, slot)
	if not abilityId then
		toast(REASONS[reason or ""] or "Unavailable")
		return
	end
	if (player:GetAttribute("CD_" .. slot) or 0) > workspace:GetServerTimeNow() then
		toast(REASONS.Cooldown)
		return
	end
	if (player:GetAttribute("SoulEnergy") or 0) < AbilityConfig.CostFor(abilityId, stage) * 0.84 then
		toast(REASONS.SoulEnergy)
		return
	end
	local aim, hitPosition = WeaponClient.Aim()
	faceDirection(root, aim)
	local gesture = AbilityConfig.Gestures[abilityId]
	if gesture then
		local ability, params = AbilityConfig.Resolve(abilityId, stage)
		local duration = (ability and ability.Kind == "TelegraphedSlam") and (params.WindUp + 0.45) or 0.7
		AnimationController.PlayAction(c, gesture, duration)
	end
	abilityRemote:FireServer(slot, aim, hitPosition)
end

-- ── Movement ──────────────────────────────────────────────────────────────────
local function dash()
	local c, humanoid, root = character()
	if not c or not humanoid or not root then
		return
	end
	local now = os.clock()
	if now - lastDash < GameConfig.Combat.DashCooldown then
		return
	end
	if (player:GetAttribute("Stamina") or 0) < GameConfig.Combat.DashStaminaCost then
		toast(REASONS.Stamina)
		return
	end
	if (c:GetAttribute("Status_Root") or 0) > workspace:GetServerTimeNow() then
		return
	end
	lastDash = now
	local direction = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.MoveDirection or root.CFrame.LookVector
	direction = flat(direction)
	local distance = GameConfig.Combat.DashDistance * (player:GetAttribute("DodgeDistance") or 1)
	push(root, direction * (distance / 0.22), 0.22)
	VFXClient.Dash(c, root.Position, direction)
	movementRemote:FireServer("Dash", direction)
end

function WeaponClient:Init()
	attackRemote = Net.Event("AttackRequest")
	abilityRemote = Net.Event("AbilityRequest")
	movementRemote = Net.Event("MovementRequest")
	equipRemote = Net.Function("EquipWeapon")
end

function WeaponClient:Start()
	InputController.Action:Connect(function(action, isDown)
		if action == "Attack" then
			attackHeld = isDown
			if isDown then
				tryAttack("M1")
			end
		elseif not isDown then
			if action == "Sprint" then
				movementRemote:FireServer("Sprint", false)
			end
			return
		elseif action == "SkillZ" then
			tryAttack("Z")
		elseif action == "SkillX" then
			tryAttack("X")
		elseif action == "SkillC" then
			tryAbility("C")
		elseif action == "SkillV" then
			tryAbility("V")
		elseif action == "Kishin" then
			tryAbility("B")
		elseif action == "Dash" then
			dash()
		elseif action == "Sprint" then
			movementRemote:FireServer("Sprint", true)
		elseif action == "Holster" then
			local c = player.Character
			if c and c:GetAttribute("EquippedWeapon") then
				local drawn = c:GetAttribute("WeaponDrawn") == true
				task.spawn(function()
					equipRemote:InvokeServer({ Action = "Draw", Drawn = not drawn })
				end)
			end
		elseif action == "Form" then
			local c = player.Character
			if c and c:GetAttribute("EquippedWeapon") == "TsubakiForms" then
				task.spawn(function()
					local result = equipRemote:InvokeServer({ Action = "Form" })
					if result and result.Ok then
						local form = WeaponConfig.Weapons.TsubakiForms.Forms[result.Form]
						toast("Form: " .. (form and form.DisplayName or result.Form), "Info")
					end
				end)
			end
		end
	end)

	-- Input buffer + hold-to-combo.
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if queued and now - queued.At > 0.35 then
			queued = nil
		end
		if now >= combo.BusyUntil - 0.08 then
			if queued then
				local slot = queued.Slot
				queued = nil
				tryAttack(slot)
			elseif attackHeld then
				tryAttack("M1")
			end
		end
	end)

	VFXClient.Knockback:Connect(function(velocity: Vector3)
		local _, _, root = character()
		if root then
			root.AssemblyLinearVelocity =
				Vector3.new(velocity.X, math.max(root.AssemblyLinearVelocity.Y, velocity.Y), velocity.Z)
		end
	end)
	VFXClient.Rejected:Connect(WeaponClient.OnReject)
end

return WeaponClient
