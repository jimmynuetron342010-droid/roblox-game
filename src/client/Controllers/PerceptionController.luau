--[[
	PerceptionController — Soul Perception (G)
	  * Outlines souls (enemies and players) within the Soul Perception stat's range, nearest first.
	  * Shrouded Kishin Eggs become clearly visible while perceived.
	  * Soul Protect: Witch players are hidden from perception unless you are a Shinigami.
	  * Divine Soul Perception (Shinigami): hidden soul fragments appear; their prompts enable.
	  * Predator Instinct (Werewolf, passive): wounded enemies nearby are outlined even with
	    perception off.
	Drains Soul Energy on the server while active (StatService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Net = require(Modules.Core.Net)
local Signal = require(Modules.Core.Signal)

local InputController = require(script.Parent.InputController)

local PerceptionController = {}

PerceptionController.Changed = Signal.new() -- (active)

local player = Players.LocalPlayer
local active = false
local highlights: { Highlight } = {}
local MAX_HIGHLIGHTS = 24
local movementRemote: RemoteEvent

local function getHighlight(index: number): Highlight
	local h = highlights[index]
	if not h then
		h = Instance.new("Highlight")
		h.Name = "SoulPerception"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillTransparency = 0.75
		h.OutlineTransparency = 0.1
		h.Parent = nil
		highlights[index] = h
	end
	return h
end

local function setShrouded(model: Model, visible: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("BaseTransparency") ~= nil then
			part.Transparency = visible and math.max(part:GetAttribute("BaseTransparency"), 0.15) or 0.78
		end
	end
end

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function refresh()
	local root = myRoot()
	local race = player:GetAttribute("Race")
	local range = player:GetAttribute("SoulPerception") or 60
	local candidates = {}
	if root then
		local enemies = workspace:FindFirstChild("Enemies")
		for _, model in enemies and enemies:GetChildren() or {} do
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local eroot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and eroot and humanoid.Health > 0 then
				local distance = (eroot.Position - root.Position).Magnitude
				local wounded = humanoid.Health < humanoid.MaxHealth * 0.5
				local instinct = race == "Werewolf" and wounded and distance <= range
				if (active and distance <= range) or instinct then
					table.insert(candidates, {
						Model = model,
						Distance = distance,
						Color = instinct and not active and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(255, 70, 80),
					})
				end
				if model:GetAttribute("Hidden") then
					setShrouded(model, active and distance <= range)
				end
			end
		end
		if active then
			for _, other in Players:GetPlayers() do
				if other ~= player and other.Character then
					local oroot = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local soulProtected = other:GetAttribute("Race") == "Witch" and race ~= "Shinigami"
					if oroot and not soulProtected then
						local distance = (oroot.Position - root.Position).Magnitude
						if distance <= range then
							table.insert(
								candidates,
								{ Model = other.Character, Distance = distance, Color = Color3.fromRGB(110, 170, 255) }
							)
						end
					end
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.Distance < b.Distance
	end)
	for i = 1, MAX_HIGHLIGHTS do
		local candidate = candidates[i]
		local h = highlights[i]
		if candidate then
			h = getHighlight(i)
			h.OutlineColor = candidate.Color
			h.FillColor = candidate.Color
			h.Adornee = candidate.Model
			h.Parent = candidate.Model
		elseif h then
			h.Adornee = nil
			h.Parent = nil
		end
	end
	-- Hidden world secrets: only Shinigami perceive them.
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, descendant in map:GetDescendants() do
			if descendant:IsA("BasePart") and descendant:GetAttribute("Secret") then
				local visible = active
					and race == "Shinigami"
					and root ~= nil
					and (descendant.Position - root.Position).Magnitude <= range
				descendant.Transparency = visible and 0.2 or 1
				local prompt = descendant:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					prompt.Enabled = visible
				end
			end
		end
	end
end

function PerceptionController.SetActive(value: boolean)
	if value and (player:GetAttribute("SoulEnergy") or 0) < 2 then
		value = false
	end
	active = value
	movementRemote:FireServer("Perception", value)
	PerceptionController.Changed:Fire(active)
	refresh()
end

function PerceptionController.IsActive(): boolean
	return active
end

function PerceptionController:Init()
	movementRemote = Net.Event("MovementRequest")
end

function PerceptionController:Start()
	InputController.Action:Connect(function(action, isDown)
		if action == "Perception" and isDown then
			PerceptionController.SetActive(not active)
		end
	end)
	-- The server switches perception off when Soul Energy runs out.
	player:GetAttributeChangedSignal("PerceptionActive"):Connect(function()
		if active and not player:GetAttribute("PerceptionActive") then
			active = false
			PerceptionController.Changed:Fire(false)
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			refresh()
		end
	end)
end

return PerceptionController
